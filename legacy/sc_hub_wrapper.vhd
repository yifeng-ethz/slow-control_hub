-- File name: sc_hub_wrapper.vhd 
-- Author: Yifeng Wang (yifenwan@phys.ethz.ch)
-- =======================================
-- Revision: 1.0 (file created)
--		Date: Nov 19, 2024
-- =========
-- Description:	[Slow Control Hub] 
--      Debrief:
--		   Convert slow-control packet into system bus (Avalon Memory-Mapped) transactions
--
--      Flow:
--          ------------------- read flow ----------------------
--          read:  perform avalon read
--          ack:   send readdata in the reply packet (K23.7 for no enough data)
--          ------------------- write flow ---------------------
--          write: perform avalon write 
--          ack:   send reply packet
--          ----------------------------------------------------
--
--      Usage: 
--          1) connects <download> to the <out> of download_fifo 
--             ('Use packet' = OFF; for adding elasticity only, will buffer new packet before sc_hub is ready to digest another packet)
--          2) connects <upload> to the <in> of upload_fifo 
--             ('Use store and forward' = ON, 'Use packet' = ON, *(require an internal master to set each time after reset) drop_on_error = ON)
--          
--
--
--			

-- ================ synthsizer configuration =================== 		
-- altera vhdl_input_version vhdl_2008
-- ============================================================= 

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use IEEE.math_real.log2;
use IEEE.math_real.ceil;
use ieee.std_logic_misc.and_reduce;
use ieee.std_logic_misc.or_reduce;

entity sc_hub_wrapper is 
    generic (
        AVMM_BURST_W                : natural := 9; -- max burst is 2^<burstcount-1>=2^8=256
        AVMM_ADDR_W                 : natural := 16; -- fixed, word addressing
        AVST_ERROR_W                : natural := 1; -- currently fixed, for future update
        DEBUG                       : natural := 1 -- debug level
    );
    port (
        -- <download> (h2d sc packet)
        asi_download_data           : in  std_logic_vector(35 downto 0);
        asi_download_valid          : in  std_logic;
        asi_download_ready          : out std_logic;
        
        -- <upload> (d2h sc packet)
        aso_upload_data             : out std_logic_vector(35 downto 0);
        aso_upload_valid            : out std_logic;
        aso_upload_ready            : in  std_logic;
        aso_upload_startopacket     : out std_logic;
        aso_upload_endofpacket      : out std_logic;
        aso_upload_error            : out std_logic_vector(AVST_ERROR_W-1 downto 0);
        
        -- <hub> (system bus interface)
        -- Read Address (AR)
        avm_hub_address				: out std_logic_vector(AVMM_ADDR_W-1 downto 0);
        avm_hub_burstcount			: out std_logic_vector(8 downto 0);
		avm_hub_read				: out std_logic;
        avm_hub_waitrequest			: in  std_logic;
        -- Read Data (R)
        avm_hub_readdatavalid		: in  std_logic;
		avm_hub_readdata			: in  std_logic_vector(31 downto 0);
        -- Write Address (AW)
            -- address = avm_hub_address
        avm_hub_write				: out std_logic;
        -- Write Data (W)
            -- writedatavalid = avm_hub_write
        avm_hub_writedata			: out std_logic_vector(31 downto 0);
        -- Write Response (B)
		avm_hub_writeresponsevalid	: in  std_logic;
		avm_hub_response			: in  std_logic_vector(1 downto 0);
    
        -- clock and reset interface 
        i_clk                   : in  std_logic;
        i_rst                   : in  std_logic
    );
end entity sc_hub_wrapper;

architecture rtl of sc_hub_wrapper is 

    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\ sc_wrapper \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    type scrollback_state_t is (IDLE,DROP,RESET);
    signal scrollback_state             : scrollback_state_t;
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

    
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\ sc_hub \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    signal linkin_data              : std_logic_vector(31 downto 0);
    signal linkin_datak             : std_logic_vector(3 downto 0);
    signal linkin_ready             : std_logic;
    
    signal linkout_data             : std_logic_vector(31 downto 0);
    signal linkout_datak            : std_logic_vector(3 downto 0);
    signal linkout_en               : std_logic;
    signal linkout_sop              : std_logic;
    signal linkout_eop              : std_logic;
    
    signal avm_hub_flush            : std_logic;
    signal avm_hub_error            : std_logic_vector(AVST_ERROR_W-1 downto 0);
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    
begin

    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    -- @blockName       sc_wrapper 
    --
    -- @berief          wrap the signals from sc_hub to support upload packet validation and generate idle
    --                  symbols when download fifo is empty. 
    -- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
    proc_sc_wrapper : process (i_clk)
    -- description: scrollback the upload fifo when the reply packet is broken 
    begin
        if (rising_edge(i_clk)) then 
            if (i_rst = '1') then 
                scrollback_state          <= RESET;
            else 
                case scrollback_state is 
                    when IDLE =>
                        -- listen signaling from sc_hub: error on avalon read timeout
                        if (avm_hub_flush = '1') then 
                            scrollback_state        <= DROP;
                        end if;
                    when DROP =>
                        -- signal upload fifo: send one beat of error and valid
                        avm_hub_error               <= (others => '1');
                        scrollback_state            <= RESET;
                    when RESET =>
                        avm_hub_error               <= (others => '0');
                        -- listen signaling from sc_hub: sc_hub is in idle
                        if (linkin_ready = '1') then -- sc_hub is in idle: ready for new command 
                            scrollback_state            <= IDLE;
                        end if;
                    when others =>
                        scrollback_state            <= RESET;
                end case;
            end if; -- end of clock - sync reset low
        end if; -- end of clock
    end process;
    
    
    proc_sc_wrapper_comb : process (all)
    -- description: 1) generate idle symbols during download fifo empty
    --              2) generate error signal to flush current reply packet in upload fifo
    begin
        -- -------------------------
        -- download -> linkin
        -- -------------------------
        -- ready
        asi_download_ready          <= linkin_ready;
        -- data
        if (asi_download_valid = '1') then 
            -- valid: fifo -> sc_hub 
            linkin_datak            <= asi_download_data(35 downto 32);
            linkin_data             <= asi_download_data(31 downto 0);
        else 
            -- not valid: K28.5 -> sc_hub
            linkin_datak            <= "0001";
            linkin_data             <= std_logic_vector(to_unsigned(16#BC#,32));
        end if;
        
        -- -------------------------
        -- linkout -> upload
        -- -------------------------
        -- data 
        aso_upload_data             <= linkout_datak & linkout_data;
        -- valid
        if (or_reduce(avm_hub_error) = '0') then 
            -- 1) no error: sc_hub -> fifo
            aso_upload_valid            <= linkout_en;
        else 
            -- 2) error present: flush_to_error -> fifo
            aso_upload_valid            <= '1';
        end if;
        -- error 
        aso_upload_error                <= avm_hub_error;       
        -- packet 
        aso_upload_startopacket         <= linkout_sop;
        aso_upload_endofpacket          <= linkout_eop;
    end process;
    
    
    
    
    
   
    
    -- ==================================================================================================== 
    -- @moduleName      sc_hub 
    -- 
    -- @berief          translate sc command packet into avalon read or write and generate sc reply packet
    -- @input           <linkin> -- command packets, from xcvr (32d+4k)
    -- @output          <linkout> -- reply packets, to merger (32d+4k)
    --                  <m0> -- avalon source, to qsys 
    -- @clockDomain     xcvr clock domain (156.25 MHz)
    -- @resetEdge       deassertion
    -- ====================================================================================================
    e_sc_hub : entity work.sc_hub
	port map(
        -- <linkin>
		i_linkin_data     			=> linkin_data,
		i_linkin_datak    			=> linkin_datak,
		o_linkin_ready				=> linkin_ready, -- high: sc_hub can accept new packet, low: full packet received, sending reply
		
        -- <linkout>
		o_linkout_data				=> linkout_data,
		o_linkout_datak				=> linkout_datak,
		o_linkout_en				=> linkout_en,
		o_linkout_sop				=> linkout_sop,
		o_linkout_eop				=> linkout_eop,
    
        -- <m0>
		avm_m0_address				=> avm_hub_address,
		avm_m0_read					=> avm_hub_read,
		avm_m0_readdata				=> avm_hub_readdata,
		avm_m0_writeresponsevalid	=> avm_hub_writeresponsevalid,
		avm_m0_response				=> avm_hub_response,
		avm_m0_write				=> avm_hub_write,
		avm_m0_writedata			=> avm_hub_writedata,
		avm_m0_waitrequest			=> avm_hub_waitrequest,
		avm_m0_readdatavalid		=> avm_hub_readdatavalid,
		avm_m0_flush				=> avm_hub_flush, -- note: this port is no longer support in avalon new spec
		avm_m0_burstcount			=> avm_hub_burstcount,
        
        -- clock and reset interface
        i_clk						=> i_clk,
		i_rst						=> i_rst
	);






end architecture rtl;
    
    
    
    
    
    