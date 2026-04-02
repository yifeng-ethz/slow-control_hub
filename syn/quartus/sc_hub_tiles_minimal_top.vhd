-- File name: sc_hub_tiles_minimal_top.vhd
-- Author: Codex
-- =======================================
-- Version : 26.2.17
-- Date    : 20260402
-- Change  : Standalone small-preset wrapper for Quartus area/timing sign-off.
--           Tighten the preset to single-outstanding non-OoO operation.
-- =======================================
-- altera vhdl_input_version vhdl_2008

library ieee;
use ieee.std_logic_1164.all;

entity sc_hub_tiles_minimal_top is
    port(
        i_clk                       : in  std_logic;
        i_rst                       : in  std_logic;
        i_download_data             : in  std_logic_vector(31 downto 0);
        i_download_datak            : in  std_logic_vector(3 downto 0);
        o_download_ready            : out std_logic;
        aso_upload_data             : out std_logic_vector(35 downto 0);
        aso_upload_valid            : out std_logic;
        aso_upload_ready            : in  std_logic;
        aso_upload_startofpacket    : out std_logic;
        aso_upload_endofpacket      : out std_logic;
        avm_hub_address             : out std_logic_vector(15 downto 0);
        avm_hub_read                : out std_logic;
        avm_hub_readdata            : in  std_logic_vector(31 downto 0);
        avm_hub_writeresponsevalid  : in  std_logic;
        avm_hub_response            : in  std_logic_vector(1 downto 0);
        avm_hub_write               : out std_logic;
        avm_hub_writedata           : out std_logic_vector(31 downto 0);
        avm_hub_waitrequest         : in  std_logic;
        avm_hub_readdatavalid       : in  std_logic;
        avm_hub_burstcount          : out std_logic_vector(8 downto 0)
    );
end entity sc_hub_tiles_minimal_top;

architecture rtl of sc_hub_tiles_minimal_top is
begin
    dut_inst : entity work.sc_hub_top
    generic map(
        INVERT_RD_SIG            => false,
        DEBUG                    => 0,
        OOO_ENABLE               => false,
        ORD_ENABLE               => false,
        ATOMIC_ENABLE            => false,
        HUB_CAP_ENABLE           => false,
        EXT_PLD_DEPTH            => 32,
        PKT_QUEUE_DEPTH          => 1,
        BP_FIFO_DEPTH            => 32,
        RD_TIMEOUT_CYCLES        => 256,
        WR_TIMEOUT_CYCLES        => 256,
        OUTSTANDING_LIMIT        => 1,
        OUTSTANDING_INT_RESERVED => 0
    )
    port map(
        i_clk                      => i_clk,
        i_rst                      => i_rst,
        i_download_data            => i_download_data,
        i_download_datak           => i_download_datak,
        o_download_ready           => o_download_ready,
        aso_upload_data            => aso_upload_data,
        aso_upload_valid           => aso_upload_valid,
        aso_upload_ready           => aso_upload_ready,
        aso_upload_startofpacket   => aso_upload_startofpacket,
        aso_upload_endofpacket     => aso_upload_endofpacket,
        avm_hub_address            => avm_hub_address,
        avm_hub_read               => avm_hub_read,
        avm_hub_readdata           => avm_hub_readdata,
        avm_hub_writeresponsevalid => avm_hub_writeresponsevalid,
        avm_hub_response           => avm_hub_response,
        avm_hub_write              => avm_hub_write,
        avm_hub_writedata          => avm_hub_writedata,
        avm_hub_waitrequest        => avm_hub_waitrequest,
        avm_hub_readdatavalid      => avm_hub_readdatavalid,
        avm_hub_burstcount         => avm_hub_burstcount
    );
end architecture rtl;
