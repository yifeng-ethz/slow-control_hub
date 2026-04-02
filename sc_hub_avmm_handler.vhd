-- File name: sc_hub_avmm_handler.vhd
-- Author: Yifeng Wang (yifenwan@phys.ethz.ch)
-- =======================================
-- Version : 26.2.1
-- Date    : 20260331
-- Change  : Bound the timeout counter to the configured read/write timeout
--           range so the timeout-enable cone does not inherit an unnecessary
--           wide integer datapath.
-- =======================================
-- altera vhdl_input_version vhdl_2008

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sc_hub_pkg.all;

entity sc_hub_avmm_handler is
    generic(
        RD_TIMEOUT_CYCLES_G : positive := DEFAULT_RD_TIMEOUT_CONST;
        WR_TIMEOUT_CYCLES_G : positive := DEFAULT_WR_TIMEOUT_CONST
    );
    port(
        i_clk               : in  std_logic;
        i_rst               : in  std_logic;
        i_cmd_valid         : in  std_logic;
        o_cmd_ready         : out std_logic;
        i_cmd_is_read       : in  std_logic;
        i_cmd_address       : in  std_logic_vector(15 downto 0);
        i_cmd_length        : in  std_logic_vector(15 downto 0);
        i_wr_data_valid     : in  std_logic;
        i_wr_data           : in  std_logic_vector(31 downto 0);
        o_wr_data_ready     : out std_logic;
        o_rd_data_valid     : out std_logic;
        o_rd_data           : out std_logic_vector(31 downto 0);
        o_rd_data_last      : out std_logic;
        o_done              : out std_logic;
        o_response          : out std_logic_vector(1 downto 0);
        o_busy              : out std_logic;
        o_timeout_pulse     : out std_logic;
        avm_hub_address      : out std_logic_vector(15 downto 0);
        avm_hub_read         : out std_logic;
        avm_hub_readdata     : in  std_logic_vector(31 downto 0);
        avm_hub_writeresponsevalid : in  std_logic;
        avm_hub_response     : in  std_logic_vector(1 downto 0);
        avm_hub_write        : out std_logic;
        avm_hub_writedata    : out std_logic_vector(31 downto 0);
        avm_hub_waitrequest  : in  std_logic;
        avm_hub_readdatavalid: in  std_logic;
        avm_hub_burstcount   : out std_logic_vector(8 downto 0)
    );
end entity sc_hub_avmm_handler;

architecture rtl of sc_hub_avmm_handler is
    type avmm_state_t is (IDLING, LAUNCHING_READ, READING_DATA, WRITING_DATA, WAITING_WRITE_RSP);

    function max_pos_func (
        lhs : positive;
        rhs : positive
    ) return positive is
    begin
        if (lhs >= rhs) then
            return lhs;
        else
            return rhs;
        end if;
    end function max_pos_func;

    constant TIMEOUT_COUNTER_MAX_C : positive := max_pos_func(RD_TIMEOUT_CYCLES_G, WR_TIMEOUT_CYCLES_G);
    subtype timeout_counter_t is natural range 0 to TIMEOUT_COUNTER_MAX_C;

    signal avmm_state          : avmm_state_t := IDLING;
    signal cmd_address_reg     : std_logic_vector(15 downto 0) := (others => '0');
    signal cmd_length_reg      : unsigned(15 downto 0) := (others => '0');
    signal words_seen          : unsigned(15 downto 0) := (others => '0');
    signal timeout_counter     : timeout_counter_t := 0;
    signal response_reg        : std_logic_vector(1 downto 0) := SC_RSP_OK_CONST;
    signal rd_data_valid_pulse : std_logic := '0';
    signal rd_data_reg         : std_logic_vector(31 downto 0) := (others => '0');
    signal rd_data_last_pulse  : std_logic := '0';
    signal done_pulse          : std_logic := '0';
    signal timeout_pulse       : std_logic := '0';
begin
    avm_hub_address    <= cmd_address_reg;
    avm_hub_burstcount <= std_logic_vector(resize(cmd_length_reg(8 downto 0), avm_hub_burstcount'length));
    avm_hub_writedata  <= i_wr_data;

    avm_hub_read  <= '1' when (avmm_state = LAUNCHING_READ) else '0';
    avm_hub_write <= '1' when (avmm_state = WRITING_DATA and i_wr_data_valid = '1') else '0';

    o_cmd_ready     <= '1' when (avmm_state = IDLING) else '0';
    o_wr_data_ready <= '1' when (avmm_state = WRITING_DATA and avm_hub_waitrequest = '0') else '0';
    o_rd_data_valid <= rd_data_valid_pulse;
    o_rd_data       <= rd_data_reg;
    o_rd_data_last  <= rd_data_last_pulse;
    o_done          <= done_pulse;
    o_response      <= response_reg;
    o_busy          <= '0' when (avmm_state = IDLING) else '1';
    o_timeout_pulse <= timeout_pulse;

    bus_handler : process(i_clk)
    begin
        if rising_edge(i_clk) then
            if (i_rst = '1') then
                avmm_state          <= IDLING;
                cmd_address_reg     <= (others => '0');
                cmd_length_reg      <= (others => '0');
                words_seen          <= (others => '0');
                timeout_counter     <= 0;
                response_reg        <= SC_RSP_OK_CONST;
                rd_data_valid_pulse <= '0';
                rd_data_reg         <= (others => '0');
                rd_data_last_pulse  <= '0';
                done_pulse          <= '0';
                timeout_pulse       <= '0';
            else
                rd_data_valid_pulse <= '0';
                rd_data_last_pulse  <= '0';
                done_pulse          <= '0';
                timeout_pulse       <= '0';

                case avmm_state is
                    when IDLING =>
                        timeout_counter <= 0;
                        words_seen      <= (others => '0');
                        if (i_cmd_valid = '1') then
                            cmd_address_reg <= i_cmd_address;
                            cmd_length_reg  <= unsigned(i_cmd_length);
                            response_reg    <= SC_RSP_OK_CONST;
                            if (i_cmd_is_read = '1') then
                                avmm_state <= LAUNCHING_READ;
                            else
                                avmm_state <= WRITING_DATA;
                            end if;
                        end if;

                    when LAUNCHING_READ =>
                        if (avm_hub_waitrequest = '0') then
                            timeout_counter <= 0;
                            avmm_state      <= READING_DATA;
                        end if;

                    when READING_DATA =>
                        if (avm_hub_readdatavalid = '1') then
                            rd_data_valid_pulse <= '1';
                            timeout_counter     <= 0;

                            if (avm_hub_response = SC_RSP_SLVERR_CONST) then
                                rd_data_reg  <= x"BBADBEEF";
                                response_reg <= avm_hub_response;
                            elsif (avm_hub_response = SC_RSP_DECERR_CONST) then
                                rd_data_reg  <= x"DEADBEEF";
                                response_reg <= avm_hub_response;
                            else
                                rd_data_reg <= avm_hub_readdata;
                            end if;

                            if (avm_hub_response /= SC_RSP_OK_CONST) then
                                response_reg <= avm_hub_response;
                            end if;

                            if (words_seen + 1 >= cmd_length_reg) then
                                rd_data_last_pulse <= '1';
                                done_pulse         <= '1';
                                avmm_state         <= IDLING;
                            end if;

                            words_seen <= words_seen + 1;
                        elsif (timeout_counter + 1 >= RD_TIMEOUT_CYCLES_G) then
                            response_reg    <= SC_RSP_DECERR_CONST;
                            done_pulse      <= '1';
                            timeout_pulse   <= '1';
                            timeout_counter <= 0;
                            avmm_state      <= IDLING;
                        else
                            timeout_counter <= timeout_counter + 1;
                        end if;

                    when WRITING_DATA =>
                        if (i_wr_data_valid = '1' and avm_hub_waitrequest = '0') then
                            if (words_seen + 1 >= cmd_length_reg) then
                                timeout_counter <= 0;
                                avmm_state      <= WAITING_WRITE_RSP;
                            end if;
                            words_seen <= words_seen + 1;
                        end if;

                    when WAITING_WRITE_RSP =>
                        if (avm_hub_writeresponsevalid = '1') then
                            response_reg <= avm_hub_response;
                            done_pulse   <= '1';
                            avmm_state   <= IDLING;
                        elsif (timeout_counter + 1 >= WR_TIMEOUT_CYCLES_G) then
                            response_reg    <= SC_RSP_DECERR_CONST;
                            done_pulse      <= '1';
                            timeout_pulse   <= '1';
                            timeout_counter <= 0;
                            avmm_state      <= IDLING;
                        else
                            timeout_counter <= timeout_counter + 1;
                        end if;
                end case;
            end if;
        end if;
    end process bus_handler;
end architecture rtl;
