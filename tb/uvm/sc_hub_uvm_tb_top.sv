`timescale 1ns/1ps

module sc_hub_uvm_tb_top;
  import uvm_pkg::*;
  import sc_hub_uvm_pkg::*;

  localparam int unsigned DEFAULT_TIMEOUT_CYCLES = 50000;

  logic clk;
  logic rst;
  int unsigned timeout_cycles;

  task automatic dump_timeout_state();
    uvm_component     test_comp_h;
    sc_hub_base_test  test_h;

    test_comp_h = uvm_root::get().find("uvm_test_top");
    if ($cast(test_h, test_comp_h) && (test_h.env_h != null)) begin
      $display("sc_hub_uvm_tb_top: timeout state expected_q=%0d pending_bus_cmd_q=%0d checks_failed=%0d checks_run=%0d",
               test_h.env_h.scoreboard_h.expected_q.size(),
               test_h.env_h.bus_agent_h.monitor_h.pending_cmd_q.size(),
               test_h.env_h.scoreboard_h.checks_failed,
               test_h.env_h.scoreboard_h.checks_run);
      if (test_h.env_h.scoreboard_h.expected_q.size() != 0) begin
        $display("sc_hub_uvm_tb_top: oldest expected reply %s",
                 test_h.env_h.scoreboard_h.build_expected_reply(
                   test_h.env_h.scoreboard_h.expected_q[0]
                 ).convert2string());
      end
      if (test_h.env_h.bus_agent_h.monitor_h.pending_cmd_q.size() != 0) begin
        $display("sc_hub_uvm_tb_top: oldest pending bus cmd %s",
                 test_h.env_h.bus_agent_h.monitor_h.pending_cmd_q[0].convert2string());
      end
    end else begin
      $display("sc_hub_uvm_tb_top: timeout state could not cast uvm_test_top");
    end

`ifdef SC_HUB_BUS_AXI4
    $display("sc_hub_uvm_tb_top: AXI4 timeout link_ready=%0b pkt_valid=%0b pkt_in_progress=%0b rx_ready=%0b wr_data_empty=%0b wr_data_rdreq=%0b dl_fifo_usedw=%0d bp_usedw=%0d",
             sc_pkt_vif.ready,
             dut_inst.pkt_valid,
             dut_inst.pkt_in_progress,
             dut_inst.rx_ready,
             dut_inst.wr_data_empty,
             dut_inst.wr_data_rdreq,
             dut_inst.dl_fifo_usedw,
             dut_inst.bp_usedw);
    $display("sc_hub_uvm_tb_top: AXI4 timeout core write_reply_pending=%0b write_reply_has_data=%0b write_is_internal=%0b write_drain_remaining=0x%0h write_stream_index=0x%0h rd_issue_valid=%0b rd_issue_slot=%0d ooo_ctrl_enable=%0b",
             dut_inst.core_inst.write_reply_pending,
             dut_inst.core_inst.write_reply_has_data,
             dut_inst.core_inst.write_is_internal,
             dut_inst.core_inst.write_drain_remaining,
             dut_inst.core_inst.write_stream_index,
             dut_inst.core_inst.rd_issue_valid,
             dut_inst.core_inst.rd_issue_slot,
             dut_inst.core_inst.ooo_ctrl_enable);
    $display("sc_hub_uvm_tb_top: AXI4 timeout bus rd_cmd=%0b/%0b rd_data=%0b rd_done=%0b wr_cmd=%0b/%0b wr_data=%0b/%0b wr_done=%0b bus_busy=%0b",
             dut_inst.bus_rd_cmd_valid,
             dut_inst.bus_rd_cmd_ready,
             dut_inst.bus_rd_data_valid,
             dut_inst.bus_rd_done,
             dut_inst.bus_wr_cmd_valid,
             dut_inst.bus_wr_cmd_ready,
             dut_inst.bus_wr_data_valid,
             dut_inst.bus_wr_data_ready,
             dut_inst.bus_wr_done,
             dut_inst.bus_busy);
    $display("sc_hub_uvm_tb_top: AXI4 timeout aw=%0b/%0b w=%0b/%0b wlast=%0b b=%0b/%0b ar=%0b/%0b r=%0b/%0b rlast=%0b",
             bus_vif.awvalid,
             bus_vif.awready,
             bus_vif.wvalid,
             bus_vif.wready,
             bus_vif.wlast,
             bus_vif.bvalid,
             bus_vif.bready,
             bus_vif.arvalid,
             bus_vif.arready,
             bus_vif.rvalid,
             bus_vif.rready,
             bus_vif.rlast);
`else
    $display("sc_hub_uvm_tb_top: AVALON timeout link_ready=%0b pkt_valid=%0b pkt_in_progress=%0b rx_ready=%0b wr_data_empty=%0b wr_data_rdreq=%0b dl_fifo_usedw=%0d bp_usedw=%0d",
             sc_pkt_vif.ready,
             dut_inst.pkt_valid,
             dut_inst.pkt_in_progress,
             dut_inst.rx_ready,
             dut_inst.wr_data_empty,
             dut_inst.wr_data_rdreq,
             dut_inst.dl_fifo_usedw,
             dut_inst.bp_usedw);
    $display("sc_hub_uvm_tb_top: AVALON timeout wrapper pkt_rx_valid=%0b core_rx_ready=%0b pkt_addr=0x%05h pkt_len=%0d pkt_rx_addr=0x%05h pkt_rx_len=%0d drop_count=%0d drop_detail=0x%08h",
             dut_inst.pkt_rx_valid,
             dut_inst.core_rx_ready,
             dut_inst.pkt_info.start_address,
             dut_inst.pkt_info.rw_length,
             dut_inst.pkt_rx_info.start_address,
             dut_inst.pkt_rx_info.rw_length,
             dut_inst.pkt_drop_count,
             dut_inst.debug_drop_detail);
    $display("sc_hub_uvm_tb_top: AVALON timeout core pending_pkt_count=%0d pending_ext_count=%0d bus_cmd_issued=%0b bus_cmd_is_read=%0b bus_cmd_noninc=%0b bus_cmd_addr=0x%05h bus_cmd_len=%0d",
             dut_inst.core_inst.pending_pkt_count,
             dut_inst.core_inst.pending_ext_count,
             dut_inst.core_inst.bus_cmd_issued,
             dut_inst.core_inst.bus_cmd_is_read_reg,
             dut_inst.core_inst.bus_cmd_nonincrement_reg,
             dut_inst.core_inst.bus_cmd_address_reg,
             dut_inst.core_inst.bus_cmd_length_reg);
    $display("sc_hub_uvm_tb_top: AVALON timeout core wr_valid=%0b wr_reload=%0b wr_word=0x%08h write_stream_index=%0d drain_remaining=%0d pkt_addr=0x%05h pkt_len=%0d suppress=%0b has_data=%0b",
             dut_inst.core_inst.wr_data_valid_reg,
             dut_inst.core_inst.wr_data_reload_pending,
             dut_inst.core_inst.wr_data_word_reg,
             dut_inst.core_inst.write_stream_index,
             dut_inst.core_inst.drain_remaining,
             dut_inst.core_inst.pkt_info_reg.start_address,
             dut_inst.core_inst.pkt_info_reg.rw_length,
             dut_inst.core_inst.reply_suppress_reg,
             dut_inst.core_inst.reply_has_data_reg);
    $display("sc_hub_uvm_tb_top: AVALON timeout bus cmd=%0b/%0b wr_data=%0b/%0b done=%0b busy=%0b timeout=%0b avm_write=%0b wait=%0b burst=%0d wr_rsp=%0b rsp=0x%0h",
             dut_inst.bus_cmd_valid,
             dut_inst.bus_cmd_ready,
             dut_inst.bus_wr_data_valid,
             dut_inst.bus_wr_data_ready,
             dut_inst.bus_done,
             dut_inst.bus_busy,
             dut_inst.bus_timeout_pulse,
             bus_vif.write,
             bus_vif.waitrequest,
             bus_vif.burstcount,
             bus_vif.writeresponsevalid,
             bus_vif.response);
    $display("sc_hub_uvm_tb_top: AVALON timeout avmm words_seen=%0d cmd_addr=0x%05h cmd_len=%0d noninc=%0b timeout_counter=%0d",
             dut_inst.avmm_handler_inst.words_seen,
             dut_inst.avmm_handler_inst.cmd_address_reg,
             dut_inst.avmm_handler_inst.cmd_length_reg,
             dut_inst.avmm_handler_inst.cmd_nonincrement_reg,
             dut_inst.avmm_handler_inst.timeout_counter);
`endif
  endtask

  sc_pkt_if   sc_pkt_vif   (clk);
  sc_reply_if sc_reply_vif (clk);

  logic [4:0]  avs_csr_address;
  logic        avs_csr_read;
  logic        avs_csr_write;
  logic [31:0] avs_csr_writedata;
  logic [31:0] avs_csr_readdata;
  logic        avs_csr_readdatavalid;
  logic        avs_csr_waitrequest;
  logic        avs_csr_burstcount;

`ifdef SC_HUB_BUS_AXI4
  sc_hub_axi4_if bus_vif(clk);
  sc_hub_avmm_if aux_avmm_vif(clk);
  logic        axi4_accept_ar_resp_valid;
  logic [1:0]  axi4_accept_ar_resp_code;
  logic        axi4_accept_aw_resp_valid;
  logic [1:0]  axi4_accept_aw_resp_code;
`ifdef SC_HUB_TB_AXI4_OOO_DISABLED
  localparam bit AXI4_DUT_OOO_ENABLE = 1'b0;
`else
  localparam bit AXI4_DUT_OOO_ENABLE = 1'b1;
`endif
`ifdef SC_HUB_TB_AXI4_ORD_DISABLED
  localparam bit AXI4_DUT_ORD_ENABLE = 1'b0;
`else
  localparam bit AXI4_DUT_ORD_ENABLE = 1'b1;
`endif
`ifdef SC_HUB_TB_AXI4_ATOMIC_DISABLED
  localparam bit AXI4_DUT_ATOMIC_ENABLE = 1'b0;
`else
  localparam bit AXI4_DUT_ATOMIC_ENABLE = 1'b1;
`endif
  localparam int unsigned AXI4_DUT_RD_TIMEOUT_CYCLES = 512;
  localparam int unsigned AXI4_DUT_WR_TIMEOUT_CYCLES = 512;
  localparam int unsigned DUT_DL_FIFO_DEPTH          = 256;
  localparam int unsigned DUT_BP_FIFO_DEPTH          = 512;
`else
  sc_hub_avmm_if bus_vif(clk);
  sc_hub_axi4_if aux_axi4_vif(clk);
  logic        avmm_accept_rd_resp_valid;
  logic [1:0]  avmm_accept_rd_resp_code;
  logic        avmm_accept_wr_resp_valid;
  logic [1:0]  avmm_accept_wr_resp_code;
  logic [8:0]  avmm_wr_cmd_beats_remaining;
`ifdef SC_HUB_TB_AVALON_OUTSTANDING_LIMIT
  localparam int unsigned AVALON_DUT_OUTSTANDING_LIMIT = `SC_HUB_TB_AVALON_OUTSTANDING_LIMIT;
`else
  localparam int unsigned AVALON_DUT_OUTSTANDING_LIMIT = 8;
`endif
`ifdef SC_HUB_TB_AVALON_OUTSTANDING_INT_RESERVED
  localparam int unsigned AVALON_DUT_OUTSTANDING_INT_RESERVED = `SC_HUB_TB_AVALON_OUTSTANDING_INT_RESERVED;
`else
  localparam int unsigned AVALON_DUT_OUTSTANDING_INT_RESERVED = 2;
`endif
`ifdef SC_HUB_TB_AVALON_EXT_PLD_DEPTH
  localparam int unsigned AVALON_DUT_EXT_PLD_DEPTH = `SC_HUB_TB_AVALON_EXT_PLD_DEPTH;
`else
  localparam int unsigned AVALON_DUT_EXT_PLD_DEPTH = 512;
`endif
`ifdef SC_HUB_TB_AVALON_BP_FIFO_DEPTH
  localparam int unsigned AVALON_DUT_BP_FIFO_DEPTH = `SC_HUB_TB_AVALON_BP_FIFO_DEPTH;
`else
  localparam int unsigned AVALON_DUT_BP_FIFO_DEPTH = 512;
`endif
`ifdef SC_HUB_TB_AVALON_RD_TIMEOUT_CYCLES
  localparam int unsigned AVALON_DUT_RD_TIMEOUT_CYCLES = `SC_HUB_TB_AVALON_RD_TIMEOUT_CYCLES;
`else
  localparam int unsigned AVALON_DUT_RD_TIMEOUT_CYCLES = 200;
`endif
`ifdef SC_HUB_TB_AVALON_WR_TIMEOUT_CYCLES
  localparam int unsigned AVALON_DUT_WR_TIMEOUT_CYCLES = `SC_HUB_TB_AVALON_WR_TIMEOUT_CYCLES;
`else
  localparam int unsigned AVALON_DUT_WR_TIMEOUT_CYCLES = 200;
`endif
`ifdef SC_HUB_TB_AVALON_OOO_ENABLED
  localparam bit AVALON_DUT_OOO_ENABLE = 1'b1;
`else
  localparam bit AVALON_DUT_OOO_ENABLE = 1'b0;
`endif
`ifdef SC_HUB_TB_AVALON_ORD_DISABLED
  localparam bit AVALON_DUT_ORD_ENABLE = 1'b0;
`else
  localparam bit AVALON_DUT_ORD_ENABLE = 1'b1;
`endif
`ifdef SC_HUB_TB_AVALON_ATOMIC_DISABLED
  localparam bit AVALON_DUT_ATOMIC_ENABLE = 1'b0;
`else
  localparam bit AVALON_DUT_ATOMIC_ENABLE = 1'b1;
`endif
  localparam int unsigned DUT_DL_FIFO_DEPTH = AVALON_DUT_EXT_PLD_DEPTH;
  localparam int unsigned DUT_BP_FIFO_DEPTH = AVALON_DUT_BP_FIFO_DEPTH;
`endif

`ifndef SC_HUB_BUS_AXI4
  task automatic configure_avmm_latency_profile(input string profile_name);
    string profile_upper;

    profile_upper = profile_name.toupper();
    avmm_bfm_inst.set_default_rd_latency(1);
    avmm_bfm_inst.set_default_wr_latency(1);

    if (profile_upper == "FIXED8") begin
      avmm_bfm_inst.set_default_rd_latency(8);
      avmm_bfm_inst.set_default_wr_latency(8);
    end else if (profile_upper == "READ8_WRITE4") begin
      avmm_bfm_inst.set_default_rd_latency(8);
      avmm_bfm_inst.set_default_wr_latency(4);
    end else if (profile_upper == "FIXED1") begin
      avmm_bfm_inst.set_default_rd_latency(1);
      avmm_bfm_inst.set_default_wr_latency(1);
    end else if (profile_upper == "UNIFORM4_50") begin
      avmm_bfm_inst.set_default_rd_latency(4);
      for (int unsigned addr = 0; addr < 16'h10000; addr++) begin
        avmm_bfm_inst.set_rd_latency_for_addr(addr[17:0], 4 + (addr % 47));
      end
    end else if (profile_upper == "UNIFORM4_20") begin
      avmm_bfm_inst.set_default_rd_latency(4);
      for (int unsigned addr = 0; addr < 16'h10000; addr++) begin
        avmm_bfm_inst.set_rd_latency_for_addr(addr[17:0], 4 + (addr % 17));
      end
    end else if (profile_upper == "UNIFORM4_200") begin
      avmm_bfm_inst.set_default_rd_latency(4);
      for (int unsigned addr = 0; addr < 16'h10000; addr++) begin
        avmm_bfm_inst.set_rd_latency_for_addr(addr[17:0], 4 + (addr % 197));
      end
    end else if (profile_upper == "BIMODAL4_40") begin
      avmm_bfm_inst.set_default_rd_latency(4);
      for (int unsigned addr = 0; addr < 16'h10000; addr++) begin
        avmm_bfm_inst.set_rd_latency_for_addr(addr[17:0], (addr[0] == 1'b0) ? 4 : 40);
      end
    end else if (profile_upper == "ADDRESSDEP") begin
      avmm_bfm_inst.set_default_rd_latency(20);
      for (int unsigned addr = 16'h0000; addr < 16'h0400; addr++) begin
        avmm_bfm_inst.set_rd_latency_for_addr(addr[17:0], 2);
      end
      for (int unsigned addr = 16'h8000; addr < 16'h8800; addr++) begin
        avmm_bfm_inst.set_rd_latency_for_addr(addr[17:0], 4 + (addr % 9));
      end
      for (int unsigned addr = 16'hA000; addr < 16'hA800; addr++) begin
        avmm_bfm_inst.set_rd_latency_for_addr(addr[17:0], 8 + (addr % 13));
      end
      for (int unsigned addr = 16'hC000; addr < 16'hC200; addr++) begin
        avmm_bfm_inst.set_rd_latency_for_addr(addr[17:0], 6 + (addr % 11));
      end
    end
  endtask
`endif

`ifdef SC_HUB_BUS_AXI4
  task automatic configure_axi4_latency_profile(input string profile_name);
    string profile_upper;

    profile_upper = profile_name.toupper();
    axi4_bfm_inst.set_default_rd_latency(1);
    axi4_bfm_inst.set_default_wr_latency(1);

    if (profile_upper == "FIXED8") begin
      axi4_bfm_inst.set_default_rd_latency(8);
      axi4_bfm_inst.set_default_wr_latency(8);
    end else if (profile_upper == "READ8_WRITE4") begin
      axi4_bfm_inst.set_default_rd_latency(8);
      axi4_bfm_inst.set_default_wr_latency(4);
    end else if (profile_upper == "FIXED1") begin
      axi4_bfm_inst.set_default_rd_latency(1);
      axi4_bfm_inst.set_default_wr_latency(1);
    end else if (profile_upper == "UNIFORM4_50") begin
      axi4_bfm_inst.set_default_rd_latency(4);
      for (int unsigned addr = 0; addr < 16'h10000; addr++) begin
        axi4_bfm_inst.set_rd_latency_for_addr(addr[17:0], 4 + (addr % 47));
      end
    end else if (profile_upper == "UNIFORM4_20") begin
      axi4_bfm_inst.set_default_rd_latency(4);
      for (int unsigned addr = 0; addr < 16'h10000; addr++) begin
        axi4_bfm_inst.set_rd_latency_for_addr(addr[17:0], 4 + (addr % 17));
      end
    end else if (profile_upper == "UNIFORM4_200") begin
      axi4_bfm_inst.set_default_rd_latency(4);
      for (int unsigned addr = 0; addr < 16'h10000; addr++) begin
        axi4_bfm_inst.set_rd_latency_for_addr(addr[17:0], 4 + (addr % 197));
      end
    end else if (profile_upper == "BIMODAL4_40") begin
      axi4_bfm_inst.set_default_rd_latency(4);
      for (int unsigned addr = 0; addr < 16'h10000; addr++) begin
        axi4_bfm_inst.set_rd_latency_for_addr(addr[17:0], (addr[0] == 1'b0) ? 4 : 40);
      end
    end else if (profile_upper == "ADDRESSDEP") begin
      axi4_bfm_inst.set_default_rd_latency(20);
      for (int unsigned addr = 16'h0000; addr < 16'h0400; addr++) begin
        axi4_bfm_inst.set_rd_latency_for_addr(addr[17:0], 2);
      end
      for (int unsigned addr = 16'h8000; addr < 16'h8800; addr++) begin
        axi4_bfm_inst.set_rd_latency_for_addr(addr[17:0], 4 + (addr % 9));
      end
      for (int unsigned addr = 16'hA000; addr < 16'hA800; addr++) begin
        axi4_bfm_inst.set_rd_latency_for_addr(addr[17:0], 8 + (addr % 13));
      end
      for (int unsigned addr = 16'hC000; addr < 16'hC200; addr++) begin
        axi4_bfm_inst.set_rd_latency_for_addr(addr[17:0], 6 + (addr % 11));
      end
    end
  endtask
`endif

`ifdef SC_HUB_BUS_AXI4
  always_comb begin
    axi4_accept_aw_resp_valid = 1'b0;
    axi4_accept_aw_resp_code  = 2'b00;
    axi4_accept_ar_resp_valid = 1'b0;
    axi4_accept_ar_resp_code  = 2'b00;

    if (!rst && bus_vif.awvalid && bus_vif.awready) begin
      bus_vif.peek_cmd_inject(1'b1, bus_vif.awaddr, bus_vif.awlen + 1,
                              axi4_accept_aw_resp_valid, axi4_accept_aw_resp_code);
    end
    if (!rst && bus_vif.arvalid && bus_vif.arready) begin
      bus_vif.peek_cmd_inject(1'b0, bus_vif.araddr, bus_vif.arlen + 1,
                              axi4_accept_ar_resp_valid, axi4_accept_ar_resp_code);
    end
  end

  always_ff @(posedge clk) begin
    bit inject_matched;
    logic [1:0] inject_response;

    if (rst) begin
      bus_vif.clear_cmd_injects();
    end else begin
      if (bus_vif.awvalid && bus_vif.awready) begin
        bus_vif.consume_cmd_inject(1'b1, bus_vif.awaddr, bus_vif.awlen + 1, inject_matched, inject_response);
      end
      if (bus_vif.arvalid && bus_vif.arready) begin
        bus_vif.consume_cmd_inject(1'b0, bus_vif.araddr, bus_vif.arlen + 1, inject_matched, inject_response);
      end
    end
  end
`else
  always_comb begin
    avmm_accept_rd_resp_valid = 1'b0;
    avmm_accept_rd_resp_code  = 2'b00;
    avmm_accept_wr_resp_valid = 1'b0;
    avmm_accept_wr_resp_code  = 2'b00;

    if (!rst && bus_vif.read && !bus_vif.waitrequest) begin
      bus_vif.peek_cmd_inject(1'b0, bus_vif.address, (bus_vif.burstcount == 0) ? 1 : bus_vif.burstcount,
                              avmm_accept_rd_resp_valid, avmm_accept_rd_resp_code);
    end
    if (!rst && bus_vif.write && !bus_vif.waitrequest && (avmm_wr_cmd_beats_remaining == 0)) begin
      bus_vif.peek_cmd_inject(1'b1, bus_vif.address, (bus_vif.burstcount == 0) ? 1 : bus_vif.burstcount,
                              avmm_accept_wr_resp_valid, avmm_accept_wr_resp_code);
    end
  end

  always_ff @(posedge clk) begin
    bit inject_matched;
    logic [1:0] inject_response;

    if (rst) begin
      avmm_wr_cmd_beats_remaining <= '0;
      bus_vif.clear_cmd_injects();
    end else begin
      if (bus_vif.read && !bus_vif.waitrequest) begin
        bus_vif.consume_cmd_inject(1'b0, bus_vif.address, (bus_vif.burstcount == 0) ? 1 : bus_vif.burstcount,
                                   inject_matched, inject_response);
      end

      if (bus_vif.write && !bus_vif.waitrequest) begin
        if (avmm_wr_cmd_beats_remaining == 0) begin
          bus_vif.consume_cmd_inject(1'b1, bus_vif.address, (bus_vif.burstcount == 0) ? 1 : bus_vif.burstcount,
                                     inject_matched, inject_response);
          avmm_wr_cmd_beats_remaining <= ((bus_vif.burstcount == 0) ? 1 : bus_vif.burstcount) - 1'b1;
        end else begin
          avmm_wr_cmd_beats_remaining <= avmm_wr_cmd_beats_remaining - 1'b1;
        end
      end
    end
  end
`endif

  initial begin
    clk = 1'b0;
    forever #3.2 clk = ~clk;
  end

  initial begin
    rst                   = 1'b1;
    sc_reply_vif.ready    = 1'b1;
    sc_pkt_vif.data       = '0;
    sc_pkt_vif.datak      = '0;
    avs_csr_address       = '0;
    avs_csr_read          = 1'b0;
    avs_csr_write         = 1'b0;
    avs_csr_writedata     = '0;
    avs_csr_burstcount    = 1'b0;
`ifdef SC_HUB_BUS_AXI4
    bus_vif.inject_rresp_err = 1'b0;
    bus_vif.inject_bresp_err = 1'b0;
    bus_vif.inject_rd_error  = 1'b0;
    bus_vif.inject_wr_error  = 1'b0;
    bus_vif.inject_decode_error = 1'b0;
    aux_avmm_vif.inject_rd_error     = 1'b0;
    aux_avmm_vif.inject_wr_error     = 1'b0;
    aux_avmm_vif.inject_decode_error = 1'b0;
`else
    bus_vif.inject_rd_error     = 1'b0;
    bus_vif.inject_wr_error     = 1'b0;
    bus_vif.inject_decode_error = 1'b0;
    aux_axi4_vif.inject_rresp_err = 1'b0;
    aux_axi4_vif.inject_bresp_err = 1'b0;
`endif
    repeat (8) @(posedge clk);
    rst = 1'b0;
  end

  initial begin
    wait (!rst);
    if (!$value$plusargs("TIMEOUT_CYCLES=%d", timeout_cycles)) begin
      timeout_cycles = DEFAULT_TIMEOUT_CYCLES;
    end
    repeat (timeout_cycles) @(posedge clk);
    dump_timeout_state();
    $fatal(1, "sc_hub_uvm_tb_top: timeout waiting for UVM test completion after %0d cycles", timeout_cycles);
  end

  initial begin
    int unsigned bp_period;
    int unsigned bp_low_cycles;
    int unsigned bp_start_delay;
    int unsigned bp_idx;

    wait (!rst);
    bp_period = 0;
    bp_low_cycles = 0;
    bp_start_delay = 0;
    void'($value$plusargs("SC_HUB_UPLINK_BP_PERIOD=%d", bp_period));
    void'($value$plusargs("SC_HUB_UPLINK_BP_LOW_CYCLES=%d", bp_low_cycles));
    void'($value$plusargs("SC_HUB_UPLINK_BP_START_DELAY=%d", bp_start_delay));

    if ((bp_period != 0) && (bp_low_cycles != 0)) begin
      if (bp_low_cycles > bp_period) begin
        bp_low_cycles = bp_period;
      end
      repeat (bp_start_delay) @(posedge clk);
      forever begin
        for (bp_idx = 0; bp_idx < bp_period; bp_idx++) begin
          @(negedge clk);
          sc_reply_vif.ready = (bp_idx >= bp_low_cycles);
        end
      end
    end
  end

  initial begin
    int unsigned rd_latency;
    int unsigned wr_latency;
    string       latency_profile;
    string       err_kind;
    string       err_op;

    wait (!rst);

    if ($value$plusargs("SC_HUB_RD_LATENCY=%d", rd_latency)) begin
`ifdef SC_HUB_BUS_AXI4
      axi4_bfm_inst.set_default_rd_latency(rd_latency);
`else
      avmm_bfm_inst.set_default_rd_latency(rd_latency);
`endif
    end

    if ($value$plusargs("SC_HUB_WR_LATENCY=%d", wr_latency)) begin
`ifdef SC_HUB_BUS_AXI4
      axi4_bfm_inst.set_default_wr_latency(wr_latency);
`else
      avmm_bfm_inst.set_default_wr_latency(wr_latency);
`endif
    end

    if ($value$plusargs("SC_HUB_LAT_PROFILE=%s", latency_profile)) begin
`ifdef SC_HUB_BUS_AXI4
      configure_axi4_latency_profile(latency_profile);
`else
      configure_avmm_latency_profile(latency_profile);
`endif
    end

    err_kind = "";
    err_op   = "";
    void'($value$plusargs("SC_HUB_ERR_KIND=%s", err_kind));
    void'($value$plusargs("SC_HUB_ERR_OP=%s", err_op));
    if (err_kind.toupper() == "TIMEOUT") begin
`ifdef SC_HUB_BUS_AXI4
      if (err_op.tolower() == "read") begin
        force bus_vif.rvalid = 1'b0;
      end else if (err_op.tolower() == "write") begin
        force bus_vif.bvalid = 1'b0;
      end
`else
      if (err_op.tolower() == "read") begin
        force bus_vif.readdatavalid = 1'b0;
      end else if (err_op.tolower() == "write") begin
        force bus_vif.writeresponsevalid = 1'b0;
      end
`endif
    end

`ifdef SC_HUB_BUS_AXI4
    if ($test$plusargs("SC_HUB_INJECT_RD_ERROR")) begin
      bus_vif.inject_rd_error = 1'b1;
      bus_vif.inject_rresp_err = 1'b1;
    end
    if ($test$plusargs("SC_HUB_INJECT_WR_ERROR")) begin
      bus_vif.inject_wr_error = 1'b1;
      bus_vif.inject_bresp_err = 1'b1;
    end
    if ($test$plusargs("SC_HUB_INJECT_DECODE_ERROR")) begin
      bus_vif.inject_decode_error = 1'b1;
    end
    if ($test$plusargs("SC_HUB_INJECT_RRESP_ERROR")) begin
      bus_vif.inject_rresp_err = 1'b1;
    end
    if ($test$plusargs("SC_HUB_INJECT_BRESP_ERROR")) begin
      bus_vif.inject_bresp_err = 1'b1;
    end
`else
    if ($test$plusargs("SC_HUB_INJECT_RD_ERROR")) begin
      bus_vif.inject_rd_error = 1'b1;
    end
    if ($test$plusargs("SC_HUB_INJECT_WR_ERROR")) begin
      bus_vif.inject_wr_error = 1'b1;
    end
    if ($test$plusargs("SC_HUB_INJECT_DECODE_ERROR")) begin
      bus_vif.inject_decode_error = 1'b1;
    end
`endif
  end

  assign sc_pkt_vif.rst   = rst;
  assign sc_reply_vif.rst = rst;
  assign bus_vif.rst      = rst;
`ifdef SC_HUB_BUS_AXI4
  assign aux_avmm_vif.rst = rst;
`else
  assign aux_axi4_vif.rst = rst;
`endif

`ifdef SC_HUB_BUS_AXI4
  sc_hub_top_axi4 #(
    .INVERT_RD_SIG(0),
    .OOO_ENABLE(AXI4_DUT_OOO_ENABLE),
    .ORD_ENABLE(AXI4_DUT_ORD_ENABLE),
    .ATOMIC_ENABLE(AXI4_DUT_ATOMIC_ENABLE),
    .RD_TIMEOUT_CYCLES(AXI4_DUT_RD_TIMEOUT_CYCLES),
    .WR_TIMEOUT_CYCLES(AXI4_DUT_WR_TIMEOUT_CYCLES)
  ) dut_inst (
    .i_clk                      (clk),
    .i_rst                      (rst),
    .i_download_data            (sc_pkt_vif.data),
    .i_download_datak           (sc_pkt_vif.datak),
    .o_download_ready           (sc_pkt_vif.ready),
    .aso_upload_data            (sc_reply_vif.data),
    .aso_upload_valid           (sc_reply_vif.valid),
    .aso_upload_ready           (sc_reply_vif.ready),
    .aso_upload_startofpacket   (sc_reply_vif.sop),
    .aso_upload_endofpacket     (sc_reply_vif.eop),
    .m_axi_awid                 (bus_vif.awid),
    .m_axi_awaddr               (bus_vif.awaddr),
    .m_axi_awlen                (bus_vif.awlen),
    .m_axi_awsize               (bus_vif.awsize),
    .m_axi_awburst              (bus_vif.awburst),
    .m_axi_awlock               (bus_vif.awlock),
    .m_axi_awvalid              (bus_vif.awvalid),
    .m_axi_awready              (bus_vif.awready),
    .m_axi_wdata                (bus_vif.wdata),
    .m_axi_wstrb                (bus_vif.wstrb),
    .m_axi_wlast                (bus_vif.wlast),
    .m_axi_wvalid               (bus_vif.wvalid),
    .m_axi_wready               (bus_vif.wready),
    .m_axi_bid                  (bus_vif.bid),
    .m_axi_bresp                (bus_vif.bresp),
    .m_axi_bvalid               (bus_vif.bvalid),
    .m_axi_bready               (bus_vif.bready),
    .m_axi_arid                 (bus_vif.arid),
    .m_axi_araddr               (bus_vif.araddr),
    .m_axi_arlen                (bus_vif.arlen),
    .m_axi_arsize               (bus_vif.arsize),
    .m_axi_arburst              (bus_vif.arburst),
    .m_axi_arlock               (bus_vif.arlock),
    .m_axi_arvalid              (bus_vif.arvalid),
    .m_axi_arready              (bus_vif.arready),
    .m_axi_rid                  (bus_vif.rid),
    .m_axi_rdata                (bus_vif.rdata),
    .m_axi_rresp                (bus_vif.rresp),
    .m_axi_rlast                (bus_vif.rlast),
    .m_axi_rvalid               (bus_vif.rvalid),
    .m_axi_rready               (bus_vif.rready)
  );

  axi4_slave_bfm axi4_bfm_inst (
    .clk             (clk),
    .rst             (rst),
    .awid            (bus_vif.awid),
    .awaddr          (bus_vif.awaddr),
    .awlen           (bus_vif.awlen),
    .awsize          (bus_vif.awsize),
    .awburst         (bus_vif.awburst),
    .awlock          (bus_vif.awlock),
    .awvalid         (bus_vif.awvalid),
    .awready         (bus_vif.awready),
    .wdata           (bus_vif.wdata),
    .wstrb           (bus_vif.wstrb),
    .wlast           (bus_vif.wlast),
    .wvalid          (bus_vif.wvalid),
    .wready          (bus_vif.wready),
    .bid             (bus_vif.bid),
    .bresp           (bus_vif.bresp),
    .bvalid          (bus_vif.bvalid),
    .bready          (bus_vif.bready),
    .arid            (bus_vif.arid),
    .araddr          (bus_vif.araddr),
    .arlen           (bus_vif.arlen),
    .arsize          (bus_vif.arsize),
    .arburst         (bus_vif.arburst),
    .arlock          (bus_vif.arlock),
    .arvalid         (bus_vif.arvalid),
    .arready         (bus_vif.arready),
    .rid             (bus_vif.rid),
    .rdata           (bus_vif.rdata),
    .rresp           (bus_vif.rresp),
    .rlast           (bus_vif.rlast),
    .rvalid          (bus_vif.rvalid),
    .rready          (bus_vif.rready),
    .accept_ar_resp_valid(axi4_accept_ar_resp_valid),
    .accept_ar_resp_code (axi4_accept_ar_resp_code),
    .accept_aw_resp_valid(axi4_accept_aw_resp_valid),
    .accept_aw_resp_code (axi4_accept_aw_resp_code),
    .inject_rd_error (bus_vif.inject_rd_error),
    .inject_wr_error (bus_vif.inject_wr_error),
    .inject_decode_error(bus_vif.inject_decode_error),
    .inject_rresp_err(bus_vif.inject_rresp_err),
    .inject_bresp_err(bus_vif.inject_bresp_err)
  );
`else
  sc_hub_top #(
    .INVERT_RD_SIG(0),
    .OOO_ENABLE(AVALON_DUT_OOO_ENABLE),
    .ORD_ENABLE(AVALON_DUT_ORD_ENABLE),
    .ATOMIC_ENABLE(AVALON_DUT_ATOMIC_ENABLE),
    .EXT_PLD_DEPTH(AVALON_DUT_EXT_PLD_DEPTH),
    .BP_FIFO_DEPTH(AVALON_DUT_BP_FIFO_DEPTH),
    .RD_TIMEOUT_CYCLES(AVALON_DUT_RD_TIMEOUT_CYCLES),
    .WR_TIMEOUT_CYCLES(AVALON_DUT_WR_TIMEOUT_CYCLES),
    .OUTSTANDING_LIMIT(AVALON_DUT_OUTSTANDING_LIMIT),
    .OUTSTANDING_INT_RESERVED(AVALON_DUT_OUTSTANDING_INT_RESERVED)
  ) dut_inst (
    .i_clk                      (clk),
    .i_rst                      (rst),
    .i_download_data            (sc_pkt_vif.data),
    .i_download_datak           (sc_pkt_vif.datak),
    .o_download_ready           (sc_pkt_vif.ready),
    .aso_upload_data            (sc_reply_vif.data),
    .aso_upload_valid           (sc_reply_vif.valid),
    .aso_upload_ready           (sc_reply_vif.ready),
    .aso_upload_startofpacket   (sc_reply_vif.sop),
    .aso_upload_endofpacket     (sc_reply_vif.eop),
    .avm_hub_address            (bus_vif.address),
    .avm_hub_read               (bus_vif.read),
    .avm_hub_readdata           (bus_vif.readdata),
    .avm_hub_writeresponsevalid (bus_vif.writeresponsevalid),
    .avm_hub_response           (bus_vif.response),
    .avm_hub_write              (bus_vif.write),
    .avm_hub_writedata          (bus_vif.writedata),
    .avm_hub_waitrequest        (bus_vif.waitrequest),
    .avm_hub_readdatavalid      (bus_vif.readdatavalid),
    .avm_hub_burstcount         (bus_vif.burstcount),
    .avs_csr_address            (avs_csr_address),
    .avs_csr_read               (avs_csr_read),
    .avs_csr_write              (avs_csr_write),
    .avs_csr_writedata          (avs_csr_writedata),
    .avs_csr_readdata           (avs_csr_readdata),
    .avs_csr_readdatavalid      (avs_csr_readdatavalid),
    .avs_csr_waitrequest        (avs_csr_waitrequest),
    .avs_csr_burstcount         (avs_csr_burstcount)
  );

  avmm_slave_bfm avmm_bfm_inst (
    .clk                   (clk),
    .rst                   (rst),
    .avm_address           (bus_vif.address),
    .avm_read              (bus_vif.read),
    .avm_readdata          (bus_vif.readdata),
    .avm_writeresponsevalid(bus_vif.writeresponsevalid),
    .avm_response          (bus_vif.response),
    .avm_write             (bus_vif.write),
    .avm_writedata         (bus_vif.writedata),
    .avm_waitrequest       (bus_vif.waitrequest),
    .avm_readdatavalid     (bus_vif.readdatavalid),
    .avm_burstcount        (bus_vif.burstcount),
    .accept_rd_resp_valid  (avmm_accept_rd_resp_valid),
    .accept_rd_resp_code   (avmm_accept_rd_resp_code),
    .accept_wr_resp_valid  (avmm_accept_wr_resp_valid),
    .accept_wr_resp_code   (avmm_accept_wr_resp_code),
    .inject_rd_error       (bus_vif.inject_rd_error),
    .inject_wr_error       (bus_vif.inject_wr_error),
    .inject_decode_error   (bus_vif.inject_decode_error)
  );

  always_ff @(posedge clk) begin
    if (!rst && $test$plusargs("SC_HUB_TRACE_FLOW")) begin
      if (dut_inst.pkt_rx_valid) begin
        $display("TRACE_FLOW t=%0t RX_PUBLISH addr=0x%05h len=%0d sc_type=%0d internal=%0b out_valid=%0b core_rx_ready=%0b enq_stage=%0d queue=%0d",
                 $time,
                 dut_inst.pkt_rx_info.start_address,
                 dut_inst.pkt_rx_info.rw_length,
                 dut_inst.pkt_rx_info.sc_type,
                 dut_inst.pkt_rx_is_internal,
                 dut_inst.pkt_valid,
                 dut_inst.core_rx_ready,
                 dut_inst.pkt_rx_inst.enqueue_stage_count,
                 dut_inst.pkt_rx_inst.pkt_queue_count);
      end
      if (dut_inst.pkt_valid && dut_inst.core_rx_ready) begin
        $display("TRACE_FLOW t=%0t CORE_ACCEPT addr=0x%05h len=%0d sc_type=%0d internal=%0b pending=%0d pending_ext=%0d",
                 $time,
                 dut_inst.pkt_info.start_address,
                 dut_inst.pkt_info.rw_length,
                 dut_inst.pkt_info.sc_type,
                 dut_inst.pkt_is_internal,
                 dut_inst.core_inst.pending_pkt_count,
                 dut_inst.core_inst.pending_ext_count);
      end
      if (dut_inst.pkt_drop_pulse) begin
        $display("TRACE_FLOW t=%0t RX_DROP drop_count=%0d detail=0x%08h fifo_usedw=%0d",
                 $time,
                 dut_inst.pkt_drop_count,
                 dut_inst.debug_drop_detail,
                 dut_inst.dl_fifo_usedw);
      end
      if (dut_inst.bus_cmd_valid && dut_inst.bus_cmd_ready) begin
        $display("TRACE_FLOW t=%0t BUS_CMD kind=%s addr=0x%05h len=%0d noninc=%0b pending=%0d pending_ext=%0d",
                 $time,
                 dut_inst.bus_cmd_is_read ? "RD" : "WR",
                 dut_inst.bus_cmd_address,
                 dut_inst.bus_cmd_length,
                 dut_inst.bus_cmd_nonincrement,
                 dut_inst.core_inst.pending_pkt_count,
                 dut_inst.core_inst.pending_ext_count);
      end
      if (dut_inst.bus_wr_data_valid && dut_inst.bus_wr_data_ready) begin
        $display("TRACE_FLOW t=%0t WR_BEAT addr=0x%05h idx=%0d data=0x%08h reload=%0b words_seen=%0d",
                 $time,
                 dut_inst.core_inst.pkt_info_reg.start_address,
                 dut_inst.core_inst.write_stream_index,
                 dut_inst.bus_wr_data,
                 dut_inst.core_inst.wr_data_reload_pending,
                 dut_inst.avmm_handler_inst.words_seen);
      end
      if (dut_inst.bus_done) begin
        $display("TRACE_FLOW t=%0t BUS_DONE rsp=0x%0h addr=0x%05h len=%0d wr_idx=%0d rd_fill=%0d",
                 $time,
                 dut_inst.bus_response,
                 dut_inst.core_inst.pkt_info_reg.start_address,
                 dut_inst.core_inst.pkt_info_reg.rw_length,
                 dut_inst.core_inst.write_stream_index,
                 dut_inst.core_inst.read_fill_index);
      end
      if (bus_vif.read && !bus_vif.waitrequest) begin
        $display("TRACE_FLOW t=%0t BUS_RD addr=0x%05h burst=%0d bfm_active=%0b bfm_addr=0x%05h bfm_beats=%0d",
                 $time, bus_vif.address, bus_vif.burstcount,
                 avmm_bfm_inst.read_active, avmm_bfm_inst.rd_addr_reg, avmm_bfm_inst.rd_beats_remaining);
      end
      if (dut_inst.tx_reply_start) begin
        $display("TRACE_FLOW t=%0t RSP_START addr=0x%05h len=%0d suppress=%0b usedw=%0d",
                 $time,
                 dut_inst.tx_reply_info.start_address,
                 dut_inst.tx_reply_info.rw_length,
                 dut_inst.tx_reply_suppress,
                 dut_inst.core_inst.rd_fifo_usedw);
      end
      if (dut_inst.tx_reply_done) begin
        $display("TRACE_FLOW t=%0t RSP_DONE usedw=%0d", $time, dut_inst.core_inst.rd_fifo_usedw);
      end
      if (dut_inst.core_inst.rd_fifo_clear && (dut_inst.core_inst.rd_fifo_usedw != 0)) begin
        $display("TRACE_FLOW t=%0t FIFO_CLEAR usedw=%0d", $time, dut_inst.core_inst.rd_fifo_usedw);
      end
      if (dut_inst.core_inst.rd_fifo_write_en) begin
        $display("TRACE_FLOW t=%0t FIFO_WRITE pkt_addr=0x%05h data=0x%08h fill_idx=%0d suppress=%0b usedw=%0d bfm_addr=0x%05h bfm_rdata=0x%08h",
                 $time,
                 dut_inst.core_inst.pkt_info_reg.start_address,
                 dut_inst.core_inst.rd_fifo_write_data,
                 dut_inst.core_inst.read_fill_index,
                 dut_inst.core_inst.reply_suppress_reg,
                 dut_inst.core_inst.rd_fifo_usedw,
                 avmm_bfm_inst.rd_addr_reg,
                 avmm_bfm_inst.avm_readdata);
      end
    end
  end
`endif


  always_ff @(posedge clk) begin
    if (!rst && $test$plusargs("SC_HUB_TRACE_REPLY_STREAM")) begin
      if (sc_reply_vif.valid) begin
        $display("TRACE_REPLY_STREAM t=%0t v=%0b r=%0b sop=%0b eop=%0b data=0x%09h",
                 $time,
                 sc_reply_vif.valid,
                 sc_reply_vif.ready,
                 sc_reply_vif.sop,
                 sc_reply_vif.eop,
                 sc_reply_vif.data);
      end
    end
  end

  initial begin
    uvm_config_db#(virtual sc_pkt_if)::set(null, "*", "sc_pkt_vif", sc_pkt_vif);
    uvm_config_db#(virtual sc_reply_if)::set(null, "*", "sc_reply_vif", sc_reply_vif);
`ifdef SC_HUB_BUS_AXI4
    uvm_config_db#(virtual sc_hub_axi4_if)::set(null, "*", "axi4_vif", bus_vif);
    uvm_config_db#(virtual sc_hub_avmm_if)::set(null, "*", "avmm_vif", aux_avmm_vif);
`else
    uvm_config_db#(virtual sc_hub_avmm_if)::set(null, "*", "avmm_vif", bus_vif);
    uvm_config_db#(virtual sc_hub_axi4_if)::set(null, "*", "axi4_vif", aux_axi4_vif);
`endif
    run_test();
  end
endmodule
