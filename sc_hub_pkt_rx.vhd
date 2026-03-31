-- File name: sc_hub_pkt_rx.vhd
-- Author: Yifeng Wang (yifenwan@phys.ethz.ch)
-- =======================================
-- Version : 26.2.9
-- Date    : 20260331
-- Change  : Split external packet-start admission from core dequeue admission so backpressure can block new packets without blocking queued-core handoff.
-- =======================================
-- altera vhdl_input_version vhdl_2008

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sc_hub_pkg.all;

entity sc_hub_pkt_rx is
    generic(
        MAX_BURST_G        : positive := MAX_BURST_WORDS_CONST;
        PKT_TIMEOUT_CYCLES : positive := DEFAULT_PKT_TIMEOUT_CONST;
        PKT_QUEUE_DEPTH_G  : positive := 16
    );
    port(
        i_clk                : in  std_logic;
        i_rst                : in  std_logic;
        i_soft_reset         : in  std_logic;
        i_download_data      : in  std_logic_vector(31 downto 0);
        i_download_datak     : in  std_logic_vector(3 downto 0);
        i_accept_new_pkt     : in  std_logic;
        i_allow_new_pkt      : in  std_logic;
        o_download_ready     : out std_logic;
        o_pkt_in_progress    : out std_logic;
        o_pkt_valid          : out std_logic;
        o_pkt_info           : out sc_pkt_info_t;
        i_wr_data_rdreq      : in  std_logic;
        o_wr_data_q          : out std_logic_vector(31 downto 0);
        o_wr_data_empty      : out std_logic;
        o_pkt_drop_count     : out std_logic_vector(15 downto 0);
        o_pkt_drop_pulse     : out std_logic;
        o_fifo_usedw         : out std_logic_vector(8 downto 0);
        o_fifo_full          : out std_logic;
        o_fifo_overflow      : out std_logic;
        o_fifo_overflow_pulse: out std_logic
    );
end entity sc_hub_pkt_rx;

architecture rtl of sc_hub_pkt_rx is
    type rx_state_t is (IDLING, ADDRING, LENGTHING, WRITING_DATA, WAITING_TRAILER);
    subtype pkt_queue_index_t is natural range 0 to PKT_QUEUE_DEPTH_G - 1;
    type pkt_queue_mem_t is array (pkt_queue_index_t) of sc_pkt_info_t;

    signal rx_state              : rx_state_t := IDLING;
    signal pkt_info_work         : sc_pkt_info_t := SC_PKT_INFO_RESET_CONST;
    signal pkt_drop_count        : unsigned(15 downto 0) := (others => '0');
    signal pkt_drop_pulse        : std_logic := '0';
    signal fifo_overflow_sticky  : std_logic := '0';
    signal fifo_overflow_pulse   : std_logic := '0';
    signal fifo_capture_start    : std_logic := '0';
    signal fifo_write_en         : std_logic := '0';
    signal fifo_write_data       : std_logic_vector(31 downto 0) := (others => '0');
    signal fifo_commit           : std_logic := '0';
    signal fifo_rollback         : std_logic := '0';
    signal fifo_q                : std_logic_vector(31 downto 0);
    signal fifo_empty            : std_logic;
    signal fifo_full_int         : std_logic;
    signal fifo_usedw_int        : std_logic_vector(8 downto 0);
    signal fifo_overflow_int     : std_logic;
    signal write_words_seen      : unsigned(15 downto 0) := (others => '0');
    signal idle_cycles           : natural range 0 to PKT_TIMEOUT_CYCLES := 0;
    signal pkt_queue_mem         : pkt_queue_mem_t := (others => SC_PKT_INFO_RESET_CONST);
    signal pkt_queue_rd_ptr      : pkt_queue_index_t := 0;
    signal pkt_queue_wr_ptr      : pkt_queue_index_t := 0;
    signal pkt_queue_count       : natural range 0 to PKT_QUEUE_DEPTH_G := 0;

    function is_sc_preamble_func (
        data_in  : std_logic_vector(31 downto 0);
        datak_in : std_logic_vector(3 downto 0)
    ) return boolean is
    begin
        return (data_in(31 downto 26) = "000111" and data_in(7 downto 0) = K285_CONST and datak_in = "0001");
    end function is_sc_preamble_func;

    function is_trailer_func (
        data_in  : std_logic_vector(31 downto 0);
        datak_in : std_logic_vector(3 downto 0)
    ) return boolean is
    begin
        return (data_in(7 downto 0) = K284_CONST and datak_in = "0001");
    end function is_trailer_func;

    function is_skip_func (
        data_in  : std_logic_vector(31 downto 0);
        datak_in : std_logic_vector(3 downto 0)
    ) return boolean is
    begin
        return (data_in = SKIP_WORD_CONST and datak_in = "0001");
    end function is_skip_func;

    function is_idle_func (
        data_in  : std_logic_vector(31 downto 0);
        datak_in : std_logic_vector(3 downto 0)
    ) return boolean is
    begin
        return (data_in = x"00000000" and datak_in = "0000");
    end function is_idle_func;

    function next_pkt_queue_index_func (
        value_in : pkt_queue_index_t
    ) return pkt_queue_index_t is
    begin
        if (value_in = PKT_QUEUE_DEPTH_G - 1) then
            return 0;
        else
            return value_in + 1;
        end if;
    end function next_pkt_queue_index_func;
begin
    fifo_inst : entity work.sc_hub_fifo_sf
    generic map(
        WIDTH_G => 32,
        DEPTH_G => MAX_BURST_G
    )
    port map(
        csi_clk       => i_clk,
        rsi_reset     => i_rst,
        clear         => i_soft_reset,
        capture_start => fifo_capture_start,
        write_en      => fifo_write_en,
        write_data    => fifo_write_data,
        commit        => fifo_commit,
        rollback      => fifo_rollback,
        read_en       => i_wr_data_rdreq,
        read_data     => fifo_q,
        empty         => fifo_empty,
        full          => fifo_full_int,
        usedw         => fifo_usedw_int,
        overflow      => fifo_overflow_int
    );

    o_wr_data_q           <= fifo_q;
    o_wr_data_empty       <= fifo_empty;
    o_pkt_in_progress     <= '1' when (rx_state /= IDLING) else '0';
    o_pkt_valid           <= '1' when (pkt_queue_count /= 0) else '0';
    o_pkt_info            <= pkt_queue_mem(pkt_queue_rd_ptr) when (pkt_queue_count /= 0) else SC_PKT_INFO_RESET_CONST;
    o_pkt_drop_count      <= std_logic_vector(pkt_drop_count);
    o_pkt_drop_pulse      <= pkt_drop_pulse;
    o_fifo_usedw          <= fifo_usedw_int;
    o_fifo_full           <= fifo_full_int;
    o_fifo_overflow       <= fifo_overflow_sticky;
    o_fifo_overflow_pulse <= fifo_overflow_pulse;

    o_download_ready <= '1'
        when (rx_state /= IDLING) or (pkt_queue_count < PKT_QUEUE_DEPTH_G)
        else '0';

    packet_receiver : process(i_clk)
        variable is_skip_v      : boolean;
        variable is_preamble_v  : boolean;
        variable is_trailer_v   : boolean;
        variable is_idle_v      : boolean;
        variable is_read_pkt_v  : boolean;
        variable drop_packet_v  : boolean;
        variable commit_packet_v: boolean;
        variable enqueue_queue_v : boolean;
        variable enqueue_pkt_info_v : sc_pkt_info_t;
        variable queue_rd_ptr_v   : pkt_queue_index_t;
        variable queue_wr_ptr_v   : pkt_queue_index_t;
        variable queue_count_v    : natural range 0 to PKT_QUEUE_DEPTH_G;
    begin
        if rising_edge(i_clk) then
            if (i_rst = '1' or i_soft_reset = '1') then
                rx_state             <= IDLING;
                pkt_info_work        <= SC_PKT_INFO_RESET_CONST;
                pkt_drop_count       <= (others => '0');
                pkt_drop_pulse       <= '0';
                fifo_overflow_sticky <= '0';
                fifo_overflow_pulse  <= '0';
                fifo_capture_start   <= '0';
                fifo_write_en        <= '0';
                fifo_write_data      <= (others => '0');
                fifo_commit          <= '0';
                fifo_rollback        <= '0';
                write_words_seen     <= (others => '0');
                idle_cycles          <= 0;
                pkt_queue_mem        <= (others => SC_PKT_INFO_RESET_CONST);
                pkt_queue_rd_ptr     <= 0;
                pkt_queue_wr_ptr     <= 0;
                pkt_queue_count      <= 0;
            else
                pkt_drop_pulse      <= '0';
                fifo_overflow_pulse <= '0';
                fifo_capture_start  <= '0';
                fifo_write_en       <= '0';
                fifo_write_data     <= (others => '0');
                fifo_commit         <= '0';
                fifo_rollback       <= '0';
                enqueue_queue_v     := false;
                enqueue_pkt_info_v  := SC_PKT_INFO_RESET_CONST;
                queue_rd_ptr_v      := pkt_queue_rd_ptr;
                queue_wr_ptr_v      := pkt_queue_wr_ptr;
                queue_count_v       := pkt_queue_count;

                if (pkt_queue_count /= 0 and i_allow_new_pkt = '1') then
                    queue_rd_ptr_v := next_pkt_queue_index_func(queue_rd_ptr_v);
                    queue_count_v  := queue_count_v - 1;
                end if;

                is_skip_v       := is_skip_func(i_download_data, i_download_datak);
                is_preamble_v   := is_sc_preamble_func(i_download_data, i_download_datak);
                is_trailer_v    := is_trailer_func(i_download_data, i_download_datak);
                is_idle_v       := is_idle_func(i_download_data, i_download_datak);
                is_read_pkt_v   := pkt_is_read_func(pkt_info_work);
                drop_packet_v   := false;
                commit_packet_v := false;

                if (fifo_overflow_int = '1') then
                    fifo_overflow_sticky <= '1';
                    fifo_overflow_pulse  <= '1';
                end if;

                if (rx_state /= IDLING) then
                    if (is_skip_v = true or is_idle_v = true) then
                        if (idle_cycles < PKT_TIMEOUT_CYCLES) then
                            idle_cycles <= idle_cycles + 1;
                        end if;
                    else
                        idle_cycles <= 0;
                    end if;

                    if (idle_cycles = PKT_TIMEOUT_CYCLES) then
                        drop_packet_v := true;
                    end if;
                else
                    idle_cycles <= 0;
                end if;

                if (rx_state /= IDLING and is_preamble_v = true and i_accept_new_pkt = '1') then
                    if (pkt_is_read_func(pkt_info_work) = false) then
                        fifo_rollback  <= '1';
                        pkt_drop_pulse <= '1';
                        pkt_drop_count <= sat_inc16_func(pkt_drop_count);
                    end if;
                    pkt_info_work.sc_type        <= i_download_data(25 downto 24);
                    pkt_info_work.fpga_id        <= i_download_data(23 downto 8);
                    pkt_info_work.start_address  <= (others => '0');
                    pkt_info_work.mask_m         <= '0';
                    pkt_info_work.mask_s         <= '0';
                    pkt_info_work.mask_t         <= '0';
                    pkt_info_work.mask_r         <= '0';
                    pkt_info_work.rw_length      <= (others => '0');
                    fifo_capture_start           <= '1';
                    write_words_seen            <= (others => '0');
                    idle_cycles                 <= 0;
                    rx_state                    <= ADDRING;
                else
                    case rx_state is
                        when IDLING =>
                            write_words_seen <= (others => '0');
                            if (i_accept_new_pkt = '1' and pkt_queue_count < PKT_QUEUE_DEPTH_G and is_preamble_v = true) then
                                pkt_info_work.sc_type       <= i_download_data(25 downto 24);
                                pkt_info_work.fpga_id       <= i_download_data(23 downto 8);
                                pkt_info_work.start_address <= (others => '0');
                                pkt_info_work.mask_m        <= '0';
                                pkt_info_work.mask_s        <= '0';
                                pkt_info_work.mask_t        <= '0';
                                pkt_info_work.mask_r        <= '0';
                                pkt_info_work.rw_length     <= (others => '0');
                                fifo_capture_start          <= '1';
                                rx_state                    <= ADDRING;
                            end if;

                        when ADDRING =>
                            if (drop_packet_v = true) then
                                fifo_rollback <= '1';
                                rx_state      <= IDLING;
                            elsif (is_skip_v = false) then
                                if (is_trailer_v = true or is_preamble_v = true) then
                                    drop_packet_v := true;
                                else
                                    pkt_info_work.start_address <= i_download_data(23 downto 0);
                                    pkt_info_work.mask_m        <= i_download_data(27);
                                    pkt_info_work.mask_s        <= i_download_data(26);
                                    pkt_info_work.mask_t        <= i_download_data(25);
                                    pkt_info_work.mask_r        <= i_download_data(24);
                                    rx_state                    <= LENGTHING;
                                end if;
                            end if;

                        when LENGTHING =>
                            if (drop_packet_v = true) then
                                fifo_rollback <= '1';
                                rx_state      <= IDLING;
                            elsif (is_skip_v = false) then
                                pkt_info_work.rw_length <= i_download_data(15 downto 0);
                                if (unsigned(i_download_data(15 downto 0)) > MAX_BURST_G) then
                                    drop_packet_v := true;
                                elsif (is_read_pkt_v = true) then
                                    if (queue_count_v < PKT_QUEUE_DEPTH_G) then
                                        enqueue_pkt_info_v           := pkt_info_work;
                                        enqueue_pkt_info_v.rw_length := i_download_data(15 downto 0);
                                        enqueue_queue_v              := true;
                                        rx_state                     <= WAITING_TRAILER;
                                    else
                                        drop_packet_v := true;
                                    end if;
                                elsif (unsigned(i_download_data(15 downto 0)) = 0) then
                                    rx_state <= WAITING_TRAILER;
                                else
                                    write_words_seen <= (others => '0');
                                    rx_state         <= WRITING_DATA;
                                end if;
                            end if;

                        when WRITING_DATA =>
                            if (drop_packet_v = true) then
                                fifo_rollback <= '1';
                                rx_state      <= IDLING;
                            elsif (is_skip_v = false) then
                                if (is_trailer_v = true) then
                                    drop_packet_v := true;
                                elsif (write_words_seen < unsigned(pkt_info_work.rw_length)) then
                                    fifo_write_en   <= '1';
                                    fifo_write_data <= i_download_data;
                                    if (fifo_full_int = '1') then
                                        drop_packet_v := true;
                                    end if;

                                    if (write_words_seen + 1 >= unsigned(pkt_info_work.rw_length)) then
                                        rx_state <= WAITING_TRAILER;
                                    end if;

                                    write_words_seen <= write_words_seen + 1;
                                else
                                    drop_packet_v := true;
                                end if;
                            end if;

                        when WAITING_TRAILER =>
                            if (drop_packet_v = true) then
                                fifo_rollback <= '1';
                                rx_state      <= IDLING;
                            elsif (is_skip_v = false) then
                                if (is_trailer_v = true) then
                                    commit_packet_v := true;
                                elsif (is_idle_v = true) then
                                    null;
                                else
                                    drop_packet_v := true;
                                end if;
                            end if;
                    end case;

                    if (drop_packet_v = true) then
                        fifo_rollback  <= '1';
                        pkt_drop_pulse <= '1';
                        pkt_drop_count <= sat_inc16_func(pkt_drop_count);
                        rx_state       <= IDLING;
                        write_words_seen <= (others => '0');
                    elsif (commit_packet_v = true) then
                        if (pkt_is_read_func(pkt_info_work)) then
                            fifo_commit <= '1';
                        elsif (queue_count_v < PKT_QUEUE_DEPTH_G) then
                            fifo_commit        <= '1';
                            enqueue_pkt_info_v := pkt_info_work;
                            enqueue_queue_v    := true;
                        else
                            fifo_rollback  <= '1';
                            pkt_drop_pulse <= '1';
                            pkt_drop_count <= sat_inc16_func(pkt_drop_count);
                        end if;
                        rx_state         <= IDLING;
                        write_words_seen <= (others => '0');
                    end if;

                    if (enqueue_queue_v = true) then
                        pkt_queue_mem(queue_wr_ptr_v) <= enqueue_pkt_info_v;
                        queue_wr_ptr_v                := next_pkt_queue_index_func(queue_wr_ptr_v);
                        queue_count_v                 := queue_count_v + 1;
                    end if;

                    pkt_queue_rd_ptr <= queue_rd_ptr_v;
                    pkt_queue_wr_ptr <= queue_wr_ptr_v;
                    pkt_queue_count  <= queue_count_v;
                end if;
            end if;
        end if;
    end process packet_receiver;
end architecture rtl;
