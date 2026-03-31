-- ------------------------------------------------------------------------------------------------------------------------------------------------------
-- IP Name:         sc_hub [Slow Control Hub]
-- Author:          Yifeng Wang (yifenwan@phys.ethz.ch)
-- Revision:        26.0.0331
-- Date:            Mar 30, 2026
-- Description:     Slow Control Hub IP core for Mu3e experiment. Handle slow control commands from host and interface with NoC IPs
--
-- Revision history:
-- format: <year>.<version>.<date>. note: <version> is the major release version number since that year
-- 24.0.0109        File created
-- 24.1.0129        Add single read and write; burst read with DP-RAM; burst write with SC-FIFO
-- 24.2.0131        All commands buffered with SC-FIFO, basic functions verified
-- 24.2.02133       Fix minor bug to release qsys read if terminated. add timeout for write
-- 24.2.0220        Clean up ready signal to download
-- 25.0.0806        Fixed bug of burst read word index mismatch
-- 25.0.0809        Fixed read-side trailer handling with K28.5 bubbles between length and trailer
-- 26.0.0330        Reissue the current hub in date-style versioning without changing its public interface
-- 26.0.0331        Add local debug CSR/FIFO telemetry and fix AVMM read launch timing for zero-wait slaves
--
-- Mu3e Slow Control Packet Format:
--
--      Command Packet from host to device: 
--      ┌─────────────────┬───────────────────────────────────────────────────────────────────────────────────────────────────────┐
--      │     Word Offset │ Name                                                                                                  │
--      │-----------------│-------------------------------------------------------------------------------------------------------│
--      │     [bit range] │ description                                                                                           │
--      ├─────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────┤
--      │               0 │ Preamble                                                                                              │
--      │-----------------│-------------------------------------------------------------------------------------------------------│
--      │         [31:26] │ data type, "000111"=SlowControl                                                                       │
--      │         [25:24] │ slow control type, "00"=BurstRead, "01"=BurstWrite, "10"=Read, "11"=Write                             │
--      │          [23:8] │ FPGA ID (16-bit), for backend outstanding transaction (currently not checked). can be modified by CSR │
--      │           [7:0] │ K28.5                                                                                                 │
--      ├─────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────┤
--      │               1 │ Start Address                                                                                         │
--      │-----------------│-------------------------------------------------------------------------------------------------------│
--      │         [31:28] │ reserved                                                                                              │
--      │         [27:24] │ mute ack, no reply packet will be sent. "1XXX"=R(mute all FEB types), "01XX"=M(mute Mupix FEB),       │
--      │                 │ "001X"=S(mute SciFi FEB), "0001"=T(mute Tile FEB)                                                     │
--      │          [23:0] │ start address (24-bit), word addressing, currently upstream only supports 16-bit                      │
--      ├─────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────┤
--      │               2 │ Burst Length                                                                                          │
--      │-----------------│-------------------------------------------------------------------------------------------------------│
--      │         [31:16] │ reserved                                                                                              │
--      │          [15:0] │ length in words = L, max length is 2^8 words. should be one for single read/write                     │
--      ├─────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────┤
--      │             2+L │ Write Data (opt)                                                                                      │
--      │-----------------│-------------------------------------------------------------------------------------------------------│
--      │         [31:0]  │ h2d data to be written to IP                                                                          │
--      │         ...     │ ...                                                                                                   │
--      ├─────────────────┼───────────────────────────────────────────────────────────────────────────────────────────────────────┤
--      │           2+L+1 │ Trailer                                                                                               │
--      │-----------------│-------------------------------------------------------------------------------------------------------│
--      │         [31:8]  │ reserved                                                                                              │
--      │          [7:0]  │ K28.4                                                                                                 │
--      └─────────────────┴───────────────────────────────────────────────────────────────────────────────────────────────────────┘
--     work flow
--         Receive upstream Mu3e Slow Control Packet, act as the hub to distribute the commands to the corresponding slaves and collect the responses.
--
-- Block diagram:
--     +------------------------------------------------+------------------+
--     |                                                |                  |
--     |  +------------+                                +--------+         |
--     |  |            |                                |        |         |
--     |  |  sc frame  |    +---------+                 |Avalon  +----+    |
--     |  |  assembly  |    |         |                 |Write   |    v    |
--     |  |            +--->| Write   +---------------->|Handler | +-------+
--     |  +------------+    | FIFO    |                 |        | |       |
--     |                    +---------+                 +--------+ |       |
--     +------+                                         |          |       |
--     |      |                                         |          |AVMM   |
--     |AVMM  |            +-----------+                |          |Master |
--     |Slave |            | Control-  |                |          |Inter- |
--     |Inter-|<---------->| Status-   |                |          |face   |
--     |face  |            | Register  |                |          |       |
--     |      |            +-----------+                |          |       |
--     +------+                                         +--------+ |       |
--     |                                                |        | +-------+
--     |  +------------+                                |Avalon  |     ^   |
--     |  |            |   +----------+                 |Read    +-----+   |
--     |  |  sc frame  |   |          |                 |Handler |         |
--     |  | deassembly |<--+ Read     |<----------------+        |         |
--     |  |            |   | FIFO     |                 +--------+         |
--     |  +------------+   +----------+                 |                  |
--     |                                               |                  |
--     +------------------------------------------------+------------------+
--
-- Mu3e IP Library:
--
-- ------------------------------------------------------------------------------------------------------------
-- Synthesizer configuration
-- altera vhdl_input_version vhdl_2008
-- ------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use IEEE.math_real.log2;
use IEEE.math_real.ceil;
use ieee.std_logic_arith.conv_std_logic_vector;

entity sc_hub is
    generic(
        DEBUG              : natural := 1
    );
    port(
        -- +---------------------+
        -- | CLK / RST Interface |
        -- +---------------------+
        i_clk             : in  std_logic;
        i_rst             : in  std_logic;

        -- +--------------------------+
        -- | SC COMMAND PKT Interface |
        -- +--------------------------+
        i_linkin_data     : in  std_logic_vector(31 downto 0);
        i_linkin_datak    : in  std_logic_vector(3 downto 0);
        o_linkin_ready    : out std_logic;

        -- +------------------------+
        -- | SC REPLY PKT Interface |
        -- +------------------------+
        o_linkout_data    : out std_logic_vector(31 downto 0);
        o_linkout_datak   : out std_logic_vector(3 downto 0);
        o_linkout_en      : out std_logic;
        o_linkout_sop     : out std_logic;
        o_linkout_eop     : out std_logic;

        -- +-------------------------+
        -- | Local FIFO Sideband CSR |
        -- +-------------------------+
        i_download_fifo_pkt_count    : in  std_logic_vector(8 downto 0);
        i_download_fifo_usedw        : in  std_logic_vector(8 downto 0);
        i_download_fifo_full         : in  std_logic;
        i_download_fifo_overflow     : in  std_logic;
        i_upload_fifo_pkt_count      : in  std_logic_vector(8 downto 0);
        i_upload_fifo_usedw          : in  std_logic_vector(8 downto 0);
        i_upload_fifo_full           : in  std_logic;
        i_upload_fifo_overflow       : in  std_logic;
        o_download_fifo_flush        : out std_logic;
        o_download_fifo_reset        : out std_logic;
        o_download_store_and_forward : out std_logic;
        o_upload_fifo_flush          : out std_logic;
        o_upload_fifo_reset          : out std_logic;
        o_upload_store_and_forward   : out std_logic;

        -- +-----------------------+
        -- | AVMM Master Interface |
        -- +-----------------------+
        avm_m0_address              : out std_logic_vector(15 downto 0); -- master is word addressing, span = 2^16 = 262KB. 
                                                                         -- mu3e only limited to 16-bit of addressing ability for FEB.    
                                                                         -- can be enlarged if upstream supports more
        avm_m0_read                 : out std_logic;
        avm_m0_readdata             : in  std_logic_vector(31 downto 0);
        avm_m0_writeresponsevalid   : in  std_logic;
        avm_m0_response             : in  std_logic_vector(1 downto 0);
        avm_m0_write                : out std_logic;
        avm_m0_writedata            : out std_logic_vector(31 downto 0);
        avm_m0_waitrequest          : in  std_logic;
        avm_m0_readdatavalid        : in  std_logic;
        avm_m0_flush                : out std_logic; -- may not supported in newer Avalon Spec. use to flush pending command
        avm_m0_burstcount           : out std_logic_vector(8 downto 0)  -- max burst is 2^<burstcount-1>=2^8=256
    );
end entity;

architecture rtl of sc_hub is
    -- K-codes for 8b10b encoding
    constant K285             : std_logic_vector(7 downto 0) := "10111100";  -- 16#BC#
    constant K284             : std_logic_vector(7 downto 0) := "10011100";  -- 16#9C#
    constant K237             : std_logic_vector(7 downto 0) := "11110111";  -- 16#F7#
    constant HUB_CSR_BASE_ADDR_CONST           : natural := 16#FE80#;
    constant HUB_CSR_WINDOW_WORDS_CONST        : natural := 32;
    constant HUB_CSR_ID_CONST                  : std_logic_vector(31 downto 0) := x"53480000";
    constant HUB_CSR_VERSION_YY_CONST          : natural := 26;
    constant HUB_CSR_VERSION_MAJOR_CONST       : natural := 0;
    constant HUB_CSR_VERSION_PRE_CONST         : natural := 0;
    constant HUB_CSR_VERSION_MONTH_CONST       : natural := 3;
    constant HUB_CSR_VERSION_DAY_CONST         : natural := 31;
    constant HUB_CSR_WO_ID_CONST               : natural := 16#000#;
    constant HUB_CSR_WO_VERSION_CONST          : natural := 16#001#;
    constant HUB_CSR_WO_CTRL_CONST             : natural := 16#002#;
    constant HUB_CSR_WO_STATUS_CONST           : natural := 16#003#;
    constant HUB_CSR_WO_ERR_FLAGS_CONST        : natural := 16#004#;
    constant HUB_CSR_WO_ERR_COUNT_CONST        : natural := 16#005#;
    constant HUB_CSR_WO_SCRATCH_CONST          : natural := 16#006#;
    constant HUB_CSR_WO_GTS_SNAP_LO_CONST      : natural := 16#007#;
    constant HUB_CSR_WO_GTS_SNAP_HI_CONST      : natural := 16#008#;
    constant HUB_CSR_WO_FIFO_CFG_CONST         : natural := 16#009#;
    constant HUB_CSR_WO_FIFO_STATUS_CONST      : natural := 16#00A#;
    constant HUB_CSR_WO_DOWN_PKT_CNT_CONST     : natural := 16#00B#;
    constant HUB_CSR_WO_UP_PKT_CNT_CONST       : natural := 16#00C#;
    constant HUB_CSR_WO_DOWN_USEDW_CONST       : natural := 16#00D#;
    constant HUB_CSR_WO_UP_USEDW_CONST         : natural := 16#00E#;
    constant HUB_CSR_WO_EXT_PKT_RD_CNT_CONST   : natural := 16#00F#;
    constant HUB_CSR_WO_EXT_PKT_WR_CNT_CONST   : natural := 16#010#;
    constant HUB_CSR_WO_EXT_WORD_RD_CNT_CONST  : natural := 16#011#;
    constant HUB_CSR_WO_EXT_WORD_WR_CNT_CONST  : natural := 16#012#;
    constant HUB_CSR_WO_LAST_RD_ADDR_CONST     : natural := 16#013#;
    constant HUB_CSR_WO_LAST_RD_DATA_CONST     : natural := 16#014#;
    constant HUB_CSR_WO_LAST_WR_ADDR_CONST     : natural := 16#015#;
    constant HUB_CSR_WO_LAST_WR_DATA_CONST     : natural := 16#016#;
    constant HUB_ERR_UP_FIFO_OVERFLOW_CONST    : natural := 0;
    constant HUB_ERR_DOWN_FIFO_OVERFLOW_CONST  : natural := 1;
    constant HUB_ERR_INTERNAL_ADDR_CONST       : natural := 2;
    constant HUB_ERR_RD_TIMEOUT_CONST          : natural := 3;

    function pack_version_func (
        constant version_yy    : natural;
        constant version_major : natural;
        constant version_pre   : natural;
        constant version_month : natural;
        constant version_day   : natural
    ) return std_logic_vector is
        variable version_v : unsigned(31 downto 0);
    begin
        version_v                  := (others => '0');
        version_v(31 downto 24)    := to_unsigned(version_yy, 8);
        version_v(23 downto 18)    := to_unsigned(version_major, 6);
        version_v(17 downto 16)    := to_unsigned(version_pre, 2);
        version_v(15 downto 8)     := to_unsigned(version_month, 8);
        version_v(7 downto 0)      := to_unsigned(version_day, 8);
        return std_logic_vector(version_v);
    end function pack_version_func;

    function sat_inc32_func (
        constant value_in   : unsigned(31 downto 0)
    ) return unsigned is
    begin
        if (value_in = (value_in'range => '1')) then
            return value_in;
        else
            return value_in + 1;
        end if;
    end function sat_inc32_func;
    
    -- Address signals
    signal address_code       : std_logic_vector(15 downto 0);
    signal qsys_addr         : std_logic_vector(15 downto 0);
    signal qsys_addr_vld     : std_logic;
    signal internal_csr_hit  : std_logic;
    signal internal_csr_word_offset : std_logic_vector(15 downto 0);
    signal internal_csr_word_data   : std_logic_vector(31 downto 0);
    signal internal_csr_invalid_addr : std_logic;
    
    -- Link interface signals
    signal link_data_comb, link_data   : std_logic_vector(31 downto 0);
    signal link_datak_comb, link_datak : std_logic_vector(3 downto 0);
    signal link_en_comb, link_en       : std_logic;
    signal link_sop, link_eop          : std_logic;
    
    -- Control and status signals
    signal wr_word_cnt          : std_logic_vector(7 downto 0);
    signal isPreamble           : std_logic;
    signal isSkipWord           : std_logic;
    signal isTrailer            : std_logic;
    signal record_preamble_done : std_logic;
    signal record_head_done     : std_logic;
    signal record_length_done   : std_logic;
    signal send_trailer_done    : std_logic;
    signal read_trans_start     : std_logic;
    signal read_ack_done        : std_logic;
    signal send_preamble_done   : std_logic;
    signal send_addr_done       : std_logic;
    signal send_write_reply_done: std_logic;
    signal reset_done           : std_logic;
    signal reset_start          : std_logic;
    
    -- Avalon transaction control signals
    signal read_avstart         : std_logic;
    signal rd_trans_terminated  : std_logic;
    signal rd_trans_terminated_prev : std_logic;
    signal rd_timeout_cnt       : std_logic_vector(15 downto 0);
    signal av_rd_cmd_send_done  : std_logic;
    
    -- Write buffer control signals
    signal write_buff_ready     : std_logic;
    signal write_buff_done      : std_logic;
    signal wr_trans_done        : std_logic;
    signal rd_trans_done        : std_logic;
    signal burst_write_avstart  : std_logic;
    signal write_av_waitforcomp : std_logic;
    signal wr_trans_cnt         : std_logic_vector(7 downto 0);
    signal rd_trans_cnt         : std_logic_vector(7 downto 0);
        
    -- Acknowledge control signals
    signal rd_ack_start        : std_logic;
    signal read_ack_almostdone : std_logic;
    signal rd_response         : std_logic_vector(1 downto 0);  -- Read response status
    signal wr_response         : std_logic_vector(1 downto 0);  -- Write response status
    signal rd_ack_word_cnt     : std_logic_vector(7 downto 0);

    -- FIFO interface signals
    signal wr_fifo_din        : std_logic_vector(31 downto 0);
    signal rd_fifo_din        : std_logic_vector(31 downto 0);
    signal wr_fifo_wrreq      : std_logic;
    signal rd_fifo_wrreq      : std_logic;
    signal wr_fifo_rdreq      : std_logic;
    signal rd_fifo_rdreq      : std_logic;
    signal wr_fifo_dout       : std_logic_vector(31 downto 0);
    signal rd_fifo_dout       : std_logic_vector(31 downto 0);
    signal wr_fifo_empty      : std_logic;
    signal rd_fifo_empty      : std_logic;
    signal wr_fifo_full       : std_logic;
    signal rd_fifo_full       : std_logic;
    signal wr_fifo_usedw      : std_logic_vector(7 downto 0);
    signal rd_fifo_usedw      : std_logic_vector(7 downto 0);
    signal wr_fifo_sclr       : std_logic;
    signal rd_fifo_sclr       : std_logic;
    
    -- Reset control
    signal sc_hub_reset_done : std_logic;
    signal hub_enable                    : std_logic;
    signal hub_flushing                  : std_logic;
    signal hub_scratch                   : std_logic_vector(31 downto 0);
    signal hub_err_flags                 : std_logic_vector(31 downto 0);
    signal hub_err_count                 : unsigned(31 downto 0);
    signal hub_gts_counter               : unsigned(47 downto 0);
    signal hub_gts_snapshot              : unsigned(47 downto 0);
    signal hub_download_store_forward    : std_logic;
    signal hub_upload_store_forward      : std_logic;
    signal hub_download_fifo_flush       : std_logic;
    signal hub_download_fifo_reset       : std_logic;
    signal hub_upload_fifo_flush         : std_logic;
    signal hub_upload_fifo_reset         : std_logic;
    signal hub_ext_pkt_read_count        : unsigned(31 downto 0);
    signal hub_ext_pkt_write_count       : unsigned(31 downto 0);
    signal hub_ext_word_read_count       : unsigned(31 downto 0);
    signal hub_ext_word_write_count      : unsigned(31 downto 0);
    signal hub_last_ext_read_addr        : std_logic_vector(31 downto 0);
    signal hub_last_ext_read_data        : std_logic_vector(31 downto 0);
    signal hub_last_ext_write_addr       : std_logic_vector(31 downto 0);
    signal hub_last_ext_write_data       : std_logic_vector(31 downto 0);
    signal hub_csr_write_valid           : std_logic;
    signal hub_csr_write_offset          : std_logic_vector(15 downto 0);
    signal hub_csr_write_data            : std_logic_vector(31 downto 0);
    signal hub_csr_snapshot_req          : std_logic;
    signal hub_ext_pkt_read_inc          : std_logic;
    signal hub_ext_pkt_write_inc         : std_logic;
    signal hub_ext_read_capture          : std_logic;
    signal hub_ext_read_capture_addr     : std_logic_vector(31 downto 0);
    signal hub_ext_read_capture_data     : std_logic_vector(31 downto 0);
    signal hub_ext_write_capture         : std_logic;
    signal hub_ext_write_capture_addr    : std_logic_vector(31 downto 0);
    signal hub_ext_write_capture_data    : std_logic_vector(31 downto 0);
    signal hub_invalid_access_pulse      : std_logic;
    
    -- Special character for skip word detection
    signal skipWord_charac   : std_logic_vector(31 downto 0) := "00000000000000000000000010111100"; 
    
    -- Packet information record type
    type sc_pkt_info_t is record
        sc_type         : std_logic_vector(1 downto 0);
        fpga_id         : std_logic_vector(15 downto 0);
        mask_m          : std_logic;
        mask_s          : std_logic;
        mask_t          : std_logic;
        mask_r          : std_logic;
        start_address   : std_logic_vector(23 downto 0);
        rw_length       : std_logic_vector(15 downto 0);
    end record;
    
    signal sc_pkt_info      : sc_pkt_info_t;
    
    -- State machine types
    type sc_hub_state_t is (IDLE, RECORD_HEADER, RUNNING_HEAD, RUNNING_READ, 
                           RUNNING_WRITE, RUNNING_TRAILER, REPLY, RESET);
    signal sc_hub_state     : sc_hub_state_t := RESET;
    
    type ack_state_t is (IDLE, PREAMBLE, ADDR, WR_ACK, RD_ACK, TRAILER, RESET);
    signal ack_state        : ack_state_t;
    
    type read_ack_flow_t is (S1, S2, IDLE);
    signal read_ack_flow    : read_ack_flow_t;
    
    type ath_state_t is (AV_RD, AV_WR, INT_RD, INT_WR, RESET, IDLE);
    signal ath_state        : ath_state_t;
    
    -- FIFO component declaration
    component alt_fifo_w32d256
    port(
        clock        : in  std_logic;
        data         : in  std_logic_vector(31 downto 0);
        rdreq        : in  std_logic;
        sclr         : in  std_logic;
        wrreq        : in  std_logic;
        empty        : out std_logic;
        full         : out std_logic;
        q            : out std_logic_vector(31 downto 0);
        usedw        : out std_logic_vector(7 downto 0)
    );
    end component;

begin
    internal_csr_hit <= '1' when (
        to_integer(unsigned(sc_pkt_info.start_address(15 downto 0))) >= HUB_CSR_BASE_ADDR_CONST and
        to_integer(unsigned(sc_pkt_info.start_address(15 downto 0))) < (HUB_CSR_BASE_ADDR_CONST + HUB_CSR_WINDOW_WORDS_CONST)
    ) else '0';
    internal_csr_word_offset <= std_logic_vector(unsigned(sc_pkt_info.start_address(15 downto 0)) - to_unsigned(HUB_CSR_BASE_ADDR_CONST, internal_csr_word_offset'length));

    o_download_fifo_flush        <= hub_download_fifo_flush;
    o_download_fifo_reset        <= hub_download_fifo_reset;
    o_download_store_and_forward <= hub_download_store_forward;
    o_upload_fifo_flush          <= hub_upload_fifo_flush;
    o_upload_fifo_reset          <= hub_upload_fifo_reset;
    o_upload_store_and_forward   <= hub_upload_store_forward;

    proc_internal_csr_read : process(all)
        variable csr_word_offset_v : natural;
        variable csr_status_v      : std_logic_vector(31 downto 0);
        variable fifo_status_v     : std_logic_vector(31 downto 0);
    begin
        csr_word_offset_v           := to_integer(unsigned(internal_csr_word_offset));
        internal_csr_word_data      <= (others => '0');
        internal_csr_invalid_addr   <= '0';
        csr_status_v                := (others => '0');
        fifo_status_v               := (others => '0');

        csr_status_v(0)             := hub_enable;
        if (sc_hub_state /= IDLE or ath_state /= IDLE or unsigned(i_download_fifo_pkt_count) /= 0 or unsigned(i_upload_fifo_pkt_count) /= 0) then
            csr_status_v(1)         := '1';
        end if;
        if (hub_err_flags /= (hub_err_flags'range => '0')) then
            csr_status_v(2)         := '1';
        end if;
        csr_status_v(3)             := hub_flushing;

        fifo_status_v(0)            := hub_download_store_forward;
        fifo_status_v(1)            := hub_upload_store_forward;
        fifo_status_v(8)            := i_download_fifo_full;
        fifo_status_v(9)            := i_upload_fifo_full;

        case csr_word_offset_v is
            when HUB_CSR_WO_ID_CONST =>
                internal_csr_word_data <= HUB_CSR_ID_CONST;

            when HUB_CSR_WO_VERSION_CONST =>
                internal_csr_word_data <= pack_version_func(
                    HUB_CSR_VERSION_YY_CONST,
                    HUB_CSR_VERSION_MAJOR_CONST,
                    HUB_CSR_VERSION_PRE_CONST,
                    HUB_CSR_VERSION_MONTH_CONST,
                    HUB_CSR_VERSION_DAY_CONST
                );

            when HUB_CSR_WO_CTRL_CONST =>
                internal_csr_word_data(0) <= hub_enable;
                internal_csr_word_data(1) <= hub_flushing;

            when HUB_CSR_WO_STATUS_CONST =>
                internal_csr_word_data <= csr_status_v;

            when HUB_CSR_WO_ERR_FLAGS_CONST =>
                internal_csr_word_data <= hub_err_flags;

            when HUB_CSR_WO_ERR_COUNT_CONST =>
                internal_csr_word_data <= std_logic_vector(hub_err_count);

            when HUB_CSR_WO_SCRATCH_CONST =>
                internal_csr_word_data <= hub_scratch;

            when HUB_CSR_WO_GTS_SNAP_LO_CONST =>
                internal_csr_word_data <= std_logic_vector(hub_gts_counter(31 downto 0));

            when HUB_CSR_WO_GTS_SNAP_HI_CONST =>
                internal_csr_word_data(15 downto 0) <= std_logic_vector(hub_gts_snapshot(47 downto 32));

            when HUB_CSR_WO_FIFO_CFG_CONST =>
                internal_csr_word_data(0) <= hub_download_store_forward;
                internal_csr_word_data(1) <= hub_upload_store_forward;

            when HUB_CSR_WO_FIFO_STATUS_CONST =>
                internal_csr_word_data <= fifo_status_v;

            when HUB_CSR_WO_DOWN_PKT_CNT_CONST =>
                internal_csr_word_data(8 downto 0) <= i_download_fifo_pkt_count;

            when HUB_CSR_WO_UP_PKT_CNT_CONST =>
                internal_csr_word_data(8 downto 0) <= i_upload_fifo_pkt_count;

            when HUB_CSR_WO_DOWN_USEDW_CONST =>
                internal_csr_word_data(8 downto 0) <= i_download_fifo_usedw;

            when HUB_CSR_WO_UP_USEDW_CONST =>
                internal_csr_word_data(8 downto 0) <= i_upload_fifo_usedw;

            when HUB_CSR_WO_EXT_PKT_RD_CNT_CONST =>
                internal_csr_word_data <= std_logic_vector(hub_ext_pkt_read_count);

            when HUB_CSR_WO_EXT_PKT_WR_CNT_CONST =>
                internal_csr_word_data <= std_logic_vector(hub_ext_pkt_write_count);

            when HUB_CSR_WO_EXT_WORD_RD_CNT_CONST =>
                internal_csr_word_data <= std_logic_vector(hub_ext_word_read_count);

            when HUB_CSR_WO_EXT_WORD_WR_CNT_CONST =>
                internal_csr_word_data <= std_logic_vector(hub_ext_word_write_count);

            when HUB_CSR_WO_LAST_RD_ADDR_CONST =>
                internal_csr_word_data <= hub_last_ext_read_addr;

            when HUB_CSR_WO_LAST_RD_DATA_CONST =>
                internal_csr_word_data <= hub_last_ext_read_data;

            when HUB_CSR_WO_LAST_WR_ADDR_CONST =>
                internal_csr_word_data <= hub_last_ext_write_addr;

            when HUB_CSR_WO_LAST_WR_DATA_CONST =>
                internal_csr_word_data <= hub_last_ext_write_data;

            when others =>
                internal_csr_invalid_addr <= '1';
        end case;
    end process proc_internal_csr_read;

    proc_hub_diag_regs : process(i_clk, i_rst)
        variable csr_write_offset_v : natural;
    begin
        if (i_rst = '1') then
            hub_enable                 <= '1';
            hub_flushing               <= '0';
            hub_scratch                <= (others => '0');
            hub_err_flags              <= (others => '0');
            hub_err_count              <= (others => '0');
            hub_gts_counter            <= (others => '0');
            hub_gts_snapshot           <= (others => '0');
            hub_download_store_forward <= '1';
            hub_upload_store_forward   <= '1';
            hub_download_fifo_flush    <= '0';
            hub_download_fifo_reset    <= '0';
            hub_upload_fifo_flush      <= '0';
            hub_upload_fifo_reset      <= '0';
            hub_ext_pkt_read_count     <= (others => '0');
            hub_ext_pkt_write_count    <= (others => '0');
            hub_ext_word_read_count    <= (others => '0');
            hub_ext_word_write_count   <= (others => '0');
            hub_last_ext_read_addr     <= (others => '0');
            hub_last_ext_read_data     <= (others => '0');
            hub_last_ext_write_addr    <= (others => '0');
            hub_last_ext_write_data    <= (others => '0');
            rd_trans_terminated_prev   <= '0';
        elsif rising_edge(i_clk) then
            hub_gts_counter          <= hub_gts_counter + 1;
            hub_download_fifo_flush  <= '0';
            hub_download_fifo_reset  <= '0';
            hub_upload_fifo_flush    <= '0';
            hub_upload_fifo_reset    <= '0';

            if (hub_flushing = '1' and unsigned(i_download_fifo_pkt_count) = 0 and unsigned(i_upload_fifo_pkt_count) = 0) then
                hub_flushing         <= '0';
            end if;

            if (hub_csr_snapshot_req = '1') then
                hub_gts_snapshot     <= hub_gts_counter;
            end if;

            if (hub_ext_pkt_read_inc = '1') then
                hub_ext_pkt_read_count <= sat_inc32_func(hub_ext_pkt_read_count);
            end if;

            if (hub_ext_pkt_write_inc = '1') then
                hub_ext_pkt_write_count <= sat_inc32_func(hub_ext_pkt_write_count);
            end if;

            if (hub_ext_read_capture = '1') then
                hub_ext_word_read_count <= sat_inc32_func(hub_ext_word_read_count);
                hub_last_ext_read_addr  <= hub_ext_read_capture_addr;
                hub_last_ext_read_data  <= hub_ext_read_capture_data;
            end if;

            if (hub_ext_write_capture = '1') then
                hub_ext_word_write_count <= sat_inc32_func(hub_ext_word_write_count);
                hub_last_ext_write_addr  <= hub_ext_write_capture_addr;
                hub_last_ext_write_data  <= hub_ext_write_capture_data;
            end if;

            if (hub_invalid_access_pulse = '1') then
                hub_err_flags(HUB_ERR_INTERNAL_ADDR_CONST) <= '1';
                hub_err_count                              <= sat_inc32_func(hub_err_count);
            end if;

            if (hub_csr_write_valid = '1') then
                csr_write_offset_v := to_integer(unsigned(hub_csr_write_offset));
                case csr_write_offset_v is
                    when HUB_CSR_WO_CTRL_CONST =>
                        hub_enable <= hub_csr_write_data(0);

                        if (hub_csr_write_data(1) = '1') then
                            hub_flushing            <= '1';
                            hub_download_fifo_flush <= '1';
                            hub_upload_fifo_flush   <= '1';
                        end if;

                        if (hub_csr_write_data(2) = '1') then
                            hub_flushing               <= '0';
                            hub_download_fifo_reset    <= '1';
                            hub_upload_fifo_reset      <= '1';
                            hub_err_flags              <= (others => '0');
                            hub_err_count              <= (others => '0');
                            hub_gts_counter            <= (others => '0');
                            hub_gts_snapshot           <= (others => '0');
                            hub_ext_pkt_read_count     <= (others => '0');
                            hub_ext_pkt_write_count    <= (others => '0');
                            hub_ext_word_read_count    <= (others => '0');
                            hub_ext_word_write_count   <= (others => '0');
                            hub_last_ext_read_addr     <= (others => '0');
                            hub_last_ext_read_data     <= (others => '0');
                            hub_last_ext_write_addr    <= (others => '0');
                            hub_last_ext_write_data    <= (others => '0');
                        end if;

                    when HUB_CSR_WO_ERR_FLAGS_CONST =>
                        hub_err_flags <= hub_err_flags and not hub_csr_write_data;

                    when HUB_CSR_WO_SCRATCH_CONST =>
                        hub_scratch <= hub_csr_write_data;

                    when HUB_CSR_WO_FIFO_CFG_CONST =>
                        hub_download_store_forward <= hub_csr_write_data(0);
                        hub_upload_store_forward   <= hub_csr_write_data(1);

                    when others =>
                        null;
                end case;
            end if;

            if (i_download_fifo_overflow = '1') then
                hub_err_flags(HUB_ERR_DOWN_FIFO_OVERFLOW_CONST) <= '1';
                hub_err_count                                   <= sat_inc32_func(hub_err_count);
            end if;

            if (i_upload_fifo_overflow = '1') then
                hub_err_flags(HUB_ERR_UP_FIFO_OVERFLOW_CONST) <= '1';
                hub_err_count                                 <= sat_inc32_func(hub_err_count);
            end if;

            if (rd_trans_terminated = '1' and rd_trans_terminated_prev = '0') then
                hub_err_flags(HUB_ERR_RD_TIMEOUT_CONST) <= '1';
                hub_err_count                           <= sat_inc32_func(hub_err_count);
            end if;

            rd_trans_terminated_prev <= rd_trans_terminated;
        end if;
    end process proc_hub_diag_regs;

    -- Time Interleaving of Multiple State Machines (hub main, avmm handler, ack)
    -- Description: 
    --     It is allowed for the write avmm handler to start while commands are being received,
    --     during which the data buffering will be kept by the local alt_fifo.
    --     For the read commands, since only start address is needed, the read avmm handler
    --     can start immediate the address and burst count is given.
    --     However, in both cases, the acknowledge state machine must start once the avmm
    --     transaction is completed. This lock mechanism will not create back-pressure on
    --     the SC_Link side (no IDLE words in ack packet), but it will induce back-pressure
    --     on the qsys bus side, which will be absorbed elastically by qsys interconnect and
    --     the local alt_fifo.
    -- 
    -- TODO:
    --       [ ] 1) add wrapper level for buffering the commands, currently only one cmd accepted until
    --              ack packet is sent.
    --
    -- Notation: ~~: idle wait
    --				 ||: wait until other process finishes
    --           |->: callback to start other process
    -- =======================================================================================================
    -- WRITE FLOW:
    -- [cmd]: main state machine => write handler -> FIFO~~||
    --		        |(fifo not empty)                        ||
    --            |->         FIFO -> write handler -> AVMM||
    -- [ack]:                                              ||(wr_trans_done)
    --                                                     |||->ack state machine -> SC_Link
    -- =======================================================================================================
    -- READ FLOW:									
    -- [cmd]: main state machine => read handler||
    --                                          ||
    --                                          ||FIFO <- read handler <- AVMM||(rd_trans_done)
    -- [ack]:                                                                 ||->ack state machine -> SC_Link
    -- =======================================================================================================
    -- ────────────────────────────────────────────────────────────────────────────────────────────────
    -- Write FIFO (wr_fifo)
    -- ────────────────────────────────────────────────────────────────────────────────────────────────
    alt_wr_fifo : alt_fifo_w32d256 
    port map(
        clock    => i_clk,
        data     => wr_fifo_din,
        rdreq    => wr_fifo_rdreq,
        sclr     => wr_fifo_sclr,
        wrreq    => wr_fifo_wrreq,
        empty    => wr_fifo_empty,
        full     => wr_fifo_full,
        q        => wr_fifo_dout,
        usedw    => wr_fifo_usedw
    );
    
    -- ────────────────────────────────────────────────────────────────────────────────────────────────
    -- Read FIFO (rd_fifo)
    -- ────────────────────────────────────────────────────────────────────────────────────────────────
    alt_rd_fifo : alt_fifo_w32d256
    port map(
        clock    => i_clk,
        data     => rd_fifo_din,
        rdreq    => rd_fifo_rdreq,
        sclr     => rd_fifo_sclr,
        wrreq    => rd_fifo_wrreq,
        empty    => rd_fifo_empty,
        full     => rd_fifo_full,
        q        => rd_fifo_dout,
        usedw    => rd_fifo_usedw
    );
    
    -- ────────────────────────────────────────────────────────────────────────────────────────────────
    -- @name            EGRESS MAPPER
    -- @brief           map the egress signal to output interface 
    -- @input           link_data, link_datak, link_en, link_sop, link_eop, rd_fifo_rdreq, rd_fifo_dout
    -- @output          o_linkout_data, o_linkout_datak, o_linkout_en, o_linkout_sop, o_linkout_eop
    -- @description     Registers all output signals and handle switchover during transmitting reply packet
    -- ────────────────────────────────────────────────────────────────────────────────────────────────
    proc_egress_mapper : process(i_clk, i_rst)
    begin
        if (i_rst = '1') then
            -- reset output 
            o_linkout_data    <= (others => '0');
            o_linkout_datak   <= (others => '0');
            o_linkout_en      <= '0';
            o_linkout_sop     <= '0';
            o_linkout_eop     <= '0';
        else 
            -- conn.
            -- > ack generator
            -- during non-data segments
            o_linkout_data    <= link_data;
            o_linkout_datak   <= link_datak;
            o_linkout_en      <= link_en;
            o_linkout_sop     <= link_sop;
            o_linkout_eop     <= link_eop;

            -- during data segments
            if rd_fifo_rdreq then -- -> read fifo
                o_linkout_data		<= rd_fifo_dout;
                o_linkout_datak		<= "0000";
            end if;
        end if;
    end process;    
    ----------------------------------------------------------------------------
    -- Process: Main State Machine
    -- Description: Controls the overall operation flow of the slow control hub
    ----------------------------------------------------------------------------
    proc_fsm : process(i_clk, i_rst)
    begin
        if (i_rst = '1') then
            sc_hub_state    <= RESET;
        elsif rising_edge(i_clk) then
            case sc_hub_state is 
                when IDLE =>
                    -- Wait for new packet, ignore commands until previous ack is done
                    if (isPreamble = '1') then
                        sc_hub_state  <= RECORD_HEADER;
                    end if;
                    o_linkin_ready  <= '1';    -- Accept new packet
                    
                when RECORD_HEADER =>
                    -- Determine operation type (read/write) from header
                    if (sc_pkt_info.sc_type(0) = '0' and (isSkipWord = '0')) then 
                        sc_hub_state  <= RUNNING_READ;
                    elsif (not isSkipWord) then
                        sc_hub_state  <= RUNNING_WRITE;
                    end if;
                when RUNNING_READ => 
                    -- Wait for the explicit trailer after the read-length word.
                    if (record_length_done = '1' and isTrailer = '1') then 
                        sc_hub_state   <= RUNNING_TRAILER;
                        o_linkin_ready <= '0';    -- Stall new packet while processing
                    end if;
                    
                when RUNNING_WRITE =>
                    -- Wait for write data and validate length
                    if (record_length_done = '1' and 
                        to_integer(unsigned(wr_word_cnt)) = to_integer(unsigned(sc_pkt_info.rw_length)) and 
                        isTrailer = '1') then
                        sc_hub_state   <= RUNNING_TRAILER;
                        o_linkin_ready <= '0';    -- Stall new packet while processing
                    end if;
                    
                when RUNNING_TRAILER =>
                    -- Delay state to ensure proper trailer timing
                    sc_hub_state <= REPLY;
                    
                when REPLY =>
                    -- Handle completion conditions
                    if (send_trailer_done = '1' or rd_trans_terminated = '1') then
                        sc_hub_state <= RESET;
                    end if;
                    
                when RESET =>
                    -- Wait for reset sequence completion
                    if (sc_hub_reset_done = '1') then
                        sc_hub_state   <= IDLE;
                    end if;
                    o_linkin_ready <= '0';    -- Stall new packets during reset
                    
                when others =>
                    -- Recover from invalid states
                    sc_hub_state <= RESET;
            end case;
        end if;
    end process proc_fsm;
    
-- === part 1: RECEIVING the commands
    
    proc_fsm_regs : process(i_clk,i_rst)
    begin
        if (i_rst = '1') then
            hub_ext_pkt_read_inc  <= '0';
            hub_ext_pkt_write_inc <= '0';
        elsif (rising_edge(i_clk))  then 
            hub_ext_pkt_read_inc  <= '0';
            hub_ext_pkt_write_inc <= '0';
            case sc_hub_state is
                when RESET =>
                    if (rd_trans_terminated = '1') then
                        avm_m0_flush	<= '1'; -- flush the unfinished read pipeline transaction, if addressed unspecified region, removed in spec 1.2
                    else
                        avm_m0_flush	<= '0';
                    end if;
                    ath_state						<= RESET;	
                    --o_linkin_ready					<= '0';
                    read_trans_start				<= '0';
                    write_buff_ready				<= '0';
                    write_buff_done					<= '0';
                    ack_state						<= RESET;
                    sc_pkt_info.sc_type				<= (others=>'0');
                    sc_pkt_info.fpga_id				<= std_logic_vector(to_unsigned(2,sc_pkt_info.fpga_id'length)); 
                    record_preamble_done			<= '0';
                    sc_pkt_info.start_address		<= (others=>'0');
                    sc_pkt_info.mask_m				<= '0';
                    sc_pkt_info.mask_s				<= '0';
                    sc_pkt_info.mask_t				<= '0';
                    sc_pkt_info.mask_r				<= '0';
                    record_head_done				<= '0';
                    sc_pkt_info.rw_length			<= (others=>'0');
                    record_length_done				<= '0';
                    wr_fifo_din						<= (others=>'0');
                    wr_word_cnt						<= (others=>'0');
                    wr_fifo_wrreq					<= '0';
                when IDLE =>
                    avm_m0_flush					<= '0';
                    ath_state						<= IDLE;
                    ack_state						<= IDLE;
                    read_trans_start               <= '0';
                    --o_linkin_ready					<= '1';
                    if (isPreamble = '1' and record_preamble_done = '0' and (isSkipWord='0')) then
                        sc_pkt_info.sc_type		<= i_linkin_data(25 downto 24);
                        sc_pkt_info.fpga_id		<= i_linkin_data(23 downto 8);
                        record_preamble_done		<= '1';
                        -- o_linkin_ready				<= '0';
                    end if;
                when RECORD_HEADER =>
                    if (record_head_done = '0' and (isSkipWord='0')) then 
                        sc_pkt_info.start_address		<= i_linkin_data(23 downto 0);
                        sc_pkt_info.mask_m				<= i_linkin_data(27);
                        sc_pkt_info.mask_s				<= i_linkin_data(26);
                        sc_pkt_info.mask_t				<= i_linkin_data(25);
                        sc_pkt_info.mask_r				<= i_linkin_data(24);
                        record_head_done				<= '1';
                    end if;
                when RUNNING_READ =>
                    read_trans_start               <= '0';
                    if (isSkipWord='0') then
                        if (record_length_done = '0') then
                            read_trans_start		<= '1';
                            sc_pkt_info.rw_length	<= i_linkin_data(15 downto 0);
                            record_length_done		<= '1';
                            if (internal_csr_hit = '1') then
                                ath_state		<= INT_RD;
                            else
                                ath_state		<= AV_RD;
                                hub_ext_pkt_read_inc <= '1';
                            end if;
                        end if;
                    end if;
                when RUNNING_WRITE => 
                    -- burst write / 
                    -- non-burst write (treated as burst write length=1)
                    if (isSkipWord='0') then
                        write_buff_ready		<= '1';
                        if (record_length_done = '0') then
                            sc_pkt_info.rw_length	<= i_linkin_data(15 downto 0);
                            record_length_done		<= '1';
                            if (internal_csr_hit = '1') then
                                ath_state		<= INT_WR;
                            else
                                ath_state		<= AV_WR;
                                hub_ext_pkt_write_inc <= '1';
                            end if;
                        end if;
                        if (to_integer(unsigned(wr_word_cnt)) < to_integer(unsigned(sc_pkt_info.rw_length)) and record_length_done='1') then 
                        -- this is case for the second cycle of receiving write command 
                            wr_fifo_wrreq		<= '1';
                            wr_fifo_din			<= i_linkin_data;
                            wr_word_cnt			<= conv_std_logic_vector(to_integer(unsigned(wr_word_cnt)) + 1, wr_word_cnt'length); 
                        elsif (record_length_done = '0') then
                        -- first cycle of one length write
                        else -- last cycle of running write, we reset everything
                            wr_fifo_wrreq		<= '0';
                            wr_word_cnt			<= conv_std_logic_vector(0, wr_word_cnt'length);
                            write_buff_done	<= '1';
                        end if;
                    else
                        wr_fifo_wrreq			<= '0';
                    end if;
                when RUNNING_TRAILER => 
                    --o_linkin_ready      <= '0'; -- deassert the ready to stop new packet coming in
                    -- TODO: confirm the packet structure is correct
                when REPLY =>
                    case ack_state is 
                        when IDLE => 
                            if ((wr_trans_done='1' or rd_trans_done='1') and send_trailer_done='0') then
                            -- prevent loop: haven't send trailer yet, so we start reply
                                ack_state	<= PREAMBLE;
                                ath_state	<= IDLE; -- it must NOT reset, until ack has done reading the fifo
                            end if;
                        when PREAMBLE =>
                            ack_state	<= ADDR;
                        when ADDR	=>
                            if (sc_pkt_info.sc_type(0) = '1') then 
                                ack_state	<= WR_ACK;
                            else
                                ack_state	<= RD_ACK;
                            end if;
                        when RD_ACK =>
                            if (read_ack_almostdone = '1') then
                                ack_state	<= TRAILER;
                            end if;
                        when WR_ACK =>					
                            ack_state	<= TRAILER;
                        when TRAILER =>
                            ack_state	<= RESET;
                        when RESET =>
                            ack_state	<= IDLE;
                        when others =>
                            ack_state	<= RESET;
                    end case;
                when others =>
                    -- do nothing 
                    -- illegal state, the main fsm will move it back to RESET, thus reset everything
            end case;
        end if;
    end process proc_fsm_regs;

    -- Avalon transaction handler (co-process as the main fsm)
    
    proc_wr_fifo2avmm_logic : process(all)
    begin -- the rdreq must be in sync with waitrequest, so no latency from the get from fifo to data available on bus
        if (burst_write_avstart = '1') then -- when avalon transaction starts
            if (wr_trans_done = '0') then
                avm_m0_writedata		<= wr_fifo_dout;
                if (wr_fifo_empty /= '1') then
                    avm_m0_write		<= '1';
                        if (avm_m0_waitrequest	= '0') then
                            wr_fifo_rdreq	<= '1';
                        else
                            wr_fifo_rdreq	<= '0';
                        end if;
                else
                    avm_m0_write		<= '0';
                    wr_fifo_rdreq		<= '0';
                end if;
            else -- transaction is completed as words are all transmitted
                avm_m0_writedata		<= (others=>'0');
                wr_fifo_rdreq			<= '0';
                avm_m0_write			<= '0';
            end if;
        else -- when the avalon transaction is permanently done
            avm_m0_writedata		<= (others=>'0');
            wr_fifo_rdreq			<= '0';
            avm_m0_write			<= '0';
        end if;
    end process proc_wr_fifo2avmm_logic;
    
    
    -- talk to qsys as a master 
    proc_read_write_trans : process(i_clk,i_rst)
        variable ext_rd_data_v     : std_logic_vector(31 downto 0);
        variable csr_word_offset_v : natural;
        variable local_word_v      : std_logic_vector(31 downto 0);
        variable csr_status_v      : std_logic_vector(31 downto 0);
        variable fifo_status_v     : std_logic_vector(31 downto 0);
    begin
        if (i_rst = '1') then
            avm_m0_address            <= (others => '0');
            avm_m0_read               <= '0';
            avm_m0_burstcount         <= (others => '0');
            read_avstart              <= '0';
            av_rd_cmd_send_done       <= '0';
            burst_write_avstart       <= '0';
            write_av_waitforcomp      <= '0';
            sc_hub_reset_done         <= '0';
            wr_trans_done             <= '0';
            rd_trans_done             <= '0';
            wr_trans_cnt              <= (others => '0');
            rd_trans_cnt              <= (others => '0');
            wr_fifo_sclr              <= '1';
            rd_fifo_sclr              <= '1';
            rd_fifo_wrreq             <= '0';
            rd_fifo_din               <= (others => '0');
            rd_timeout_cnt            <= (others => '0');
            rd_response               <= (others => '0');
            wr_response               <= (others => '0');
            rd_trans_terminated       <= '0';
            hub_csr_write_valid      <= '0';
            hub_csr_write_offset     <= (others => '0');
            hub_csr_write_data       <= (others => '0');
            hub_csr_snapshot_req     <= '0';
            hub_ext_read_capture     <= '0';
            hub_ext_read_capture_addr <= (others => '0');
            hub_ext_read_capture_data <= (others => '0');
            hub_ext_write_capture    <= '0';
            hub_ext_write_capture_addr <= (others => '0');
            hub_ext_write_capture_data <= (others => '0');
            hub_invalid_access_pulse <= '0';
        elsif rising_edge(i_clk) then
            hub_csr_write_valid        <= '0';
            hub_csr_write_offset       <= (others => '0');
            hub_csr_write_data         <= (others => '0');
            hub_csr_snapshot_req       <= '0';
            hub_ext_read_capture       <= '0';
            hub_ext_read_capture_addr  <= (others => '0');
            hub_ext_read_capture_data  <= (others => '0');
            hub_ext_write_capture      <= '0';
            hub_ext_write_capture_addr <= (others => '0');
            hub_ext_write_capture_data <= (others => '0');
            hub_invalid_access_pulse   <= '0';

            case ath_state is
                when AV_RD =>
                    wr_fifo_sclr         <= '0';
                    rd_fifo_sclr         <= '0';
                    burst_write_avstart  <= '0';
                    write_av_waitforcomp <= '0';

                    if (read_avstart = '0') then
                        avm_m0_address        <= conv_std_logic_vector(to_integer(unsigned(sc_pkt_info.start_address)), avm_m0_address'length);
                        avm_m0_burstcount     <= sc_pkt_info.rw_length(8 downto 0);
                        read_avstart          <= '1';
                        av_rd_cmd_send_done   <= '0';
                        avm_m0_read           <= '1';
                    elsif (av_rd_cmd_send_done = '0') then
                        if (avm_m0_waitrequest = '0') then
                            avm_m0_read           <= '0';
                            av_rd_cmd_send_done <= '1';
                        else
                            avm_m0_read           <= '1';
                        end if;
                    else
                        avm_m0_read           <= '0';
                    end if;

                    if (to_integer(unsigned(rd_trans_cnt)) < to_integer(unsigned(sc_pkt_info.rw_length))) then
                        if (rd_fifo_full /= '1' and avm_m0_readdatavalid = '1') then
                            if (avm_m0_response = "11") then
                                ext_rd_data_v := x"DEADBEEF";
                            elsif (avm_m0_response = "10") then
                                ext_rd_data_v := x"BBADBEEF";
                            else
                                ext_rd_data_v := avm_m0_readdata;
                            end if;

                            rd_trans_cnt               <= conv_std_logic_vector(to_integer(unsigned(rd_trans_cnt)) + 1, rd_trans_cnt'length);
                            rd_fifo_wrreq              <= '1';
                            rd_fifo_din                <= ext_rd_data_v;
                            rd_timeout_cnt             <= (others => '0');
                            hub_ext_read_capture       <= '1';
                            hub_ext_read_capture_addr  <= conv_std_logic_vector(to_integer(unsigned(sc_pkt_info.start_address)) + to_integer(unsigned(rd_trans_cnt)), 32);
                            hub_ext_read_capture_data  <= ext_rd_data_v;
                        else
                            rd_timeout_cnt             <= conv_std_logic_vector(to_integer(unsigned(rd_timeout_cnt)) + 1, rd_timeout_cnt'length);
                            rd_fifo_wrreq              <= '0';
                            rd_fifo_din                <= (others => '0');
                        end if;

                        if (avm_m0_readdatavalid = '1' and avm_m0_response /= "00") then
                            rd_response                <= avm_m0_response;
                        end if;

                        rd_trans_done                 <= '0';
                    else
                        rd_fifo_wrreq                  <= '0';
                        rd_fifo_din                    <= (others => '0');
                        rd_trans_done                  <= '1';
                    end if;

                    if (to_integer(unsigned(rd_timeout_cnt)) >= 200) then
                        rd_trans_terminated <= '1';
                    end if;

                when AV_WR =>
                    wr_fifo_sclr          <= '0';
                    rd_fifo_sclr          <= '0';
                    avm_m0_read           <= '0';
                    read_avstart          <= '0';
                    av_rd_cmd_send_done   <= '0';
                    rd_fifo_wrreq         <= '0';
                    rd_fifo_din           <= (others => '0');
                    if (write_av_waitforcomp = '0') then
                        avm_m0_address        <= conv_std_logic_vector(to_integer(unsigned(sc_pkt_info.start_address)), avm_m0_address'length);
                        avm_m0_burstcount     <= sc_pkt_info.rw_length(8 downto 0);
                        burst_write_avstart   <= '0';
                        write_av_waitforcomp  <= '1';
                    else
                        burst_write_avstart   <= '1';
                    end if;

                    if (to_integer(unsigned(wr_trans_cnt)) < to_integer(unsigned(sc_pkt_info.rw_length))) then
                        if (wr_fifo_rdreq = '1') then
                            wr_trans_cnt               <= conv_std_logic_vector(to_integer(unsigned(wr_trans_cnt)) + 1, wr_trans_cnt'length);
                            hub_ext_write_capture      <= '1';
                            hub_ext_write_capture_addr <= conv_std_logic_vector(to_integer(unsigned(sc_pkt_info.start_address)) + to_integer(unsigned(wr_trans_cnt)), 32);
                            hub_ext_write_capture_data <= wr_fifo_dout;
                        end if;
                    end if;

                    if (avm_m0_writeresponsevalid = '1') then
                        wr_response                  <= avm_m0_response;
                        wr_trans_done                <= '1';
                    end if;

                when INT_RD =>
                    wr_fifo_sclr         <= '0';
                    rd_fifo_sclr         <= '0';
                    avm_m0_read          <= '0';
                    read_avstart         <= '0';
                    av_rd_cmd_send_done  <= '0';
                    burst_write_avstart  <= '0';
                    rd_timeout_cnt       <= (others => '0');

                    if (to_integer(unsigned(rd_trans_cnt)) < to_integer(unsigned(sc_pkt_info.rw_length))) then
                        if (rd_fifo_full /= '1') then
                            csr_word_offset_v := to_integer(unsigned(internal_csr_word_offset)) + to_integer(unsigned(rd_trans_cnt));
                            local_word_v      := (others => '0');
                            csr_status_v      := (others => '0');
                            fifo_status_v     := (others => '0');

                            csr_status_v(0)   := hub_enable;
                            if (sc_hub_state /= IDLE or ath_state /= IDLE or unsigned(i_download_fifo_pkt_count) /= 0 or unsigned(i_upload_fifo_pkt_count) /= 0) then
                                csr_status_v(1) := '1';
                            end if;
                            if (hub_err_flags /= (hub_err_flags'range => '0')) then
                                csr_status_v(2) := '1';
                            end if;
                            csr_status_v(3)   := hub_flushing;

                            fifo_status_v(0)  := hub_download_store_forward;
                            fifo_status_v(1)  := hub_upload_store_forward;
                            fifo_status_v(8)  := i_download_fifo_full;
                            fifo_status_v(9)  := i_upload_fifo_full;

                            case csr_word_offset_v is
                                when HUB_CSR_WO_ID_CONST =>
                                    local_word_v := HUB_CSR_ID_CONST;
                                when HUB_CSR_WO_VERSION_CONST =>
                                    local_word_v := pack_version_func(
                                        HUB_CSR_VERSION_YY_CONST,
                                        HUB_CSR_VERSION_MAJOR_CONST,
                                        HUB_CSR_VERSION_PRE_CONST,
                                        HUB_CSR_VERSION_MONTH_CONST,
                                        HUB_CSR_VERSION_DAY_CONST
                                    );
                                when HUB_CSR_WO_CTRL_CONST =>
                                    local_word_v(0) := hub_enable;
                                    local_word_v(1) := hub_flushing;
                                when HUB_CSR_WO_STATUS_CONST =>
                                    local_word_v := csr_status_v;
                                when HUB_CSR_WO_ERR_FLAGS_CONST =>
                                    local_word_v := hub_err_flags;
                                when HUB_CSR_WO_ERR_COUNT_CONST =>
                                    local_word_v := std_logic_vector(hub_err_count);
                                when HUB_CSR_WO_SCRATCH_CONST =>
                                    local_word_v := hub_scratch;
                                when HUB_CSR_WO_GTS_SNAP_LO_CONST =>
                                    local_word_v := std_logic_vector(hub_gts_counter(31 downto 0));
                                    hub_csr_snapshot_req <= '1';
                                when HUB_CSR_WO_GTS_SNAP_HI_CONST =>
                                    local_word_v(15 downto 0) := std_logic_vector(hub_gts_snapshot(47 downto 32));
                                when HUB_CSR_WO_FIFO_CFG_CONST =>
                                    local_word_v(0) := hub_download_store_forward;
                                    local_word_v(1) := hub_upload_store_forward;
                                when HUB_CSR_WO_FIFO_STATUS_CONST =>
                                    local_word_v := fifo_status_v;
                                when HUB_CSR_WO_DOWN_PKT_CNT_CONST =>
                                    local_word_v(8 downto 0) := i_download_fifo_pkt_count;
                                when HUB_CSR_WO_UP_PKT_CNT_CONST =>
                                    local_word_v(8 downto 0) := i_upload_fifo_pkt_count;
                                when HUB_CSR_WO_DOWN_USEDW_CONST =>
                                    local_word_v(8 downto 0) := i_download_fifo_usedw;
                                when HUB_CSR_WO_UP_USEDW_CONST =>
                                    local_word_v(8 downto 0) := i_upload_fifo_usedw;
                                when HUB_CSR_WO_EXT_PKT_RD_CNT_CONST =>
                                    local_word_v := std_logic_vector(hub_ext_pkt_read_count);
                                when HUB_CSR_WO_EXT_PKT_WR_CNT_CONST =>
                                    local_word_v := std_logic_vector(hub_ext_pkt_write_count);
                                when HUB_CSR_WO_EXT_WORD_RD_CNT_CONST =>
                                    local_word_v := std_logic_vector(hub_ext_word_read_count);
                                when HUB_CSR_WO_EXT_WORD_WR_CNT_CONST =>
                                    local_word_v := std_logic_vector(hub_ext_word_write_count);
                                when HUB_CSR_WO_LAST_RD_ADDR_CONST =>
                                    local_word_v := hub_last_ext_read_addr;
                                when HUB_CSR_WO_LAST_RD_DATA_CONST =>
                                    local_word_v := hub_last_ext_read_data;
                                when HUB_CSR_WO_LAST_WR_ADDR_CONST =>
                                    local_word_v := hub_last_ext_write_addr;
                                when HUB_CSR_WO_LAST_WR_DATA_CONST =>
                                    local_word_v := hub_last_ext_write_data;
                                when others =>
                                    local_word_v            := x"EEEEEEEE";
                                    rd_response             <= "10";
                                    hub_invalid_access_pulse <= '1';
                            end case;

                            rd_fifo_wrreq <= '1';
                            rd_fifo_din   <= local_word_v;
                            rd_trans_cnt  <= conv_std_logic_vector(to_integer(unsigned(rd_trans_cnt)) + 1, rd_trans_cnt'length);

                            if (to_integer(unsigned(rd_trans_cnt)) + 1 >= to_integer(unsigned(sc_pkt_info.rw_length))) then
                                rd_trans_done <= '1';
                            else
                                rd_trans_done <= '0';
                            end if;
                        else
                            rd_fifo_wrreq <= '0';
                            rd_fifo_din   <= (others => '0');
                            rd_trans_done <= '0';
                        end if;
                    else
                        rd_fifo_wrreq <= '0';
                        rd_fifo_din   <= (others => '0');
                        rd_trans_done <= '1';
                    end if;

                when INT_WR =>
                    wr_fifo_sclr         <= '0';
                    rd_fifo_sclr         <= '0';
                    avm_m0_read          <= '0';
                    read_avstart         <= '0';
                    av_rd_cmd_send_done  <= '0';
                    burst_write_avstart  <= '0';
                    write_av_waitforcomp <= '0';
                    rd_fifo_wrreq        <= '0';
                    rd_fifo_din          <= (others => '0');
                    rd_timeout_cnt       <= (others => '0');

                    if (unsigned(sc_pkt_info.rw_length) /= 1) then
                        wr_response              <= "10";
                        hub_invalid_access_pulse <= '1';
                    elsif (wr_fifo_empty /= '1') then
                        csr_word_offset_v := to_integer(unsigned(internal_csr_word_offset));
                        wr_response       <= "00";

                        case csr_word_offset_v is
                            when HUB_CSR_WO_CTRL_CONST | HUB_CSR_WO_ERR_FLAGS_CONST | HUB_CSR_WO_SCRATCH_CONST | HUB_CSR_WO_FIFO_CFG_CONST =>
                                hub_csr_write_valid  <= '1';
                                hub_csr_write_offset <= internal_csr_word_offset;
                                hub_csr_write_data   <= wr_fifo_dout;
                            when others =>
                                wr_response          <= "10";
                                hub_invalid_access_pulse <= '1';
                        end case;
                    else
                        wr_response              <= "10";
                        hub_invalid_access_pulse <= '1';
                    end if;

                    wr_trans_done               <= '1';

                when RESET =>
                    avm_m0_read             <= '0';
                    read_avstart            <= '0';
                    av_rd_cmd_send_done     <= '0';
                    burst_write_avstart     <= '0';
                    write_av_waitforcomp    <= '0';
                    wr_trans_done           <= '0';
                    rd_trans_done           <= '0';
                    wr_trans_cnt            <= (others => '0');
                    avm_m0_address          <= (others => '0');
                    avm_m0_burstcount       <= (others => '0');
                    rd_trans_cnt            <= (others => '0');
                    wr_fifo_sclr            <= '1';
                    rd_fifo_sclr            <= '1';
                    rd_fifo_wrreq           <= '0';
                    rd_timeout_cnt          <= (others => '0');
                    rd_response             <= (others => '0');
                    wr_response             <= (others => '0');

                    if (wr_fifo_empty = '1') then
                        sc_hub_reset_done   <= '1';
                    else
                        sc_hub_reset_done   <= '0';
                    end if;

                when IDLE =>
                    avm_m0_read             <= '0';
                    read_avstart            <= '0';
                    av_rd_cmd_send_done     <= '0';
                    burst_write_avstart     <= '0';
                    write_av_waitforcomp    <= '0';
                    rd_fifo_wrreq           <= '0';
                    rd_fifo_din             <= (others => '0');
                    rd_trans_terminated     <= '0';
                    sc_hub_reset_done       <= '0';
                    wr_fifo_sclr            <= '0';
                    rd_fifo_sclr            <= '0';

                when others =>
                    rd_trans_terminated     <= '1';
            end case;
        end if;
    end process proc_read_write_trans;
    
-- === part 2: REPLYING the commands

    -- dump qsys -> rdfifo -> upload packet (data section)
    proc_rd_fifo2acklink_logic : process(all)
    begin
        -- default 
        link_data_comb(31 downto 8)	<= (others => '0'); -- send comma word
        link_data_comb(7 downto 0)		<= K285;
        link_datak_comb					<= "0001";
        link_en_comb					<= '0';	
        -- logic (connects rdfifo q <-> link)
        if (read_ack_flow = S2) then -- be mindful: this state is comb out!
            if (to_integer(unsigned(rd_ack_word_cnt)) <= to_integer(unsigned(sc_pkt_info.rw_length))-1) then
                if (rd_fifo_empty /= '1') then
                    -- 1) in good transaction state
                    link_data_comb		<= rd_fifo_dout;
                    link_datak_comb		<= "0000";
                    link_en_comb		<= '1';				
                else 
                    -- 2) read fifo underflow, critical error, but we continue...
                    link_data_comb		<= x"CCCCCCCC"; -- wiki: Used by Microsoft's C++ debugging runtime library and many DOS environments to mark uninitialized stack memory.
                    link_datak_comb		<= "0000";
                    link_en_comb		<= '1';			
                end if;
            end if;
        end if;	
        
        -- alert almost done so the ack_state can do RD_ACK -> TRAILER the data has been read out from rd fifo
        -- this alert is at the last word of the rd fifo, so no slack state is between RD_ACK and TRAILER to remove bubble in upload packet.
        read_ack_almostdone	<= '0';
        if (to_integer(unsigned(sc_pkt_info.rw_length)) = 1) then 
            if (read_ack_flow = S2) then 
                read_ack_almostdone     <= '1';
            end if;
        elsif (to_integer(unsigned(sc_pkt_info.rw_length)) > 1) then 
            if (to_integer(unsigned(sc_pkt_info.rw_length)) - to_integer(unsigned(rd_ack_word_cnt)) <= 1) then 
                read_ack_almostdone     <= '1';
            end if;
        end if;
    end process;
    
    -- assemble slow control reply packet 
    proc_ack_fsm_regs : process(i_clk,i_rst)
    begin
        if (i_rst = '1') then
        
        elsif rising_edge(i_clk) then 
            -- default 
            link_data           <= (others => '0');
            link_datak          <= (others => '0');
            link_en             <= '0';
            link_eop            <= '0';
            link_sop            <= '0';


            case ack_state is
                when PREAMBLE =>
                    link_eop					<= '0';
                    if (send_preamble_done = '0') then
                        link_data				<= "000111" & sc_pkt_info.sc_type & sc_pkt_info.fpga_id & K285;
                        link_datak				<= "0001";
                        link_en					<= '1';
                        link_sop				<= '1';
                        send_preamble_done	<= '1';
                    else
                        link_en					<= '0'; -- toggle the link_en
                        link_sop				<= '0';
                    end if;
                when ADDR =>
                    link_sop					<= '0';
                    if (send_addr_done = '0') then
                        link_data(23 downto 0) 		<= sc_pkt_info.start_address;
                        link_data(31 downto 24)		<= (others=>'0');
                        link_datak					<= "0000";
                        link_en						<= '1';
                        send_addr_done				<= '1';
                    else
                        link_en		<= '0'; -- toggle the link_en 
                    end if;
                    if (rd_trans_done = '1') then
                        read_ack_flow	<= S1;
                    end if;
                when RD_ACK => 
                    case read_ack_flow is
                        when S1 =>
                            link_data(15 downto 0)		<= sc_pkt_info.rw_length;
                            link_data(16)				<= '1';
                            link_data(29 downto 28)     <= rd_response; -- highest byte
                            link_datak					<= "0000";
                            link_en						<= '1';
                            read_ack_flow				<= S2;
                        when S2 =>
                            rd_ack_start				<= '1';
                            if (rd_fifo_empty /= '1') then
                                rd_ack_word_cnt				<= conv_std_logic_vector(to_integer(unsigned(rd_ack_word_cnt)) + 1, rd_ack_word_cnt'length);
                            end if;
                            link_data					<= link_data_comb;
                            link_datak					<= link_datak_comb;
                            link_en 					<= link_en_comb;
                            if (to_integer(unsigned(rd_ack_word_cnt)) = to_integer(unsigned(sc_pkt_info.rw_length))-1) then
                                -- almost finish read fifo
                                read_ack_flow	<= S2;
                                read_ack_done	<= '0';
                                rd_fifo_rdreq	<= '1';
                            elsif (to_integer(unsigned(rd_ack_word_cnt)) > to_integer(unsigned(sc_pkt_info.rw_length))-1) then
                                -- finish read fifo
                                read_ack_flow	<= IDLE;
                                read_ack_done	<= '1';
                                --rd_fifo_rdreq	<= '0';
                            else 
                                -- reading fifo
                                read_ack_flow	<= S2;
                                read_ack_done	<= '0';
                                if (rd_fifo_empty /= '1') then
                                    rd_fifo_rdreq		<= '1';
                                else 
                                    rd_fifo_rdreq		<= '0';
                                end if;
                            end if;
                        when IDLE =>
                            link_en				<= '0';
                            rd_fifo_rdreq		<= '0';
                        when others => 
                            null;
                    end case;
                when WR_ACK =>
                    if (send_write_reply_done = '0') then 
                        link_data(15 downto 0)		<= sc_pkt_info.rw_length;
                        link_data(16)				<= '1';
                        link_data(29 downto 28)     <= wr_response; -- highest byte
                        link_datak	                <= "0000";
                        link_en		                <= '1';
                        send_write_reply_done	<= '1';
                    elsif (send_write_reply_done = '1') then
                        link_en		<= '0'; -- toggle the link_en 
                    end if;
                when TRAILER =>
                    rd_fifo_rdreq			<= '0'; -- fix: shrink the rd_ack forward by 1 cycle
                    if (send_trailer_done = '0') then
                        link_eop							<= '1';
                        link_data(7 downto 0)			    <= K284;
                        link_data(31 downto 8)			    <= (others=>'0');
                        link_datak							<= "0001";
                        link_en								<= '1';
                        send_trailer_done					<= '1';
                    elsif (send_trailer_done = '1') then
                        link_eop							<= '0';
                        link_en								<= '0'; -- toggle the link_en 
                    end if;
                when RESET =>
                    link_sop						<= '0';
                    link_eop						<= '0';
                    rd_ack_start				<= '0';
                    rd_ack_word_cnt			<= (others=>'0');
                    send_preamble_done		<= '0';
                    link_data					<= (others=>'0');
                    link_datak					<= (others=>'0');
                    link_en						<= '0';
                    send_addr_done				<= '0';
                    read_ack_done				<= '0';
                    send_write_reply_done	<= '0';
                    send_trailer_done			<= '0';
                    read_ack_flow				<= IDLE;
                    rd_fifo_rdreq				<= '0';
                when IDLE =>
                    link_sop						<= '0';
                    link_eop						<= '0';
                    link_en						<= '0';
                    read_ack_done				<= '0';
                    send_write_reply_done	<= '0';
                    read_ack_flow				<= IDLE;
                when others =>
                    -- illegal state
                    -- fake send_trailer_done and the main fsm will move on
                    link_en				<= '0';
                    send_trailer_done	<= '1';
            end case;
            

        end if;
    end process proc_ack_fsm_regs;
        
-- === some utilities

    proc_preamble_det : process(all)
    begin
        if (i_linkin_data(31 downto 26)="000111" and i_linkin_data(7 downto 0)=K285 and i_linkin_datak="0001") then
            isPreamble <= '1';
        else 
            isPreamble	<= '0';
        end if;                                                                                                    
    end process proc_preamble_det;
    
    proc_skip_word_det : process(all)
    begin 
        if (i_linkin_data = skipWord_charac and i_linkin_datak="0001") then
            isSkipWord <= '1';
        else
            isSkipWord	<= '0';
        end if;
    end process proc_skip_word_det;

    proc_trailer_det : process(all)
    begin
        if (i_linkin_data(7 downto 0) = K284 and i_linkin_datak = "0001") then
            isTrailer <= '1';
        else
            isTrailer <= '0';
        end if;
    end process proc_trailer_det;

end architecture rtl;
