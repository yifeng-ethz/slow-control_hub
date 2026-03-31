-- File name: sc_hub_fifo_sf.vhd
-- Author: Yifeng Wang (yifenwan@phys.ethz.ch)
-- =======================================
-- Version : 26.2.0
-- Date    : 20260331
-- Change  : Add the download store-and-forward FIFO with commit/rollback support.
-- =======================================
-- altera vhdl_input_version vhdl_2008

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sc_hub_pkg.all;

entity sc_hub_fifo_sf is
    generic(
        WIDTH_G : positive := 32;
        DEPTH_G : positive := 256
    );
    port(
        csi_clk       : in  std_logic;
        rsi_reset     : in  std_logic;
        clear         : in  std_logic;
        capture_start : in  std_logic;
        write_en      : in  std_logic;
        write_data    : in  std_logic_vector(WIDTH_G - 1 downto 0);
        commit        : in  std_logic;
        rollback      : in  std_logic;
        read_en       : in  std_logic;
        read_data     : out std_logic_vector(WIDTH_G - 1 downto 0);
        empty         : out std_logic;
        full          : out std_logic;
        usedw         : out std_logic_vector(ceil_log2_func(DEPTH_G + 1) - 1 downto 0);
        overflow      : out std_logic
    );
end entity sc_hub_fifo_sf;

architecture rtl of sc_hub_fifo_sf is
    subtype fifo_index_t is natural range 0 to DEPTH_G - 1;
    type fifo_mem_t is array (fifo_index_t) of std_logic_vector(WIDTH_G - 1 downto 0);

    signal fifo_mem         : fifo_mem_t := (others => (others => '0'));
    signal rd_ptr           : fifo_index_t := 0;
    signal commit_wr_ptr    : fifo_index_t := 0;
    signal shadow_wr_ptr    : fifo_index_t := 0;
    signal committed_words  : natural range 0 to DEPTH_G := 0;
    signal shadow_words     : natural range 0 to DEPTH_G := 0;
    signal overflow_sticky  : std_logic := '0';
    signal read_data_int    : std_logic_vector(WIDTH_G - 1 downto 0);

    function next_index_func (
        value_in : fifo_index_t
    ) return fifo_index_t is
    begin
        if (value_in = DEPTH_G - 1) then
            return 0;
        else
            return value_in + 1;
        end if;
    end function next_index_func;
begin
    read_data_int <= fifo_mem(rd_ptr) when (committed_words /= 0) else (others => '0');

    read_data <= read_data_int;
    empty     <= '1' when (committed_words = 0) else '0';
    full      <= '1' when ((committed_words + shadow_words) = DEPTH_G) else '0';
    usedw     <= std_logic_vector(to_unsigned(committed_words + shadow_words, usedw'length));
    overflow  <= overflow_sticky;

    fifo_storage : process(csi_clk)
    begin
        if rising_edge(csi_clk) then
            if (rsi_reset = '1' or clear = '1') then
                rd_ptr          <= 0;
                commit_wr_ptr   <= 0;
                shadow_wr_ptr   <= 0;
                committed_words <= 0;
                shadow_words    <= 0;
                overflow_sticky <= '0';
            else
                if (capture_start = '1') then
                    shadow_wr_ptr   <= commit_wr_ptr;
                    shadow_words    <= 0;
                    overflow_sticky <= '0';
                end if;

                if (write_en = '1') then
                    if ((committed_words + shadow_words) < DEPTH_G) then
                        fifo_mem(shadow_wr_ptr) <= write_data;
                        shadow_wr_ptr           <= next_index_func(shadow_wr_ptr);
                        shadow_words            <= shadow_words + 1;
                    else
                        overflow_sticky <= '1';
                    end if;
                end if;

                if (commit = '1') then
                    commit_wr_ptr   <= shadow_wr_ptr;
                    committed_words <= min_nat_func(DEPTH_G, committed_words + shadow_words);
                    shadow_words    <= 0;
                elsif (rollback = '1') then
                    shadow_wr_ptr   <= commit_wr_ptr;
                    shadow_words    <= 0;
                    overflow_sticky <= '0';
                end if;

                if (read_en = '1' and committed_words > 0) then
                    rd_ptr          <= next_index_func(rd_ptr);
                    committed_words <= committed_words - 1;
                end if;
            end if;
        end if;
    end process fifo_storage;
end architecture rtl;
