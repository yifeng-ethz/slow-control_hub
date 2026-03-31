`timescale 1ns/1ps

module sc_hub_uvm_tb_top;
  import uvm_pkg::*;
  import sc_hub_uvm_pkg::*;

  localparam int unsigned DEFAULT_TIMEOUT_CYCLES = 50000;

  logic clk;
  logic rst;
  int unsigned timeout_cycles;

  sc_pkt_if   sc_pkt_vif   (clk);
  sc_reply_if sc_reply_vif (clk);

`ifdef SC_HUB_BUS_AXI4
  sc_hub_axi4_if bus_vif(clk);
  sc_hub_avmm_if aux_avmm_vif(clk);
`else
  sc_hub_avmm_if bus_vif(clk);
  sc_hub_axi4_if aux_axi4_vif(clk);
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
    $fatal(1, "sc_hub_uvm_tb_top: timeout waiting for UVM test completion after %0d cycles", timeout_cycles);
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
    .uplink_eop  (sc_reply_vif.eop)
`ifdef SC_HUB_BUS_AXI4
    ,
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
    .INVERT_RD_SIG(0)
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
    .arvalid         (bus_vif.arvalid),
    .arready         (bus_vif.arready),
    .rid             (bus_vif.rid),
    .rdata           (bus_vif.rdata),
    .rresp           (bus_vif.rresp),
    .rlast           (bus_vif.rlast),
    .rvalid          (bus_vif.rvalid),
    .rready          (bus_vif.rready),
    .inject_rresp_err(bus_vif.inject_rresp_err),
    .inject_bresp_err(bus_vif.inject_bresp_err)
  );
`else
  sc_hub_top #(
    .INVERT_RD_SIG(0)
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
