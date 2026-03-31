-- File name: sc_hub_core.vhd
-- Author: Yifeng Wang (yifenwan@phys.ethz.ch)
-- =======================================
-- Version : 26.2.1
-- Date    : 20260331
-- Change  : Add a software-reset pulse that clears datapath FIFOs and restores the core reset image.
-- =======================================
-- altera vhdl_input_version vhdl_2008

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sc_hub_pkg.all;

entity sc_hub_core is
    generic(
        DEBUG_G : natural := 1
    );
    port(
        i_clk                    : in  std_logic;
        i_rst                    : in  std_logic;
        i_pkt_valid              : in  std_logic;
        i_pkt_info               : in  sc_pkt_info_t;
        o_rx_ready               : out std_logic;
        o_soft_reset_pulse       : out std_logic;
        o_wr_data_rdreq          : out std_logic;
        i_wr_data_q              : in  std_logic_vector(31 downto 0);
        i_wr_data_empty          : in  std_logic;
        i_pkt_drop_count         : in  std_logic_vector(15 downto 0);
        i_pkt_drop_pulse         : in  std_logic;
        i_dl_fifo_usedw          : in  std_logic_vector(8 downto 0);
        i_dl_fifo_full           : in  std_logic;
        i_dl_fifo_overflow       : in  std_logic;
        i_dl_fifo_overflow_pulse : in  std_logic;
        i_bp_usedw               : in  std_logic_vector(ceil_log2_func(DEFAULT_BP_FIFO_DEPTH_CONST + 1) - 1 downto 0);
        i_bp_full                : in  std_logic;
        i_bp_overflow            : in  std_logic;
        i_bp_overflow_pulse      : in  std_logic;
        i_bp_pkt_count           : in  std_logic_vector(ceil_log2_func(DEFAULT_BP_FIFO_DEPTH_CONST + 1) - 1 downto 0);
        o_tx_reply_start         : out std_logic;
        o_tx_reply_info          : out sc_pkt_info_t;
        o_tx_reply_response      : out std_logic_vector(1 downto 0);
        o_tx_reply_has_data      : out std_logic;
        o_tx_reply_suppress      : out std_logic;
        i_tx_reply_ready         : in  std_logic;
        i_tx_reply_done          : in  std_logic;
        o_tx_data_valid          : out std_logic;
        o_tx_data_word           : out std_logic_vector(31 downto 0);
        i_tx_data_ready          : in  std_logic;
        o_bus_cmd_valid          : out std_logic;
        o_bus_cmd_is_read        : out std_logic;
        o_bus_cmd_address        : out std_logic_vector(15 downto 0);
        o_bus_cmd_length         : out std_logic_vector(15 downto 0);
        i_bus_cmd_ready          : in  std_logic;
        o_bus_wr_data_valid      : out std_logic;
        o_bus_wr_data            : out std_logic_vector(31 downto 0);
        i_bus_wr_data_ready      : in  std_logic;
        i_bus_rd_data_valid      : in  std_logic;
        i_bus_rd_data            : in  std_logic_vector(31 downto 0);
        i_bus_done               : in  std_logic;
        i_bus_response           : in  std_logic_vector(1 downto 0);
        i_bus_busy               : in  std_logic;
        i_bus_timeout_pulse      : in  std_logic
    );
end entity sc_hub_core;

architecture rtl of sc_hub_core is
    type core_state_t is (
        IDLING,
        INT_RD_FILLING,
        EXT_RD_RUNNING,
        RD_PADDING,
        RD_REPLY_ARMING,
        RD_REPLY_STREAMING,
        INT_WR_DRAINING,
        EXT_WR_ARMING,
        EXT_WR_RUNNING,
        WR_REPLY_ARMING,
        WAITING_REPLY
    );

    signal core_state                : core_state_t := IDLING;
    signal pkt_info_reg              : sc_pkt_info_t := SC_PKT_INFO_RESET_CONST;
    signal reply_suppress_reg        : std_logic := '0';
    signal reply_has_data_reg        : std_logic := '0';
    signal reply_is_internal_reg     : std_logic := '0';
    signal response_reg              : std_logic_vector(1 downto 0) := SC_RSP_OK_CONST;
    signal hub_enable                : std_logic := '1';
    signal hub_scratch               : std_logic_vector(31 downto 0) := (others => '0');
    signal hub_err_flags             : std_logic_vector(31 downto 0) := (others => '0');
    signal hub_err_count             : unsigned(31 downto 0) := (others => '0');
    signal hub_gts_counter           : unsigned(47 downto 0) := (others => '0');
    signal hub_gts_snapshot          : unsigned(47 downto 0) := (others => '0');
    signal hub_upload_store_forward  : std_logic := '1';
    signal ext_pkt_read_count        : unsigned(31 downto 0) := (others => '0');
    signal ext_pkt_write_count       : unsigned(31 downto 0) := (others => '0');
    signal ext_word_read_count       : unsigned(31 downto 0) := (others => '0');
    signal ext_word_write_count      : unsigned(31 downto 0) := (others => '0');
    signal last_ext_read_addr        : std_logic_vector(31 downto 0) := (others => '0');
    signal last_ext_read_data        : std_logic_vector(31 downto 0) := (others => '0');
    signal last_ext_write_addr       : std_logic_vector(31 downto 0) := (others => '0');
    signal last_ext_write_data       : std_logic_vector(31 downto 0) := (others => '0');
    signal read_fill_index           : unsigned(15 downto 0) := (others => '0');
    signal reply_stream_index        : unsigned(15 downto 0) := (others => '0');
    signal write_stream_index        : unsigned(15 downto 0) := (others => '0');
    signal drain_remaining           : unsigned(15 downto 0) := (others => '0');
    signal bus_cmd_issued            : std_logic := '0';
    signal rd_fifo_clear             : std_logic := '0';
    signal rd_fifo_write_en          : std_logic := '0';
    signal rd_fifo_write_data        : std_logic_vector(31 downto 0) := (others => '0');
    signal rd_fifo_read_en           : std_logic := '0';
    signal rd_fifo_q                 : std_logic_vector(31 downto 0);
    signal rd_fifo_empty             : std_logic;
    signal rd_fifo_full              : std_logic;
    signal rd_fifo_usedw             : std_logic_vector(8 downto 0);
    signal tx_reply_start_pulse      : std_logic := '0';
    signal soft_reset_pulse          : std_logic := '0';
    signal bus_cmd_valid_pulse       : std_logic := '0';
    signal bus_cmd_is_read_reg       : std_logic := '0';
    signal bus_cmd_address_reg       : std_logic_vector(15 downto 0) := (others => '0');
    signal bus_cmd_length_reg        : std_logic_vector(15 downto 0) := (others => '0');

    function pkt_length_func (
        pkt_info : sc_pkt_info_t
    ) return unsigned is
    begin
        return unsigned(pkt_info.rw_length);
    end function pkt_length_func;

    function internal_hit_func (
        pkt_info : sc_pkt_info_t
    ) return boolean is
        variable addr_v : natural;
    begin
        addr_v := to_integer(unsigned(pkt_info.start_address(15 downto 0)));
        return (addr_v >= HUB_CSR_BASE_ADDR_CONST and addr_v < HUB_CSR_BASE_ADDR_CONST + HUB_CSR_WINDOW_WORDS_CONST);
    end function internal_hit_func;
begin
    rd_fifo_inst : entity work.sc_hub_fifo_sc
    generic map(
        WIDTH_G => 32,
        DEPTH_G => MAX_BURST_WORDS_CONST
    )
    port map(
        csi_clk    => i_clk,
        rsi_reset  => i_rst,
        clear      => rd_fifo_clear,
        write_en   => rd_fifo_write_en,
        write_data => rd_fifo_write_data,
        read_en    => rd_fifo_read_en,
        read_data  => rd_fifo_q,
        empty      => rd_fifo_empty,
        full       => rd_fifo_full,
        usedw      => rd_fifo_usedw
    );

    o_rx_ready          <= '1' when (core_state = IDLING and hub_enable = '1') else '0';
    o_soft_reset_pulse  <= soft_reset_pulse;
    o_wr_data_rdreq     <= '1'
        when (
            (core_state = INT_WR_DRAINING and i_wr_data_empty = '0' and drain_remaining > 0) or
            (core_state = EXT_WR_RUNNING and i_bus_wr_data_ready = '1' and i_wr_data_empty = '0')
        )
        else '0';
    o_tx_reply_start    <= tx_reply_start_pulse;
    o_tx_reply_info     <= pkt_info_reg;
    o_tx_reply_response <= response_reg;
    o_tx_reply_has_data <= reply_has_data_reg;
    o_tx_reply_suppress <= reply_suppress_reg;
    o_tx_data_valid     <= '1' when (core_state = RD_REPLY_STREAMING and rd_fifo_empty = '0') else '0';
    o_tx_data_word      <= rd_fifo_q;
    o_bus_cmd_valid     <= bus_cmd_valid_pulse;
    o_bus_cmd_is_read   <= bus_cmd_is_read_reg;
    o_bus_cmd_address   <= bus_cmd_address_reg;
    o_bus_cmd_length    <= bus_cmd_length_reg;
    o_bus_wr_data_valid <= '1' when (core_state = EXT_WR_RUNNING and i_wr_data_empty = '0') else '0';
    o_bus_wr_data       <= i_wr_data_q;
    rd_fifo_read_en     <= '1' when (core_state = RD_REPLY_STREAMING and i_tx_data_ready = '1' and rd_fifo_empty = '0') else '0';

    core_fsm : process(i_clk)
        variable csr_word_v             : std_logic_vector(31 downto 0);
        variable status_word_v          : std_logic_vector(31 downto 0);
        variable fifo_status_word_v     : std_logic_vector(31 downto 0);
        variable offset_v               : natural;
        variable pkt_len_v              : unsigned(15 downto 0);
        variable err_pulse_v            : boolean;
        variable internal_addr_error_v  : boolean;
        variable soft_reset_request_v   : boolean;
        variable csr_write_offset_v     : natural;
        variable next_read_addr_v       : unsigned(31 downto 0);
    begin
        if rising_edge(i_clk) then
            if (i_rst = '1') then
                core_state               <= IDLING;
                pkt_info_reg             <= SC_PKT_INFO_RESET_CONST;
                reply_suppress_reg       <= '0';
                reply_has_data_reg       <= '0';
                reply_is_internal_reg    <= '0';
                response_reg             <= SC_RSP_OK_CONST;
                hub_enable               <= '1';
                hub_scratch              <= (others => '0');
                hub_err_flags            <= (others => '0');
                hub_err_count            <= (others => '0');
                hub_gts_counter          <= (others => '0');
                hub_gts_snapshot         <= (others => '0');
                hub_upload_store_forward <= '1';
                ext_pkt_read_count       <= (others => '0');
                ext_pkt_write_count      <= (others => '0');
                ext_word_read_count      <= (others => '0');
                ext_word_write_count     <= (others => '0');
                last_ext_read_addr       <= (others => '0');
                last_ext_read_data       <= (others => '0');
                last_ext_write_addr      <= (others => '0');
                last_ext_write_data      <= (others => '0');
                read_fill_index          <= (others => '0');
                reply_stream_index       <= (others => '0');
                write_stream_index       <= (others => '0');
                drain_remaining          <= (others => '0');
                bus_cmd_issued           <= '0';
                rd_fifo_clear            <= '0';
                rd_fifo_write_en         <= '0';
                rd_fifo_write_data       <= (others => '0');
                tx_reply_start_pulse     <= '0';
                soft_reset_pulse         <= '0';
                bus_cmd_valid_pulse      <= '0';
                bus_cmd_is_read_reg      <= '0';
                bus_cmd_address_reg      <= (others => '0');
                bus_cmd_length_reg       <= (others => '0');
            else
                tx_reply_start_pulse <= '0';
                soft_reset_pulse     <= '0';
                bus_cmd_valid_pulse  <= '0';
                rd_fifo_clear        <= '0';
                rd_fifo_write_en     <= '0';
                rd_fifo_write_data   <= (others => '0');
                err_pulse_v          := false;
                internal_addr_error_v := false;
                soft_reset_request_v := false;
                pkt_len_v            := pkt_length_func(pkt_info_reg);

                hub_gts_counter <= hub_gts_counter + 1;

                if (i_bp_overflow_pulse = '1') then
                    hub_err_flags(HUB_ERR_UP_FIFO_OVERFLOW_CONST) <= '1';
                    err_pulse_v := true;
                end if;

                if (i_dl_fifo_overflow_pulse = '1') then
                    hub_err_flags(HUB_ERR_DOWN_FIFO_OVERFLOW_CONST) <= '1';
                    err_pulse_v := true;
                end if;

                if (i_pkt_drop_pulse = '1') then
                    hub_err_flags(HUB_ERR_PKT_DROP_CONST) <= '1';
                    err_pulse_v := true;
                end if;

                if (i_bus_timeout_pulse = '1') then
                    hub_err_flags(HUB_ERR_RD_TIMEOUT_CONST) <= '1';
                    err_pulse_v := true;
                end if;

                case core_state is
                    when IDLING =>
                        bus_cmd_issued <= '0';
                        if (i_pkt_valid = '1' and hub_enable = '1') then
                            pkt_info_reg          <= i_pkt_info;
                            if (pkt_reply_suppressed_func(i_pkt_info)) then
                                reply_suppress_reg <= '1';
                            else
                                reply_suppress_reg <= '0';
                            end if;
                            reply_is_internal_reg <= '0';
                            response_reg          <= SC_RSP_OK_CONST;
                            read_fill_index       <= (others => '0');
                            reply_stream_index    <= (others => '0');
                            write_stream_index    <= (others => '0');
                            drain_remaining       <= unsigned(i_pkt_info.rw_length);
                            bus_cmd_is_read_reg   <= '0';
                            bus_cmd_address_reg   <= i_pkt_info.start_address(15 downto 0);
                            bus_cmd_length_reg    <= i_pkt_info.rw_length;
                            rd_fifo_clear         <= '1';

                            if (pkt_is_read_func(i_pkt_info)) then
                                reply_has_data_reg <= '1';
                                if (unsigned(i_pkt_info.rw_length) = 0) then
                                    if (internal_hit_func(i_pkt_info) = false) then
                                        ext_pkt_read_count <= sat_inc32_func(ext_pkt_read_count);
                                    end if;

                                    if (pkt_reply_suppressed_func(i_pkt_info)) then
                                        core_state <= IDLING;
                                    else
                                        core_state <= RD_REPLY_ARMING;
                                    end if;
                                elsif (internal_hit_func(i_pkt_info)) then
                                    reply_is_internal_reg <= '1';
                                    core_state            <= INT_RD_FILLING;
                                else
                                    ext_pkt_read_count  <= sat_inc32_func(ext_pkt_read_count);
                                    bus_cmd_is_read_reg <= '1';
                                    core_state          <= EXT_RD_RUNNING;
                                end if;
                            else
                                reply_has_data_reg <= '0';
                                if (unsigned(i_pkt_info.rw_length) = 0) then
                                    if (internal_hit_func(i_pkt_info) = false) then
                                        ext_pkt_write_count <= sat_inc32_func(ext_pkt_write_count);
                                    end if;

                                    if (pkt_reply_suppressed_func(i_pkt_info)) then
                                        core_state <= IDLING;
                                    else
                                        core_state <= WR_REPLY_ARMING;
                                    end if;
                                elsif (internal_hit_func(i_pkt_info)) then
                                    core_state <= INT_WR_DRAINING;
                                else
                                    ext_pkt_write_count <= sat_inc32_func(ext_pkt_write_count);
                                    core_state         <= EXT_WR_ARMING;
                                end if;
                            end if;
                        end if;

                    when INT_RD_FILLING =>
                        offset_v := to_integer(unsigned(pkt_info_reg.start_address(15 downto 0))) - HUB_CSR_BASE_ADDR_CONST + to_integer(read_fill_index);
                        csr_word_v := (others => '0');
                        status_word_v := (others => '0');
                        fifo_status_word_v := (others => '0');

                        if (core_state /= IDLING) then
                            status_word_v(0) := '1';
                        else
                            status_word_v(0) := '0';
                        end if;
                        if (reply_is_internal_reg = '1' and offset_v = HUB_CSR_WO_STATUS_CONST) then
                            status_word_v(0) := '0';
                        end if;
                        if (hub_err_flags /= std_logic_vector(to_unsigned(0, hub_err_flags'length))) then
                            status_word_v(1) := '1';
                        else
                            status_word_v(1) := '0';
                        end if;
                        status_word_v(2) := i_dl_fifo_full;
                        status_word_v(3) := i_bp_full;
                        status_word_v(4) := hub_enable;
                        status_word_v(5) := i_bus_busy;

                        fifo_status_word_v(0) := i_dl_fifo_full;
                        fifo_status_word_v(1) := i_bp_full;
                        fifo_status_word_v(2) := i_dl_fifo_overflow;
                        fifo_status_word_v(3) := i_bp_overflow;
                        fifo_status_word_v(4) := rd_fifo_full;
                        fifo_status_word_v(5) := rd_fifo_empty;

                        case offset_v is
                            when HUB_CSR_WO_ID_CONST =>
                                csr_word_v := HUB_ID_CONST;
                            when HUB_CSR_WO_VERSION_CONST =>
                                csr_word_v := pack_version_func(
                                    HUB_VERSION_YY_CONST,
                                    HUB_VERSION_MAJOR_CONST,
                                    HUB_VERSION_PRE_CONST,
                                    HUB_VERSION_MONTH_CONST,
                                    HUB_VERSION_DAY_CONST
                                );
                            when HUB_CSR_WO_CTRL_CONST =>
                                csr_word_v(0) := hub_enable;
                            when HUB_CSR_WO_STATUS_CONST =>
                                csr_word_v := status_word_v;
                            when HUB_CSR_WO_ERR_FLAGS_CONST =>
                                csr_word_v := hub_err_flags;
                            when HUB_CSR_WO_ERR_COUNT_CONST =>
                                csr_word_v := std_logic_vector(hub_err_count);
                            when HUB_CSR_WO_SCRATCH_CONST =>
                                csr_word_v := hub_scratch;
                            when HUB_CSR_WO_GTS_SNAP_LO_CONST =>
                                csr_word_v := std_logic_vector(hub_gts_snapshot(31 downto 0));
                            when HUB_CSR_WO_GTS_SNAP_HI_CONST =>
                                csr_word_v(15 downto 0) := std_logic_vector(hub_gts_snapshot(47 downto 32));
                                hub_gts_snapshot        <= hub_gts_counter;
                            when HUB_CSR_WO_FIFO_CFG_CONST =>
                                csr_word_v(0) := '1';
                                csr_word_v(1) := hub_upload_store_forward;
                            when HUB_CSR_WO_FIFO_STATUS_CONST =>
                                csr_word_v := fifo_status_word_v;
                            when HUB_CSR_WO_DOWN_PKT_CNT_CONST =>
                                if (core_state /= IDLING) then
                                    csr_word_v(0) := '1';
                                else
                                    csr_word_v(0) := '0';
                                end if;
                            when HUB_CSR_WO_UP_PKT_CNT_CONST =>
                                csr_word_v(9 downto 0) := i_bp_pkt_count;
                            when HUB_CSR_WO_DOWN_USEDW_CONST =>
                                csr_word_v(8 downto 0) := i_dl_fifo_usedw;
                            when HUB_CSR_WO_UP_USEDW_CONST =>
                                csr_word_v(9 downto 0) := i_bp_usedw;
                            when HUB_CSR_WO_EXT_PKT_RD_CONST =>
                                csr_word_v := std_logic_vector(ext_pkt_read_count);
                            when HUB_CSR_WO_EXT_PKT_WR_CONST =>
                                csr_word_v := std_logic_vector(ext_pkt_write_count);
                            when HUB_CSR_WO_EXT_WORD_RD_CONST =>
                                csr_word_v := std_logic_vector(ext_word_read_count);
                            when HUB_CSR_WO_EXT_WORD_WR_CONST =>
                                csr_word_v := std_logic_vector(ext_word_write_count);
                            when HUB_CSR_WO_LAST_RD_ADDR_CONST =>
                                csr_word_v := last_ext_read_addr;
                            when HUB_CSR_WO_LAST_RD_DATA_CONST =>
                                csr_word_v := last_ext_read_data;
                            when HUB_CSR_WO_LAST_WR_ADDR_CONST =>
                                csr_word_v := last_ext_write_addr;
                            when HUB_CSR_WO_LAST_WR_DATA_CONST =>
                                csr_word_v := last_ext_write_data;
                            when HUB_CSR_WO_PKT_DROP_CNT_CONST =>
                                csr_word_v(15 downto 0) := i_pkt_drop_count;
                            when others =>
                                csr_word_v            := x"EEEEEEEE";
                                response_reg          <= SC_RSP_SLVERR_CONST;
                                internal_addr_error_v := true;
                        end case;

                        rd_fifo_write_en   <= '1';
                        rd_fifo_write_data <= csr_word_v;

                        if (read_fill_index + 1 >= pkt_len_v) then
                            if (reply_suppress_reg = '1') then
                                core_state <= IDLING;
                            else
                                reply_stream_index <= (others => '0');
                                core_state         <= RD_REPLY_ARMING;
                            end if;
                        end if;

                        read_fill_index <= read_fill_index + 1;

                    when EXT_RD_RUNNING =>
                        if (bus_cmd_issued = '0' and i_bus_cmd_ready = '1') then
                            bus_cmd_valid_pulse <= '1';
                            bus_cmd_issued      <= '1';
                        end if;

                        if (i_bus_rd_data_valid = '1') then
                            rd_fifo_write_en    <= '1';
                            rd_fifo_write_data  <= i_bus_rd_data;
                            ext_word_read_count <= sat_inc32_func(ext_word_read_count);
                            next_read_addr_v    := resize(unsigned(pkt_info_reg.start_address(15 downto 0)), 32) + resize(read_fill_index, 32);
                            last_ext_read_addr  <= std_logic_vector(next_read_addr_v);
                            last_ext_read_data  <= i_bus_rd_data;
                            read_fill_index     <= read_fill_index + 1;
                        end if;

                        if (i_bus_done = '1') then
                            response_reg <= i_bus_response;
                            if (read_fill_index < pkt_len_v) then
                                core_state <= RD_PADDING;
                            elsif (reply_suppress_reg = '1') then
                                core_state <= IDLING;
                            else
                                reply_stream_index <= (others => '0');
                                core_state         <= RD_REPLY_ARMING;
                            end if;
                        end if;

                    when RD_PADDING =>
                        rd_fifo_write_en   <= '1';
                        rd_fifo_write_data <= x"EEEEEEEE";
                        read_fill_index    <= read_fill_index + 1;

                        if (read_fill_index + 1 >= pkt_len_v) then
                            if (reply_suppress_reg = '1') then
                                core_state <= IDLING;
                            else
                                reply_stream_index <= (others => '0');
                                core_state         <= RD_REPLY_ARMING;
                            end if;
                        end if;

                    when RD_REPLY_ARMING =>
                        if (i_tx_reply_ready = '1') then
                            tx_reply_start_pulse <= '1';
                            core_state           <= RD_REPLY_STREAMING;
                        end if;

                    when RD_REPLY_STREAMING =>
                        if (i_tx_data_ready = '1' and rd_fifo_empty = '0') then
                            if (reply_stream_index + 1 >= pkt_len_v) then
                                core_state <= WAITING_REPLY;
                            end if;

                            reply_stream_index <= reply_stream_index + 1;
                        end if;

                    when INT_WR_DRAINING =>
                        if (i_wr_data_empty = '0' and drain_remaining > 0) then
                            if (drain_remaining = pkt_len_v) then
                                if (pkt_len_v /= 1) then
                                    response_reg          <= SC_RSP_SLVERR_CONST;
                                    internal_addr_error_v := true;
                                else
                                    csr_write_offset_v := to_integer(unsigned(pkt_info_reg.start_address(15 downto 0))) - HUB_CSR_BASE_ADDR_CONST;
                                    case csr_write_offset_v is
                                        when HUB_CSR_WO_CTRL_CONST =>
                                            hub_enable <= i_wr_data_q(0);
                                            if (i_wr_data_q(1) = '1' or i_wr_data_q(2) = '1') then
                                                hub_err_flags        <= (others => '0');
                                                hub_err_count        <= (others => '0');
                                                ext_pkt_read_count   <= (others => '0');
                                                ext_pkt_write_count  <= (others => '0');
                                                ext_word_read_count  <= (others => '0');
                                                ext_word_write_count <= (others => '0');
                                                last_ext_read_addr   <= (others => '0');
                                                last_ext_read_data   <= (others => '0');
                                                last_ext_write_addr  <= (others => '0');
                                                last_ext_write_data  <= (others => '0');
                                            end if;
                                            if (i_wr_data_q(2) = '1') then
                                                soft_reset_request_v := true;
                                            end if;
                                        when HUB_CSR_WO_ERR_FLAGS_CONST =>
                                            hub_err_flags <= hub_err_flags and not i_wr_data_q;
                                        when HUB_CSR_WO_SCRATCH_CONST =>
                                            hub_scratch <= i_wr_data_q;
                                        when HUB_CSR_WO_FIFO_CFG_CONST =>
                                            hub_upload_store_forward <= i_wr_data_q(1);
                                        when others =>
                                            response_reg          <= SC_RSP_SLVERR_CONST;
                                            internal_addr_error_v := true;
                                    end case;
                                end if;
                            end if;

                            drain_remaining <= drain_remaining - 1;
                            if (drain_remaining = 1) then
                                if (reply_suppress_reg = '1') then
                                    core_state <= IDLING;
                                else
                                    core_state <= WR_REPLY_ARMING;
                                end if;
                            end if;
                        end if;

                    when EXT_WR_ARMING =>
                        if (i_bus_cmd_ready = '1') then
                            bus_cmd_valid_pulse <= '1';
                            write_stream_index  <= (others => '0');
                            core_state          <= EXT_WR_RUNNING;
                        end if;

                    when EXT_WR_RUNNING =>
                        if (i_bus_wr_data_ready = '1' and i_wr_data_empty = '0') then
                            ext_word_write_count <= sat_inc32_func(ext_word_write_count);
                            last_ext_write_addr  <= std_logic_vector(resize(unsigned(pkt_info_reg.start_address(15 downto 0)), 32) + resize(write_stream_index, 32));
                            last_ext_write_data  <= i_wr_data_q;
                            write_stream_index   <= write_stream_index + 1;
                        end if;

                        if (i_bus_done = '1') then
                            response_reg <= i_bus_response;
                            if (reply_suppress_reg = '1') then
                                core_state <= IDLING;
                            else
                                core_state <= WR_REPLY_ARMING;
                            end if;
                        end if;

                    when WR_REPLY_ARMING =>
                        if (i_tx_reply_ready = '1') then
                            tx_reply_start_pulse <= '1';
                            core_state           <= WAITING_REPLY;
                        end if;

                    when WAITING_REPLY =>
                        if (i_tx_reply_done = '1') then
                            core_state <= IDLING;
                        end if;
                end case;

                if (internal_addr_error_v = true) then
                    hub_err_flags(HUB_ERR_INTERNAL_ADDR_CONST) <= '1';
                    err_pulse_v := true;
                end if;

                if (err_pulse_v = true) then
                    if (hub_err_count(7 downto 0) /= to_unsigned(16#FF#, 8)) then
                        hub_err_count <= resize(hub_err_count(7 downto 0) + 1, hub_err_count'length);
                    end if;
                end if;

                if (soft_reset_request_v = true) then
                    core_state               <= IDLING;
                    pkt_info_reg             <= SC_PKT_INFO_RESET_CONST;
                    reply_suppress_reg       <= '0';
                    reply_has_data_reg       <= '0';
                    reply_is_internal_reg    <= '0';
                    response_reg             <= SC_RSP_OK_CONST;
                    hub_enable               <= '1';
                    hub_scratch              <= (others => '0');
                    hub_err_flags            <= (others => '0');
                    hub_err_count            <= (others => '0');
                    hub_gts_counter          <= (others => '0');
                    hub_gts_snapshot         <= (others => '0');
                    hub_upload_store_forward <= '1';
                    ext_pkt_read_count       <= (others => '0');
                    ext_pkt_write_count      <= (others => '0');
                    ext_word_read_count      <= (others => '0');
                    ext_word_write_count     <= (others => '0');
                    last_ext_read_addr       <= (others => '0');
                    last_ext_read_data       <= (others => '0');
                    last_ext_write_addr      <= (others => '0');
                    last_ext_write_data      <= (others => '0');
                    read_fill_index          <= (others => '0');
                    reply_stream_index       <= (others => '0');
                    write_stream_index       <= (others => '0');
                    drain_remaining          <= (others => '0');
                    bus_cmd_issued           <= '0';
                    rd_fifo_clear            <= '1';
                    rd_fifo_write_en         <= '0';
                    rd_fifo_write_data       <= (others => '0');
                    tx_reply_start_pulse     <= '0';
                    soft_reset_pulse         <= '1';
                    bus_cmd_valid_pulse      <= '0';
                    bus_cmd_is_read_reg      <= '0';
                    bus_cmd_address_reg      <= (others => '0');
                    bus_cmd_length_reg       <= (others => '0');
                end if;
            end if;
        end if;
    end process core_fsm;
end architecture rtl;
