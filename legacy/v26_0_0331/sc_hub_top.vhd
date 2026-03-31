-- File name: sc_hub_top.vhd
-- Author: Yifeng Wang (yifenwan@phys.ethz.ch)
-- =======================================
-- Revision: 3.1 (add explicit download/upload FIFO telemetry and hub-managed FIFO controls)
--     Date: Mar 31, 2026
-- =========
-- Description: [Slow Control Hub Top-Level File]
--     hierarchy:
--         top --
--             sc_hub
--             bp_fifo
--             down_fifo

-- ================ synthsizer configuration ===================
-- altera vhdl_input_version vhdl_2008
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_arith.conv_std_logic_vector;

entity sc_hub_top is
    generic(
        BACKPRESSURE               : boolean := True;
        SCHEDULER_USE_PKT_TRANSFER : boolean := True; -- should be true if you use the mux Intel ip.
        INVERT_RD_SIG              : boolean := True; -- Intel Mux IP has inverted ready signal at its input
        DEBUG                      : natural := 1
    );
    port(
        i_clk                         : in  std_logic;
        i_rst                         : in  std_logic;

        i_linkin_data                 : in  std_logic_vector(31 downto 0);
        i_linkin_datak                : in  std_logic_vector(3 downto 0);
        o_linkin_ready                : out std_logic;

        aso_to_uplink_data            : out std_logic_vector(35 downto 0); -- bit 35-32(datak), bit 31-0(data)
        aso_to_uplink_valid           : out std_logic;
        aso_to_uplink_ready           : in  std_logic;
        aso_to_uplink_startofpacket   : out std_logic;
        aso_to_uplink_endofpacket     : out std_logic;

        avm_m0_address                : out std_logic_vector(15 downto 0);
        avm_m0_read                   : out std_logic;
        avm_m0_readdata               : in  std_logic_vector(31 downto 0);
        avm_m0_writeresponsevalid     : in  std_logic;
        avm_m0_response               : in  std_logic_vector(1 downto 0);
        avm_m0_write                  : out std_logic;
        avm_m0_writedata              : out std_logic_vector(31 downto 0);
        avm_m0_waitrequest            : in  std_logic;
        avm_m0_readdatavalid          : in  std_logic;
        avm_m0_flush                  : out std_logic;
        avm_m0_burstcount             : out std_logic_vector(8 downto 0) -- max burst is 2^<burstcount-1>=2^8=256
    );
end entity sc_hub_top;

architecture rtl of sc_hub_top is
    constant K285_CONST              : std_logic_vector(7 downto 0)  := "10111100";
    constant K284_CONST              : std_logic_vector(7 downto 0)  := "10011100";
    constant SKIP_WORD_CONST         : std_logic_vector(31 downto 0) := x"000000BC";
    constant EMPTY_WORD40_CONST      : std_logic_vector(39 downto 0) := (others => '0');

    signal up_link_data              : std_logic_vector(31 downto 0);
    signal up_link_datak             : std_logic_vector(3 downto 0);
    signal up_link_en                : std_logic;
    signal up_link_sop               : std_logic;
    signal up_link_eop               : std_logic;

    signal down_link_data            : std_logic_vector(31 downto 0);
    signal down_link_datak           : std_logic_vector(3 downto 0);
    signal down_link_ready           : std_logic;

    signal bkpr_fifo_wrreq           : std_logic;
    signal bkpr_fifo_din             : std_logic_vector(39 downto 0);
    signal bkpr_fifo_rdreq           : std_logic;
    signal bkpr_fifo_dout            : std_logic_vector(39 downto 0);
    signal bkpr_fifo_empty           : std_logic;
    signal bkpr_fifo_full            : std_logic;
    signal bkpr_fifo_usedw           : std_logic_vector(8 downto 0);
    signal bkpr_fifo_sclr            : std_logic;

    signal down_fifo_wrreq           : std_logic;
    signal down_fifo_din             : std_logic_vector(39 downto 0);
    signal down_fifo_rdreq           : std_logic;
    signal down_fifo_dout            : std_logic_vector(39 downto 0);
    signal down_fifo_empty           : std_logic;
    signal down_fifo_full            : std_logic;
    signal down_fifo_usedw           : std_logic_vector(8 downto 0);
    signal down_fifo_sclr            : std_logic;

    signal upload_packet_in_fifo_cnt   : std_logic_vector(8 downto 0);
    signal download_packet_in_fifo_cnt : std_logic_vector(8 downto 0);
    signal avst_trans_start            : std_logic;
    signal down_pkt_capture_active     : std_logic;

    signal aso_to_uplink_ready_int     : std_logic;

    signal hub_download_fifo_flush     : std_logic := '0';
    signal hub_download_fifo_reset     : std_logic := '0';
    signal hub_download_store_forward  : std_logic := '1';
    signal hub_upload_fifo_flush       : std_logic := '0';
    signal hub_upload_fifo_reset       : std_logic := '0';
    signal hub_upload_store_forward    : std_logic := '1';
    signal hub_download_fifo_overflow  : std_logic := '0';
    signal hub_upload_fifo_overflow    : std_logic := '0';

    component alt_fifo_w40d512
    port(
        clock   : in  std_logic;
        data    : in  std_logic_vector(39 downto 0);
        rdreq   : in  std_logic;
        sclr    : in  std_logic;
        wrreq   : in  std_logic;
        empty   : out std_logic;
        full    : out std_logic;
        q       : out std_logic_vector(39 downto 0);
        usedw   : out std_logic_vector(8 downto 0)
    );
    end component;
begin
    gen_inv_rd : if INVERT_RD_SIG = True generate
        aso_to_uplink_ready_int <= not aso_to_uplink_ready;
    else generate
        aso_to_uplink_ready_int <= aso_to_uplink_ready;
    end generate gen_inv_rd;

    bkpr_fifo_sclr <= i_rst or hub_upload_fifo_flush or hub_upload_fifo_reset;
    down_fifo_sclr <= i_rst or hub_download_fifo_flush or hub_download_fifo_reset;

    -- Keep the live SC packet stream direct until the dedicated downlink FIFO path is revalidated.
    down_link_data  <= i_linkin_data;
    down_link_datak <= i_linkin_datak;

    o_linkin_ready <= down_link_ready;

    e_sc_hub : entity work.sc_hub
    port map(
        i_clk                         => i_clk,
        i_rst                         => i_rst,

        i_linkin_data                 => down_link_data,
        i_linkin_datak                => down_link_datak,
        o_linkin_ready                => down_link_ready,

        o_linkout_data                => up_link_data,
        o_linkout_datak               => up_link_datak,
        o_linkout_en                  => up_link_en,
        o_linkout_sop                 => up_link_sop,
        o_linkout_eop                 => up_link_eop,

        i_download_fifo_pkt_count     => download_packet_in_fifo_cnt,
        i_download_fifo_usedw         => down_fifo_usedw,
        i_download_fifo_full          => down_fifo_full,
        i_download_fifo_overflow      => hub_download_fifo_overflow,
        i_upload_fifo_pkt_count       => upload_packet_in_fifo_cnt,
        i_upload_fifo_usedw           => bkpr_fifo_usedw,
        i_upload_fifo_full            => bkpr_fifo_full,
        i_upload_fifo_overflow        => hub_upload_fifo_overflow,
        o_download_fifo_flush         => hub_download_fifo_flush,
        o_download_fifo_reset         => hub_download_fifo_reset,
        o_download_store_and_forward  => hub_download_store_forward,
        o_upload_fifo_flush           => hub_upload_fifo_flush,
        o_upload_fifo_reset           => hub_upload_fifo_reset,
        o_upload_store_and_forward    => hub_upload_store_forward,

        avm_m0_address                => avm_m0_address,
        avm_m0_read                   => avm_m0_read,
        avm_m0_readdata               => avm_m0_readdata,
        avm_m0_writeresponsevalid     => avm_m0_writeresponsevalid,
        avm_m0_response               => avm_m0_response,
        avm_m0_write                  => avm_m0_write,
        avm_m0_writedata              => avm_m0_writedata,
        avm_m0_waitrequest            => avm_m0_waitrequest,
        avm_m0_readdatavalid          => avm_m0_readdatavalid,
        avm_m0_flush                  => avm_m0_flush,
        avm_m0_burstcount             => avm_m0_burstcount
    );

    alt_fifo_bkpr_uplink : alt_fifo_w40d512
    port map(
        clock   => i_clk,
        sclr    => bkpr_fifo_sclr,
        wrreq   => bkpr_fifo_wrreq,
        data    => bkpr_fifo_din,
        rdreq   => bkpr_fifo_rdreq,
        q       => bkpr_fifo_dout,
        empty   => bkpr_fifo_empty,
        full    => bkpr_fifo_full,
        usedw   => bkpr_fifo_usedw
    );

    alt_fifo_downlink : alt_fifo_w40d512
    port map(
        clock   => i_clk,
        sclr    => down_fifo_sclr,
        wrreq   => down_fifo_wrreq,
        data    => down_fifo_din,
        rdreq   => down_fifo_rdreq,
        q       => down_fifo_dout,
        empty   => down_fifo_empty,
        full    => down_fifo_full,
        usedw   => down_fifo_usedw
    );

    proc_wr_to_uplink_fifo : process(i_clk, i_rst)
    begin
        if (i_rst = '1') then
            bkpr_fifo_wrreq          <= '0';
            bkpr_fifo_din            <= EMPTY_WORD40_CONST;
            hub_upload_fifo_overflow <= '0';
        elsif rising_edge(i_clk) then
            bkpr_fifo_wrreq          <= '0';
            bkpr_fifo_din            <= EMPTY_WORD40_CONST;
            hub_upload_fifo_overflow <= '0';

            if (bkpr_fifo_sclr = '1') then
                null;
            elsif (up_link_en = '1') then
                if (bkpr_fifo_full /= '1') then
                    bkpr_fifo_wrreq               <= '1';
                    bkpr_fifo_din(31 downto 0)    <= up_link_data;
                    bkpr_fifo_din(35 downto 32)   <= up_link_datak;
                    bkpr_fifo_din(36)             <= up_link_sop;
                    bkpr_fifo_din(37)             <= up_link_eop;
                else
                    hub_upload_fifo_overflow      <= '1';
                end if;
            end if;
        end if;
    end process proc_wr_to_uplink_fifo;

    proc_wr_to_down_fifo : process(i_clk, i_rst)
        variable is_preamble_v : boolean;
        variable is_trailer_v  : boolean;
        variable is_skip_v     : boolean;
    begin
        if (i_rst = '1') then
            down_fifo_wrreq          <= '0';
            down_fifo_din            <= EMPTY_WORD40_CONST;
            down_pkt_capture_active  <= '0';
            hub_download_fifo_overflow <= '0';
        elsif rising_edge(i_clk) then
            down_fifo_wrreq            <= '0';
            down_fifo_din              <= EMPTY_WORD40_CONST;
            hub_download_fifo_overflow <= '0';

            if (down_fifo_sclr = '1') then
                down_pkt_capture_active <= '0';
            else
                is_preamble_v := (i_linkin_data(31 downto 26) = "000111") and (i_linkin_data(7 downto 0) = K285_CONST) and (i_linkin_datak = "0001");
                is_trailer_v  := (i_linkin_data(7 downto 0) = K284_CONST) and (i_linkin_datak = "0001");
                is_skip_v     := (i_linkin_data = SKIP_WORD_CONST) and (i_linkin_datak = "0001");

                if (is_preamble_v = true) then
                    down_pkt_capture_active <= '1';
                elsif (down_pkt_capture_active = '1' and is_trailer_v = true and is_skip_v = false) then
                    down_pkt_capture_active <= '0';
                end if;

                if ((is_preamble_v = true or down_pkt_capture_active = '1') and is_skip_v = false) then
                    if (down_fifo_full /= '1') then
                        down_fifo_wrreq             <= '1';
                        down_fifo_din(31 downto 0)  <= i_linkin_data;
                        down_fifo_din(35 downto 32) <= i_linkin_datak;
                    else
                        hub_download_fifo_overflow  <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process proc_wr_to_down_fifo;

    proc_upload_pkt_count : process(i_clk, i_rst)
    begin
        if (i_rst = '1') then
            upload_packet_in_fifo_cnt <= (others => '0');
        elsif rising_edge(i_clk) then
            if (bkpr_fifo_sclr = '1') then
                upload_packet_in_fifo_cnt <= (others => '0');
            elsif (up_link_eop = '1' and aso_to_uplink_endofpacket = '0') then
                upload_packet_in_fifo_cnt <= conv_std_logic_vector(to_integer(unsigned(upload_packet_in_fifo_cnt)) + 1, upload_packet_in_fifo_cnt'length);
            elsif (up_link_eop = '0' and aso_to_uplink_endofpacket = '1') then
                upload_packet_in_fifo_cnt <= conv_std_logic_vector(to_integer(unsigned(upload_packet_in_fifo_cnt)) - 1, upload_packet_in_fifo_cnt'length);
            end if;
        end if;
    end process proc_upload_pkt_count;

    proc_download_pkt_count : process(i_clk, i_rst)
        variable down_wr_trailer_v : boolean;
        variable down_rd_trailer_v : boolean;
    begin
        if (i_rst = '1') then
            download_packet_in_fifo_cnt <= (others => '0');
        elsif rising_edge(i_clk) then
            if (down_fifo_sclr = '1') then
                download_packet_in_fifo_cnt <= (others => '0');
            else
                down_wr_trailer_v := (down_fifo_wrreq = '1') and (down_fifo_din(35 downto 32) = "0001") and (down_fifo_din(7 downto 0) = K284_CONST);
                down_rd_trailer_v := (down_fifo_rdreq = '1') and (down_fifo_dout(35 downto 32) = "0001") and (down_fifo_dout(7 downto 0) = K284_CONST);

                if (down_wr_trailer_v = true and down_rd_trailer_v = false) then
                    download_packet_in_fifo_cnt <= conv_std_logic_vector(to_integer(unsigned(download_packet_in_fifo_cnt)) + 1, download_packet_in_fifo_cnt'length);
                elsif (down_wr_trailer_v = false and down_rd_trailer_v = true) then
                    download_packet_in_fifo_cnt <= conv_std_logic_vector(to_integer(unsigned(download_packet_in_fifo_cnt)) - 1, download_packet_in_fifo_cnt'length);
                end if;
            end if;
        end if;
    end process proc_download_pkt_count;

    proc_rd_from_down_fifo_comb : process(all)
    begin
        down_fifo_rdreq <= '0';

        if (down_fifo_empty /= '1' and down_link_ready = '1') then
            if (hub_download_store_forward = '0' or to_integer(unsigned(download_packet_in_fifo_cnt)) >= 1) then
                down_fifo_rdreq <= '1';
            end if;
        end if;
    end process proc_rd_from_down_fifo_comb;

    proc_rd_from_uplink_fifo_comb : process(all)
    begin
        bkpr_fifo_rdreq <= '0';

        if (avst_trans_start = '1') then
            if (aso_to_uplink_ready_int = '1') then
                bkpr_fifo_rdreq <= '1';
            end if;
        elsif (bkpr_fifo_empty /= '1') then
            if (hub_upload_store_forward = '0' or to_integer(unsigned(upload_packet_in_fifo_cnt)) >= 1) then
                bkpr_fifo_rdreq <= '1';
            end if;
        end if;
    end process proc_rd_from_uplink_fifo_comb;

    proc_rd_from_uplink_fifo : process(i_clk, i_rst)
    begin
        if (i_rst = '1') then
            aso_to_uplink_data          <= (others => '0');
            aso_to_uplink_valid         <= '0';
            aso_to_uplink_startofpacket <= '0';
            aso_to_uplink_endofpacket   <= '0';
            avst_trans_start            <= '0';
        elsif rising_edge(i_clk) then
            if (bkpr_fifo_sclr = '1') then
                aso_to_uplink_data          <= (others => '0');
                aso_to_uplink_valid         <= '0';
                aso_to_uplink_startofpacket <= '0';
                aso_to_uplink_endofpacket   <= '0';
                avst_trans_start            <= '0';
            elsif (avst_trans_start = '1' and aso_to_uplink_ready_int = '0') then
                aso_to_uplink_valid         <= '1';
            elsif (bkpr_fifo_empty /= '1' and bkpr_fifo_rdreq = '1') then
                aso_to_uplink_data          <= bkpr_fifo_dout(35 downto 0);
                aso_to_uplink_valid         <= '1';
                aso_to_uplink_startofpacket <= bkpr_fifo_dout(36);
                aso_to_uplink_endofpacket   <= bkpr_fifo_dout(37);

                if (bkpr_fifo_dout(37) = '1') then
                    avst_trans_start        <= '0';
                else
                    avst_trans_start        <= '1';
                end if;
            else
                aso_to_uplink_data          <= (others => '0');
                aso_to_uplink_valid         <= '0';
                aso_to_uplink_startofpacket <= '0';
                aso_to_uplink_endofpacket   <= '0';
            end if;
        end if;
    end process proc_rd_from_uplink_fifo;

end architecture rtl;
