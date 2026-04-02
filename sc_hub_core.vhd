-- File name: sc_hub_core.vhd
-- Author: Yifeng Wang (yifenwan@phys.ethz.ch)
-- =======================================
-- Version : 26.2.37
-- Date    : 20260402
-- Change  : Keep external-write diagnostics in their own owner process and
--           drive response_reg through explicit next-state muxing instead of a
--           sparse clock-enable cone.
-- =======================================
-- altera vhdl_input_version vhdl_2008

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sc_hub_pkg.all;

entity sc_hub_core is
    generic(
        DEBUG_G                    : natural := 1;
        OOO_ENABLE_G               : boolean := false;
        ORD_ENABLE_G               : boolean := true;
        ATOMIC_ENABLE_G            : boolean := true;
        HUB_CAP_ENABLE_G           : boolean := true;
        BP_FIFO_DEPTH_G            : positive := DEFAULT_BP_FIFO_DEPTH_CONST;
        OUTSTANDING_LIMIT_G        : positive := 8;
        OUTSTANDING_INT_RESERVED_G : natural := 2
    );
    port(
        i_clk                    : in  std_logic;
        i_rst                    : in  std_logic;
        i_pkt_valid              : in  std_logic;
        i_pkt_info               : in  sc_pkt_info_t;
        i_pkt_is_internal        : in  std_logic;
        o_rx_ready               : out std_logic;
        o_soft_reset_pulse       : out std_logic;
        o_wr_data_rdreq          : out std_logic;
        i_wr_data_q              : in  std_logic_vector(31 downto 0);
        i_wr_data_empty          : in  std_logic;
        i_pkt_drop_count         : in  std_logic_vector(15 downto 0);
        i_pkt_drop_pulse         : in  std_logic;
        i_dl_fifo_usedw          : in  std_logic_vector(9 downto 0);
        i_dl_fifo_full           : in  std_logic;
        i_dl_fifo_overflow       : in  std_logic;
        i_dl_fifo_overflow_pulse : in  std_logic;
        i_bp_usedw               : in  std_logic_vector(ceil_log2_func(BP_FIFO_DEPTH_G + 1) - 1 downto 0);
        i_bp_full                : in  std_logic;
        i_bp_overflow            : in  std_logic;
        i_bp_overflow_pulse      : in  std_logic;
        i_bp_pkt_count           : in  std_logic_vector(ceil_log2_func(BP_FIFO_DEPTH_G + 1) - 1 downto 0);
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
        DISPATCH_CAPTURING,
        DISPATCH_DECODING,
        INT_RD_OFFSETING,
        INT_RD_FILLING,
        INT_RD_PUSHING,
        EXT_RD_RUNNING,
        ATOMIC_EXT_RD_RUNNING,
        ATOMIC_EXT_WR_ARMING,
        ATOMIC_EXT_WR_RUNNING,
        RD_PADDING,
        RD_REPLY_ARMING,
        RD_REPLY_STREAMING,
        INT_WR_DRAINING,
        EXT_WR_ARMING,
        EXT_WR_RUNNING,
        WR_REPLY_ARMING,
        WAITING_REPLY
    );
    subtype pending_queue_index_t is natural range 0 to OUTSTANDING_LIMIT_G - 1;
    type pending_pkt_mem_t is array (pending_queue_index_t) of sc_pkt_info_t;

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
    signal ooo_ctrl_enable           : std_logic := '0';
    signal ord_drain_count           : unsigned(31 downto 0) := (others => '0');
    signal ord_hold_count            : unsigned(31 downto 0) := (others => '0');
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
    signal reply_words_remaining     : unsigned(15 downto 0) := (others => '0');
    signal reply_arm_pending         : std_logic := '0';
    signal reply_arm_use_fifo_usedw  : std_logic := '0';
    signal write_stream_index        : unsigned(15 downto 0) := (others => '0');
    signal drain_remaining           : unsigned(15 downto 0) := (others => '0');
    signal atomic_read_data_reg      : std_logic_vector(31 downto 0) := (others => '0');
    signal atomic_write_data_reg     : std_logic_vector(31 downto 0) := (others => '0');
    signal deferred_atomic_pending   : std_logic := '0';
    signal deferred_atomic_pkt_info  : sc_pkt_info_t := SC_PKT_INFO_RESET_CONST;
    signal deferred_atomic_response  : std_logic_vector(1 downto 0) := SC_RSP_OK_CONST;
    signal deferred_atomic_has_data  : std_logic := '0';
    signal deferred_atomic_suppress  : std_logic := '0';
    signal deferred_atomic_data_word : std_logic_vector(31 downto 0) := (others => '0');
    signal bus_cmd_issued            : std_logic := '0';
    signal rd_fifo_clear             : std_logic := '0';
    signal rd_fifo_write_en          : std_logic := '0';
    signal rd_fifo_write_data        : std_logic_vector(31 downto 0) := (others => '0');
    signal int_read_offset_reg       : unsigned(15 downto 0) := (others => '0');
    signal int_read_word_reg         : std_logic_vector(31 downto 0) := (others => '0');
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
    signal pending_pkt_mem           : pending_pkt_mem_t := (others => SC_PKT_INFO_RESET_CONST);
    signal pending_pkt_rd_ptr        : pending_queue_index_t := 0;
    signal pending_pkt_wr_ptr        : pending_queue_index_t := 0;
    signal pending_pkt_count         : natural range 0 to OUTSTANDING_LIMIT_G := 0;
    signal pending_ext_count         : natural range 0 to OUTSTANDING_LIMIT_G := 0;
    signal active_pkt_slots          : natural range 0 to 1 := 0;
    signal active_ext_slots          : natural range 0 to 1 := 0;
    signal tracked_pkt_count         : natural range 0 to OUTSTANDING_LIMIT_G + 1 := 0;
    signal tracked_ext_count         : natural range 0 to OUTSTANDING_LIMIT_G + 1 := 0;
    signal barrier_guard_counter     : natural range 0 to 15 := 0;
    signal wr_data_valid_reg         : std_logic := '0';
    signal wr_data_word_reg          : std_logic_vector(31 downto 0) := (others => '0');
    signal wr_data_reload_pending    : std_logic := '0';
    signal dispatch_pkt_reg          : sc_pkt_info_t := SC_PKT_INFO_RESET_CONST;
    signal dispatch_queue_idx_reg    : pending_queue_index_t := 0;
    signal err_count_pulse_q         : std_logic := '0';
    signal tx_reply_ready_q          : std_logic := '0';
    signal soft_reset_pending        : std_logic := '0';
    signal ext_write_diag_pending    : std_logic := '0';
    signal ext_write_diag_addr_hold  : std_logic_vector(31 downto 0) := (others => '0');
    signal ext_write_diag_data_hold  : std_logic_vector(31 downto 0) := (others => '0');

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

    function pkt_is_internal_func (
        pkt_info : sc_pkt_info_t
    ) return boolean is
    begin
        for idx in 15 downto 0 loop
            if (pkt_info.start_address(idx) /= '0' and pkt_info.start_address(idx) /= '1') then
                return false;
            end if;
        end loop;
        return internal_hit_func(pkt_info);
    end function pkt_is_internal_func;

    function next_pending_index_func (
        value_in : pending_queue_index_t
    ) return pending_queue_index_t is
    begin
        if (value_in = OUTSTANDING_LIMIT_G - 1) then
            return 0;
        else
            return value_in + 1;
        end if;
    end function next_pending_index_func;

    function ext_track_limit_func (
        outstanding_limit_in : positive;
        int_reserved_in      : natural
    ) return natural is
    begin
        if (int_reserved_in >= outstanding_limit_in) then
            return 0;
        else
            return outstanding_limit_in - int_reserved_in;
        end if;
    end function ext_track_limit_func;

    function pkt_requires_reply_payload_credit_func (
        pkt_info : sc_pkt_info_t
    ) return boolean is
    begin
        return (
            pkt_is_internal_func(pkt_info) = false and
            pkt_reply_suppressed_func(pkt_info) = false and
            to_integer(unsigned(pkt_info.rw_length)) /= 0 and
            (pkt_is_read_func(pkt_info) or pkt_is_atomic_func(pkt_info))
        );
    end function pkt_requires_reply_payload_credit_func;

    function reply_payload_credit_ready_func (
        pkt_info : sc_pkt_info_t;
        bp_usedw : std_logic_vector
    ) return boolean is
    begin
        if (pkt_requires_reply_payload_credit_func(pkt_info) = false) then
            return true;
        else
            return (to_integer(unsigned(bp_usedw)) + to_integer(unsigned(pkt_info.rw_length)) <= BP_FIFO_DEPTH_G);
        end if;
    end function reply_payload_credit_ready_func;

begin
    active_pkt_slots <= 0
        when (core_state = IDLING and deferred_atomic_pending = '0')
        else 1;
    active_ext_slots <= 1
        when (
            (core_state /= IDLING and pkt_is_internal_func(pkt_info_reg) = false) or
            (
                core_state = IDLING and
                deferred_atomic_pending = '1' and
                pkt_is_internal_func(deferred_atomic_pkt_info) = false
            )
        )
        else 0;
    tracked_pkt_count <= pending_pkt_count + active_pkt_slots;
    tracked_ext_count <= pending_ext_count + active_ext_slots;

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

    o_rx_ready <= '1'
        when (
            tracked_pkt_count < OUTSTANDING_LIMIT_G and
            (
                i_pkt_is_internal = '1' or
                tracked_ext_count < ext_track_limit_func(OUTSTANDING_LIMIT_G, OUTSTANDING_INT_RESERVED_G)
            )
        )
        else '0';
    o_soft_reset_pulse  <= soft_reset_pulse;
    o_wr_data_rdreq     <= '1'
        when (
            (
                core_state = INT_WR_DRAINING and
                drain_remaining > 0 and
                not (
                    pkt_is_internal_func(pkt_info_reg) and
                    pkt_is_read_func(pkt_info_reg) = false and
                    pkt_info_reg.atomic_flag = '0' and
                    unsigned(pkt_info_reg.rw_length) = 1
                ) and
                i_wr_data_empty = '0'
            ) or
            (core_state = EXT_WR_RUNNING and i_bus_wr_data_ready = '1' and wr_data_valid_reg = '1')
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
    o_bus_wr_data_valid <= '1'
        when (
            (core_state = EXT_WR_RUNNING and wr_data_valid_reg = '1') or
            (core_state = ATOMIC_EXT_WR_RUNNING)
        )
        else '0';
    o_bus_wr_data       <= atomic_write_data_reg when (core_state = ATOMIC_EXT_WR_RUNNING) else
                           i_wr_data_q when (wr_data_reload_pending = '1') else
                           wr_data_word_reg;
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
        variable unsupported_feature_v  : boolean;
        variable unsupported_order_v    : boolean;
        variable unsupported_atomic_v   : boolean;
        variable csr_write_offset_v     : natural;
        variable next_read_addr_v       : unsigned(31 downto 0);
        variable hub_cap_word_v         : std_logic_vector(31 downto 0);
        variable atomic_read_word_v     : std_logic_vector(31 downto 0);
        variable queue_mem_v            : pending_pkt_mem_t;
        variable queue_rd_ptr_v         : pending_queue_index_t;
        variable queue_wr_ptr_v         : pending_queue_index_t;
        variable queue_count_v          : natural range 0 to OUTSTANDING_LIMIT_G;
        variable queue_ext_count_v      : natural range 0 to OUTSTANDING_LIMIT_G;
        variable dispatch_pkt_v         : sc_pkt_info_t;
        variable dispatch_pkt_valid_v   : boolean;
        variable dispatch_queue_found_v : boolean;
        variable dispatch_queue_idx_v   : pending_queue_index_t;
        variable same_domain_block_v    : boolean;
        variable prefer_non_barrier_v   : boolean;
        variable barrier_guard_block_v  : boolean;
        variable reply_credit_ready_v   : boolean;
        variable barrier_guard_v        : natural range 0 to 15;
        variable int_sideband_write_v   : boolean;
        variable write_word_v           : std_logic_vector(31 downto 0);
        variable ext_write_word_v       : std_logic_vector(31 downto 0);
        variable response_reg_v         : std_logic_vector(1 downto 0);
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
                ooo_ctrl_enable          <= '0';
                ord_drain_count          <= (others => '0');
                ord_hold_count           <= (others => '0');
                ext_pkt_read_count       <= (others => '0');
                ext_pkt_write_count      <= (others => '0');
                ext_word_read_count      <= (others => '0');
                last_ext_read_addr       <= (others => '0');
                last_ext_read_data       <= (others => '0');
                read_fill_index          <= (others => '0');
                reply_stream_index       <= (others => '0');
                reply_words_remaining    <= (others => '0');
                reply_arm_pending        <= '0';
                reply_arm_use_fifo_usedw <= '0';
                write_stream_index       <= (others => '0');
                drain_remaining          <= (others => '0');
                atomic_read_data_reg     <= (others => '0');
                atomic_write_data_reg    <= (others => '0');
                deferred_atomic_pending  <= '0';
                deferred_atomic_pkt_info <= SC_PKT_INFO_RESET_CONST;
                deferred_atomic_response <= SC_RSP_OK_CONST;
                deferred_atomic_has_data <= '0';
                deferred_atomic_suppress <= '0';
                deferred_atomic_data_word <= (others => '0');
                bus_cmd_issued           <= '0';
                rd_fifo_clear            <= '0';
                rd_fifo_write_en         <= '0';
                rd_fifo_write_data       <= (others => '0');
                int_read_offset_reg      <= (others => '0');
                int_read_word_reg        <= (others => '0');
                tx_reply_start_pulse     <= '0';
                soft_reset_pulse         <= '0';
                bus_cmd_valid_pulse      <= '0';
                bus_cmd_is_read_reg      <= '0';
                bus_cmd_address_reg      <= (others => '0');
                bus_cmd_length_reg       <= (others => '0');
                pending_pkt_mem          <= (others => SC_PKT_INFO_RESET_CONST);
                pending_pkt_rd_ptr       <= 0;
                pending_pkt_wr_ptr       <= 0;
                pending_pkt_count        <= 0;
                pending_ext_count        <= 0;
                barrier_guard_counter    <= 0;
                wr_data_valid_reg        <= '0';
                wr_data_word_reg         <= (others => '0');
                wr_data_reload_pending   <= '0';
                dispatch_pkt_reg         <= SC_PKT_INFO_RESET_CONST;
                dispatch_queue_idx_reg   <= 0;
                err_count_pulse_q        <= '0';
                tx_reply_ready_q         <= '0';
                soft_reset_pending       <= '0';
            else
                tx_reply_start_pulse <= '0';
                soft_reset_pulse     <= '0';
                bus_cmd_valid_pulse  <= '0';
                rd_fifo_clear        <= '0';
                rd_fifo_write_en     <= '0';
                err_pulse_v          := false;
                internal_addr_error_v := false;
                soft_reset_request_v := false;
                unsupported_feature_v := false;
                unsupported_order_v   := false;
                unsupported_atomic_v  := false;
                pkt_len_v            := pkt_length_func(pkt_info_reg);
                hub_cap_word_v       := (others => '0');
                atomic_read_word_v   := atomic_read_data_reg;
                queue_mem_v          := pending_pkt_mem;
                queue_rd_ptr_v       := 0;
                queue_wr_ptr_v       := 0;
                queue_count_v        := pending_pkt_count;
                queue_ext_count_v    := pending_ext_count;
                dispatch_pkt_v       := SC_PKT_INFO_RESET_CONST;
                dispatch_pkt_valid_v := false;
                dispatch_queue_found_v := false;
                dispatch_queue_idx_v := 0;
                same_domain_block_v  := false;
                prefer_non_barrier_v := false;
                barrier_guard_block_v := false;
                reply_credit_ready_v := true;
                barrier_guard_v      := barrier_guard_counter;
                int_sideband_write_v := false;
                write_word_v         := i_wr_data_q;
                ext_write_word_v     := wr_data_word_reg;
                response_reg_v       := response_reg;
                if (barrier_guard_v /= 0) then
                    barrier_guard_v := barrier_guard_v - 1;
                end if;
                tx_reply_ready_q <= i_tx_reply_ready;
                if (soft_reset_pending = '1') then
                    soft_reset_request_v := true;
                    soft_reset_pending   <= '0';
                end if;
                if (err_count_pulse_q = '1') then
                    if (hub_err_count(7 downto 0) /= to_unsigned(16#FF#, 8)) then
                        hub_err_count <= resize(hub_err_count(7 downto 0) + 1, hub_err_count'length);
                    end if;
                end if;
                if (wr_data_reload_pending = '1') then
                    wr_data_word_reg       <= i_wr_data_q;
                    wr_data_reload_pending <= '0';
                    ext_write_word_v       := i_wr_data_q;
                end if;
                if (OOO_ENABLE_G) then
                    hub_cap_word_v(0) := '1';
                end if;
                if (ORD_ENABLE_G) then
                    hub_cap_word_v(1) := '1';
                end if;
                if (ATOMIC_ENABLE_G) then
                    hub_cap_word_v(2) := '1';
                end if;
                hub_cap_word_v(3) := '1';

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

                if (core_state = IDLING) then
                    if (queue_count_v /= 0) then
                        for pass_idx in 0 to 1 loop
                            exit when dispatch_queue_found_v = true;
                            for queue_idx in 0 to OUTSTANDING_LIMIT_G - 1 loop
                                exit when queue_idx >= queue_count_v;
                                same_domain_block_v := false;
                                if (queue_idx /= 0) then
                                    for older_idx in 0 to queue_idx - 1 loop
                                        if (queue_mem_v(older_idx).order_domain = queue_mem_v(queue_idx).order_domain) then
                                            same_domain_block_v := true;
                                            exit;
                                        end if;
                                    end loop;
                                end if;

                                if (
                                    same_domain_block_v = false and
                                    (hub_enable = '1' or pkt_is_internal_func(queue_mem_v(queue_idx))) and
                                    not (deferred_atomic_pending = '1' and pkt_is_internal_func(queue_mem_v(queue_idx)) = false)
                                ) then
                                    prefer_non_barrier_v := (
                                        pkt_is_internal_func(queue_mem_v(queue_idx)) or
                                        queue_mem_v(queue_idx).order_mode = SC_ORDER_RELAXED_CONST
                                    );
                                    barrier_guard_block_v := (
                                        queue_count_v = 1 and
                                        pkt_is_internal_func(queue_mem_v(queue_idx)) = false and
                                        queue_mem_v(queue_idx).order_mode /= SC_ORDER_RELAXED_CONST and
                                        barrier_guard_v /= 0 and
                                        not (
                                            i_pkt_valid = '1' and
                                            o_rx_ready = '1' and
                                            i_pkt_info.order_domain = queue_mem_v(queue_idx).order_domain
                                        )
                                    );
                                    if (
                                        barrier_guard_block_v = false and
                                        ((pass_idx = 0 and prefer_non_barrier_v = true) or pass_idx = 1)
                                    ) then
                                        reply_credit_ready_v := reply_payload_credit_ready_func(
                                            queue_mem_v(queue_idx),
                                            i_bp_usedw
                                        );
                                        if (reply_credit_ready_v = true) then
                                            dispatch_pkt_v         := queue_mem_v(queue_idx);
                                            dispatch_pkt_valid_v   := true;
                                            dispatch_queue_found_v := true;
                                            dispatch_queue_idx_v   := queue_idx;
                                            exit;
                                        end if;
                                    end if;
                                end if;
                            end loop;
                        end loop;
                    end if;
                end if;

                if (i_pkt_valid = '1' and o_rx_ready = '1') then
                    if (queue_count_v < OUTSTANDING_LIMIT_G) then
                        if (
                            queue_count_v = 0 and
                            i_pkt_is_internal = '0' and
                            i_pkt_info.order_mode /= SC_ORDER_RELAXED_CONST
                        ) then
                            barrier_guard_v := 8;
                        end if;
                        queue_mem_v(queue_count_v) := i_pkt_info;
                        queue_count_v              := queue_count_v + 1;
                        if (i_pkt_is_internal = '0') then
                            queue_ext_count_v := queue_ext_count_v + 1;
                        end if;
                    end if;
                end if;

                case core_state is
                    when IDLING =>
                        bus_cmd_issued <= '0';
                        if (deferred_atomic_pending = '1' and dispatch_pkt_valid_v = false) then
                            pkt_info_reg          <= deferred_atomic_pkt_info;
                            reply_suppress_reg    <= deferred_atomic_suppress;
                            reply_has_data_reg    <= deferred_atomic_has_data;
                            reply_is_internal_reg <= '0';
                            response_reg_v        := deferred_atomic_response;
                            read_fill_index       <= (others => '0');
                            reply_stream_index    <= (others => '0');
                            reply_words_remaining <= (others => '0');
                            write_stream_index    <= (others => '0');
                            drain_remaining       <= unsigned(deferred_atomic_pkt_info.rw_length);
                            deferred_atomic_pending <= '0';
                            if (deferred_atomic_suppress = '1') then
                                core_state <= IDLING;
                            elsif (deferred_atomic_has_data = '1') then
                                rd_fifo_write_en   <= '1';
                                rd_fifo_write_data <= deferred_atomic_data_word;
                                read_fill_index    <= to_unsigned(1, read_fill_index'length);
                                reply_arm_pending        <= '1';
                                reply_arm_use_fifo_usedw <= '0';
                                core_state               <= RD_REPLY_ARMING;
                            else
                                core_state <= WR_REPLY_ARMING;
                            end if;
                        elsif (dispatch_pkt_valid_v = true) then
                            dispatch_pkt_reg       <= dispatch_pkt_v;
                            dispatch_queue_idx_reg <= dispatch_queue_idx_v;
                            core_state             <= DISPATCH_CAPTURING;
                        end if;

                    when DISPATCH_CAPTURING =>
                        pkt_info_reg <= dispatch_pkt_reg;
                        if (pkt_reply_suppressed_func(dispatch_pkt_reg)) then
                            reply_suppress_reg <= '1';
                        else
                            reply_suppress_reg <= '0';
                        end if;
                        reply_is_internal_reg <= '0';
                        read_fill_index       <= (others => '0');
                        reply_stream_index    <= (others => '0');
                        reply_words_remaining <= (others => '0');
                        write_stream_index    <= (others => '0');
                        wr_data_valid_reg     <= '0';
                        wr_data_word_reg      <= (others => '0');
                        wr_data_reload_pending <= '0';
                        if (pkt_is_internal_func(dispatch_pkt_reg) = false and queue_ext_count_v /= 0) then
                            queue_ext_count_v := queue_ext_count_v - 1;
                        end if;
                        if (queue_count_v > 1) then
                            for shift_idx in 0 to OUTSTANDING_LIMIT_G - 2 loop
                                if (shift_idx >= dispatch_queue_idx_reg and shift_idx + 1 < queue_count_v) then
                                    queue_mem_v(shift_idx) := queue_mem_v(shift_idx + 1);
                                end if;
                            end loop;
                        end if;
                        if (queue_count_v /= 0) then
                            if (queue_count_v = 1) then
                                barrier_guard_v := 0;
                            end if;
                            queue_count_v := queue_count_v - 1;
                        end if;
                        core_state            <= DISPATCH_DECODING;

                    when DISPATCH_DECODING =>
                        response_reg_v        := SC_RSP_OK_CONST;
                        drain_remaining       <= unsigned(pkt_info_reg.rw_length);
                        bus_cmd_is_read_reg   <= '0';
                        bus_cmd_address_reg   <= pkt_info_reg.start_address(15 downto 0);
                        bus_cmd_length_reg    <= pkt_info_reg.rw_length;
                        rd_fifo_clear         <= '1';
                        unsupported_order_v   := (ORD_ENABLE_G = false and pkt_info_reg.order_mode /= SC_ORDER_RELAXED_CONST);
                        unsupported_atomic_v  := (pkt_info_reg.atomic_flag = '1' and (ATOMIC_ENABLE_G = false or internal_hit_func(pkt_info_reg)));
                        unsupported_feature_v := unsupported_order_v or unsupported_atomic_v;

                        if (pkt_info_reg.order_mode = SC_ORDER_RELEASE_CONST) then
                            ord_drain_count <= sat_inc32_func(ord_drain_count);
                        elsif (pkt_info_reg.order_mode = SC_ORDER_ACQUIRE_CONST) then
                            ord_hold_count <= sat_inc32_func(ord_hold_count);
                        end if;

                        if (unsupported_feature_v = true) then
                            response_reg_v     := SC_RSP_SLVERR_CONST;
                            reply_has_data_reg <= '0';
                            if (reply_suppress_reg = '1') then
                                core_state <= IDLING;
                            else
                                core_state <= WR_REPLY_ARMING;
                            end if;
                        elsif (pkt_is_atomic_func(pkt_info_reg)) then
                            reply_has_data_reg  <= '1';
                            ext_pkt_read_count  <= sat_inc32_func(ext_pkt_read_count);
                            bus_cmd_is_read_reg <= '1';
                            bus_cmd_length_reg  <= std_logic_vector(to_unsigned(1, bus_cmd_length_reg'length));
                            core_state          <= ATOMIC_EXT_RD_RUNNING;
                        elsif (pkt_is_read_func(pkt_info_reg)) then
                            reply_has_data_reg <= '1';
                            if (unsigned(pkt_info_reg.rw_length) = 0) then
                                if (internal_hit_func(pkt_info_reg) = false) then
                                    ext_pkt_read_count <= sat_inc32_func(ext_pkt_read_count);
                                end if;

                                if (reply_suppress_reg = '1') then
                                    core_state <= IDLING;
                                else
                                    core_state <= RD_REPLY_ARMING;
                                end if;
                            elsif (internal_hit_func(pkt_info_reg)) then
                                reply_is_internal_reg <= '1';
                                core_state            <= INT_RD_OFFSETING;
                            else
                                ext_pkt_read_count  <= sat_inc32_func(ext_pkt_read_count);
                                bus_cmd_is_read_reg <= '1';
                                core_state          <= EXT_RD_RUNNING;
                            end if;
                        else
                            reply_has_data_reg <= '0';
                            if (unsigned(pkt_info_reg.rw_length) = 0) then
                                if (internal_hit_func(pkt_info_reg) = false) then
                                    ext_pkt_write_count <= sat_inc32_func(ext_pkt_write_count);
                                end if;

                                if (reply_suppress_reg = '1') then
                                    core_state <= IDLING;
                                else
                                    core_state <= WR_REPLY_ARMING;
                                end if;
                            elsif (internal_hit_func(pkt_info_reg)) then
                                core_state <= INT_WR_DRAINING;
                            else
                                ext_pkt_write_count <= sat_inc32_func(ext_pkt_write_count);
                                core_state         <= EXT_WR_ARMING;
                            end if;
                        end if;

                    when INT_RD_OFFSETING =>
                        int_read_offset_reg <= resize(unsigned(pkt_info_reg.start_address(15 downto 0)), int_read_offset_reg'length) -
                                               to_unsigned(HUB_CSR_BASE_ADDR_CONST, int_read_offset_reg'length) +
                                               resize(read_fill_index, int_read_offset_reg'length);
                        core_state          <= INT_RD_FILLING;

                    when INT_RD_FILLING =>
                        offset_v := to_integer(int_read_offset_reg);
                        csr_word_v := (others => '0');
                        status_word_v := (others => '0');
                        fifo_status_word_v := (others => '0');

                        if (core_state /= IDLING or pending_pkt_count /= 0 or deferred_atomic_pending = '1') then
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
                                if (core_state /= IDLING or pending_pkt_count /= 0 or deferred_atomic_pending = '1') then
                                    csr_word_v(0) := '1';
                                else
                                    csr_word_v(0) := '0';
                                end if;
                            when HUB_CSR_WO_UP_PKT_CNT_CONST =>
                                csr_word_v(9 downto 0) := std_logic_vector(resize(unsigned(i_bp_pkt_count), 10));
                            when HUB_CSR_WO_DOWN_USEDW_CONST =>
                                csr_word_v(9 downto 0) := i_dl_fifo_usedw;
                            when HUB_CSR_WO_UP_USEDW_CONST =>
                                csr_word_v(9 downto 0) := std_logic_vector(resize(unsigned(i_bp_usedw), 10));
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
                            when HUB_CSR_WO_OOO_CTRL_CONST =>
                                if (OOO_ENABLE_G) then
                                    csr_word_v(0) := ooo_ctrl_enable;
                                end if;
                            when HUB_CSR_WO_ORD_DRAIN_CNT_CONST =>
                                csr_word_v := std_logic_vector(ord_drain_count);
                            when HUB_CSR_WO_ORD_HOLD_CNT_CONST =>
                                csr_word_v := std_logic_vector(ord_hold_count);
                            when HUB_CSR_WO_HUB_CAP_CONST =>
                                if (HUB_CAP_ENABLE_G) then
                                    csr_word_v := hub_cap_word_v;
                                end if;
                            when others =>
                                csr_word_v            := x"EEEEEEEE";
                                response_reg_v        := SC_RSP_SLVERR_CONST;
                                internal_addr_error_v := true;
                        end case;

                        int_read_word_reg <= csr_word_v;
                        core_state        <= INT_RD_PUSHING;

                    when INT_RD_PUSHING =>
                        rd_fifo_write_en   <= '1';
                        rd_fifo_write_data <= int_read_word_reg;

                        if (read_fill_index + 1 >= pkt_len_v) then
                            if (reply_suppress_reg = '1') then
                                core_state <= IDLING;
                            else
                                reply_stream_index       <= (others => '0');
                                reply_arm_pending        <= '1';
                                reply_arm_use_fifo_usedw <= '0';
                                core_state               <= RD_REPLY_ARMING;
                            end if;
                        else
                            core_state <= INT_RD_OFFSETING;
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
                            response_reg_v := i_bus_response;
                            if (i_bus_response = SC_RSP_SLVERR_CONST) then
                                hub_err_flags(HUB_ERR_SLVERR_CONST) <= '1';
                                err_pulse_v := true;
                            elsif (i_bus_response = SC_RSP_DECERR_CONST) then
                                hub_err_flags(HUB_ERR_DECERR_CONST) <= '1';
                                err_pulse_v := true;
                            end if;
                            if (read_fill_index < pkt_len_v) then
                                core_state <= RD_PADDING;
                            elsif (reply_suppress_reg = '1') then
                                core_state <= IDLING;
                            else
                                reply_stream_index       <= (others => '0');
                                reply_arm_pending        <= '1';
                                reply_arm_use_fifo_usedw <= '0';
                                core_state               <= RD_REPLY_ARMING;
                            end if;
                        end if;

                    when ATOMIC_EXT_RD_RUNNING =>
                        if (bus_cmd_issued = '0' and i_bus_cmd_ready = '1') then
                            bus_cmd_valid_pulse <= '1';
                            bus_cmd_issued      <= '1';
                        end if;

                        if (i_bus_rd_data_valid = '1') then
                            atomic_read_word_v  := i_bus_rd_data;
                            atomic_read_data_reg <= i_bus_rd_data;
                            ext_word_read_count  <= sat_inc32_func(ext_word_read_count);
                            next_read_addr_v     := resize(unsigned(pkt_info_reg.start_address(15 downto 0)), 32);
                            last_ext_read_addr   <= std_logic_vector(next_read_addr_v);
                            last_ext_read_data   <= i_bus_rd_data;
                            read_fill_index      <= to_unsigned(1, read_fill_index'length);
                        end if;

                        if (i_bus_done = '1') then
                            response_reg_v := i_bus_response;
                            bus_cmd_issued <= '0';
                            if (i_bus_response = SC_RSP_SLVERR_CONST) then
                                hub_err_flags(HUB_ERR_SLVERR_CONST) <= '1';
                                err_pulse_v := true;
                            elsif (i_bus_response = SC_RSP_DECERR_CONST) then
                                hub_err_flags(HUB_ERR_DECERR_CONST) <= '1';
                                err_pulse_v := true;
                            end if;
                            if (i_bus_response = SC_RSP_OK_CONST and (i_bus_rd_data_valid = '1' or read_fill_index /= 0)) then
                                atomic_write_data_reg <= (atomic_read_word_v and not pkt_info_reg.atomic_mask) or
                                                         (pkt_info_reg.atomic_data and pkt_info_reg.atomic_mask);
                                bus_cmd_is_read_reg   <= '0';
                                bus_cmd_length_reg    <= std_logic_vector(to_unsigned(1, bus_cmd_length_reg'length));
                                core_state            <= ATOMIC_EXT_WR_ARMING;
                            else
                                reply_has_data_reg <= '0';
                                if (reply_suppress_reg = '1') then
                                    core_state <= IDLING;
                                else
                                    deferred_atomic_pending   <= '1';
                                    deferred_atomic_pkt_info  <= pkt_info_reg;
                                    deferred_atomic_response  <= i_bus_response;
                                    deferred_atomic_has_data  <= '0';
                                    deferred_atomic_suppress  <= reply_suppress_reg;
                                    deferred_atomic_data_word <= (others => '0');
                                    core_state                <= IDLING;
                                end if;
                            end if;
                        end if;

                    when ATOMIC_EXT_WR_ARMING =>
                        if (i_bus_cmd_ready = '1') then
                            bus_cmd_valid_pulse <= '1';
                            write_stream_index  <= (others => '0');
                            core_state          <= ATOMIC_EXT_WR_RUNNING;
                        end if;

                    when ATOMIC_EXT_WR_RUNNING =>
                        if (i_bus_wr_data_ready = '1') then
                        end if;

                        if (i_bus_done = '1') then
                            response_reg_v := i_bus_response;
                            if (i_bus_response = SC_RSP_SLVERR_CONST) then
                                hub_err_flags(HUB_ERR_SLVERR_CONST) <= '1';
                                err_pulse_v := true;
                            elsif (i_bus_response = SC_RSP_DECERR_CONST) then
                                hub_err_flags(HUB_ERR_DECERR_CONST) <= '1';
                                err_pulse_v := true;
                            end if;
                            if (reply_suppress_reg = '1') then
                                core_state <= IDLING;
                            else
                                deferred_atomic_pending   <= '1';
                                deferred_atomic_pkt_info  <= pkt_info_reg;
                                deferred_atomic_response  <= i_bus_response;
                                deferred_atomic_has_data  <= '1';
                                deferred_atomic_suppress  <= reply_suppress_reg;
                                deferred_atomic_data_word <= atomic_read_data_reg;
                                core_state                <= IDLING;
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
                                reply_stream_index       <= (others => '0');
                                reply_arm_pending        <= '1';
                                reply_arm_use_fifo_usedw <= '0';
                                core_state               <= RD_REPLY_ARMING;
                            end if;
                        end if;

                    when RD_REPLY_ARMING =>
                        if (reply_arm_pending = '1') then
                            if (reply_arm_use_fifo_usedw = '1') then
                                reply_words_remaining <= resize(unsigned(rd_fifo_usedw), reply_words_remaining'length);
                            else
                                reply_words_remaining <= pkt_len_v;
                            end if;
                            reply_arm_pending        <= '0';
                            reply_arm_use_fifo_usedw <= '0';
                        elsif (tx_reply_ready_q = '1') then
                            tx_reply_start_pulse <= '1';
                            core_state           <= RD_REPLY_STREAMING;
                        end if;

                    when RD_REPLY_STREAMING =>
                        if (i_tx_data_ready = '1' and rd_fifo_empty = '0') then
                            if (reply_words_remaining <= 1) then
                                core_state <= WAITING_REPLY;
                            end if;
                            if (reply_words_remaining /= 0) then
                                reply_words_remaining <= reply_words_remaining - 1;
                            end if;
                        end if;

                    when INT_WR_DRAINING =>
                        int_sideband_write_v := (
                            pkt_is_internal_func(pkt_info_reg) and
                            pkt_is_read_func(pkt_info_reg) = false and
                            pkt_info_reg.atomic_flag = '0' and
                            pkt_len_v = 1
                        );
                        if (int_sideband_write_v = true) then
                            write_word_v := pkt_info_reg.atomic_data;
                        else
                            write_word_v := i_wr_data_q;
                        end if;

                        if (((int_sideband_write_v = true) or i_wr_data_empty = '0') and drain_remaining > 0) then
                            if (drain_remaining = pkt_len_v) then
                                if (pkt_len_v /= 1) then
                                    response_reg_v        := SC_RSP_SLVERR_CONST;
                                    internal_addr_error_v := true;
                                else
                                    csr_write_offset_v := to_integer(unsigned(pkt_info_reg.start_address(15 downto 0))) - HUB_CSR_BASE_ADDR_CONST;
                                    case csr_write_offset_v is
                                        when HUB_CSR_WO_CTRL_CONST =>
                                            hub_enable <= write_word_v(0);
                                            if (write_word_v(1) = '1' or write_word_v(2) = '1') then
                                                hub_err_flags        <= (others => '0');
                                                hub_err_count        <= (others => '0');
                                                ext_pkt_read_count   <= (others => '0');
                                                ext_pkt_write_count  <= (others => '0');
                                                ext_word_read_count  <= (others => '0');
                                                last_ext_read_addr   <= (others => '0');
                                                last_ext_read_data   <= (others => '0');
                                            end if;
                                            if (write_word_v(2) = '1') then
                                                soft_reset_pending <= '1';
                                            end if;
                                        when HUB_CSR_WO_ERR_FLAGS_CONST =>
                                            hub_err_flags <= hub_err_flags and not write_word_v;
                                        when HUB_CSR_WO_SCRATCH_CONST =>
                                            hub_scratch <= write_word_v;
                                        when HUB_CSR_WO_FIFO_CFG_CONST =>
                                            hub_upload_store_forward <= write_word_v(1);
                                        when HUB_CSR_WO_OOO_CTRL_CONST =>
                                            if (OOO_ENABLE_G) then
                                                ooo_ctrl_enable <= write_word_v(0);
                                            else
                                                ooo_ctrl_enable <= '0';
                                            end if;
                                        when others =>
                                            response_reg_v        := SC_RSP_SLVERR_CONST;
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
                            wr_data_word_reg    <= i_wr_data_q;
                            wr_data_valid_reg   <= '1';
                            wr_data_reload_pending <= '0';
                            core_state          <= EXT_WR_RUNNING;
                        end if;

                    when EXT_WR_RUNNING =>
                        ext_write_word_v := wr_data_word_reg;
                        if (wr_data_reload_pending = '1') then
                            ext_write_word_v := i_wr_data_q;
                        end if;

                        if (i_bus_wr_data_ready = '1' and wr_data_valid_reg = '1') then
                            write_stream_index       <= write_stream_index + 1;
                            if (write_stream_index + 1 >= pkt_len_v) then
                                wr_data_valid_reg      <= '0';
                                wr_data_reload_pending <= '0';
                            else
                                wr_data_valid_reg      <= '1';
                                wr_data_reload_pending <= '1';
                            end if;
                        end if;

                        if (i_bus_done = '1') then
                            response_reg_v := i_bus_response;
                            if (i_bus_response = SC_RSP_SLVERR_CONST) then
                                hub_err_flags(HUB_ERR_SLVERR_CONST) <= '1';
                                err_pulse_v := true;
                            elsif (i_bus_response = SC_RSP_DECERR_CONST) then
                                hub_err_flags(HUB_ERR_DECERR_CONST) <= '1';
                                err_pulse_v := true;
                            end if;
                            if (reply_suppress_reg = '1') then
                                core_state <= IDLING;
                            else
                                core_state <= WR_REPLY_ARMING;
                            end if;
                            wr_data_valid_reg      <= '0';
                            wr_data_reload_pending <= '0';
                        end if;

                    when WR_REPLY_ARMING =>
                        if (tx_reply_ready_q = '1') then
                            tx_reply_start_pulse <= '1';
                            core_state           <= WAITING_REPLY;
                        end if;

                    when WAITING_REPLY =>
                        if (i_tx_reply_done = '1') then
                            core_state <= IDLING;
                        elsif (
                            tx_reply_ready_q = '1' and
                            reply_has_data_reg = '1' and
                            reply_suppress_reg = '0' and
                            rd_fifo_empty = '0'
                        ) then
                            reply_stream_index       <= (others => '0');
                            reply_arm_pending        <= '1';
                            reply_arm_use_fifo_usedw <= '1';
                            core_state               <= RD_REPLY_ARMING;
                        end if;
                end case;

                if (internal_addr_error_v = true) then
                    hub_err_flags(HUB_ERR_INTERNAL_ADDR_CONST) <= '1';
                    err_pulse_v := true;
                end if;

                if (err_pulse_v = true) then
                    err_count_pulse_q <= '1';
                else
                    err_count_pulse_q <= '0';
                end if;

                response_reg         <= response_reg_v;
                pending_pkt_mem      <= queue_mem_v;
                pending_pkt_rd_ptr   <= 0;
                pending_pkt_wr_ptr   <= 0;
                pending_pkt_count    <= queue_count_v;
                pending_ext_count    <= queue_ext_count_v;
                barrier_guard_counter <= barrier_guard_v;

                if (soft_reset_request_v = true) then
                    core_state               <= IDLING;
                    pkt_info_reg             <= SC_PKT_INFO_RESET_CONST;
                    reply_suppress_reg       <= '0';
                    reply_has_data_reg       <= '0';
                    reply_is_internal_reg    <= '0';
                    response_reg_v           := SC_RSP_OK_CONST;
                    hub_enable               <= '1';
                    hub_scratch              <= (others => '0');
                    hub_err_flags            <= (others => '0');
                    hub_err_count            <= (others => '0');
                    hub_gts_counter          <= (others => '0');
                    hub_gts_snapshot         <= (others => '0');
                    hub_upload_store_forward <= '1';
                    ooo_ctrl_enable          <= '0';
                    ord_drain_count          <= (others => '0');
                    ord_hold_count           <= (others => '0');
                    ext_pkt_read_count       <= (others => '0');
                    ext_pkt_write_count      <= (others => '0');
                    ext_word_read_count      <= (others => '0');
                    last_ext_read_addr       <= (others => '0');
                    last_ext_read_data       <= (others => '0');
                    read_fill_index          <= (others => '0');
                    reply_stream_index       <= (others => '0');
                    reply_words_remaining    <= (others => '0');
                    reply_arm_pending        <= '0';
                    reply_arm_use_fifo_usedw <= '0';
                    write_stream_index       <= (others => '0');
                    drain_remaining          <= (others => '0');
                    atomic_read_data_reg     <= (others => '0');
                    atomic_write_data_reg    <= (others => '0');
                    deferred_atomic_pending  <= '0';
                    deferred_atomic_pkt_info <= SC_PKT_INFO_RESET_CONST;
                    deferred_atomic_response <= SC_RSP_OK_CONST;
                    deferred_atomic_has_data <= '0';
                    deferred_atomic_suppress <= '0';
                    deferred_atomic_data_word <= (others => '0');
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
                    pending_pkt_mem          <= (others => SC_PKT_INFO_RESET_CONST);
                    pending_pkt_rd_ptr       <= 0;
                    pending_pkt_wr_ptr       <= 0;
                    pending_pkt_count        <= 0;
                    pending_ext_count        <= 0;
                    barrier_guard_counter    <= 0;
                    wr_data_valid_reg        <= '0';
                    wr_data_word_reg         <= (others => '0');
                    wr_data_reload_pending   <= '0';
                    dispatch_pkt_reg         <= SC_PKT_INFO_RESET_CONST;
                    dispatch_queue_idx_reg   <= 0;
                    err_count_pulse_q        <= '0';
                    tx_reply_ready_q         <= '0';
                    soft_reset_pending       <= '0';
                end if;
            end if;
        end if;
    end process core_fsm;

    ext_write_diag_reg : process(i_clk)
        variable pkt_len_v            : natural;
        variable int_sideband_write_v : boolean;
        variable write_beat_valid_v   : boolean;
        variable write_word_v         : std_logic_vector(31 downto 0);
        variable ctrl_clear_v         : boolean;
    begin
        if rising_edge(i_clk) then
            if (i_rst = '1') then
                ext_word_write_count   <= (others => '0');
                last_ext_write_addr    <= (others => '0');
                last_ext_write_data    <= (others => '0');
                ext_write_diag_pending <= '0';
                ext_write_diag_addr_hold <= (others => '0');
                ext_write_diag_data_hold <= (others => '0');
            else
                pkt_len_v            := to_integer(pkt_length_func(pkt_info_reg));
                int_sideband_write_v := (
                    pkt_is_internal_func(pkt_info_reg) and
                    pkt_is_read_func(pkt_info_reg) = false and
                    pkt_info_reg.atomic_flag = '0' and
                    pkt_len_v = 1
                );
                write_word_v       := i_wr_data_q;
                write_beat_valid_v := (((int_sideband_write_v = true) or i_wr_data_empty = '0') and drain_remaining > 0);
                ctrl_clear_v       := false;

                if (int_sideband_write_v) then
                    write_word_v := pkt_info_reg.atomic_data;
                end if;

                if (
                    core_state = INT_WR_DRAINING and
                    write_beat_valid_v and
                    drain_remaining = pkt_length_func(pkt_info_reg) and
                    int_sideband_write_v and
                    to_integer(unsigned(pkt_info_reg.start_address(15 downto 0))) = HUB_CSR_BASE_ADDR_CONST + HUB_CSR_WO_CTRL_CONST and
                    (write_word_v(1) = '1' or write_word_v(2) = '1')
                ) then
                    ctrl_clear_v := true;
                end if;

                if (soft_reset_pending = '1' or ctrl_clear_v) then
                    ext_word_write_count   <= (others => '0');
                    last_ext_write_addr    <= (others => '0');
                    last_ext_write_data    <= (others => '0');
                    ext_write_diag_pending <= '0';
                    ext_write_diag_addr_hold <= (others => '0');
                    ext_write_diag_data_hold <= (others => '0');
                else
                    if (ext_write_diag_pending = '1') then
                        ext_word_write_count   <= sat_inc32_func(ext_word_write_count);
                        last_ext_write_addr    <= ext_write_diag_addr_hold;
                        last_ext_write_data    <= ext_write_diag_data_hold;
                        ext_write_diag_pending <= '0';
                    end if;

                    if (core_state = ATOMIC_EXT_WR_RUNNING and i_bus_wr_data_ready = '1') then
                        ext_write_diag_pending   <= '1';
                        ext_write_diag_addr_hold <= std_logic_vector(resize(unsigned(pkt_info_reg.start_address(15 downto 0)), 32));
                        ext_write_diag_data_hold <= atomic_write_data_reg;
                    elsif (core_state = EXT_WR_RUNNING and i_bus_wr_data_ready = '1' and wr_data_valid_reg = '1') then
                        ext_write_diag_pending   <= '1';
                        ext_write_diag_addr_hold <= std_logic_vector(resize(unsigned(pkt_info_reg.start_address(15 downto 0)), 32) + resize(write_stream_index, 32));
                        if (wr_data_reload_pending = '1') then
                            ext_write_diag_data_hold <= i_wr_data_q;
                        else
                            ext_write_diag_data_hold <= wr_data_word_reg;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process ext_write_diag_reg;
end architecture rtl;
