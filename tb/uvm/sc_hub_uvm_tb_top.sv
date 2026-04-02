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
`endif
  endtask

  sc_pkt_if   sc_pkt_vif   (clk);
  sc_reply_if sc_reply_vif (clk);

`ifdef SC_HUB_BUS_AXI4
  sc_hub_axi4_if bus_vif(clk);
  sc_hub_avmm_if aux_avmm_vif(clk);
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
        avmm_bfm_inst.set_rd_latency_for_addr(addr[15:0], 4 + (addr % 47));
      end
    end else if (profile_upper == "UNIFORM4_20") begin
      avmm_bfm_inst.set_default_rd_latency(4);
      for (int unsigned addr = 0; addr < 16'h10000; addr++) begin
        avmm_bfm_inst.set_rd_latency_for_addr(addr[15:0], 4 + (addr % 17));
      end
    end else if (profile_upper == "UNIFORM4_200") begin
      avmm_bfm_inst.set_default_rd_latency(4);
      for (int unsigned addr = 0; addr < 16'h10000; addr++) begin
        avmm_bfm_inst.set_rd_latency_for_addr(addr[15:0], 4 + (addr % 197));
      end
    end else if (profile_upper == "BIMODAL4_40") begin
      avmm_bfm_inst.set_default_rd_latency(4);
      for (int unsigned addr = 0; addr < 16'h10000; addr++) begin
        avmm_bfm_inst.set_rd_latency_for_addr(addr[15:0], (addr[0] == 1'b0) ? 4 : 40);
      end
    end else if (profile_upper == "ADDRESSDEP") begin
      avmm_bfm_inst.set_default_rd_latency(20);
      for (int unsigned addr = 16'h0000; addr < 16'h0400; addr++) begin
        avmm_bfm_inst.set_rd_latency_for_addr(addr[15:0], 2);
      end
      for (int unsigned addr = 16'h8000; addr < 16'h8800; addr++) begin
        avmm_bfm_inst.set_rd_latency_for_addr(addr[15:0], 4 + (addr % 9));
      end
      for (int unsigned addr = 16'hA000; addr < 16'hA800; addr++) begin
        avmm_bfm_inst.set_rd_latency_for_addr(addr[15:0], 8 + (addr % 13));
      end
      for (int unsigned addr = 16'hC000; addr < 16'hC200; addr++) begin
        avmm_bfm_inst.set_rd_latency_for_addr(addr[15:0], 6 + (addr % 11));
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
        axi4_bfm_inst.set_rd_latency_for_addr(addr[15:0], 4 + (addr % 47));
      end
    end else if (profile_upper == "UNIFORM4_20") begin
      axi4_bfm_inst.set_default_rd_latency(4);
      for (int unsigned addr = 0; addr < 16'h10000; addr++) begin
        axi4_bfm_inst.set_rd_latency_for_addr(addr[15:0], 4 + (addr % 17));
      end
    end else if (profile_upper == "UNIFORM4_200") begin
      axi4_bfm_inst.set_default_rd_latency(4);
      for (int unsigned addr = 0; addr < 16'h10000; addr++) begin
        axi4_bfm_inst.set_rd_latency_for_addr(addr[15:0], 4 + (addr % 197));
      end
    end else if (profile_upper == "BIMODAL4_40") begin
      axi4_bfm_inst.set_default_rd_latency(4);
      for (int unsigned addr = 0; addr < 16'h10000; addr++) begin
        axi4_bfm_inst.set_rd_latency_for_addr(addr[15:0], (addr[0] == 1'b0) ? 4 : 40);
      end
    end else if (profile_upper == "ADDRESSDEP") begin
      axi4_bfm_inst.set_default_rd_latency(20);
      for (int unsigned addr = 16'h0000; addr < 16'h0400; addr++) begin
        axi4_bfm_inst.set_rd_latency_for_addr(addr[15:0], 2);
      end
      for (int unsigned addr = 16'h8000; addr < 16'h8800; addr++) begin
        axi4_bfm_inst.set_rd_latency_for_addr(addr[15:0], 4 + (addr % 9));
      end
      for (int unsigned addr = 16'hA000; addr < 16'hA800; addr++) begin
        axi4_bfm_inst.set_rd_latency_for_addr(addr[15:0], 8 + (addr % 13));
      end
      for (int unsigned addr = 16'hC000; addr < 16'hC200; addr++) begin
        axi4_bfm_inst.set_rd_latency_for_addr(addr[15:0], 6 + (addr % 11));
      end
    end
  endtask
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

  sc_hub_assertions assertions_inst (
    .clk         (clk),
    .rst         (rst),
    .link_ready  (sc_pkt_vif.ready),
    .link_data   (sc_pkt_vif.data),
    .link_datak  (sc_pkt_vif.datak),
    .uplink_valid(sc_reply_vif.valid),
    .uplink_ready(sc_reply_vif.ready),
    .uplink_data (sc_reply_vif.data),
    .uplink_sop  (sc_reply_vif.sop),
    .uplink_eop  (sc_reply_vif.eop),
    .dl_fifo_usedw({6'd0, dut_inst.dl_fifo_usedw}),
    .dl_fifo_full(dut_inst.dl_fifo_full),
    .wr_data_rdreq(dut_inst.wr_data_rdreq),
    .wr_data_empty(dut_inst.wr_data_empty),
    .pkt_rx_download_ready(dut_inst.download_ready_int),
    .pkt_rx_payload_space_ready(dut_inst.pkt_rx_inst.payload_space_ready),
    .tx_reply_start(dut_inst.tx_reply_start),
    .tx_reply_ready(dut_inst.tx_reply_ready),
    .tx_reply_has_data(dut_inst.tx_reply_has_data),
    .tx_reply_suppress(dut_inst.tx_reply_suppress),
    .tx_reply_len(dut_inst.tx_reply_info.rw_length),
    .bp_usedw({6'd0, dut_inst.bp_usedw}),
    .dl_fifo_depth(16'(DUT_DL_FIFO_DEPTH)),
    .bp_fifo_depth(16'(DUT_BP_FIFO_DEPTH))
`ifdef SC_HUB_BUS_AXI4
    ,
    .axi_rd_done (dut_inst.bus_rd_done),
    .axi_rd_done_tag (dut_inst.bus_rd_done_tag),
    .axi_awid    (bus_vif.awid),
    .axi_awaddr  (bus_vif.awaddr),
    .axi_awlen   (bus_vif.awlen),
    .axi_awsize  (bus_vif.awsize),
    .axi_awburst (bus_vif.awburst),
    .axi_awvalid (bus_vif.awvalid),
    .axi_awready (bus_vif.awready),
    .axi_wdata   (bus_vif.wdata),
    .axi_wstrb   (bus_vif.wstrb),
    .axi_wlast   (bus_vif.wlast),
    .axi_wvalid  (bus_vif.wvalid),
    .axi_wready  (bus_vif.wready),
    .axi_bid     (bus_vif.bid),
    .axi_bresp   (bus_vif.bresp),
    .axi_bvalid  (bus_vif.bvalid),
    .axi_bready  (bus_vif.bready),
    .axi_arid    (bus_vif.arid),
    .axi_araddr  (bus_vif.araddr),
    .axi_arlen   (bus_vif.arlen),
    .axi_arsize  (bus_vif.arsize),
    .axi_arburst (bus_vif.arburst),
    .axi_arvalid (bus_vif.arvalid),
    .axi_arready (bus_vif.arready),
    .axi_rid     (bus_vif.rid),
    .axi_rdata   (bus_vif.rdata),
    .axi_rresp   (bus_vif.rresp),
    .axi_rlast   (bus_vif.rlast),
    .axi_rvalid  (bus_vif.rvalid),
    .axi_rready  (bus_vif.rready)
`else
    ,
    .avm_read        (bus_vif.read),
    .avm_write       (bus_vif.write),
    .avm_address     (bus_vif.address),
    .avm_writedata   (bus_vif.writedata),
    .avm_waitrequest (bus_vif.waitrequest),
    .avm_response    (bus_vif.response),
    .avm_burstcount  (bus_vif.burstcount)
`endif
  );

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
    .avm_hub_burstcount         (bus_vif.burstcount)
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
    .inject_rd_error       (bus_vif.inject_rd_error),
    .inject_wr_error       (bus_vif.inject_wr_error),
    .inject_decode_error   (bus_vif.inject_decode_error)
  );
`endif

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
