-- File name: sc_hub_top.vhd 
-- Author: Yifeng Wang (yifenwan@phys.ethz.ch)
-- =======================================
-- Revision: 1.0 (file created)
--		Date: Feb 2, 2024
-- Revision: 2.0 (add backpressure support for the output uplink to the mux,
--						a further investigation is needed to accept the ready signal from the asi)
-- =========
-- Description:	[Slow Control Hub Top-Level File] 
--						hierarchy:
--						top --
--								sc_hub
--								bp_fifo

-- ================ synthsizer configuration =================== 		
-- altera vhdl_input_version vhdl_2008
-- ============================================================= 

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use IEEE.math_real.log2;
use IEEE.math_real.ceil;
use ieee.std_logic_arith.conv_std_logic_vector;

entity sc_hub_top is 
	generic(
		BACKPRESSURE									: boolean := True;
		SCHEDULER_USE_PKT_TRANSFER						: boolean := True; -- should be true if you use the mux Intel ip. 
		INVERT_RD_SIG									: boolean := True; -- Intel Mux IP has inverted ready signal at its input
		DEBUG											: natural := 1
	);
	port(
		i_clk				: in  std_logic;
		i_rst				: in  std_logic;
		
		i_linkin_data     	: in  std_logic_vector(31 downto 0);
		i_linkin_datak    	: in  std_logic_vector(3 downto 0);
		o_linkin_ready		: out std_logic;
		
		aso_to_uplink_data				: out std_logic_vector(35 downto 0); -- bit 35-32(datak), bit 31-0(data)
		aso_to_uplink_valid				: out std_logic;
		aso_to_uplink_ready				: in  std_logic;
		aso_to_uplink_startofpacket		: out std_logic;
		aso_to_uplink_endofpacket		: out std_logic;
		
		avm_m0_address					: out std_logic_vector(15 downto 0);
		avm_m0_read						: out std_logic;
		avm_m0_readdata					: in  std_logic_vector(31 downto 0);
		avm_m0_writeresponsevalid		: in std_logic;
		avm_m0_response					: in  std_logic_vector(1 downto 0);
		avm_m0_write					: out std_logic;
		avm_m0_writedata				: out std_logic_vector(31 downto 0);
		avm_m0_waitrequest				: in  std_logic;
		avm_m0_readdatavalid			: in  std_logic;
		avm_m0_flush					: out std_logic;
		avm_m0_burstcount				: out std_logic_vector(8 downto 0) -- max burst is 2^<burstcount-1>=2^8=256
	);
end entity sc_hub_top;

architecture rtl of sc_hub_top is 
	
	signal up_link_data				: std_logic_vector(31 downto 0);
	signal up_link_datak				: std_logic_vector(3 downto 0);
	signal up_link_en					: std_logic;
	signal up_link_sop				: std_logic;		
	signal up_link_eop				: std_logic;
	
	signal down_link_data			: std_logic_vector(31 downto 0);
	signal down_link_datak			: std_logic_vector(3 downto 0);
	signal down_link_ready			: std_logic;
	
	signal bkpr_fifo_wrreq			: std_logic;
	signal bkpr_fifo_din				: std_logic_vector(39 downto 0);
	signal bkpr_fifo_rdreq			: std_logic;
	signal bkpr_fifo_dout			: std_logic_vector(39 downto 0);
	signal bkpr_fifo_empty			: std_logic;
	signal bkpr_fifo_full			: std_logic;
	signal bkpr_fifo_usedw			: std_logic_vector(8 downto 0);
	
	signal packet_in_fifo_cnt		: std_logic_vector(8 downto 0);
	signal avst_trans_start			: std_logic;
	
	signal aso_to_uplink_ready_int	: std_logic;
	
	
	component alt_fifo_w40d512
	PORT
	(
		clock		: IN STD_LOGIC ;
		data		: IN STD_LOGIC_VECTOR (39 DOWNTO 0);
		rdreq		: IN STD_LOGIC ;
		sclr		: IN STD_LOGIC ;
		wrreq		: IN STD_LOGIC ;
		empty		: OUT STD_LOGIC ;
		full		: OUT STD_LOGIC ;
		q			: OUT STD_LOGIC_VECTOR (39 DOWNTO 0);
		usedw		: OUT STD_LOGIC_VECTOR (8 DOWNTO 0)
	);
	end component;

begin

	gen_inv_rd : if INVERT_RD_SIG = True generate
		aso_to_uplink_ready_int	<= not aso_to_uplink_ready;
	else generate 
		aso_to_uplink_ready_int	<= aso_to_uplink_ready;
	end generate gen_inv_rd;
	
		
	down_link_data 	<= i_linkin_data;
	down_link_datak	<= i_linkin_datak;
	-- o_linkin_ready		<= down_link_ready;
	
	e_sc_hub : entity work.sc_hub
	port map(
		i_clk						=> i_clk,
		i_rst						=> i_rst,
		
		i_linkin_data     			=> down_link_data,
		i_linkin_datak    			=> down_link_datak,
		o_linkin_ready				=> down_link_ready, -- sc_hub is able to take in new command, deassert during command processing
		-- reassert after ack is sent
		
		o_linkout_data				=> up_link_data,
		o_linkout_datak				=> up_link_datak,
		o_linkout_en				=> up_link_en,
		o_linkout_sop				=> up_link_sop,
		o_linkout_eop				=> up_link_eop,

		avm_m0_address				=> avm_m0_address,
		avm_m0_read					=> avm_m0_read,
		avm_m0_readdata				=> avm_m0_readdata,
		avm_m0_writeresponsevalid	=> avm_m0_writeresponsevalid,
		avm_m0_response				=> avm_m0_response,
		avm_m0_write				=> avm_m0_write,
		avm_m0_writedata			=> avm_m0_writedata,
		avm_m0_waitrequest			=> avm_m0_waitrequest,
		avm_m0_readdatavalid		=> avm_m0_readdatavalid,
		avm_m0_flush				=> avm_m0_flush,
		avm_m0_burstcount			=> avm_m0_burstcount
	);
	
	alt_fifo_bkpr_uplink	: alt_fifo_w40d512
	port map(
		clock				=> i_clk,
		sclr				=> i_rst,
		wrreq				=> bkpr_fifo_wrreq,
		data				=> bkpr_fifo_din,
		rdreq				=> bkpr_fifo_rdreq,
		q					=> bkpr_fifo_dout,
		empty				=> bkpr_fifo_empty,
		full				=> bkpr_fifo_full,
		usedw				=> bkpr_fifo_usedw
	);
	
	
	proc_wr_to_fifo : process(i_clk,i_rst)
	begin
		if (i_rst = '1') then
			bkpr_fifo_wrreq					<= '0';
			bkpr_fifo_din(31 downto 0)		<= (others=>'0');
			bkpr_fifo_din(35 downto 32)	<= (others=>'0');
			bkpr_fifo_din(36)					<= '0';
			bkpr_fifo_din(37)					<= '0';
		elsif (rising_edge(i_clk)) then
			if (up_link_en = '1') then -- TODO: use almost full to check if there is enough space before write
			-- if not checked, the packet will be incomplete, as they are omitted by the buffer
			-- so, it is better to flush the fifo if the uplink gets congestion to at least transmit a couple
			-- of packets in full, before uplink congested again in case of bandwith limits. 
				bkpr_fifo_wrreq					<= '1';
				bkpr_fifo_din(31 downto 0)		<= up_link_data;
				bkpr_fifo_din(35 downto 32)	<= up_link_datak;
				bkpr_fifo_din(36)					<= up_link_sop;
				bkpr_fifo_din(37)					<= up_link_eop;
			else
				bkpr_fifo_wrreq					<= '0';
				bkpr_fifo_din(31 downto 0)		<= (others=>'0');
				bkpr_fifo_din(35 downto 32)	<= (others=>'0');
				bkpr_fifo_din(36)					<= '0';
				bkpr_fifo_din(37)					<= '0';
			end if;
		end if;
	end process proc_wr_to_fifo;
	
	proc_pkt_transfer : process(i_clk,i_rst)
	begin -- only output when seen eop in the fifo, but not seen enough eop output from the fifo
		if (i_rst = '1') then
			packet_in_fifo_cnt	<= (others=>'0');
		elsif (rising_edge(i_clk)) then
			if (up_link_eop = '1' and aso_to_uplink_endofpacket = '0') then
				packet_in_fifo_cnt 	<= conv_std_logic_vector(to_integer(unsigned(packet_in_fifo_cnt)) + 1, packet_in_fifo_cnt'length);
			elsif (up_link_eop = '0' and aso_to_uplink_endofpacket = '1') then
				packet_in_fifo_cnt 	<= conv_std_logic_vector(to_integer(unsigned(packet_in_fifo_cnt)) - 1, packet_in_fifo_cnt'length);
			else
				packet_in_fifo_cnt	<= packet_in_fifo_cnt;
			end if;
		end if;
	
	end process proc_pkt_transfer;
	
	proc_rd_from_fifo_comb : process(all)
	begin -- the read side of fifo must use comb logic, as the latency from not empty to rdreq (rdack) must be 0.
	-- otherwise, the extra latency will cause the fifo will not sense the first word been consumed and thus miss the 
	-- last word in the fifo.
		if (bkpr_fifo_empty /= '1' and to_integer(unsigned(packet_in_fifo_cnt)) >= 1 and avst_trans_start = '0') then
			bkpr_fifo_rdreq		<= '1';
		elsif (avst_trans_start = '1' and aso_to_uplink_ready_int = '1') then
			bkpr_fifo_rdreq		<= '1';
		elsif (avst_trans_start = '1' and aso_to_uplink_ready_int = '0') then
		-- but do not ack the read, since the transaction at this cycle is halted
			bkpr_fifo_rdreq		<= '0';
		else 
			bkpr_fifo_rdreq		<= '0';
		end if;
	end process proc_rd_from_fifo_comb;
	
	proc_rd_from_fifo	: process(i_clk,i_rst)
	begin
		if (i_rst = '1') then
			aso_to_uplink_data				<= (others => '0');
			aso_to_uplink_valid				<= '0';
			aso_to_uplink_startofpacket	<= '0';
			aso_to_uplink_endofpacket		<= '0';
			avst_trans_start					<= '0';
		elsif (rising_edge(i_clk)) then
			if (bkpr_fifo_empty /= '1' and to_integer(unsigned(packet_in_fifo_cnt)) >= 1 and avst_trans_start = '0') then
			-- fifo is not empty, give valid signal no matter upstream is ready or not
			-- illegal case: fifo is empty before the eop, do nothing, new packet will flush over the incomplete one
				aso_to_uplink_data				<= bkpr_fifo_dout(35 downto 0);
				aso_to_uplink_valid				<= '1';
				aso_to_uplink_startofpacket	<= bkpr_fifo_dout(36);
				aso_to_uplink_endofpacket		<= bkpr_fifo_dout(37);
				avst_trans_start					<= '1';
			elsif (avst_trans_start = '1' and aso_to_uplink_ready_int = '1') then
			-- continue transaction if the upstream is ready
				aso_to_uplink_data				<= bkpr_fifo_dout(35 downto 0);
				aso_to_uplink_valid				<= '1';
				aso_to_uplink_startofpacket	<= bkpr_fifo_dout(36);
				aso_to_uplink_endofpacket		<= bkpr_fifo_dout(37);
				if (bkpr_fifo_dout(37) = '1') then -- mark the completion of transaction
					avst_trans_start				<= '0'; -- goto state 1 if there is another complete pkt, otherwise idle
				end if;
			elsif (avst_trans_start = '1' and aso_to_uplink_ready_int = '0') then
			-- continue assert valid if the upstream is not ready
				aso_to_uplink_valid				<= '1'; 
			else 
				aso_to_uplink_data				<= (others => '0');
				aso_to_uplink_valid				<= '0';
				aso_to_uplink_startofpacket	<= '0';
				aso_to_uplink_endofpacket		<= '0';
			end if;
		end if;
	end process proc_rd_from_fifo;
	
	proc_bkpr_fifo_overflow_protection : process(i_clk,i_rst)
	begin
		if (i_rst = '1') then
			o_linkin_ready		<= '0';
		elsif (rising_edge(i_clk)) then
			if (bkpr_fifo_usedw(bkpr_fifo_usedw'high) = '1' or down_link_ready = '0')  then 
			-- backpressure is half full or sc_hub is processing a command, TODO: add queue at the input of sc_hub
			-- For read command, it might overflow if the merger is stuck. 
			-- half full will flag not ready, to improve: allow one full packet transfer at this moment
			-- otherwise, this will be toggling and create bubbles in the input link to sc_hub.
				o_linkin_ready			<= '0';
			else 
				o_linkin_ready			<= '1';
			end if;
				
		end if;
	
	
	end process proc_bkpr_fifo_overflow_protection;
	
	
end architecture rtl;

