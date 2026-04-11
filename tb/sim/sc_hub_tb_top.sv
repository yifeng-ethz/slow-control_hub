`timescale 1ns/1ps

module sc_hub_tb_top;
  import sc_hub_sim_pkg::*;
  import sc_hub_ref_model_pkg::*;

  localparam int unsigned TIMEOUT_CYCLES = 200000;
  localparam int unsigned T523_TIMEOUT_CYCLES = 5000000;
  localparam int unsigned HUB_ERR_UP_FIFO_OVERFLOW_BIT   = 0;
  localparam int unsigned HUB_ERR_DOWN_FIFO_OVERFLOW_BIT = 1;
  localparam int unsigned HUB_ERR_INTERNAL_ADDR_BIT      = 2;
  localparam int unsigned HUB_ERR_RD_TIMEOUT_BIT         = 3;
  localparam int unsigned HUB_ERR_PKT_DROP_BIT           = 4;
  localparam int unsigned HUB_ERR_SLVERR_BIT             = 5;
  localparam int unsigned HUB_ERR_DECERR_BIT             = 6;
  localparam int unsigned HUB_CSR_WO_EXT_PKT_RD_CONST    = 16'h00F;
  localparam int unsigned HUB_CSR_WO_EXT_PKT_WR_CONST    = 16'h010;
  localparam int unsigned HUB_CSR_WO_EXT_WORD_RD_CONST   = 16'h011;
  localparam int unsigned HUB_CSR_WO_EXT_WORD_WR_CONST   = 16'h012;
  localparam int unsigned HUB_CSR_WO_FEB_TYPE_CONST      = 16'h01C;
  localparam logic [31:0] HUB_UID_CONST                  = 32'h5343_4842;
  localparam logic [31:0] HUB_VERSION_CONST              = {8'd26, 8'd6, 4'd1, 12'd411};

  logic clk;
  logic rst;

  logic [31:0] link_data;
  logic [3:0]  link_datak;
  logic        link_ready;

  logic [35:0] uplink_data;
  logic        uplink_valid;
  logic        uplink_ready;
  logic        uplink_sop;
  logic        uplink_eop;

  logic [17:0] avm_address;
  logic        avm_read;
  logic [31:0] avm_readdata;
  logic        avm_writeresponsevalid;
  logic [1:0]  avm_response;
  logic        avm_write;
  logic [31:0] avm_writedata;
  logic        avm_waitrequest;
  logic        avm_readdatavalid;
  logic [8:0]  avm_burstcount;

  logic [4:0]  avs_csr_address;
  logic        avs_csr_read;
  logic        avs_csr_write;
  logic [31:0] avs_csr_writedata;
  logic [31:0] avs_csr_readdata;
  logic        avs_csr_readdatavalid;
  logic        avs_csr_waitrequest;
  logic        avs_csr_burstcount;

  logic [3:0]  axi_awid;
  logic [17:0] axi_awaddr;
  logic [7:0]  axi_awlen;
  logic [2:0]  axi_awsize;
  logic [1:0]  axi_awburst;
  logic        axi_awlock;
  logic        axi_awvalid;
  logic        axi_awready;
  logic [31:0] axi_wdata;
  logic [3:0]  axi_wstrb;
  logic        axi_wlast;
  logic        axi_wvalid;
  logic        axi_wready;
  logic [3:0]  axi_bid;
  logic [1:0]  axi_bresp;
  logic        axi_bvalid;
  logic        axi_bready;
  logic [3:0]  axi_arid;
  logic [17:0] axi_araddr;
  logic [7:0]  axi_arlen;
  logic [2:0]  axi_arsize;
  logic [1:0]  axi_arburst;
  logic        axi_arlock;
  logic        axi_arvalid;
  logic        axi_arready;
  logic [3:0]  axi_rid;
  logic [31:0] axi_rdata;
  logic [1:0]  axi_rresp;
  logic        axi_rlast;
  logic        axi_rvalid;
  logic        axi_rready;

  logic inject_rd_error;
  logic inject_wr_error;
  logic inject_decode_error;
  logic inject_rresp_err;
  logic inject_bresp_err;
  logic [15:0] forced_bp_usedw_value;

`ifdef SC_HUB_BUS_AXI4
  int unsigned axi_aw_count;
  int unsigned axi_w_count;
  int unsigned axi_b_count;
  int unsigned axi_ar_count;
  int unsigned axi_r_count;
  int unsigned axi_wlast_count;
  int unsigned axi_rlast_count;
  logic [7:0] axi_last_awlen;
  logic [7:0] axi_last_arlen;
  logic [2:0] axi_last_awsize;
  logic [2:0] axi_last_arsize;
  logic [1:0] axi_last_awburst;
  logic [1:0] axi_last_arburst;
  logic       axi_last_awlock;
  logic       axi_last_arlock;
  logic [3:0] axi_last_awid;
  logic [3:0] axi_last_arid;
  logic [3:0] axi_last_bid;
  logic [3:0] axi_last_rid;
  logic [3:0] axi_last_wstrb;
  logic [1:0] axi_last_bresp;
  logic [1:0] axi_last_rresp;
  logic       axi_w_before_aw_violation;
  logic [3:0] axi_arid_log[$];
  logic [17:0] axi_araddr_log[$];
  logic [3:0] axi_rid_log[$];
`endif

  sc_reply_t captured_reply;
  string     test_name;
  longint unsigned cycle_counter;
  int unsigned t523_issue_count_dbg;
  int unsigned t523_core_accept_count_dbg;
  int unsigned t523_reply_count_dbg;
  int unsigned t523_txn_count_dbg;
  int unsigned t523_write_reply_count_dbg;
  int unsigned t523_read_reply_count_dbg;
  int unsigned t523_ordered_reply_count_dbg;

`ifdef SC_HUB_BUS_AXI4
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
  localparam int unsigned AXI4_DUT_EXT_PLD_DEPTH = 256;
  localparam int unsigned AXI4_DUT_BP_FIFO_DEPTH = 512;
`else
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
  localparam int unsigned AVALON_DUT_EXT_TRACK_LIMIT =
    (AVALON_DUT_OUTSTANDING_INT_RESERVED >= AVALON_DUT_OUTSTANDING_LIMIT) ?
    0 : (AVALON_DUT_OUTSTANDING_LIMIT - AVALON_DUT_OUTSTANDING_INT_RESERVED);
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
`endif

`ifdef SC_HUB_BUS_AXI4
  localparam int unsigned DUT_DL_FIFO_DEPTH = AXI4_DUT_EXT_PLD_DEPTH;
  localparam int unsigned DUT_BP_FIFO_DEPTH = AXI4_DUT_BP_FIFO_DEPTH;
`else
  localparam int unsigned DUT_DL_FIFO_DEPTH = AVALON_DUT_EXT_PLD_DEPTH;
  localparam int unsigned DUT_BP_FIFO_DEPTH = AVALON_DUT_BP_FIFO_DEPTH;
`endif

  function automatic logic [31:0] expected_bus_word(
    input logic [23:0] start_address,
    input int unsigned word_index
  );
`ifdef SC_HUB_BUS_AXI4
    return 32'h2000_0000 + start_address + word_index;
`else
    return 32'h1000_0000 + start_address + word_index;
`endif
  endfunction

  function automatic logic [23:0] csr_addr(input int unsigned word_offset);
    return 24'h00FE80 + word_offset[23:0];
  endfunction

  task automatic expect_reply_header_rsp(
    input sc_reply_t    reply,
    input logic [23:0]  expected_start_address,
    input int unsigned  expected_length,
    input logic [1:0]   expected_response
  );
    if (expected_response == 2'b00) begin
      scoreboard_inst.expect_header_ok(reply, expected_length);
    end else if (!reply.header_valid ||
                 reply.echoed_length != expected_length[15:0] ||
                 reply.response != expected_response) begin
      $error("sc_hub_tb_top: reply header mismatch addr=0x%06h exp_len=%0d act_len=%0d exp_rsp=%0b act_rsp=%0b valid=%0b",
             expected_start_address,
             expected_length,
             reply.echoed_length,
             expected_response,
             reply.response,
             reply.header_valid);
    end
    if (reply.start_address !== expected_start_address) begin
      $error("sc_hub_tb_top: start address mismatch exp=0x%06h act=0x%06h",
             expected_start_address, reply.start_address);
    end
  endtask

  task automatic expect_reply_metadata(
    input sc_reply_t       reply,
    input sc_order_mode_e  expected_order_mode,
    input logic [3:0]      expected_order_domain,
    input logic [7:0]      expected_order_epoch,
    input logic [1:0]      expected_order_scope,
    input logic            expected_atomic
  );
    if (reply.order_mode !== expected_order_mode ||
        reply.order_domain !== expected_order_domain ||
        reply.order_epoch !== expected_order_epoch ||
        reply.atomic !== expected_atomic) begin
      $error("sc_hub_tb_top: reply metadata mismatch mode=%0b/%0b dom=%0h/%0h epoch=0x%0h/0x%0h atomic=%0b/%0b (scope exp=%0b act=%0b not echoed in reply)",
             reply.order_mode,
             expected_order_mode,
             reply.order_domain,
             expected_order_domain,
             reply.order_epoch,
             expected_order_epoch,
             reply.atomic,
             expected_atomic,
             expected_order_scope,
             reply.order_scope);
    end
  endtask

  task automatic expect_reply_header_ok(
    input sc_reply_t    reply,
    input logic [23:0]  expected_start_address,
    input int unsigned  expected_length
  );
    expect_reply_header_rsp(reply, expected_start_address, expected_length, 2'b00);
    expect_reply_metadata(reply, SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00, 1'b0);
  endtask

  task automatic expect_atomic_ok_reply(
    input sc_reply_t       reply,
    input logic [23:0]     expected_start_address,
    input logic [31:0]     expected_word,
    input sc_order_mode_e  expected_order_mode,
    input logic [3:0]      expected_order_domain,
    input logic [7:0]      expected_order_epoch,
    input logic [1:0]      expected_order_scope
  );
    expect_reply_header_rsp(reply, expected_start_address, 1, 2'b00);
    expect_reply_metadata(reply,
                          expected_order_mode,
                          expected_order_domain,
                          expected_order_epoch,
                          expected_order_scope,
                          1'b1);
    if (reply.payload_words != 1 || reply.payload[0] !== expected_word) begin
      $error("sc_hub_tb_top: atomic reply mismatch addr=0x%06h exp=0x%08h act_words=%0d act=0x%08h",
             expected_start_address,
             expected_word,
             reply.payload_words,
             reply.payload[0]);
    end
  endtask

  task automatic expect_read_reply(
    input sc_reply_t    reply,
    input logic [23:0]  expected_start_address,
    input int unsigned  expected_words
  );
    expect_reply_header_ok(reply, expected_start_address, expected_words);
    if (reply.payload_words != expected_words) begin
      $error("sc_hub_tb_top: payload count mismatch exp=%0d act=%0d",
             expected_words, reply.payload_words);
    end
    for (int unsigned idx = 0; idx < expected_words; idx++) begin
      if (reply.payload[idx] !== expected_bus_word(expected_start_address, idx)) begin
        $error("sc_hub_tb_top: payload[%0d] mismatch exp=0x%08h act=0x%08h",
               idx,
               expected_bus_word(expected_start_address, idx),
               reply.payload[idx]);
      end
    end
  endtask

  task automatic expect_nonincrementing_read_reply(
    input sc_reply_t    reply,
    input logic [23:0]  expected_start_address,
    input int unsigned  expected_words
  );
    logic [31:0] expected_word;

    expected_word = expected_bus_word(expected_start_address, 0);
    expect_reply_header_ok(reply, expected_start_address, expected_words);
    if (reply.payload_words != expected_words) begin
      $error("sc_hub_tb_top: nonincrementing payload count mismatch exp=%0d act=%0d",
             expected_words, reply.payload_words);
    end
    for (int unsigned idx = 0; idx < expected_words; idx++) begin
      if (reply.payload[idx] !== expected_word) begin
        $error("sc_hub_tb_top: nonincrementing payload[%0d] mismatch exp=0x%08h act=0x%08h",
               idx, expected_word, reply.payload[idx]);
      end
    end
  endtask

  task automatic expect_write_reply(
    input sc_reply_t    reply,
    input logic [23:0]  expected_start_address,
    input int unsigned  expected_words
  );
    expect_reply_header_ok(reply, expected_start_address, expected_words);
    if (reply.payload_words != 0) begin
      $error("sc_hub_tb_top: write reply unexpectedly carried %0d payload words",
             reply.payload_words);
    end
  endtask

  task automatic expect_single_word_reply(
    input sc_reply_t    reply,
    input logic [23:0]  expected_start_address,
    input logic [31:0]  expected_word
  );
    expect_reply_header_ok(reply, expected_start_address, 1);
    if (reply.payload_words != 1 || reply.payload[0] !== expected_word) begin
      $error("sc_hub_tb_top: single-word reply mismatch addr=0x%06h exp=0x%08h act_words=%0d act=0x%08h",
             expected_start_address,
             expected_word,
             reply.payload_words,
             reply.payload[0]);
    end
  endtask

  task automatic read_pkt_drop_count(output logic [31:0] pkt_drop_count);
    driver_inst.send_read(24'h00FE97, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_single_word_reply(captured_reply, 24'h00FE97, captured_reply.payload[0]);
    pkt_drop_count = captured_reply.payload[0];
  endtask

  task automatic read_csr_word(
    input  int unsigned word_offset,
    output logic [31:0] csr_word
  );
    driver_inst.send_read(csr_addr(word_offset), 1);
    monitor_inst.wait_reply(captured_reply);
    expect_single_word_reply(captured_reply, csr_addr(word_offset), captured_reply.payload[0]);
    csr_word = captured_reply.payload[0];
  endtask

  task automatic write_csr_word(
    input int unsigned  word_offset,
    input logic [31:0]  csr_word
  );
    logic [31:0] wr_words[$];

    wr_words.push_back(csr_word);
    driver_inst.send_write(csr_addr(word_offset), 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, csr_addr(word_offset), 1);
  endtask

  task automatic set_local_feb_type(input feb_type_e feb_type);
    write_csr_word(HUB_CSR_WO_FEB_TYPE_CONST, {30'h0, feb_type});
  endtask

  task automatic send_swb_style_cmd(
    input sc_cmd_t       cmd,
    input logic [31:0]   payload_words[$],
    input int unsigned   interword_skip_cycles
  );
    logic [31:0] swb_words[$];
    logic [3:0]  swb_dataks[$];

    swb_words.delete();
    swb_dataks.delete();

    swb_words.push_back(make_preamble_word(cmd));
    swb_dataks.push_back(4'b0001);
    swb_words.push_back(make_addr_word(cmd));
    swb_dataks.push_back(4'b0000);
    swb_words.push_back(make_length_word(cmd));
    swb_dataks.push_back(4'b0000);

    for (int unsigned idx = 0; idx < payload_words.size(); idx++) begin
      swb_words.push_back(payload_words[idx]);
      swb_dataks.push_back(4'b0000);
    end

    swb_words.push_back({24'h0, K284_CONST});
    swb_dataks.push_back(4'b0001);

    driver_inst.send_swb_style_raw(swb_words, swb_dataks, interword_skip_cycles);
  endtask

  task automatic clear_hub_counters();
    write_csr_word(16'h002, 32'h0000_0003);
  endtask

  task automatic issue_masked_soft_reset();
    sc_cmd_t reset_cmd;

    reset_cmd = make_cmd(SC_WRITE, csr_addr(16'h002), 1);
    reset_cmd.mask_r        = 1'b1;
    reset_cmd.data_words[0] = 32'h0000_0004;
    send_cmd(reset_cmd);
  endtask

  task automatic read_err_status(
    output logic [31:0] err_flags_word,
    output logic [31:0] err_count_word
  );
    read_csr_word(16'h004, err_flags_word);
    read_csr_word(16'h005, err_count_word);
  endtask

  task automatic expect_err_flag_and_count(
    input int unsigned flag_bit,
    input logic [31:0] expected_count,
    input string context_name
  );
    logic [31:0] err_flags_word;
    logic [31:0] err_count_word;

    read_err_status(err_flags_word, err_count_word);
    if (err_flags_word[flag_bit] !== 1'b1) begin
      $error("sc_hub_tb_top: %s expected ERR_FLAGS[%0d]=1 act=0x%08h",
             context_name, flag_bit, err_flags_word);
    end
    if (err_count_word !== expected_count) begin
      $error("sc_hub_tb_top: %s expected ERR_COUNT=0x%08h act=0x%08h",
             context_name, expected_count, err_count_word);
    end
  endtask

  task automatic trigger_avmm_read_timeout(
    input  logic [23:0] start_address,
    input  int unsigned word_count,
    output sc_reply_t   timeout_reply
  );
`ifdef SC_HUB_BUS_AXI4
    force axi4_bfm_inst.rvalid = 1'b0;
    force axi4_bfm_inst.rlast  = 1'b0;
    driver_inst.send_read(start_address, word_count);
    monitor_inst.wait_reply(timeout_reply);
    release axi4_bfm_inst.rvalid;
    release axi4_bfm_inst.rlast;
`else
    force avm_readdatavalid = 1'b0;
    force avm_response      = 2'b00;
    driver_inst.send_read(start_address, word_count);
    monitor_inst.wait_reply(timeout_reply);
    release avm_readdatavalid;
    release avm_response;
`endif
  endtask

`ifndef SC_HUB_BUS_AXI4
  task automatic require_avalon_ord_disabled(input string test_name);
    if (AVALON_DUT_ORD_ENABLE) begin
      $error("sc_hub_tb_top: %s requires SC_HUB_TB_AVALON_ORD_DISABLED and ORD_ENABLE=false",
             test_name);
    end
  endtask

  task automatic require_avalon_atomic_disabled(input string test_name);
    if (AVALON_DUT_ATOMIC_ENABLE) begin
      $error("sc_hub_tb_top: %s requires SC_HUB_TB_AVALON_ATOMIC_DISABLED and ATOMIC_ENABLE=false",
             test_name);
    end
  endtask

  task automatic wait_avalon_tracked_count(
    input int unsigned expected_count,
    input string       context_name
  );
    int unsigned waited_cycles;

    waited_cycles = 0;
    while (dut_inst.core_inst.tracked_pkt_count != expected_count) begin
      @(posedge clk);
      waited_cycles++;
      if (waited_cycles > 128) begin
        $error("sc_hub_tb_top: %s timed out waiting for tracked_pkt_count=%0d act=%0d",
               context_name,
               expected_count,
               dut_inst.core_inst.tracked_pkt_count);
        disable wait_avalon_tracked_count;
      end
    end
  endtask

  task automatic stall_avalon_reads(
    input logic [23:0] start_address,
    input int unsigned read_count
  );
    force dut_inst.bus_cmd_ready = 1'b0;
    for (int unsigned idx = 0; idx < read_count; idx++) begin
      driver_inst.send_read(start_address + idx, 1);
    end
    wait_avalon_tracked_count(read_count, "stall_avalon_reads");
  endtask

  task automatic drain_avalon_read_queue(
    input logic [23:0] start_address,
    input int unsigned read_count
  );
    release dut_inst.bus_cmd_ready;
    for (int unsigned idx = 0; idx < read_count; idx++) begin
      monitor_inst.wait_reply(captured_reply);
      expect_read_reply(captured_reply, start_address + idx, 1);
    end
  endtask

  task automatic send_stalled_avalon_write(
    input logic [23:0] start_address,
    input int unsigned word_count,
    input logic [31:0] base_word
  );
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, word_count, base_word);
    driver_inst.send_write(start_address, word_count, wr_words);
  endtask

  task automatic wait_link_ready_value(
    input logic        expected_ready,
    input string       context_name,
    input int unsigned timeout_cycles = 128
  );
    int unsigned waited_cycles;

    waited_cycles = 0;
    while (link_ready !== expected_ready) begin
      @(posedge clk);
      waited_cycles++;
      if (waited_cycles > timeout_cycles) begin
        $error("sc_hub_tb_top: %s timed out waiting for link_ready=%0b act=%0b",
               context_name,
               expected_ready,
               link_ready);
        disable wait_link_ready_value;
      end
    end
  endtask

  task automatic force_avalon_bp_usedw(
    input int unsigned forced_usedw
  );
    forced_bp_usedw_value = forced_usedw;
    force dut_inst.pkt_tx_inst.bp_fifo_usedw = forced_bp_usedw_value;
  endtask

  task automatic release_avalon_bp_usedw();
    release dut_inst.pkt_tx_inst.bp_fifo_usedw;
  endtask

  task automatic wait_avalon_read_pulse(
    input string       context_name,
    input int unsigned timeout_cycles = 128
  );
    int unsigned waited_cycles;

    waited_cycles = 0;
    while (avm_read !== 1'b1) begin
      @(posedge clk);
      waited_cycles++;
      if (waited_cycles > timeout_cycles) begin
        $error("sc_hub_tb_top: %s timed out waiting for avm_read pulse", context_name);
        disable wait_avalon_read_pulse;
      end
    end
  endtask
`endif

  task automatic fill_write_words(
    output logic [31:0] data_words[$],
    input  int unsigned word_count,
    input  logic [31:0] base_word
  );
    data_words.delete();
    for (int unsigned idx = 0; idx < word_count; idx++) begin
      data_words.push_back(base_word + idx);
    end
  endtask

  task automatic drive_word_ignore_ready(
    input logic [31:0] word,
    input logic [3:0]  datak
  );
    link_data  <= word;
    link_datak <= datak;
    @(posedge clk);
  endtask

  task automatic check_bfm_words(
    input logic [23:0] start_address,
    input logic [31:0] expected_words[]
  );
    for (int unsigned idx = 0; idx < expected_words.size(); idx++) begin
`ifdef SC_HUB_BUS_AXI4
      if (axi4_bfm_inst.mem[(start_address + idx) & 18'h3FFFF] !== expected_words[idx]) begin
        $error("sc_hub_tb_top: AXI4 mem[0x%05h] mismatch exp=0x%08h act=0x%08h",
               (start_address + idx) & 18'h3FFFF,
               expected_words[idx],
               axi4_bfm_inst.mem[(start_address + idx) & 18'h3FFFF]);
      end
`else
      if (avmm_bfm_inst.mem[(start_address + idx) & 18'h3FFFF] !== expected_words[idx]) begin
        $error("sc_hub_tb_top: AVMM mem[0x%05h] mismatch exp=0x%08h act=0x%08h",
               (start_address + idx) & 18'h3FFFF,
               expected_words[idx],
               avmm_bfm_inst.mem[(start_address + idx) & 18'h3FFFF]);
      end
`endif
    end
  endtask

  task automatic read_bfm_words(
    input  logic [23:0] start_address,
    input  int unsigned word_count,
    output logic [31:0] observed_words[$]
  );
    observed_words.delete();
    for (int unsigned idx = 0; idx < word_count; idx++) begin
`ifdef SC_HUB_BUS_AXI4
      observed_words.push_back(axi4_bfm_inst.mem[(start_address + idx) & 18'h3FFFF]);
`else
      observed_words.push_back(avmm_bfm_inst.mem[(start_address + idx) & 18'h3FFFF]);
`endif
    end
  endtask

  task automatic expect_reply_words(
    input sc_reply_t       reply,
    input logic [23:0]     expected_start_address,
    input logic [31:0]     expected_words[]
  );
    expect_reply_header_ok(reply, expected_start_address, expected_words.size());
    if (reply.payload_words != expected_words.size()) begin
      $error("sc_hub_tb_top: reply payload word-count mismatch addr=0x%06h exp=%0d act=%0d",
             expected_start_address,
             expected_words.size(),
             reply.payload_words);
    end
    for (int unsigned idx = 0; idx < expected_words.size(); idx++) begin
      if (reply.payload[idx] !== expected_words[idx]) begin
        $error("sc_hub_tb_top: reply payload[%0d] mismatch addr=0x%06h exp=0x%08h act=0x%08h",
               idx,
               expected_start_address,
               expected_words[idx],
               reply.payload[idx]);
      end
    end
  endtask

  task automatic run_burst_len_case(
    input logic            do_write,
    input logic [23:0]     start_address,
    input int unsigned     word_count,
    input logic [31:0]     base_word
  );
    logic [31:0] expected_words[$];

    if (do_write) begin
      fill_write_words(expected_words, word_count, base_word);
      driver_inst.send_burst_write(start_address, word_count, expected_words);
      monitor_inst.wait_reply(captured_reply);
      expect_write_reply(captured_reply, start_address, word_count);
      check_bfm_words(start_address, expected_words);
    end else begin
      read_bfm_words(start_address, word_count, expected_words);
      driver_inst.send_burst_read(start_address, word_count);
      monitor_inst.wait_reply(captured_reply);
      expect_reply_words(captured_reply, start_address, expected_words);
    end
  endtask

  task automatic wait_clks(input int unsigned cycle_count);
    repeat (cycle_count) @(posedge clk);
  endtask

`ifdef SC_HUB_BUS_AXI4
  task automatic reset_axi4_rd_latencies(input int unsigned default_latency = 1);
    axi4_bfm_inst.set_default_rd_latency(default_latency);
  endtask

  task automatic set_axi4_rd_latency(
    input logic [23:0] start_address,
    input int unsigned latency
  );
    axi4_bfm_inst.set_rd_latency_for_addr(start_address[17:0], latency);
  endtask

  task automatic set_axi4_wr_latency(
    input int unsigned latency
  );
    axi4_bfm_inst.set_default_wr_latency(latency);
  endtask

  task automatic write_ooo_ctrl(input bit enable_ooo);
    write_csr_word(16'h018, {31'd0, enable_ooo});
  endtask

  task automatic write_ooo_ctrl_with_replies(
    input  bit           enable_ooo,
    input  int unsigned  expected_reply_count,
    output sc_reply_t    replies[0:15],
    output int unsigned  csr_reply_idx,
    output int unsigned  non_csr_reply_count
  );
    logic [31:0] wr_words[$];
    sc_reply_t   candidate_reply;

    wr_words.delete();
    wr_words.push_back({31'd0, enable_ooo});
    driver_inst.send_write(csr_addr(16'h018), 1, wr_words);
    collect_replies(expected_reply_count, replies);

    csr_reply_idx      = 16'hFFFF;
    non_csr_reply_count = 0;
    for (int unsigned idx = 0; idx < expected_reply_count; idx++) begin
      candidate_reply = replies[idx];
      if (candidate_reply.start_address == csr_addr(16'h018)) begin
        if (csr_reply_idx != 16'hFFFF) begin
          $error("sc_hub_tb_top: write_ooo_ctrl expected a single CSR write reply for 0x%06h",
                 csr_addr(16'h018));
        end
        csr_reply_idx = idx;
      end else begin
        non_csr_reply_count++;
      end
    end

    if (csr_reply_idx == 16'hFFFF) begin
      $error("sc_hub_tb_top: write_ooo_ctrl timed out waiting for CSR write reply 0x%06h",
             csr_addr(16'h018));
    end else begin
      expect_write_reply(replies[csr_reply_idx], csr_addr(16'h018), 1);
    end
  endtask
`else
  task automatic reset_avmm_rd_latencies(input int unsigned default_latency = 1);
    avmm_bfm_inst.set_default_rd_latency(default_latency);
  endtask

  task automatic set_avmm_rd_latency(
    input logic [23:0] start_address,
    input int unsigned latency
  );
    avmm_bfm_inst.set_rd_latency_for_addr(start_address[17:0], latency);
  endtask

  task automatic set_avmm_wr_latency(
    input int unsigned latency
  );
    avmm_bfm_inst.set_default_wr_latency(latency);
  endtask
`endif

  task automatic collect_replies(
    input  int unsigned count,
    output sc_reply_t   replies[0:15]
  );
    for (int unsigned idx = 0; idx < 16; idx++) begin
      replies[idx] = make_empty_reply();
    end
    for (int unsigned idx = 0; idx < count; idx++) begin
      monitor_inst.wait_reply(replies[idx]);
    end
  endtask

  task automatic pulse_reset(input int unsigned cycle_count);
    inject_rd_error     <= 1'b0;
    inject_wr_error     <= 1'b0;
    inject_decode_error <= 1'b0;
    inject_rresp_err    <= 1'b0;
    inject_bresp_err    <= 1'b0;
    rst <= 1'b1;
    repeat (cycle_count) @(posedge clk);
    rst <= 1'b0;
  endtask

  task automatic send_cmd(input sc_cmd_t cmd);
    driver_inst.drive_word(make_preamble_word(cmd), 4'b0001);
    driver_inst.drive_word(make_addr_word(cmd), 4'b0000);
    driver_inst.drive_word(make_length_word(cmd), 4'b0000);
    if (cmd_is_write(cmd)) begin
      for (int unsigned idx = 0; idx < cmd.rw_length; idx++) begin
        driver_inst.drive_word(cmd.data_words[idx], 4'b0000);
      end
    end
    driver_inst.drive_word({24'h0, K284_CONST}, 4'b0001);
    driver_inst.drive_idle();
  endtask

  task automatic report_sc_debug_state(input string context_name);
`ifdef SC_HUB_BUS_AXI4
    $display("sc_hub_tb_top: %s rx_state=%0d pkt_in_progress=%0b pkt_valid=%0b rx_ready=%0b core_rx_ready=%0b accept_new=%0b link_ready=%0b rx_q=%0d enqueue=%0d payload_grant=%0b payload_words=%0d dl_fifo=%0d pending=%0d pending_ext=%0d dispatch_valid=%0b dispatch_idx=%0d core_state=%0d bus_cmd_issued=%0b bus_cmd_pulse=%0b bus_cmd_ready=%0b bus_done=%0b bus_timeout=%0b reply_words=%0d tx_reply_ready_q=%0b tx_reply_start=%0b tx_reply_done=%0b tx_pkt_q=%0d seen_replies=%0d ext_pkt_rd=%0d ext_word_rd=%0d last_rd_addr=0x%08h last_rd_data=0x%08h ext_pkt_wr=%0d ext_word_wr=%0d last_wr_addr=0x%08h last_wr_data=0x%08h pkt_drop=%0d",
             context_name,
             dut_inst.pkt_rx_inst.rx_state,
             dut_inst.pkt_in_progress,
             dut_inst.pkt_valid,
             dut_inst.rx_ready,
             dut_inst.core_rx_ready,
             dut_inst.accept_new_pkt_int,
             link_ready,
             dut_inst.pkt_rx_inst.pkt_queue_count,
             dut_inst.pkt_rx_inst.enqueue_stage_count,
             dut_inst.pkt_rx_inst.payload_space_granted,
             dut_inst.pkt_rx_inst.payload_check_words,
             dut_inst.dl_fifo_usedw,
             0,
             0,
             1'b0,
             0,
             0,
             1'b0,
             1'b0,
             (dut_inst.bus_rd_cmd_ready || dut_inst.bus_wr_cmd_ready),
             (dut_inst.bus_rd_done || dut_inst.bus_wr_done),
             (dut_inst.bus_rd_timeout_pulse || dut_inst.bus_wr_timeout_pulse),
             1'b0,
             1'b0,
             dut_inst.tx_reply_start,
             dut_inst.tx_reply_done,
             dut_inst.pkt_tx_inst.pkt_count,
             monitor_inst.reply_seen_count,
             dut_inst.core_inst.ext_pkt_read_count,
             dut_inst.core_inst.ext_word_read_count,
             dut_inst.core_inst.last_ext_read_addr,
             dut_inst.core_inst.last_ext_read_data,
             dut_inst.core_inst.ext_pkt_write_count,
             dut_inst.core_inst.ext_word_write_count,
             dut_inst.core_inst.last_ext_write_addr,
             dut_inst.core_inst.last_ext_write_data,
             dut_inst.pkt_rx_inst.pkt_drop_count);
`else
    $display("sc_hub_tb_top: %s rx_state=%0d pkt_in_progress=%0b pkt_valid=%0b rx_ready=%0b core_rx_ready=%0b accept_new=%0b link_ready=%0b rx_q=%0d enqueue=%0d payload_grant=%0b payload_words=%0d dl_fifo=%0d pending=%0d pending_ext=%0d dispatch_valid=%0b dispatch_idx=%0d core_state=%0d bus_cmd_issued=%0b bus_cmd_pulse=%0b bus_cmd_ready=%0b bus_done=%0b bus_timeout=%0b reply_arm=%0b tx_reply_ready_q=%0b tx_reply_start=%0b tx_reply_done=%0b tx_pkt_q=%0d seen_replies=%0d ext_pkt_rd=%0d ext_word_rd=%0d last_rd_addr=0x%08h last_rd_data=0x%08h ext_pkt_wr=%0d ext_word_wr=%0d last_wr_addr=0x%08h last_wr_data=0x%08h pkt_drop=%0d",
             context_name,
             dut_inst.pkt_rx_inst.rx_state,
             dut_inst.pkt_in_progress,
             dut_inst.pkt_valid,
             dut_inst.rx_ready,
             dut_inst.core_rx_ready,
             dut_inst.accept_new_pkt_int,
             link_ready,
             dut_inst.pkt_rx_inst.pkt_queue_count,
             dut_inst.pkt_rx_inst.enqueue_stage_count,
             dut_inst.pkt_rx_inst.payload_space_granted,
             dut_inst.pkt_rx_inst.payload_check_words,
             dut_inst.dl_fifo_usedw,
             dut_inst.core_inst.pending_pkt_count,
             dut_inst.core_inst.pending_ext_count,
             dut_inst.core_inst.dispatch_winner_valid_q,
             dut_inst.core_inst.dispatch_winner_idx_q,
             dut_inst.core_inst.core_state,
             dut_inst.core_inst.bus_cmd_issued,
             dut_inst.core_inst.bus_cmd_valid_pulse,
             dut_inst.bus_cmd_ready,
             dut_inst.bus_done,
             dut_inst.bus_timeout_pulse,
             dut_inst.core_inst.reply_words_remaining,
             dut_inst.core_inst.tx_reply_ready_q,
             dut_inst.tx_reply_start,
             dut_inst.tx_reply_done,
             dut_inst.pkt_tx_inst.pkt_count,
             monitor_inst.reply_seen_count,
             dut_inst.core_inst.ext_pkt_read_count,
             dut_inst.core_inst.ext_word_read_count,
             dut_inst.core_inst.last_ext_read_addr,
             dut_inst.core_inst.last_ext_read_data,
             dut_inst.core_inst.ext_pkt_write_count,
             dut_inst.core_inst.ext_word_write_count,
             dut_inst.core_inst.last_ext_write_addr,
             dut_inst.core_inst.last_ext_write_data,
             dut_inst.pkt_rx_inst.pkt_drop_count);
`endif
  endtask

  task automatic run_t001();
    driver_inst.send_read(24'h000000, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000000, 1);
  endtask

  task automatic run_t002();
    driver_inst.send_read(24'h00FC04, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h00FC04, 1);
  endtask

  task automatic run_t003();
    driver_inst.send_read(24'h008002, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h008002, 1);
  endtask

  task automatic run_t004();
    logic [31:0] wr_words[$];

    for (int unsigned idx = 0; idx < 64; idx++) begin
      wr_words.delete();
      wr_words.push_back(32'hA500_0000 + idx);
      driver_inst.send_write(24'h000040 + idx, 1, wr_words);
      monitor_inst.wait_reply(captured_reply);
      expect_write_reply(captured_reply, 24'h000040 + idx, 1);

      driver_inst.send_read(24'h000040 + idx, 1);
      monitor_inst.wait_reply(captured_reply);
      expect_reply_header_ok(captured_reply, 24'h000040 + idx, 1);
      if (captured_reply.payload_words != 1 || captured_reply.payload[0] !== wr_words[0]) begin
        $error("sc_hub_tb_top: readback mismatch addr=0x%06h exp=0x%08h act_words=%0d act=0x%08h",
               24'h000040 + idx,
               wr_words[0],
               captured_reply.payload_words,
               captured_reply.payload[0]);
      end
    end
  endtask

  task automatic run_t005();
    driver_inst.send_read(24'h000000, 64);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000000, 64);
  endtask

  task automatic run_t006();
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, 64, 32'hC600_0000);
    driver_inst.send_write(24'h000000, 64, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000000, 64);
    check_bfm_words(24'h000000, wr_words);
  endtask

  task automatic run_t007();
    driver_inst.send_read(24'h000000, 256);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000000, 256);
  endtask

  task automatic run_t008();
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, 256, 32'hD700_0000);
    driver_inst.send_write(24'h000000, 256, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000000, 256);
    check_bfm_words(24'h000000, wr_words);
  endtask

  task automatic run_t009();
    driver_inst.send_read(24'h000000, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000000, 1);
  endtask

  task automatic run_t010();
    driver_inst.send_read(24'h001000, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_ok(captured_reply, 24'h001000, 1);
  endtask

  task automatic run_t011();
    logic [31:0] wr_words[$];

    wr_words.push_back(32'h0000_ABCD);
    driver_inst.send_write(24'h001000, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h001000, 1);
  endtask

  task automatic run_t012();
    driver_inst.send_read_with_fpga_id(16'hABCD, 24'h000000, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000000, 1);
    if (captured_reply.fpga_id !== 16'hABCD) begin
      $error("sc_hub_tb_top: fpga_id echo mismatch exp=0x%04h act=0x%04h",
             16'hABCD, captured_reply.fpga_id);
    end
  endtask

  task automatic run_t025();
    logic [31:0] wr_words[$];
    sc_cmd_t     cmd;

    fill_write_words(wr_words, 16, 32'hCC00_0000);
    cmd = make_cmd(SC_WRITE, 24'h000000, 16);

    driver_inst.drive_word(make_preamble_word(cmd), 4'b0001);
`ifdef SC_HUB_BUS_AXI4
    if (axi_aw_count != 0 || axi_w_count != 0) begin
      $error("sc_hub_tb_top: AXI4 activity observed during write preamble phase");
    end
`else
    if (avm_write !== 1'b0) begin
      $error("sc_hub_tb_top: AVMM write asserted during write preamble phase");
    end
`endif

    driver_inst.drive_word(make_addr_word(cmd), 4'b0000);
`ifdef SC_HUB_BUS_AXI4
    if (axi_aw_count != 0 || axi_w_count != 0) begin
      $error("sc_hub_tb_top: AXI4 activity observed during write address phase");
    end
`else
    if (avm_write !== 1'b0) begin
      $error("sc_hub_tb_top: AVMM write asserted during write address phase");
    end
`endif

    driver_inst.drive_word(make_length_word(cmd), 4'b0000);
`ifdef SC_HUB_BUS_AXI4
    if (axi_aw_count != 0 || axi_w_count != 0) begin
      $error("sc_hub_tb_top: AXI4 activity observed during write length phase");
    end
`else
    if (avm_write !== 1'b0) begin
      $error("sc_hub_tb_top: AVMM write asserted during write length phase");
    end
`endif

    for (int unsigned idx = 0; idx < wr_words.size(); idx++) begin
      driver_inst.drive_word(wr_words[idx], 4'b0000);
`ifdef SC_HUB_BUS_AXI4
      if (axi_aw_count != 0 || axi_w_count != 0) begin
        $error("sc_hub_tb_top: AXI4 activity observed before trailer at beat %0d", idx);
      end
`else
      if (avm_write !== 1'b0) begin
        $error("sc_hub_tb_top: AVMM write asserted before trailer at beat %0d", idx);
      end
`endif
    end

    driver_inst.drive_word({24'h0, K284_CONST}, 4'b0001);
    driver_inst.drive_idle();

    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000000, 16);
    check_bfm_words(24'h000000, wr_words);
  endtask

  task automatic run_t027();
    logic [31:0] words[$];
    logic [3:0]  dataks[$];
    logic [31:0] pkt_drop_count;

    for (int unsigned idx = 0; idx < 8; idx++) begin
      words.push_back(32'hDD00_0000 + idx);
      dataks.push_back(4'b0000);
    end

    words.insert(0, 32'h0000_0008);
    dataks.insert(0, 4'b0000);
    words.insert(0, 32'h0000_0000);
    dataks.insert(0, 4'b0000);
    words.insert(0, 32'h1F00_02BC);
    dataks.insert(0, 4'b0001);
    words.push_back(32'h1234_5678);
    dataks.push_back(4'b0000);

    driver_inst.send_raw(words, dataks);
    monitor_inst.assert_no_reply(400ns);
    read_pkt_drop_count(pkt_drop_count);
    if (pkt_drop_count !== 32'd1) begin
      $error("sc_hub_tb_top: PKT_DROP_CNT mismatch after missing trailer exp=1 act=%0d",
             pkt_drop_count);
    end
  endtask

  task automatic run_t028();
    logic [31:0] words[$];
    logic [3:0]  dataks[$];
    logic [31:0] pkt_drop_count;
    sc_cmd_t     cmd;

    cmd = make_cmd(SC_WRITE, 24'h000000, 257);
    words.push_back(make_preamble_word(cmd));
    dataks.push_back(4'b0001);
    words.push_back(make_addr_word(cmd));
    dataks.push_back(4'b0000);
    words.push_back(make_length_word(cmd));
    dataks.push_back(4'b0000);
    words.push_back({24'h0, K284_CONST});
    dataks.push_back(4'b0001);

    driver_inst.send_raw(words, dataks);
    monitor_inst.assert_no_reply(400ns);
    read_pkt_drop_count(pkt_drop_count);
    if (pkt_drop_count !== 32'd1) begin
      $error("sc_hub_tb_top: PKT_DROP_CNT mismatch after oversize packet exp=1 act=%0d",
             pkt_drop_count);
    end
  endtask

  task automatic run_t029();
    logic [31:0] words[$];
    logic [3:0]  dataks[$];
    sc_cmd_t     cmd;

    cmd = make_cmd(SC_WRITE, 24'h000000, 0);
    words.push_back(make_preamble_word(cmd));
    dataks.push_back(4'b0001);
    words.push_back(make_addr_word(cmd));
    dataks.push_back(4'b0000);
    words.push_back(make_length_word(cmd));
    dataks.push_back(4'b0000);
    words.push_back({24'h0, K284_CONST});
    dataks.push_back(4'b0001);

    driver_inst.send_raw(words, dataks);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000000, 0);
  endtask

  task automatic run_t030();
    logic [31:0] words[$];
    logic [3:0]  dataks[$];
    logic [31:0] pkt_drop_count;

    words.push_back(32'h1F00_02BC);
    dataks.push_back(4'b0001);
    words.push_back(32'h0000_0000);
    dataks.push_back(4'b0000);
    words.push_back(32'h0000_0008);
    dataks.push_back(4'b0000);
    for (int unsigned idx = 0; idx < 4; idx++) begin
      words.push_back(32'hDE00_0000 + idx);
      dataks.push_back(4'b0000);
    end
    words.push_back({24'h0, K284_CONST});
    dataks.push_back(4'b0001);

    driver_inst.send_raw(words, dataks);
    monitor_inst.assert_no_reply(400ns);
    read_pkt_drop_count(pkt_drop_count);
    if (pkt_drop_count !== 32'd1) begin
      $error("sc_hub_tb_top: PKT_DROP_CNT mismatch after short packet exp=1 act=%0d",
             pkt_drop_count);
    end
  endtask

  task automatic run_t031();
    logic [31:0] words[$];
    logic [3:0]  dataks[$];
    logic [31:0] pkt_drop_count;

    words.push_back(32'h1F00_02BC);
    dataks.push_back(4'b0001);
    words.push_back(32'h0000_0000);
    dataks.push_back(4'b0000);
    words.push_back(32'h0000_0004);
    dataks.push_back(4'b0000);
    for (int unsigned idx = 0; idx < 8; idx++) begin
      words.push_back(32'hEF00_0000 + idx);
      dataks.push_back(4'b0000);
    end
    words.push_back({24'h0, K284_CONST});
    dataks.push_back(4'b0001);

    driver_inst.send_raw(words, dataks);
    monitor_inst.assert_no_reply(400ns);
    read_pkt_drop_count(pkt_drop_count);
    if (pkt_drop_count !== 32'd1) begin
      $error("sc_hub_tb_top: PKT_DROP_CNT mismatch after long packet exp=1 act=%0d",
             pkt_drop_count);
    end
  endtask

  task automatic run_t032();
    sc_cmd_t cmd;
    bit      saw_drop;

    cmd = make_cmd(SC_WRITE, 24'h000000, 16);
    driver_inst.drive_word(make_preamble_word(cmd), 4'b0001);
    driver_inst.drive_word(make_addr_word(cmd), 4'b0000);
    driver_inst.drive_word(make_length_word(cmd), 4'b0000);
    for (int unsigned idx = 0; idx < 8; idx++) begin
      driver_inst.drive_word(32'hF000_0000 + idx, 4'b0000);
    end
    driver_inst.drive_idle();

    saw_drop = 1'b0;
    repeat (128) begin
      @(posedge clk);
      if (dut_inst.pkt_drop_pulse == 1'b1) begin
        saw_drop = 1'b1;
      end
    end

    if (!saw_drop) begin
      $error("sc_hub_tb_top: truncated packet did not time out and assert pkt_drop_pulse");
    end
  endtask

  task automatic run_t033();
    sc_cmd_t cmd;
    bit      saw_early_drop;
    bit      saw_timeout_drop;

    cmd = make_cmd(SC_WRITE, 24'h000000, 16);
    driver_inst.drive_word(make_preamble_word(cmd), 4'b0001);
    driver_inst.drive_idle();

    saw_early_drop   = 1'b0;
    saw_timeout_drop = 1'b0;

    repeat (32) begin
      @(posedge clk);
      if (dut_inst.pkt_drop_pulse == 1'b1) begin
        saw_early_drop = 1'b1;
      end
      if (avm_write == 1'b1 || avm_read == 1'b1) begin
        $error("sc_hub_tb_top: bus activity observed after preamble-only malformed packet");
      end
    end

    if (saw_early_drop) begin
      $error("sc_hub_tb_top: preamble-only packet dropped before RX timeout window elapsed");
    end

    repeat (96) begin
      @(posedge clk);
      if (dut_inst.pkt_drop_pulse == 1'b1) begin
        saw_timeout_drop = 1'b1;
      end
      if (avm_write == 1'b1 || avm_read == 1'b1) begin
        $error("sc_hub_tb_top: bus activity observed during preamble-only timeout handling");
      end
    end

    if (!saw_timeout_drop) begin
      $error("sc_hub_tb_top: preamble-only packet never timed out and dropped");
    end
  endtask

  task automatic run_t034();
    logic [31:0] words[$];
    logic [3:0]  dataks[$];
    logic [31:0] pkt_drop_count;

    words.push_back(32'h3F00_02BC);
    dataks.push_back(4'b0001);
    words.push_back(32'h0000_0000);
    dataks.push_back(4'b0000);
    words.push_back(32'h0000_0001);
    dataks.push_back(4'b0000);
    words.push_back({24'h0, K284_CONST});
    dataks.push_back(4'b0001);

    driver_inst.send_raw(words, dataks);

    repeat (32) begin
      @(posedge clk);
      if (avm_write == 1'b1 || avm_read == 1'b1) begin
        $error("sc_hub_tb_top: bus activity observed for non-SC preamble");
      end
    end

    monitor_inst.assert_no_reply(400ns);
    read_pkt_drop_count(pkt_drop_count);
    if (pkt_drop_count !== 32'd0) begin
      $error("sc_hub_tb_top: PKT_DROP_CNT changed on ignored non-SC preamble exp=0 act=%0d",
             pkt_drop_count);
    end
  endtask

  task automatic run_t035();
    logic [31:0] pkt_drop_count;
    bit          saw_drop;

    saw_drop = 1'b0;

    driver_inst.drive_word(32'h1F00_02BC, 4'b0001);
    driver_inst.drive_word(32'h0000_0000, 4'b0000);
    driver_inst.drive_word(32'h0000_0002, 4'b0000);
    driver_inst.drive_word(32'hAA00_0001, 4'b0000);

    force dut_inst.pkt_rx_inst.fifo_full_int = 1'b1;
    force dut_inst.dl_fifo_usedw = DUT_DL_FIFO_DEPTH;
    drive_word_ignore_ready(32'hAA00_0002, 4'b0000);
    release dut_inst.pkt_rx_inst.fifo_full_int;
    release dut_inst.dl_fifo_usedw;
    driver_inst.drive_idle();

    repeat (32) begin
      @(posedge clk);
      if (dut_inst.pkt_drop_pulse == 1'b1) begin
        saw_drop = 1'b1;
      end
      if (avm_write == 1'b1 || avm_read == 1'b1) begin
        $error("sc_hub_tb_top: bus activity observed during forced RX FIFO overflow test");
      end
    end

    if (!saw_drop) begin
      $error("sc_hub_tb_top: forced RX FIFO overflow did not assert pkt_drop_pulse");
    end

    repeat (4) @(posedge clk);
    read_pkt_drop_count(pkt_drop_count);
    if (pkt_drop_count !== 32'd1) begin
      $error("sc_hub_tb_top: PKT_DROP_CNT mismatch after forced RX FIFO overflow exp=1 act=%0d",
             pkt_drop_count);
    end
  endtask

  task automatic run_t036();
    logic [31:0] words[$];
    logic [3:0]  dataks[$];
    logic [31:0] wr_words[$];
    logic [31:0] pkt_drop_count;
    bit          saw_drop;

    words.push_back(32'h1F00_02BC);
    dataks.push_back(4'b0001);
    words.push_back(32'h0000_0000);
    dataks.push_back(4'b0000);
    words.push_back(32'h0000_0004);
    dataks.push_back(4'b0000);
    words.push_back(32'hDE00_0000);
    dataks.push_back(4'b0000);
    words.push_back(32'hDE00_0001);
    dataks.push_back(4'b0000);

    driver_inst.send_raw(words, dataks);
    saw_drop = 1'b0;
    repeat (128) begin
      @(posedge clk);
      if (dut_inst.pkt_drop_pulse == 1'b1) begin
        saw_drop = 1'b1;
      end
    end
    if (!saw_drop) begin
      $error("sc_hub_tb_top: malformed packet did not drop before recovery test");
    end

    fill_write_words(wr_words, 1, 32'h3600_0000);
    driver_inst.send_write(24'h000030, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000030, 1);
    check_bfm_words(24'h000030, wr_words);

    read_pkt_drop_count(pkt_drop_count);
    if (pkt_drop_count !== 32'd1) begin
      $error("sc_hub_tb_top: PKT_DROP_CNT mismatch after drop+recovery exp=1 act=%0d",
             pkt_drop_count);
    end
  endtask

  task automatic run_t037();
    logic [31:0] words[$];
    logic [3:0]  dataks[$];
    logic [31:0] pkt_drop_count;
    bit          saw_drop;

    for (int unsigned drop_idx = 0; drop_idx < 3; drop_idx++) begin
      words.delete();
      dataks.delete();
      words.push_back(32'h1F00_02BC);
      dataks.push_back(4'b0001);
      words.push_back(32'h0000_0000);
      dataks.push_back(4'b0000);
      words.push_back(32'h0000_0004);
      dataks.push_back(4'b0000);
      words.push_back(32'hE700_0000 + drop_idx);
      dataks.push_back(4'b0000);
      driver_inst.send_raw(words, dataks);
      saw_drop = 1'b0;
      repeat (128) begin
        @(posedge clk);
        if (dut_inst.pkt_drop_pulse == 1'b1) begin
          saw_drop = 1'b1;
        end
      end
      if (!saw_drop) begin
        $error("sc_hub_tb_top: drop packet %0d did not assert pkt_drop_pulse", drop_idx);
      end
    end

    driver_inst.send_read(24'h000040, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000040, 1);

    read_pkt_drop_count(pkt_drop_count);
    if (pkt_drop_count !== 32'd3) begin
      $error("sc_hub_tb_top: PKT_DROP_CNT mismatch after 3 drops exp=3 act=%0d",
             pkt_drop_count);
    end
  endtask

  task automatic run_t038();
    sc_cmd_t   cmd;
    sc_reply_t read_reply;
    bit        saw_bus_read_before_trailer;

    cmd = make_cmd(SC_READ, 24'h000020, 1);
    saw_bus_read_before_trailer = 1'b0;

    fork
      begin
        monitor_inst.wait_reply(read_reply);
      end
      begin
        driver_inst.drive_word(make_preamble_word(cmd), 4'b0001);
        driver_inst.drive_word(make_addr_word(cmd), 4'b0000);
        driver_inst.drive_word(make_length_word(cmd), 4'b0000);

        repeat (8) begin
          @(posedge clk);
`ifdef SC_HUB_BUS_AXI4
          if (axi_ar_count != 0) begin
            saw_bus_read_before_trailer = 1'b1;
          end
`else
          if (avm_read == 1'b1) begin
            saw_bus_read_before_trailer = 1'b1;
          end
`endif
        end

        if (!saw_bus_read_before_trailer) begin
          $error("sc_hub_tb_top: read transaction did not launch before trailer");
        end

        driver_inst.drive_word({24'h0, K284_CONST}, 4'b0001);
        driver_inst.drive_idle();
      end
    join

    captured_reply = read_reply;
    expect_read_reply(captured_reply, 24'h000020, 1);
  endtask

  task automatic run_t039();
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, 4, 32'h3900_0000);

    driver_inst.drive_word(32'h1F00_02BC, 4'b0001);
    driver_inst.drive_word(32'h0000_0040, 4'b0000);
    driver_inst.drive_word(32'h0000_0004, 4'b0000);
    driver_inst.drive_word(wr_words[0], 4'b0000);
    driver_inst.drive_word(32'h0000_00BC, 4'b0001);
    driver_inst.drive_word(wr_words[1], 4'b0000);
    driver_inst.drive_word(32'h0000_00BC, 4'b0001);
    driver_inst.drive_word(wr_words[2], 4'b0000);
    driver_inst.drive_word(32'h0000_00BC, 4'b0001);
    driver_inst.drive_word(wr_words[3], 4'b0000);
    driver_inst.drive_word({24'h0, K284_CONST}, 4'b0001);
    driver_inst.drive_idle();

    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000040, 4);
    check_bfm_words(24'h000040, wr_words);
  endtask

  task automatic run_t041();
    sc_cmd_t cmd1;
    sc_cmd_t cmd2;

    cmd1 = make_cmd(SC_WRITE, 24'h000000, 4);
    cmd2 = make_cmd(SC_READ, 24'h000020, 1);

    driver_inst.drive_word(make_preamble_word(cmd1), 4'b0001);
    driver_inst.drive_word(make_preamble_word(cmd2), 4'b0001);
    driver_inst.drive_word(make_addr_word(cmd2), 4'b0000);
    driver_inst.drive_word(make_length_word(cmd2), 4'b0000);
    driver_inst.drive_word({24'h0, K284_CONST}, 4'b0001);
    driver_inst.drive_idle();

    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000020, 1);
  endtask

  task automatic run_t042();
    logic [31:0] words[$];
    logic [3:0]  dataks[$];

    for (int unsigned idx = 0; idx < 4; idx++) begin
`ifdef SC_HUB_BUS_AXI4
      axi4_bfm_inst.mem[16'h0060 + idx] = 32'h4200_1000 + idx;
`else
      avmm_bfm_inst.mem[16'h0060 + idx] = 32'h4200_1000 + idx;
`endif
    end

    words.push_back(32'h1F00_02BC);
    dataks.push_back(4'b0001);
    words.push_back(32'h0000_0060);
    dataks.push_back(4'b0000);
    words.push_back(32'h0000_0004);
    dataks.push_back(4'b0000);
    words.push_back(32'h4200_AAAA);
    dataks.push_back(4'b0000);
    words.push_back(32'h4200_BBBB);
    dataks.push_back(4'b0000);

    driver_inst.send_raw(words, dataks);
    monitor_inst.assert_no_reply(400ns);

    for (int unsigned idx = 0; idx < 4; idx++) begin
`ifdef SC_HUB_BUS_AXI4
      if (axi4_bfm_inst.mem[16'h0060 + idx] !== 32'h4200_1000 + idx) begin
        $error("sc_hub_tb_top: AXI4 memory corrupted by dropped packet at idx=%0d act=0x%08h",
               idx, axi4_bfm_inst.mem[16'h0060 + idx]);
      end
`else
      if (avmm_bfm_inst.mem[16'h0060 + idx] !== 32'h4200_1000 + idx) begin
        $error("sc_hub_tb_top: AVMM memory corrupted by dropped packet at idx=%0d act=0x%08h",
               idx, avmm_bfm_inst.mem[16'h0060 + idx]);
      end
`endif
    end
  endtask

  task automatic run_t043();
    logic [31:0] csr_word;

    read_csr_word(16'h000, csr_word);
    if (csr_word !== HUB_UID_CONST) begin
      $error("sc_hub_tb_top: CSR UID mismatch exp=0x%08h act=0x%08h",
             HUB_UID_CONST, csr_word);
    end
  endtask

  task automatic run_t044();
    logic [31:0] csr_word;

    read_csr_word(16'h001, csr_word);
    if (csr_word !== HUB_VERSION_CONST) begin
      $error("sc_hub_tb_top: CSR META/VERSION mismatch exp=0x%08h act=0x%08h",
             HUB_VERSION_CONST, csr_word);
    end
  endtask

  task automatic run_t045();
    logic [31:0] csr_word;

    write_csr_word(16'h002, 32'h0000_0001);
    read_csr_word(16'h002, csr_word);
    if (csr_word[0] !== 1'b1) begin
      $error("sc_hub_tb_top: CSR CTRL enable mismatch exp=1 act=%0b", csr_word[0]);
    end
  endtask

  task automatic run_t046();
    logic [31:0] csr_word;

    read_csr_word(16'h003, csr_word);
    if (csr_word[0] !== 1'b0) begin
      $error("sc_hub_tb_top: CSR STATUS busy mismatch exp=0 act=%0b", csr_word[0]);
    end
    if (csr_word[5] !== 1'b0) begin
      $error("sc_hub_tb_top: CSR STATUS bus_busy mismatch exp=0 act=%0b", csr_word[5]);
    end
  endtask

  task automatic run_t047();
    logic [31:0] err_flags_word;
    sc_reply_t   timeout_reply;

    write_csr_word(16'h002, 32'h0000_0003);
    trigger_avmm_read_timeout(24'h000080, 1, timeout_reply);
    if (!timeout_reply.header_valid || timeout_reply.echoed_length != 16'd1 ||
        timeout_reply.response != 2'b11 || timeout_reply.payload_words != 1 ||
        timeout_reply.payload[0] !== 32'hEEEE_EEEE) begin
      $error("sc_hub_tb_top: timeout reply mismatch valid=%0b len=%0d rsp=%0b words=%0d data=0x%08h",
             timeout_reply.header_valid,
             timeout_reply.echoed_length,
             timeout_reply.response,
             timeout_reply.payload_words,
             timeout_reply.payload[0]);
    end

    read_csr_word(16'h004, err_flags_word);
    if (err_flags_word[3] !== 1'b1) begin
      $error("sc_hub_tb_top: ERR_FLAGS.rd_timeout mismatch exp=1 act=%0b",
             err_flags_word[3]);
    end

    write_csr_word(16'h004, 32'h0000_0008);
    read_csr_word(16'h004, err_flags_word);
    if (err_flags_word[3] !== 1'b0) begin
      $error("sc_hub_tb_top: ERR_FLAGS.rd_timeout clear mismatch exp=0 act=%0b",
             err_flags_word[3]);
    end
  endtask

  task automatic run_t048();
    logic [31:0] err_count_word;
    sc_reply_t   timeout_reply;

    write_csr_word(16'h002, 32'h0000_0003);

    for (int unsigned idx = 0; idx < 260; idx++) begin
      trigger_avmm_read_timeout(24'h000100 + idx, 1, timeout_reply);
      if (timeout_reply.response !== 2'b11) begin
        $error("sc_hub_tb_top: timeout response mismatch at iter=%0d rsp=%0b",
               idx, timeout_reply.response);
      end
    end

    read_csr_word(16'h005, err_count_word);
    if (err_count_word !== 32'h0000_00FF) begin
      $error("sc_hub_tb_top: ERR_COUNT saturation mismatch exp=0x000000FF act=0x%08h",
             err_count_word);
    end
  endtask

  task automatic run_t049();
    logic [31:0] scratch_word;

    write_csr_word(16'h006, 32'hDEAD_BEEF);
    read_csr_word(16'h006, scratch_word);
    if (scratch_word !== 32'hDEAD_BEEF) begin
      $error("sc_hub_tb_top: SCRATCH readback mismatch exp=0xDEADBEEF act=0x%08h",
             scratch_word);
    end

    write_csr_word(16'h006, 32'h1234_5678);
    read_csr_word(16'h006, scratch_word);
    if (scratch_word !== 32'h1234_5678) begin
      $error("sc_hub_tb_top: SCRATCH second readback mismatch exp=0x12345678 act=0x%08h",
             scratch_word);
    end
  endtask

  task automatic run_t050();
    logic [31:0] snap_hi_word;
    logic [31:0] snap_lo_word;

    read_csr_word(16'h008, snap_hi_word);
    read_csr_word(16'h007, snap_lo_word);
    if (snap_hi_word[31:16] !== 16'h0000) begin
      $error("sc_hub_tb_top: GTS_SNAP_HI upper bits mismatch exp=0 act=0x%04h",
             snap_hi_word[31:16]);
    end
    if ({snap_hi_word[15:0], snap_lo_word} == 48'h0) begin
      $error("sc_hub_tb_top: GTS snapshot unexpectedly zero");
    end
  endtask

  task automatic run_t051();
    logic [31:0] fifo_cfg_word;

    read_csr_word(16'h009, fifo_cfg_word);
    if (fifo_cfg_word[0] !== 1'b1) begin
      $error("sc_hub_tb_top: FIFO_CFG download S&F mismatch exp=1 act=%0b",
             fifo_cfg_word[0]);
    end
  endtask

  task automatic run_t052();
    logic [31:0] fifo_status_word;
    logic [31:0] down_usedw_word;
    logic [31:0] up_usedw_word;

    force dut_inst.dl_fifo_usedw     = 9'd7;
    force dut_inst.bp_usedw          = 10'd9;
    force dut_inst.dl_fifo_full      = 1'b0;
    force dut_inst.bp_full           = 1'b0;
    force dut_inst.dl_fifo_overflow  = 1'b1;
    force dut_inst.bp_overflow       = 1'b0;

    read_csr_word(16'h00A, fifo_status_word);
    read_csr_word(16'h00D, down_usedw_word);
    read_csr_word(16'h00E, up_usedw_word);

    release dut_inst.dl_fifo_usedw;
    release dut_inst.bp_usedw;
    release dut_inst.dl_fifo_full;
    release dut_inst.bp_full;
    release dut_inst.dl_fifo_overflow;
    release dut_inst.bp_overflow;

    if (fifo_status_word[0] !== 1'b0 || fifo_status_word[1] !== 1'b0 ||
        fifo_status_word[2] !== 1'b1 || fifo_status_word[3] !== 1'b0) begin
      $error("sc_hub_tb_top: FIFO_STATUS mismatch exp[3:0]=4'b0100 act=0x%0h",
             fifo_status_word[3:0]);
    end
    if (down_usedw_word[8:0] !== 9'd7) begin
      $error("sc_hub_tb_top: DOWN_USEDW mismatch exp=7 act=%0d",
             down_usedw_word[8:0]);
    end
    if (up_usedw_word[9:0] !== 10'd9) begin
      $error("sc_hub_tb_top: UP_USEDW mismatch exp=9 act=%0d",
             up_usedw_word[9:0]);
    end
  endtask

  task automatic run_t053();
    logic [31:0] csr_word;
    logic [31:0] wr_words[$];

    clear_hub_counters();

    for (int unsigned idx = 0; idx < 5; idx++) begin
      driver_inst.send_read(24'h000100 + idx, 1);
      monitor_inst.wait_reply(captured_reply);
      expect_read_reply(captured_reply, 24'h000100 + idx, 1);
    end

    for (int unsigned idx = 0; idx < 3; idx++) begin
      wr_words.delete();
      wr_words.push_back(32'h5300_0000 + idx);
      driver_inst.send_write(24'h000200 + idx, 1, wr_words);
      monitor_inst.wait_reply(captured_reply);
      expect_write_reply(captured_reply, 24'h000200 + idx, 1);
    end

    read_csr_word(16'h00F, csr_word);
    if (csr_word !== 32'd5) begin
      $error("sc_hub_tb_top: EXT_PKT_RD count mismatch exp=5 act=%0d", csr_word);
    end
    read_csr_word(16'h010, csr_word);
    if (csr_word !== 32'd3) begin
      $error("sc_hub_tb_top: EXT_PKT_WR count mismatch exp=3 act=%0d", csr_word);
    end
  endtask

  task automatic run_t054();
    logic [31:0] csr_word;
    logic [31:0] wr_words[$];

    clear_hub_counters();

    driver_inst.send_read(24'h000300, 10);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000300, 10);

    fill_write_words(wr_words, 20, 32'h5400_0000);
    driver_inst.send_write(24'h000320, 20, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000320, 20);

    read_csr_word(16'h011, csr_word);
    if (csr_word !== 32'd10) begin
      $error("sc_hub_tb_top: EXT_WORD_RD count mismatch exp=10 act=%0d", csr_word);
    end
    read_csr_word(16'h012, csr_word);
    if (csr_word !== 32'd20) begin
      $error("sc_hub_tb_top: EXT_WORD_WR count mismatch exp=20 act=%0d", csr_word);
    end
  endtask

  task automatic run_t055();
    logic [31:0] csr_word;

    clear_hub_counters();
    driver_inst.send_read(24'h001234, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h001234, 1);

    read_csr_word(16'h013, csr_word);
    if (csr_word !== 32'h0000_1234) begin
      $error("sc_hub_tb_top: LAST_RD_ADDR mismatch exp=0x00001234 act=0x%08h", csr_word);
    end
    read_csr_word(16'h014, csr_word);
    if (csr_word !== expected_bus_word(24'h001234, 0)) begin
      $error("sc_hub_tb_top: LAST_RD_DATA mismatch exp=0x%08h act=0x%08h",
             expected_bus_word(24'h001234, 0), csr_word);
    end
  endtask

  task automatic run_t056();
    logic [31:0] csr_word;
    logic [31:0] wr_words[$];

    clear_hub_counters();
    wr_words.push_back(32'hCAFE_BABE);
    driver_inst.send_write(24'h005678, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h005678, 1);

    read_csr_word(16'h015, csr_word);
    if (csr_word !== 32'h0000_5678) begin
      $error("sc_hub_tb_top: LAST_WR_ADDR mismatch exp=0x00005678 act=0x%08h", csr_word);
    end
    read_csr_word(16'h016, csr_word);
    if (csr_word !== 32'hCAFE_BABE) begin
      $error("sc_hub_tb_top: LAST_WR_DATA mismatch exp=0xCAFEBABE act=0x%08h", csr_word);
    end
  endtask

  task automatic run_t057();
    logic [31:0] pkt_drop_count;
    logic [31:0] words[$];
    logic [3:0]  dataks[$];
    bit          saw_drop;

    clear_hub_counters();

    for (int unsigned drop_idx = 0; drop_idx < 3; drop_idx++) begin
      words.delete();
      dataks.delete();
      words.push_back(32'h1F00_02BC);
      dataks.push_back(4'b0001);
      words.push_back(32'h0000_0000);
      dataks.push_back(4'b0000);
      words.push_back(32'h0000_0004);
      dataks.push_back(4'b0000);
      words.push_back(32'h5700_0000 + drop_idx);
      dataks.push_back(4'b0000);
      driver_inst.send_raw(words, dataks);
      saw_drop = 1'b0;
      repeat (128) begin
        @(posedge clk);
        if (dut_inst.pkt_drop_pulse == 1'b1) begin
          saw_drop = 1'b1;
        end
      end
      if (!saw_drop) begin
        $error("sc_hub_tb_top: PKT_DROP pulse missing at iter=%0d", drop_idx);
      end
    end

    read_pkt_drop_count(pkt_drop_count);
    if (pkt_drop_count !== 32'd3) begin
      $error("sc_hub_tb_top: PKT_DROP_CNT mismatch exp=3 act=%0d", pkt_drop_count);
    end
  endtask

  task automatic run_t058();
    localparam int unsigned INVALID_CSR_WORD_OFFSET = 16'h01B;
`ifdef SC_HUB_BUS_AXI4
    driver_inst.send_read(csr_addr(16'h018), 1);
    monitor_inst.wait_reply(captured_reply);
    expect_single_word_reply(captured_reply, csr_addr(16'h018), 32'h0000_0000);
`else
    driver_inst.send_read(csr_addr(INVALID_CSR_WORD_OFFSET), 1);
    monitor_inst.wait_reply(captured_reply);
    if (!captured_reply.header_valid ||
        captured_reply.start_address != csr_addr(INVALID_CSR_WORD_OFFSET) ||
        captured_reply.echoed_length != 16'd1 ||
        captured_reply.response != 2'b10 || captured_reply.payload_words != 1 ||
        captured_reply.payload[0] !== 32'hEEEE_EEEE) begin
      $error("sc_hub_tb_top: invalid CSR offset reply mismatch valid=%0b len=%0d rsp=%0b words=%0d data=0x%08h",
             captured_reply.header_valid,
             captured_reply.echoed_length,
             captured_reply.response,
             captured_reply.payload_words,
             captured_reply.payload[0]);
    end
`endif
  endtask

  task automatic run_t059();
    logic [31:0] wr_words[$];

    wr_words.push_back(32'h0000_0001);
    wr_words.push_back(32'h0000_0002);
    driver_inst.send_write(csr_addr(16'h006), 2, wr_words);
    monitor_inst.wait_reply(captured_reply);
    if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd2 ||
        captured_reply.response != 2'b10 || captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: burst CSR write reply mismatch valid=%0b len=%0d rsp=%0b words=%0d",
             captured_reply.header_valid,
             captured_reply.echoed_length,
             captured_reply.response,
             captured_reply.payload_words);
    end
  endtask

  task automatic run_t060();
    logic [31:0] csr_word;

    read_csr_word(16'h000, csr_word);
    if (csr_word !== HUB_UID_CONST) begin
      $error("sc_hub_tb_top: AXI4 CSR UID mismatch exp=0x%08h act=0x%08h",
             HUB_UID_CONST, csr_word);
    end
  endtask

  task automatic run_t061();
    inject_rd_error = 1'b1;
    driver_inst.send_read(24'h000040, 1);
    monitor_inst.wait_reply(captured_reply);
    inject_rd_error = 1'b0;
    if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
        captured_reply.response != 2'b10 || captured_reply.payload_words != 1 ||
        captured_reply.payload[0] !== 32'hBBAD_BEEF) begin
      $error("sc_hub_tb_top: SLAVEERROR read reply mismatch valid=%0b len=%0d rsp=%0b words=%0d data=0x%08h",
             captured_reply.header_valid,
             captured_reply.echoed_length,
             captured_reply.response,
             captured_reply.payload_words,
             captured_reply.payload[0]);
    end
  endtask

  task automatic run_t062();
    inject_decode_error = 1'b1;
    driver_inst.send_read(24'h000044, 1);
    monitor_inst.wait_reply(captured_reply);
    inject_decode_error = 1'b0;
    if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
        captured_reply.response != 2'b11 || captured_reply.payload_words != 1 ||
        captured_reply.payload[0] !== 32'hDEAD_BEEF) begin
      $error("sc_hub_tb_top: DECODEERROR read reply mismatch valid=%0b len=%0d rsp=%0b words=%0d data=0x%08h",
             captured_reply.header_valid,
             captured_reply.echoed_length,
             captured_reply.response,
             captured_reply.payload_words,
             captured_reply.payload[0]);
    end
  endtask

  task automatic run_t063();
    logic [31:0] wr_words[$];

    wr_words.push_back(32'h6300_0001);
    inject_wr_error = 1'b1;
    driver_inst.send_write(24'h000048, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    inject_wr_error = 1'b0;
    if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
        captured_reply.response != 2'b10 || captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: SLAVEERROR write reply mismatch valid=%0b len=%0d rsp=%0b words=%0d",
             captured_reply.header_valid,
             captured_reply.echoed_length,
             captured_reply.response,
             captured_reply.payload_words);
    end
  endtask

  task automatic run_t064();
    logic [31:0] wr_words[$];

    wr_words.push_back(32'h6400_0001);
    inject_decode_error = 1'b1;
    driver_inst.send_write(24'h00004C, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    inject_decode_error = 1'b0;
    if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
        captured_reply.response != 2'b11 || captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: DECODEERROR write reply mismatch valid=%0b len=%0d rsp=%0b words=%0d",
             captured_reply.header_valid,
             captured_reply.echoed_length,
             captured_reply.response,
             captured_reply.payload_words);
    end
  endtask

  task automatic run_t065();
    logic [31:0] err_flags_word;
    sc_reply_t   timeout_reply;

    clear_hub_counters();
    trigger_avmm_read_timeout(24'h000080, 1, timeout_reply);
    if (!timeout_reply.header_valid || timeout_reply.echoed_length != 16'd1 ||
        timeout_reply.response != 2'b11 || timeout_reply.payload_words != 1 ||
        timeout_reply.payload[0] !== 32'hEEEE_EEEE) begin
      $error("sc_hub_tb_top: read timeout reply mismatch valid=%0b len=%0d rsp=%0b words=%0d data=0x%08h",
             timeout_reply.header_valid,
             timeout_reply.echoed_length,
             timeout_reply.response,
             timeout_reply.payload_words,
             timeout_reply.payload[0]);
    end

    read_csr_word(16'h004, err_flags_word);
    if (err_flags_word[3] !== 1'b1) begin
      $error("sc_hub_tb_top: ERR_FLAGS.rd_timeout mismatch exp=1 act=%0b",
             err_flags_word[3]);
    end
  endtask

  task automatic run_t066();
    sc_reply_t timeout_reply;

    clear_hub_counters();
    trigger_avmm_read_timeout(24'h000084, 1, timeout_reply);

    driver_inst.send_read(24'h000088, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000088, 1);
  endtask

  task automatic run_t067();
    sc_reply_t timeout_reply;

    trigger_avmm_read_timeout(24'h00008C, 1, timeout_reply);
    if (timeout_reply.response !== 2'b11) begin
      $error("sc_hub_tb_top: no-flush check expected timeout response act=%0b",
             timeout_reply.response);
    end
  endtask

  task automatic run_t068();
    sc_reply_t partial_reply;

    clear_hub_counters();
    fork
      begin : force_timeout_after_four_beats
        int unsigned beat_count;
        beat_count = 0;
        forever begin
          @(posedge clk);
`ifdef SC_HUB_BUS_AXI4
          if (axi_rvalid == 1'b1 && axi_rready == 1'b1) begin
            beat_count++;
            if (beat_count >= 4) begin
              force axi4_bfm_inst.rvalid = 1'b0;
              force axi4_bfm_inst.rlast  = 1'b0;
              disable force_timeout_after_four_beats;
            end
          end
`else
          if (avm_readdatavalid == 1'b1) begin
            beat_count++;
            if (beat_count >= 4) begin
              force avm_readdatavalid = 1'b0;
              disable force_timeout_after_four_beats;
            end
          end
`endif
        end
      end
      begin
        driver_inst.send_read(24'h000090, 8);
        monitor_inst.wait_reply(partial_reply);
      end
    join
`ifdef SC_HUB_BUS_AXI4
    release axi4_bfm_inst.rvalid;
    release axi4_bfm_inst.rlast;
`else
    release avm_readdatavalid;
`endif

    if (!partial_reply.header_valid || partial_reply.echoed_length != 16'd8 ||
        partial_reply.response != 2'b11 || partial_reply.payload_words != 8) begin
      $error("sc_hub_tb_top: partial-timeout reply header mismatch valid=%0b len=%0d rsp=%0b words=%0d",
             partial_reply.header_valid,
             partial_reply.echoed_length,
             partial_reply.response,
             partial_reply.payload_words);
    end

    for (int unsigned idx = 0; idx < 4; idx++) begin
      if (partial_reply.payload[idx] !== expected_bus_word(24'h000090, idx)) begin
        $error("sc_hub_tb_top: partial-timeout payload[%0d] mismatch exp=0x%08h act=0x%08h",
               idx,
               expected_bus_word(24'h000090, idx),
               partial_reply.payload[idx]);
      end
    end

    for (int unsigned idx = 4; idx < 8; idx++) begin
      if (partial_reply.payload[idx] !== 32'hEEEE_EEEE) begin
        $error("sc_hub_tb_top: partial-timeout pad[%0d] mismatch exp=0xEEEEEEEE act=0x%08h",
               idx,
               partial_reply.payload[idx]);
      end
    end
  endtask

  task automatic run_t069();
    inject_decode_error = 1'b1;
    for (int unsigned idx = 0; idx < 64; idx++) begin
      driver_inst.send_read(24'h008000 + idx, 1);
      monitor_inst.wait_reply(captured_reply);
      if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
          captured_reply.response != 2'b11 || captured_reply.payload_words != 1 ||
          captured_reply.payload[0] !== 32'hDEAD_BEEF) begin
        $error("sc_hub_tb_top: unmapped read reply mismatch idx=%0d rsp=%0b data=0x%08h",
               idx,
               captured_reply.response,
               captured_reply.payload[0]);
      end
    end
    inject_decode_error = 1'b0;
  endtask

  task automatic run_t070();
    logic [31:0] wr_words[$];

    inject_decode_error = 1'b1;
    for (int unsigned idx = 0; idx < 64; idx++) begin
      wr_words.delete();
      wr_words.push_back(32'h7000_0000 + idx);
      driver_inst.send_write(24'h009000 + idx, 1, wr_words);
      monitor_inst.wait_reply(captured_reply);
      if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
          captured_reply.response != 2'b11 || captured_reply.payload_words != 0) begin
        $error("sc_hub_tb_top: unmapped write reply mismatch idx=%0d rsp=%0b words=%0d",
               idx,
               captured_reply.response,
               captured_reply.payload_words);
      end
    end
    inject_decode_error = 1'b0;
  endtask

`ifdef SC_HUB_BUS_AXI4
  task automatic expect_axi4_read_summary(
    input int unsigned expected_beats,
    input logic [7:0]  expected_arlen
  );
    if (axi_ar_count != 1) begin
      $error("sc_hub_tb_top: AXI4 AR handshake count mismatch exp=1 act=%0d", axi_ar_count);
    end
    if (axi_r_count != expected_beats) begin
      $error("sc_hub_tb_top: AXI4 R handshake count mismatch exp=%0d act=%0d",
             expected_beats, axi_r_count);
    end
    if (axi_rlast_count != 1) begin
      $error("sc_hub_tb_top: AXI4 RLAST count mismatch exp=1 act=%0d", axi_rlast_count);
    end
    if (axi_last_arlen !== expected_arlen) begin
      $error("sc_hub_tb_top: AXI4 ARLEN mismatch exp=%0d act=%0d",
             expected_arlen, axi_last_arlen);
    end
    if (axi_last_arsize !== 3'b010) begin
      $error("sc_hub_tb_top: AXI4 ARSIZE mismatch exp=2 act=%0d", axi_last_arsize);
    end
    if (axi_last_arburst !== 2'b01) begin
      $error("sc_hub_tb_top: AXI4 ARBURST mismatch exp=1 act=%0d", axi_last_arburst);
    end
    if (axi_last_arid !== 4'h0 || axi_last_rid !== 4'h0) begin
      $error("sc_hub_tb_top: AXI4 read ID mismatch ARID=0x%0h RID=0x%0h",
             axi_last_arid, axi_last_rid);
    end
  endtask

  task automatic expect_axi4_write_summary(
    input int unsigned expected_beats,
    input logic [7:0]  expected_awlen
  );
    if (axi_aw_count != 1) begin
      $error("sc_hub_tb_top: AXI4 AW handshake count mismatch exp=1 act=%0d", axi_aw_count);
    end
    if (axi_w_count != expected_beats) begin
      $error("sc_hub_tb_top: AXI4 W handshake count mismatch exp=%0d act=%0d",
             expected_beats, axi_w_count);
    end
    if (axi_b_count != 1) begin
      $error("sc_hub_tb_top: AXI4 B handshake count mismatch exp=1 act=%0d", axi_b_count);
    end
    if (axi_wlast_count != 1) begin
      $error("sc_hub_tb_top: AXI4 WLAST count mismatch exp=1 act=%0d", axi_wlast_count);
    end
    if (axi_last_awlen !== expected_awlen) begin
      $error("sc_hub_tb_top: AXI4 AWLEN mismatch exp=%0d act=%0d",
             expected_awlen, axi_last_awlen);
    end
    if (axi_last_awsize !== 3'b010) begin
      $error("sc_hub_tb_top: AXI4 AWSIZE mismatch exp=2 act=%0d", axi_last_awsize);
    end
    if (axi_last_awburst !== 2'b01) begin
      $error("sc_hub_tb_top: AXI4 AWBURST mismatch exp=1 act=%0d", axi_last_awburst);
    end
    if (axi_last_awid !== 4'h0 || axi_last_bid !== 4'h0) begin
      $error("sc_hub_tb_top: AXI4 write ID mismatch AWID=0x%0h BID=0x%0h",
             axi_last_awid, axi_last_bid);
    end
    if (axi_last_wstrb !== 4'hF) begin
      $error("sc_hub_tb_top: AXI4 WSTRB mismatch exp=0xF act=0x%0h", axi_last_wstrb);
    end
    if (axi_w_before_aw_violation) begin
      $error("sc_hub_tb_top: AXI4 W handshake occurred before AW handshake");
    end
  endtask

  task automatic run_t013();
    driver_inst.send_read(24'h000000, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000000, 1);
    expect_axi4_read_summary(1, 8'd0);
  endtask

  task automatic run_t014();
    logic [31:0] wr_words[$];

    wr_words.push_back(32'h0000_1234);
    driver_inst.send_write(24'h000000, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000000, 1);
    expect_axi4_write_summary(1, 8'd0);
    check_bfm_words(24'h000000, wr_words);
  endtask

  task automatic run_t015();
    driver_inst.send_read(24'h000000, 8);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000000, 8);
    expect_axi4_read_summary(8, 8'd7);
  endtask

  task automatic run_t016();
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, 8, 32'hA800_0000);
    driver_inst.send_write(24'h000000, 8, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000000, 8);
    expect_axi4_write_summary(8, 8'd7);
    check_bfm_words(24'h000000, wr_words);
  endtask

  task automatic run_t017();
    driver_inst.send_read(24'h000000, 256);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000000, 256);
    expect_axi4_read_summary(256, 8'hFF);
  endtask

  task automatic run_t018();
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, 256, 32'hB900_0000);
    driver_inst.send_write(24'h000000, 256, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000000, 256);
    expect_axi4_write_summary(256, 8'hFF);
    check_bfm_words(24'h000000, wr_words);
  endtask

  task automatic run_t019();
    logic [31:0] wr_words[$];

    wr_words.push_back(32'h0000_5678);
    driver_inst.send_read(24'h000010, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000010, 1);

    driver_inst.send_write(24'h000020, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000020, 1);

    if (axi_last_arsize !== 3'b010 || axi_last_awsize !== 3'b010) begin
      $error("sc_hub_tb_top: AXI4 size mismatch ARSIZE=%0d AWSIZE=%0d",
             axi_last_arsize, axi_last_awsize);
    end
  endtask

  task automatic run_t020();
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, 8, 32'hBB00_0000);
    driver_inst.send_read(24'h000010, 8);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000010, 8);

    driver_inst.send_write(24'h000020, 8, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000020, 8);

    if (axi_last_arburst !== 2'b01 || axi_last_awburst !== 2'b01) begin
      $error("sc_hub_tb_top: AXI4 burst mismatch ARBURST=%0d AWBURST=%0d",
             axi_last_arburst, axi_last_awburst);
    end
  endtask

  task automatic run_t021();
    logic [31:0] wr_words[$];

    wr_words.push_back(32'h0000_789A);
    driver_inst.send_read(24'h000010, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000010, 1);

    driver_inst.send_write(24'h000020, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000020, 1);

    if (axi_last_awid !== 4'h0 || axi_last_arid !== 4'h0 ||
        axi_last_bid !== 4'h0 || axi_last_rid !== 4'h0) begin
      $error("sc_hub_tb_top: AXI4 ID mismatch AWID=0x%0h ARID=0x%0h BID=0x%0h RID=0x%0h",
             axi_last_awid, axi_last_arid, axi_last_bid, axi_last_rid);
    end
  endtask

  task automatic run_t022();
    logic [31:0] wr_words[$];

    wr_words.push_back(32'h0000_89AB);
    driver_inst.send_write(24'h000020, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000020, 1);
    if (axi_last_wstrb !== 4'hF) begin
      $error("sc_hub_tb_top: AXI4 WSTRB mismatch exp=0xF act=0x%0h", axi_last_wstrb);
    end
  endtask

  task automatic run_t023();
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, 8, 32'hCA00_0000);
    driver_inst.send_write(24'h000100, 8, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000100, 8);
    if (axi_w_before_aw_violation) begin
      $error("sc_hub_tb_top: AXI4 W handshake occurred before AW handshake");
    end
  endtask

  task automatic run_t024();
    driver_inst.send_read(24'h00FE80, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_ok(captured_reply, 24'h00FE80, 1);
  endtask

  task automatic run_t026();
    logic [31:0] wr_words[$];
    sc_cmd_t     cmd;

    fill_write_words(wr_words, 16, 32'hCE00_0000);
    cmd = make_cmd(SC_WRITE, 24'h000000, 16);

    driver_inst.drive_word(make_preamble_word(cmd), 4'b0001);
    if (axi_aw_count != 0 || axi_w_count != 0) begin
      $error("sc_hub_tb_top: AXI4 activity observed during write preamble");
    end

    driver_inst.drive_word(make_addr_word(cmd), 4'b0000);
    if (axi_aw_count != 0 || axi_w_count != 0) begin
      $error("sc_hub_tb_top: AXI4 activity observed during write address");
    end

    driver_inst.drive_word(make_length_word(cmd), 4'b0000);
    if (axi_aw_count != 0 || axi_w_count != 0) begin
      $error("sc_hub_tb_top: AXI4 activity observed during write length");
    end

    for (int unsigned idx = 0; idx < wr_words.size(); idx++) begin
      driver_inst.drive_word(wr_words[idx], 4'b0000);
      if (axi_aw_count != 0 || axi_w_count != 0) begin
        $error("sc_hub_tb_top: AXI4 activity observed before trailer at beat %0d", idx);
      end
    end

    driver_inst.drive_word({24'h0, K284_CONST}, 4'b0001);
    driver_inst.drive_idle();

    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000000, 16);
    check_bfm_words(24'h000000, wr_words);
  endtask

  task automatic run_t040();
    logic [31:0] words[$];
    logic [3:0]  dataks[$];
    logic [31:0] pkt_drop_count;

    words.push_back(32'h1F00_02BC);
    dataks.push_back(4'b0001);
    words.push_back(32'h0000_0000);
    dataks.push_back(4'b0000);
    words.push_back(32'h0000_0004);
    dataks.push_back(4'b0000);
    words.push_back(32'h4000_0000);
    dataks.push_back(4'b0000);
    words.push_back(32'h4000_0001);
    dataks.push_back(4'b0000);

    driver_inst.send_raw(words, dataks);

    repeat (48) begin
      @(posedge clk);
      if (axi_aw_count != 0 || axi_w_count != 0 || axi_ar_count != 0) begin
        $error("sc_hub_tb_top: AXI4 activity observed after malformed write drop");
      end
    end

    monitor_inst.assert_no_reply(400ns);
    read_pkt_drop_count(pkt_drop_count);
    if (pkt_drop_count !== 32'd1) begin
      $error("sc_hub_tb_top: PKT_DROP_CNT mismatch after AXI4 malformed drop exp=1 act=%0d",
             pkt_drop_count);
    end
  endtask

  task automatic run_t071();
    force axi_rresp = 2'b10;
    driver_inst.send_read(24'h000040, 1);
    monitor_inst.wait_reply(captured_reply);
    release axi_rresp;
    if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
        captured_reply.response != 2'b10 || captured_reply.payload_words != 1) begin
      $error("sc_hub_tb_top: AXI4 SLVERR read reply mismatch valid=%0b len=%0d rsp=%0b words=%0d",
             captured_reply.header_valid,
             captured_reply.echoed_length,
             captured_reply.response,
             captured_reply.payload_words);
    end
  endtask

  task automatic run_t072();
    force axi_rresp = 2'b11;
    driver_inst.send_read(24'h000044, 1);
    monitor_inst.wait_reply(captured_reply);
    release axi_rresp;
    if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
        captured_reply.response != 2'b11 || captured_reply.payload_words != 1 ||
        captured_reply.payload[0] !== 32'hDEAD_BEEF) begin
      $error("sc_hub_tb_top: AXI4 DECERR read reply mismatch valid=%0b len=%0d rsp=%0b words=%0d data=0x%08h",
             captured_reply.header_valid,
             captured_reply.echoed_length,
             captured_reply.response,
             captured_reply.payload_words,
             captured_reply.payload[0]);
    end
  endtask

  task automatic run_t073();
    logic [31:0] wr_words[$];

    wr_words.push_back(32'h7300_0001);
    force axi_bresp = 2'b10;
    driver_inst.send_write(24'h000048, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    release axi_bresp;
    if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
        captured_reply.response != 2'b10 || captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: AXI4 SLVERR write reply mismatch valid=%0b len=%0d rsp=%0b words=%0d",
             captured_reply.header_valid,
             captured_reply.echoed_length,
             captured_reply.response,
             captured_reply.payload_words);
    end
  endtask

  task automatic run_t074();
    logic [31:0] wr_words[$];

    wr_words.push_back(32'h7400_0001);
    force axi_bresp = 2'b11;
    driver_inst.send_write(24'h00004C, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    release axi_bresp;
    if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
        captured_reply.response != 2'b11 || captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: AXI4 DECERR write reply mismatch valid=%0b len=%0d rsp=%0b words=%0d",
             captured_reply.header_valid,
             captured_reply.echoed_length,
             captured_reply.response,
             captured_reply.payload_words);
    end
  endtask

  task automatic run_t075();
    force axi_rvalid = 1'b0;
    driver_inst.send_read(24'h000050, 1);
    monitor_inst.wait_reply(captured_reply);
    release axi_rvalid;
    if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
        captured_reply.response != 2'b11 || captured_reply.payload_words != 1 ||
        captured_reply.payload[0] !== 32'hEEEE_EEEE) begin
      $error("sc_hub_tb_top: AXI4 read-timeout reply mismatch valid=%0b len=%0d rsp=%0b words=%0d data=0x%08h",
             captured_reply.header_valid,
             captured_reply.echoed_length,
             captured_reply.response,
             captured_reply.payload_words,
             captured_reply.payload[0]);
    end
  endtask

  task automatic run_t076();
    sc_reply_t partial_reply;

    fork
      begin : force_axi_partial_error
        int unsigned beat_count;
        beat_count = 0;
        forever begin
          @(posedge clk);
          if (axi_rvalid && axi_rready) begin
            beat_count++;
            if (beat_count >= 4) begin
              force axi_rresp = 2'b10;
              disable force_axi_partial_error;
            end
          end
        end
      end
      begin
        driver_inst.send_read(24'h000060, 8);
        monitor_inst.wait_reply(partial_reply);
      end
    join
    release axi_rresp;

    if (!partial_reply.header_valid || partial_reply.echoed_length != 16'd8 ||
        partial_reply.response != 2'b10 || partial_reply.payload_words != 8) begin
      $error("sc_hub_tb_top: AXI4 partial-error header mismatch valid=%0b len=%0d rsp=%0b words=%0d",
             partial_reply.header_valid,
             partial_reply.echoed_length,
             partial_reply.response,
             partial_reply.payload_words);
    end

    for (int unsigned idx = 0; idx < 4; idx++) begin
      if (partial_reply.payload[idx] !== expected_bus_word(24'h000060, idx)) begin
        $error("sc_hub_tb_top: AXI4 partial-error payload[%0d] mismatch exp=0x%08h act=0x%08h",
               idx,
               expected_bus_word(24'h000060, idx),
               partial_reply.payload[idx]);
      end
    end

    for (int unsigned idx = 4; idx < 8; idx++) begin
      if (partial_reply.payload[idx] !== 32'hBBAD_BEEF) begin
        $error("sc_hub_tb_top: AXI4 partial-error pad[%0d] mismatch exp=0xBBADBEEF act=0x%08h",
               idx,
               partial_reply.payload[idx]);
      end
    end
  endtask

  task automatic run_t084();
    fork
      begin
        force axi4_bfm_inst.arready = 1'b0;
        wait (axi_arvalid === 1'b1);
        wait_clks(50);
        release axi4_bfm_inst.arready;
      end
      begin
        driver_inst.send_read(24'h000700, 4);
        monitor_inst.wait_reply(captured_reply);
      end
    join

    expect_read_reply(captured_reply, 24'h000700, 4);
    if (axi_ar_count != 1) begin
      $error("sc_hub_tb_top: AXI4 ARREADY stall caused AR handshake count mismatch exp=1 act=%0d",
             axi_ar_count);
    end
  endtask

  task automatic run_t085();
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, 16, 32'h8500_0000);

    fork
      begin : toggle_wready_t085
        wait (axi_wvalid === 1'b1);
        forever begin
          force axi4_bfm_inst.wready = 1'b1;
          wait_clks(1);
          force axi4_bfm_inst.wready = 1'b0;
          wait_clks(1);
        end
      end
      begin
        driver_inst.send_write(24'h000720, 16, wr_words);
        monitor_inst.wait_reply(captured_reply);
        disable toggle_wready_t085;
      end
    join
    release axi4_bfm_inst.wready;

    expect_write_reply(captured_reply, 24'h000720, 16);
    check_bfm_words(24'h000720, wr_words);
    if (axi_wlast_count != 1 || axi_w_count != 16) begin
      $error("sc_hub_tb_top: AXI4 WREADY toggling corrupted beat count W=%0d WLAST=%0d",
             axi_w_count, axi_wlast_count);
    end
  endtask

  task automatic run_t086();
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, 4, 32'h8600_0000);

    fork
      begin
        wait (axi_awvalid === 1'b1);
        force axi4_bfm_inst.awready = 1'b0;
        wait_clks(30);
        release axi4_bfm_inst.awready;
      end
      begin
        driver_inst.send_write(24'h000740, 4, wr_words);
        monitor_inst.wait_reply(captured_reply);
      end
    join

    expect_write_reply(captured_reply, 24'h000740, 4);
    check_bfm_words(24'h000740, wr_words);
    if (axi_aw_count != 1) begin
      $error("sc_hub_tb_top: AXI4 AWREADY stall caused AW handshake count mismatch exp=1 act=%0d",
             axi_aw_count);
    end
  endtask

  task automatic run_t210();
    sc_reply_t replies[0:15];
    int pos_b;
    int pos_c;

    reset_axi4_rd_latencies(1);
    write_ooo_ctrl(1'b1);
    set_axi4_rd_latency(24'h001000, 2);
    set_axi4_rd_latency(24'h001010, 50);
    set_axi4_rd_latency(24'h001020, 2);
    set_axi4_rd_latency(24'h001030, 50);

    driver_inst.send_read(24'h001000, 4);
    driver_inst.send_read(24'h001010, 4);
    driver_inst.send_read(24'h001020, 4);
    driver_inst.send_read(24'h001030, 4);
    collect_replies(4, replies);

    pos_b = -1;
    pos_c = -1;
    for (int unsigned idx = 0; idx < 4; idx++) begin
      case (replies[idx].start_address)
        24'h001000: expect_read_reply(replies[idx], 24'h001000, 4);
        24'h001010: begin
          expect_read_reply(replies[idx], 24'h001010, 4);
          pos_b = idx;
        end
        24'h001020: begin
          expect_read_reply(replies[idx], 24'h001020, 4);
          pos_c = idx;
        end
        24'h001030: expect_read_reply(replies[idx], 24'h001030, 4);
        default: $error("sc_hub_tb_top: unexpected reply address in T210 addr=0x%06h",
                        replies[idx].start_address);
      endcase
    end

    if (pos_b < 0 || pos_c < 0 || pos_c > pos_b) begin
      $error("sc_hub_tb_top: T210 expected fast read C to retire before slow read B (posC=%0d posB=%0d)",
             pos_c, pos_b);
    end
  endtask

  task automatic run_t211();
    sc_reply_t replies[0:15];
    bit seen[0:7];

    reset_axi4_rd_latencies(1);
    write_ooo_ctrl(1'b1);
    for (int unsigned idx = 0; idx < 8; idx++) begin
      set_axi4_rd_latency(24'h001100 + idx * 16, (idx % 2) ? 40 : 2);
      driver_inst.send_read(24'h001100 + idx * 16, 1);
      seen[idx] = 1'b0;
    end
    collect_replies(8, replies);

    for (int unsigned idx = 0; idx < 8; idx++) begin
      int match_idx;
      match_idx = -1;
      for (int unsigned exp_idx = 0; exp_idx < 8; exp_idx++) begin
        if (replies[idx].start_address == (24'h001100 + exp_idx * 16)) begin
          match_idx = exp_idx;
        end
      end
      if (match_idx < 0) begin
        $error("sc_hub_tb_top: T211 unexpected reply address addr=0x%06h", replies[idx].start_address);
      end else begin
        if (seen[match_idx]) begin
          $error("sc_hub_tb_top: T211 duplicate reply for addr=0x%06h", replies[idx].start_address);
        end
        seen[match_idx] = 1'b1;
        expect_read_reply(replies[idx], 24'h001100 + match_idx * 16, 1);
      end
    end

    for (int unsigned idx = 0; idx < 8; idx++) begin
      if (!seen[idx]) begin
        $error("sc_hub_tb_top: T211 missing reply for addr=0x%06h", 24'h001100 + idx * 16);
      end
    end
  endtask

  task automatic run_t212();
    sc_reply_t replies[0:15];
    bit seen_read[0:7];
    bit seen_write[0:3];
    logic [31:0] wr_words[$];

    reset_axi4_rd_latencies(1);
    write_ooo_ctrl(1'b1);
    for (int unsigned idx = 0; idx < 8; idx++) begin
      set_axi4_rd_latency(24'h001200 + idx * 16, (idx % 2) ? 35 : 2);
      driver_inst.send_read(24'h001200 + idx * 16, 1);
      seen_read[idx] = 1'b0;
    end

    for (int unsigned idx = 0; idx < 4; idx++) begin
      wr_words.delete();
      wr_words.push_back(32'hD212_0000 + idx);
      driver_inst.send_write(24'h001280 + idx * 4, 1, wr_words);
      seen_write[idx] = 1'b0;
    end

    collect_replies(12, replies);

    for (int unsigned idx = 0; idx < 12; idx++) begin
      if (replies[idx].start_address >= 24'h001200 && replies[idx].start_address < 24'h001280) begin
        int read_idx;
        read_idx = (replies[idx].start_address - 24'h001200) / 16;
        if (seen_read[read_idx]) begin
          $error("sc_hub_tb_top: T212 duplicate read reply addr=0x%06h", replies[idx].start_address);
        end
        seen_read[read_idx] = 1'b1;
        expect_read_reply(replies[idx], 24'h001200 + read_idx * 16, 1);
      end else if (replies[idx].start_address >= 24'h001280 && replies[idx].start_address < 24'h001290) begin
        int write_idx;
        write_idx = (replies[idx].start_address - 24'h001280) / 4;
        if (seen_write[write_idx]) begin
          $error("sc_hub_tb_top: T212 duplicate write reply addr=0x%06h", replies[idx].start_address);
        end
        seen_write[write_idx] = 1'b1;
        expect_write_reply(replies[idx], 24'h001280 + write_idx * 4, 1);
        if (axi4_bfm_inst.mem[(24'h001280 + write_idx * 4) & 18'h3FFFF] !== 32'hD212_0000 + write_idx) begin
          $error("sc_hub_tb_top: T212 write payload mismatch addr=0x%06h", 24'h001280 + write_idx * 4);
        end
      end else begin
        $error("sc_hub_tb_top: T212 unexpected reply address addr=0x%06h", replies[idx].start_address);
      end
    end

    for (int unsigned idx = 0; idx < 8; idx++) begin
      if (!seen_read[idx]) begin
        $error("sc_hub_tb_top: T212 missing read reply addr=0x%06h", 24'h001200 + idx * 16);
      end
    end
    for (int unsigned idx = 0; idx < 4; idx++) begin
      if (!seen_write[idx]) begin
        $error("sc_hub_tb_top: T212 missing write reply addr=0x%06h", 24'h001280 + idx * 4);
      end
    end
  endtask

  task automatic run_t213();
    sc_reply_t replies[0:15];

    reset_axi4_rd_latencies(1);
    write_ooo_ctrl(1'b1);
    set_axi4_rd_latency(24'h001300, 50);
    set_axi4_rd_latency(24'h001340, 2);
    set_axi4_rd_latency(24'h001380, 35);
    set_axi4_rd_latency(24'h0013C0, 2);

    driver_inst.send_read(24'h001300, 32);
    driver_inst.send_read(24'h001340, 16);
    driver_inst.send_read(24'h001380, 8);
    driver_inst.send_read(24'h0013C0, 4);
    collect_replies(4, replies);

    for (int unsigned idx = 0; idx < 4; idx++) begin
      case (replies[idx].start_address)
        24'h001300: expect_read_reply(replies[idx], 24'h001300, 32);
        24'h001340: expect_read_reply(replies[idx], 24'h001340, 16);
        24'h001380: expect_read_reply(replies[idx], 24'h001380, 8);
        24'h0013C0: expect_read_reply(replies[idx], 24'h0013C0, 4);
        default: $error("sc_hub_tb_top: T213 unexpected reply address addr=0x%06h",
                        replies[idx].start_address);
      endcase
    end
  endtask

  task automatic run_t214();
    sc_reply_t replies[0:15];
    bit saw_id[0:3];

    // The live RTL uses slot-based reply storage rather than the planned
    // linked-list payload pools. This check validates slot reclamation at quiesce.
    reset_axi4_rd_latencies(1);
    write_ooo_ctrl(1'b1);
    for (int unsigned idx = 0; idx < 12; idx++) begin
      set_axi4_rd_latency(24'h001400 + idx * 8, (idx % 3 == 0) ? 25 : 2);
      driver_inst.send_read(24'h001400 + idx * 8, 1);
    end
    collect_replies(12, replies);

    axi_arid_log.delete();
    axi_araddr_log.delete();
    axi_rid_log.delete();
    for (int unsigned idx = 0; idx < 4; idx++) begin
      saw_id[idx] = 1'b0;
      driver_inst.send_read(24'h001500 + idx * 8, 1);
    end
    collect_replies(4, replies);
    for (int unsigned idx = 0; idx < 4; idx++) begin
      expect_read_reply(replies[idx], 24'h001500 + idx * 8, 1);
    end
    for (int unsigned idx = 0; idx < axi_arid_log.size(); idx++) begin
      if (axi_arid_log[idx] < 4) begin
        saw_id[axi_arid_log[idx]] = 1'b1;
      end
    end
    for (int unsigned idx = 0; idx < 4; idx++) begin
      if (!saw_id[idx]) begin
        $error("sc_hub_tb_top: T214 expected slot/ARID %0d to be reusable after quiesce", idx);
      end
    end
  endtask

  task automatic run_t215();
    sc_reply_t replies[0:15];
    int phase1_pos_b;
    int phase1_pos_c;

    reset_axi4_rd_latencies(1);
    write_ooo_ctrl(1'b1);
    set_axi4_rd_latency(24'h001600, 2);
    set_axi4_rd_latency(24'h001610, 50);
    set_axi4_rd_latency(24'h001620, 2);
    set_axi4_rd_latency(24'h001630, 50);
    driver_inst.send_read(24'h001600, 1);
    driver_inst.send_read(24'h001610, 1);
    driver_inst.send_read(24'h001620, 1);
    driver_inst.send_read(24'h001630, 1);
    collect_replies(4, replies);

    phase1_pos_b = -1;
    phase1_pos_c = -1;
    for (int unsigned idx = 0; idx < 4; idx++) begin
      if (replies[idx].start_address == 24'h001610) phase1_pos_b = idx;
      if (replies[idx].start_address == 24'h001620) phase1_pos_c = idx;
    end
    if (phase1_pos_b < 0 || phase1_pos_c < 0 || phase1_pos_c > phase1_pos_b) begin
      $error("sc_hub_tb_top: T215 phase1 did not exhibit OoO ordering (C=%0d B=%0d)",
             phase1_pos_c, phase1_pos_b);
    end

    write_ooo_ctrl(1'b0);
    set_axi4_rd_latency(24'h001680, 2);
    set_axi4_rd_latency(24'h001690, 50);
    set_axi4_rd_latency(24'h0016A0, 2);
    set_axi4_rd_latency(24'h0016B0, 50);
    axi_arid_log.delete();
    axi_araddr_log.delete();
    axi_rid_log.delete();
    driver_inst.send_read(24'h001680, 1);
    driver_inst.send_read(24'h001690, 1);
    driver_inst.send_read(24'h0016A0, 1);
    driver_inst.send_read(24'h0016B0, 1);
    collect_replies(4, replies);

    if (replies[0].start_address !== 24'h001680 ||
        replies[1].start_address !== 24'h001690 ||
        replies[2].start_address !== 24'h0016A0 ||
        replies[3].start_address !== 24'h0016B0) begin
      $error("sc_hub_tb_top: T215 phase2 expected strict in-order replies after OOO disable");
    end
    for (int unsigned idx = 0; idx < 4; idx++) begin
      expect_read_reply(replies[idx], 24'h001680 + idx * 16, 1);
    end
  endtask

  task automatic run_t216();
    sc_reply_t replies[0:15];
    int first_ext_pos;

    reset_axi4_rd_latencies(1);
    write_ooo_ctrl(1'b1);
    for (int unsigned idx = 0; idx < 4; idx++) begin
      set_axi4_rd_latency(24'h001700 + idx * 16, 50);
      driver_inst.send_read(24'h001700 + idx * 16, 1);
    end
    driver_inst.send_read(csr_addr(16'h000), 1);
    driver_inst.send_read(csr_addr(16'h001), 1);
    driver_inst.send_read(csr_addr(16'h002), 1);
    driver_inst.send_read(csr_addr(16'h006), 1);
    collect_replies(8, replies);

    first_ext_pos = 8;
    for (int unsigned idx = 0; idx < 8; idx++) begin
      if (replies[idx].start_address >= 24'h001700 && replies[idx].start_address < 24'h001740) begin
        if (idx < first_ext_pos) begin
          first_ext_pos = idx;
        end
        expect_read_reply(replies[idx], replies[idx].start_address, 1);
      end else begin
        case (replies[idx].start_address)
          24'h00FE80: expect_single_word_reply(replies[idx], 24'h00FE80, HUB_UID_CONST);
          24'h00FE81: expect_single_word_reply(replies[idx], 24'h00FE81, HUB_VERSION_CONST);
          24'h00FE82: expect_single_word_reply(replies[idx], 24'h00FE82, 32'h0000_0001);
          24'h00FE86: expect_single_word_reply(replies[idx], 24'h00FE86, 32'h0000_0000);
          default: $error("sc_hub_tb_top: T216 unexpected internal reply addr=0x%06h",
                          replies[idx].start_address);
        endcase
      end
    end

    if (first_ext_pos < 4) begin
      $error("sc_hub_tb_top: T216 expected all 4 internal CSR replies before any slow external reply (first_ext_pos=%0d)",
             first_ext_pos);
    end
  endtask

  task automatic run_t217();
    sc_reply_t replies[0:15];
    bit saw_id[0:3];
    bit saw_rid_reorder;

    axi_arid_log.delete();
    axi_araddr_log.delete();
    axi_rid_log.delete();
    reset_axi4_rd_latencies(1);
    write_ooo_ctrl(1'b1);
    set_axi4_rd_latency(24'h001800, 2);
    set_axi4_rd_latency(24'h001810, 50);
    set_axi4_rd_latency(24'h001820, 2);
    set_axi4_rd_latency(24'h001830, 50);

    driver_inst.send_read(24'h001800, 1);
    driver_inst.send_read(24'h001810, 1);
    driver_inst.send_read(24'h001820, 1);
    driver_inst.send_read(24'h001830, 1);
    collect_replies(4, replies);

    for (int unsigned idx = 0; idx < 4; idx++) begin
      saw_id[idx] = 1'b0;
      expect_read_reply(replies[idx], replies[idx].start_address, 1);
    end
    for (int unsigned idx = 0; idx < axi_arid_log.size(); idx++) begin
      if (axi_arid_log[idx] < 4) begin
        saw_id[axi_arid_log[idx]] = 1'b1;
      end
    end
    for (int unsigned idx = 0; idx < 4; idx++) begin
      if (!saw_id[idx]) begin
        $error("sc_hub_tb_top: T217 expected ARID %0d to be used for concurrent reads", idx);
      end
    end

    saw_rid_reorder = 1'b0;
    if (axi_rid_log.size() >= 4 && axi_arid_log.size() >= 4) begin
      for (int unsigned idx = 0; idx < 4; idx++) begin
        if (axi_rid_log[idx] !== axi_arid_log[idx]) begin
          saw_rid_reorder = 1'b1;
        end
      end
    end
    if (!saw_rid_reorder) begin
      $error("sc_hub_tb_top: T217 expected RID completion order to differ from ARID issue order");
    end
  endtask

  task automatic run_t219();
    sc_reply_t replies[0:15];

    reset_axi4_rd_latencies(1);
    write_ooo_ctrl(1'b1);
    set_axi4_rd_latency(24'h001900, 50);
    set_axi4_rd_latency(24'h001910, 2);
    driver_inst.send_read(24'h001900, 1);
    driver_inst.send_read(24'h001910, 1);
    collect_replies(2, replies);

    if (replies[0].start_address !== 24'h001910) begin
      $error("sc_hub_tb_top: T219 expected fast read reply to retire first");
    end
    expect_read_reply(replies[0], replies[0].start_address, 1);
    expect_read_reply(replies[1], replies[1].start_address, 1);
  endtask

  task automatic run_t226();
    logic [31:0] original_word;
    logic [31:0] expected_word;
    int unsigned aw_count_before;
    int unsigned ar_count_before;

    original_word   = 32'h2260_0055;
    expected_word   = (original_word & ~32'h0000_00FF) | 32'h0000_00AB;
    aw_count_before = axi_aw_count;
    ar_count_before = axi_ar_count;
    axi4_bfm_inst.mem[16'h0226] = original_word;
    reset_axi4_rd_latencies(1);
    set_axi4_wr_latency(1);

    driver_inst.send_atomic_rmw(24'h000226, 32'h0000_00FF, 32'h0000_00AB,
                                SC_ORDER_RELAXED, 4'h0, 8'h00);
    monitor_inst.wait_reply(captured_reply);
    expect_atomic_ok_reply(captured_reply, 24'h000226, original_word,
                           SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00);

    if (axi4_bfm_inst.mem[16'h0226] !== expected_word) begin
      $error("sc_hub_tb_top: T226 AXI4 atomic post-write mismatch exp=0x%08h act=0x%08h",
             expected_word,
             axi4_bfm_inst.mem[16'h0226]);
    end
    if (axi_ar_count !== ar_count_before + 1) begin
      $error("sc_hub_tb_top: T226 expected exactly one AXI4 AR issue for atomic read phase");
    end
    if (axi_aw_count !== aw_count_before + 1) begin
      $error("sc_hub_tb_top: T226 expected exactly one AXI4 AW issue for atomic write phase");
    end
    if (axi_last_arlock !== 1'b1) begin
      $error("sc_hub_tb_top: T226 expected ARLOCK=1 during AXI4 atomic read phase");
    end
    if (axi_last_awlock !== 1'b1) begin
      $error("sc_hub_tb_top: T226 expected AWLOCK=1 during AXI4 atomic write phase");
    end
  endtask

  task automatic run_t430();
    sc_reply_t replies[0:15];
    sc_reply_t read_replies[0:3];
    logic [23:0] expected_inflight_order[0:3];
    int unsigned read_reply_count;
    int unsigned csr_reply_idx;
    int unsigned read_idx;

    reset_axi4_rd_latencies(1);
    write_ooo_ctrl(1'b1);
    set_axi4_rd_latency(24'h001A00, 50);
    set_axi4_rd_latency(24'h001A10, 2);
    set_axi4_rd_latency(24'h001A20, 20);
    set_axi4_rd_latency(24'h001A30, 35);

    driver_inst.send_read(24'h001A00, 1);
    driver_inst.send_read(24'h001A10, 1);
    driver_inst.send_read(24'h001A20, 1);
    driver_inst.send_read(24'h001A30, 1);
    write_ooo_ctrl_with_replies(1'b0, 5, replies, csr_reply_idx, read_reply_count);

    if (read_reply_count !== 4) begin
      $error("sc_hub_tb_top: T430 expected 4 in-flight read replies during OOO disable");
    end

    read_idx = 0;
    for (int unsigned idx = 0; idx < 5; idx++) begin
      if (idx == csr_reply_idx) begin
        continue;
      end
      if (read_idx >= 4) begin
        $error("sc_hub_tb_top: T430 saw extra in-flight reply index=%0d addr=0x%06h",
               idx, replies[idx].start_address);
      end else begin
        read_replies[read_idx] = replies[idx];
        read_idx++;
      end
    end

    expected_inflight_order[0] = 24'h001A10;
    expected_inflight_order[1] = 24'h001A20;
    expected_inflight_order[2] = 24'h001A30;
    expected_inflight_order[3] = 24'h001A00;
    for (int unsigned idx = 0; idx < 4; idx++) begin
      if (read_replies[idx].start_address !== expected_inflight_order[idx]) begin
        $error("sc_hub_tb_top: T430 expected in-flight replies to drain in natural order after runtime OoO disable");
      end
      expect_read_reply(read_replies[idx], read_replies[idx].start_address, 1);
    end

    set_axi4_rd_latency(24'h001A40, 50);
    set_axi4_rd_latency(24'h001A50, 2);
    set_axi4_rd_latency(24'h001A60, 20);
    set_axi4_rd_latency(24'h001A70, 35);
    driver_inst.send_read(24'h001A40, 1);
    driver_inst.send_read(24'h001A50, 1);
    driver_inst.send_read(24'h001A60, 1);
    driver_inst.send_read(24'h001A70, 1);

    collect_replies(4, replies);
    if (replies[0].start_address !== 24'h001A40 ||
        replies[1].start_address !== 24'h001A50 ||
        replies[2].start_address !== 24'h001A60 ||
        replies[3].start_address !== 24'h001A70) begin
      $error("sc_hub_tb_top: T430 expected new post-toggle transactions to complete strict in-order");
    end
    for (int unsigned idx = 0; idx < 4; idx++) begin
      expect_read_reply(replies[idx], 24'h001A40 + (idx * 16), 1);
    end
  endtask

  task automatic run_t431();
    sc_reply_t replies[0:15];
    sc_reply_t read_replies[0:1];
    logic [23:0] expected_final_inflight_order[0:1];
    int unsigned read_reply_count;
    int unsigned csr_reply_idx;
    int unsigned read_idx;

    reset_axi4_rd_latencies(1);
    write_ooo_ctrl(1'b1);
    set_axi4_rd_latency(24'h001A00, 50);
    set_axi4_rd_latency(24'h001A10, 2);
    driver_inst.send_read(24'h001A00, 1);
    driver_inst.send_read(24'h001A10, 1);
    write_ooo_ctrl_with_replies(1'b0, 3, replies, csr_reply_idx, read_reply_count);
    if (read_reply_count !== 2) begin
      $error("sc_hub_tb_top: T431 expected 2 in-flight read replies during phase1 toggle");
    end
    read_idx = 0;
    for (int unsigned idx = 0; idx < 3; idx++) begin
      if (idx == csr_reply_idx) begin
        continue;
      end
      if (read_idx >= 2) begin
        $error("sc_hub_tb_top: T431 saw extra in-flight reply index=%0d addr=0x%06h",
               idx, replies[idx].start_address);
      end else begin
        read_replies[read_idx] = replies[idx];
        read_idx++;
      end
    end
    if (read_replies[0].start_address !== 24'h001A10 || read_replies[1].start_address !== 24'h001A00) begin
      $error("sc_hub_tb_top: T431 expected OoO phase1 fast reply first");
    end
    expect_read_reply(read_replies[0], read_replies[0].start_address, 1);
    expect_read_reply(read_replies[1], read_replies[1].start_address, 1);

    write_ooo_ctrl(1'b0);
    set_axi4_rd_latency(24'h001A20, 50);
    set_axi4_rd_latency(24'h001A30, 2);
    driver_inst.send_read(24'h001A20, 1);
    driver_inst.send_read(24'h001A30, 1);
    collect_replies(2, replies);
    if (replies[0].start_address !== 24'h001A20 || replies[1].start_address !== 24'h001A30) begin
      $error("sc_hub_tb_top: T431 expected in-order replies while OOO is off");
    end
    expect_read_reply(replies[0], replies[0].start_address, 1);
    expect_read_reply(replies[1], replies[1].start_address, 1);

    write_ooo_ctrl(1'b1);
    set_axi4_rd_latency(24'h001A40, 50);
    set_axi4_rd_latency(24'h001A50, 2);
    driver_inst.send_read(24'h001A40, 1);
    driver_inst.send_read(24'h001A50, 1);
    collect_replies(2, replies);
    if (replies[0].start_address !== 24'h001A50 || replies[1].start_address !== 24'h001A40) begin
      $error("sc_hub_tb_top: T431 expected OoO phase3 fast reply first");
    end
    expect_read_reply(replies[0], replies[0].start_address, 1);
    expect_read_reply(replies[1], replies[1].start_address, 1);

    set_axi4_rd_latency(24'h001A60, 50);
    set_axi4_rd_latency(24'h001A70, 2);
    driver_inst.send_read(24'h001A60, 1);
    driver_inst.send_read(24'h001A70, 1);
    write_ooo_ctrl_with_replies(1'b0, 3, replies, csr_reply_idx, read_reply_count);
    if (read_reply_count !== 2) begin
      $error("sc_hub_tb_top: T431 expected 2 in-flight read replies during final toggle");
    end
    read_idx = 0;
    for (int unsigned idx = 0; idx < 3; idx++) begin
      if (idx == csr_reply_idx) begin
        continue;
      end
      if (read_idx >= 2) begin
        $error("sc_hub_tb_top: T431 saw extra in-flight reply index=%0d addr=0x%06h",
               idx, replies[idx].start_address);
      end else begin
        read_replies[read_idx] = replies[idx];
        read_idx++;
      end
    end
    expected_final_inflight_order[0] = 24'h001A70;
    expected_final_inflight_order[1] = 24'h001A60;
    for (int unsigned idx = 0; idx < 2; idx++) begin
      if (read_replies[idx].start_address !== expected_final_inflight_order[idx]) begin
        $error("sc_hub_tb_top: T431 expected in-flight replies to drain in natural order after final OOO disable");
      end
      expect_read_reply(read_replies[idx], read_replies[idx].start_address, 1);
    end
  endtask

  task automatic run_t504();
    clear_hub_counters();
    inject_rresp_err = 1'b1;
    driver_inst.send_read(24'h000504, 1);
    monitor_inst.wait_reply(captured_reply);
    inject_rresp_err = 1'b0;
    if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
        captured_reply.response != 2'b10 || captured_reply.payload_words != 1 ||
        captured_reply.payload[0] !== 32'hBBAD_BEEF) begin
      $error("sc_hub_tb_top: T504 AXI4 SLVERR read reply mismatch rsp=%0b words=%0d data=0x%08h",
             captured_reply.response,
             captured_reply.payload_words,
             captured_reply.payload[0]);
    end
    expect_err_flag_and_count(HUB_ERR_SLVERR_BIT, 32'h0000_0001, "T504");
  endtask

  task automatic run_t505();
    clear_hub_counters();
    inject_decode_error = 1'b1;
    driver_inst.send_read(24'h000505, 1);
    monitor_inst.wait_reply(captured_reply);
    inject_decode_error = 1'b0;
    if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
        captured_reply.response != 2'b11 || captured_reply.payload_words != 1 ||
        captured_reply.payload[0] !== 32'hDEAD_BEEF) begin
      $error("sc_hub_tb_top: T505 AXI4 DECERR read reply mismatch rsp=%0b words=%0d data=0x%08h",
             captured_reply.response,
             captured_reply.payload_words,
             captured_reply.payload[0]);
    end
    expect_err_flag_and_count(HUB_ERR_DECERR_BIT, 32'h0000_0001, "T505");
  endtask

  task automatic run_t506();
    logic [31:0] wr_words[$];

    clear_hub_counters();
    wr_words.push_back(32'h5060_0001);
    inject_bresp_err = 1'b1;
    driver_inst.send_write(24'h000506, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    inject_bresp_err = 1'b0;
    if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
        captured_reply.response != 2'b10 || captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T506 AXI4 SLVERR write reply mismatch rsp=%0b words=%0d",
             captured_reply.response,
             captured_reply.payload_words);
    end
    expect_err_flag_and_count(HUB_ERR_SLVERR_BIT, 32'h0000_0001, "T506");
  endtask

  task automatic run_t507();
    logic [31:0] wr_words[$];

    clear_hub_counters();
    wr_words.push_back(32'h5070_0001);
    inject_decode_error = 1'b1;
    driver_inst.send_write(24'h000507, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    inject_decode_error = 1'b0;
    if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
        captured_reply.response != 2'b11 || captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T507 AXI4 DECERR write reply mismatch rsp=%0b words=%0d",
             captured_reply.response,
             captured_reply.payload_words);
    end
    expect_err_flag_and_count(HUB_ERR_DECERR_BIT, 32'h0000_0001, "T507");
  endtask

  task automatic run_t508();
    sc_reply_t partial_reply;

    clear_hub_counters();
    fork
      begin : t508_force_tail_slverr
        int unsigned beat_count;
        beat_count = 0;
        forever begin
          @(posedge clk);
          if (axi_rvalid == 1'b1 && axi_rready == 1'b1) begin
            beat_count++;
            if (beat_count >= 4) begin
              force axi_rresp = 2'b10;
              if (axi_rlast == 1'b1) begin
                disable t508_force_tail_slverr;
              end
            end
          end
        end
      end
      begin
        driver_inst.send_read(24'h000508, 8);
        monitor_inst.wait_reply(partial_reply);
      end
    join
    release axi_rresp;

    if (!partial_reply.header_valid || partial_reply.echoed_length != 16'd8 ||
        partial_reply.response != 2'b10 || partial_reply.payload_words != 8) begin
      $error("sc_hub_tb_top: T508 reply header mismatch rsp=%0b words=%0d",
             partial_reply.response,
             partial_reply.payload_words);
    end
    for (int unsigned idx = 0; idx < 4; idx++) begin
      if (partial_reply.payload[idx] !== expected_bus_word(24'h000508, idx)) begin
        $error("sc_hub_tb_top: T508 expected valid word[%0d] exp=0x%08h act=0x%08h",
               idx,
               expected_bus_word(24'h000508, idx),
               partial_reply.payload[idx]);
      end
    end
    for (int unsigned idx = 4; idx < 8; idx++) begin
      if (partial_reply.payload[idx] !== 32'hBBAD_BEEF) begin
        $error("sc_hub_tb_top: T508 expected error-fill word[%0d]=0xBBADBEEF act=0x%08h",
               idx,
               partial_reply.payload[idx]);
      end
    end
    expect_err_flag_and_count(HUB_ERR_SLVERR_BIT, 32'h0000_0001, "T508");
  endtask

  task automatic require_axi4_ooo_disabled(input string test_name);
    if (AXI4_DUT_OOO_ENABLE) begin
      $error("sc_hub_tb_top: %s requires SC_HUB_TB_AXI4_OOO_DISABLED and OOO_ENABLE=false",
             test_name);
    end
  endtask

  task automatic require_axi4_ord_disabled(input string test_name);
    if (AXI4_DUT_ORD_ENABLE) begin
      $error("sc_hub_tb_top: %s requires SC_HUB_TB_AXI4_ORD_DISABLED and ORD_ENABLE=false",
             test_name);
    end
  endtask

  task automatic require_axi4_atomic_disabled(input string test_name);
    if (AXI4_DUT_ATOMIC_ENABLE) begin
      $error("sc_hub_tb_top: %s requires SC_HUB_TB_AXI4_ATOMIC_DISABLED and ATOMIC_ENABLE=false",
             test_name);
    end
  endtask

  task automatic run_t532();
    logic [31:0] csr_word;
    sc_reply_t   replies[0:15];

    require_axi4_ooo_disabled("T532");
    write_csr_word(16'h018, 32'h0000_0001);
    read_csr_word(16'h018, csr_word);
    if (csr_word !== 32'h0000_0000) begin
      $error("sc_hub_tb_top: T532 expected OOO_CTRL readback=0 when OOO_ENABLE=false, act=0x%08h",
             csr_word);
    end

    reset_axi4_rd_latencies(1);
    set_axi4_rd_latency(24'h001AD0, 50);
    set_axi4_rd_latency(24'h001AE0, 2);
    driver_inst.send_read(24'h001AD0, 1);
    driver_inst.send_read(24'h001AE0, 1);
    collect_replies(2, replies);
    if (replies[0].start_address !== 24'h001AD0 || replies[1].start_address !== 24'h001AE0) begin
      $error("sc_hub_tb_top: T532 expected in-order replies after ignored OOO enable write");
    end
    expect_read_reply(replies[0], 24'h001AD0, 1);
    expect_read_reply(replies[1], 24'h001AE0, 1);
  endtask

  task automatic run_t533();
    sc_reply_t replies[0:15];

    require_axi4_ooo_disabled("T533");
    reset_axi4_rd_latencies(1);
    set_axi4_rd_latency(24'h001B00, 50);
    set_axi4_rd_latency(24'h001B10, 2);
    set_axi4_rd_latency(24'h001B20, 30);
    set_axi4_rd_latency(24'h001B30, 5);

    axi_arid_log.delete();
    axi_araddr_log.delete();
    axi_rid_log.delete();

    driver_inst.send_read(24'h001B00, 1);
    driver_inst.send_read(24'h001B10, 1);
    driver_inst.send_read(24'h001B20, 1);
    driver_inst.send_read(24'h001B30, 1);
    collect_replies(4, replies);

    for (int unsigned idx = 0; idx < 4; idx++) begin
      expect_read_reply(replies[idx], 24'h001B00 + (idx * 16), 1);
      if (axi_arid_log[idx] !== 4'h0) begin
        $error("sc_hub_tb_top: T533 expected AXI4 ARID to stay at 0 when OOO_ENABLE=false (got 0x%0h at idx=%0d)",
               axi_arid_log[idx], idx);
      end
      if (axi_rid_log[idx] !== 4'h0) begin
        $error("sc_hub_tb_top: T533 expected AXI4 RID to stay at 0 when OOO_ENABLE=false (got 0x%0h at idx=%0d)",
               axi_rid_log[idx], idx);
      end
    end

    if (axi_arid_log.size() !== 4) begin
      $error("sc_hub_tb_top: T533 expected exactly 4 ARID captures with OOO disabled, act=%0d", axi_arid_log.size());
    end
    if (axi_rid_log.size() !== 4) begin
      $error("sc_hub_tb_top: T533 expected exactly 4 RID captures with OOO disabled, act=%0d", axi_rid_log.size());
    end
  endtask

  task automatic run_t534();
    sc_reply_t replies[0:3];
    longint unsigned reply_cycle[0:3];
    longint unsigned total_span;

    require_axi4_ooo_disabled("T534");
    reset_axi4_rd_latencies(1);
    axi_arid_log.delete();
    axi_araddr_log.delete();
    axi_rid_log.delete();

    set_axi4_rd_latency(24'h001C00, 10);
    set_axi4_rd_latency(24'h001C10, 50);
    set_axi4_rd_latency(24'h001C20, 10);
    set_axi4_rd_latency(24'h001C30, 50);

    driver_inst.send_read(24'h001C00, 1);
    driver_inst.send_read(24'h001C10, 1);
    driver_inst.send_read(24'h001C20, 1);
    driver_inst.send_read(24'h001C30, 1);

    for (int unsigned idx = 0; idx < 4; idx++) begin
      monitor_inst.wait_reply(replies[idx]);
      reply_cycle[idx] = cycle_counter;
      if (idx > 0 && reply_cycle[idx] <= reply_cycle[idx - 1]) begin
        $error("sc_hub_tb_top: T534 observed non-monotonic reply times at idx=%0d", idx);
      end
      expect_read_reply(replies[idx], 24'h001C00 + (idx * 16), 1);
    end

    if (axi_arid_log.size() !== 4) begin
      $error("sc_hub_tb_top: T534 expected 4 ARID captures, act=%0d", axi_arid_log.size());
    end
    if (axi_rid_log.size() !== 4) begin
      $error("sc_hub_tb_top: T534 expected 4 RID captures, act=%0d", axi_rid_log.size());
    end

    total_span = reply_cycle[3] - reply_cycle[0];
    if (total_span < 100) begin
      $error("sc_hub_tb_top: T534 expected serialized high-latency drain with OOO disabled (span=%0d cy)",
             total_span);
    end
  endtask

  task automatic run_t535();
    logic [31:0] wr_words[$];
    logic [31:0] hub_cap_word;
    logic [31:0] original_word;

    require_axi4_ord_disabled("T535");
    read_csr_word(16'h01F, hub_cap_word);
    if (hub_cap_word[1] !== 1'b0) begin
      $error("sc_hub_tb_top: T535 expected HUB_CAP.ORD bit to be 0 when ORD_ENABLE=false, act=0x%08h",
             hub_cap_word);
    end

    original_word = axi4_bfm_inst.mem[16'h0350];
    wr_words.push_back(32'h5350_0001);
    driver_inst.send_ordered_write(24'h000350, 1, wr_words,
                                   SC_ORDER_RELEASE, 4'h1, 8'h01);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h000350, 0, 2'b10);
    expect_reply_metadata(captured_reply, SC_ORDER_RELEASE, 4'h1, 8'h01, 2'b00, 1'b0);
    if (captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T535 expected SLVERR write reply without payload");
    end
    if (axi4_bfm_inst.mem[16'h0350] !== original_word) begin
      $error("sc_hub_tb_top: T535 unsupported RELEASE write should not update AXI4 memory act=0x%08h",
             axi4_bfm_inst.mem[16'h0350]);
    end
  endtask

  task automatic run_t536();
    logic [31:0] hub_cap_word;

    require_axi4_ord_disabled("T536");
    read_csr_word(16'h01F, hub_cap_word);
    if (hub_cap_word[1] !== 1'b0) begin
      $error("sc_hub_tb_top: T536 expected HUB_CAP.ORD bit to be 0 when ORD_ENABLE=false, act=0x%08h",
             hub_cap_word);
    end

    driver_inst.send_ordered_read(24'h000360, 1, SC_ORDER_ACQUIRE, 4'h1, 8'h02);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h000360, 0, 2'b10);
    expect_reply_metadata(captured_reply, SC_ORDER_ACQUIRE, 4'h1, 8'h02, 2'b00, 1'b0);
    if (captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T536 expected SLVERR acquire reply without payload");
    end
  endtask

  task automatic run_t537();
    logic [31:0] wr_words[$];
    logic [31:0] hub_cap_word;

    require_axi4_ord_disabled("T537");
    read_csr_word(16'h01F, hub_cap_word);
    if (hub_cap_word[1] !== 1'b0) begin
      $error("sc_hub_tb_top: T537 expected HUB_CAP.ORD bit to be 0 when ORD_ENABLE=false, act=0x%08h",
             hub_cap_word);
    end

    wr_words.push_back(32'h5370_0001);
    driver_inst.send_write(24'h000370, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000370, 1);
    driver_inst.send_read(24'h000370, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_ok(captured_reply, 24'h000370, 1);
    if (captured_reply.payload_words != 1) begin
      $error("sc_hub_tb_top: T537 expected one AXI4 readback word, act=%0d",
             captured_reply.payload_words);
    end
    if (captured_reply.payload[0] !== wr_words[0]) begin
      $error("sc_hub_tb_top: T537 relaxed AXI4 traffic mismatch exp=0x%08h act=0x%08h",
             wr_words[0],
             captured_reply.payload[0]);
    end
  endtask

  task automatic run_t538();
    logic [31:0] hub_cap_word;
    logic [31:0] original_word;

    require_axi4_atomic_disabled("T538");
    read_csr_word(16'h01F, hub_cap_word);
    if (hub_cap_word[2] !== 1'b0) begin
      $error("sc_hub_tb_top: T538 expected HUB_CAP.ATOMIC bit to be 0 when ATOMIC_ENABLE=false, act=0x%08h",
             hub_cap_word);
    end

    original_word = axi4_bfm_inst.mem[16'h0380];
    driver_inst.send_atomic_rmw(24'h000380, 32'h0000_FFFF, 32'h0000_00AA,
                                SC_ORDER_RELAXED, 4'h0, 8'h00);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h000380, 0, 2'b10);
    expect_reply_metadata(captured_reply, SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00, 1'b1);
    if (captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T538 expected unsupported AXI4 atomic reply without payload");
    end
    if (axi4_bfm_inst.mem[16'h0380] !== original_word) begin
      $error("sc_hub_tb_top: T538 unsupported AXI4 atomic should not modify memory exp=0x%08h act=0x%08h",
             original_word,
             axi4_bfm_inst.mem[16'h0380]);
    end
  endtask

  task automatic run_t539();
    logic [31:0] wr_words[$];
    logic [31:0] hub_cap_word;

    require_axi4_atomic_disabled("T539");
    read_csr_word(16'h01F, hub_cap_word);
    if (hub_cap_word[2] !== 1'b0) begin
      $error("sc_hub_tb_top: T539 expected HUB_CAP.ATOMIC bit to be 0 when ATOMIC_ENABLE=false, act=0x%08h",
             hub_cap_word);
    end

    wr_words.push_back(32'h5390_0001);
    driver_inst.send_write(24'h000390, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000390, 1);
    driver_inst.send_read(24'h000390, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_ok(captured_reply, 24'h000390, 1);
    if (captured_reply.payload_words != 1) begin
      $error("sc_hub_tb_top: T539 expected one AXI4 readback word, act=%0d",
             captured_reply.payload_words);
    end
    if (captured_reply.payload[0] !== wr_words[0]) begin
      $error("sc_hub_tb_top: T539 non-atomic AXI4 traffic mismatch exp=0x%08h act=0x%08h",
             wr_words[0],
             captured_reply.payload[0]);
    end
  endtask

  task automatic run_t545();
    run_t060();
    driver_inst.send_read(24'h000545, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000545, 1);
  endtask

  task automatic run_t089();
    logic [31:0] csr_word;
    sc_cmd_t     cmd;

    clear_hub_counters();
    set_local_feb_type(FEB_TYPE_SCIFI);
    cmd = make_cmd(SC_READ, 24'h001200, 1);
    cmd.mask_s = 1'b1;
    send_cmd(cmd);
    monitor_inst.assert_no_reply(400ns);
    read_csr_word(16'h00F, csr_word);
    if (csr_word !== 32'd0) begin
      $error("sc_hub_tb_top: local SciFi mute should ignore read exp EXT_PKT_RD=0 act=%0d",
             csr_word);
    end
  endtask

  task automatic run_t090();
    logic [31:0] csr_word;
    sc_cmd_t     cmd;

    clear_hub_counters();
    set_local_feb_type(FEB_TYPE_SCIFI);
    cmd = make_cmd(SC_WRITE, 24'h001220, 1);
    cmd.mask_r        = 1'b1;
    cmd.data_words[0] = 32'h9000_0001;
    send_cmd(cmd);
    wait (axi_bvalid === 1'b1);
    wait_clks(2);
    monitor_inst.assert_no_reply(400ns);
    if (axi4_bfm_inst.mem[18'h01220] !== 32'h9000_0001) begin
      $error("sc_hub_tb_top: muted write did not update downstream AXI4 memory");
    end
    read_csr_word(16'h010, csr_word);
    if (csr_word !== 32'd1) begin
      $error("sc_hub_tb_top: muted mask_r write did not increment EXT_PKT_WR count exp=1 act=%0d",
             csr_word);
    end
  endtask

  task automatic run_t091();
    logic [31:0] csr_word;
    sc_cmd_t     cmd;

    clear_hub_counters();
    set_local_feb_type(FEB_TYPE_SCIFI);
    cmd = make_cmd(SC_READ, 24'h001240, 1);
    cmd.mask_m = 1'b1;
    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_nonincrementing_read_reply(captured_reply, 24'h001240, 1);
    read_csr_word(16'h00F, csr_word);
    if (csr_word !== 32'd1) begin
      $error("sc_hub_tb_top: non-local M mask should still execute read exp EXT_PKT_RD=1 act=%0d",
             csr_word);
    end
  endtask

  task automatic run_t092();
    logic [31:0] csr_word;
    sc_cmd_t     cmd;

    clear_hub_counters();
    set_local_feb_type(FEB_TYPE_SCIFI);
    cmd = make_cmd(SC_READ, 24'h001260, 1);
    cmd.mask_t = 1'b1;
    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_nonincrementing_read_reply(captured_reply, 24'h001260, 1);
    read_csr_word(16'h00F, csr_word);
    if (csr_word !== 32'd1) begin
      $error("sc_hub_tb_top: non-local T mask should still execute read exp EXT_PKT_RD=1 act=%0d",
             csr_word);
    end
  endtask

  task automatic run_t093();
    sc_cmd_t cmd;

    set_local_feb_type(FEB_TYPE_SCIFI);
    cmd = make_cmd(SC_READ, 24'h001280, 1);
    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_nonincrementing_read_reply(captured_reply, 24'h001280, 1);
  endtask

  task automatic run_t094();
    logic [31:0] csr_word;
    sc_cmd_t     cmd;

    clear_hub_counters();
    set_local_feb_type(FEB_TYPE_SCIFI);

    cmd = make_cmd(SC_READ, 24'h0012A0, 1);
    cmd.mask_s = 1'b1;
    send_cmd(cmd);
    monitor_inst.assert_no_reply(400ns);

    cmd.mask_s = 1'b0;
    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_nonincrementing_read_reply(captured_reply, 24'h0012A0, 1);
    monitor_inst.assert_no_reply(400ns);

    read_csr_word(16'h00F, csr_word);
    if (csr_word !== 32'd1) begin
      $error("sc_hub_tb_top: local mute should suppress execution, only unmuted read should count exp=1 act=%0d",
             csr_word);
    end
  endtask

  task automatic run_t129();
    sc_cmd_t cmd;

    cmd = make_cmd(SC_READ_NONINCREMENTING, 24'h0013C0, 4);
    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_nonincrementing_read_reply(captured_reply, 24'h0013C0, 4);
    if (captured_reply.sc_type !== SC_READ_NONINCREMENTING) begin
      $error("sc_hub_tb_top: nonincrementing read reply sc_type mismatch exp=%0d act=%0d",
             SC_READ_NONINCREMENTING, captured_reply.sc_type);
    end
  endtask

  task automatic run_t130();
    logic [31:0] wr_words[$];
    logic [31:0] next_addr_before;
    sc_cmd_t     cmd;

    next_addr_before = axi4_bfm_inst.mem[18'h013E1];
    fill_write_words(wr_words, 4, 32'hA110_0000);
    cmd = make_cmd(SC_WRITE_NONINCREMENTING, 24'h0013E0, 4);
    foreach (cmd.data_words[idx]) begin
      if (idx < wr_words.size()) begin
        cmd.data_words[idx] = wr_words[idx];
      end
    end

    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h0013E0, 4);
    if (axi4_bfm_inst.mem[18'h013E0] !== wr_words[wr_words.size() - 1]) begin
      $error("sc_hub_tb_top: nonincrementing write did not leave last word at fixed address exp=0x%08h act=0x%08h",
             wr_words[wr_words.size() - 1], axi4_bfm_inst.mem[18'h013E0]);
    end
    if (axi4_bfm_inst.mem[18'h013E1] !== next_addr_before) begin
      $error("sc_hub_tb_top: nonincrementing write incorrectly touched next address exp=0x%08h act=0x%08h",
             next_addr_before, axi4_bfm_inst.mem[18'h013E1]);
    end
  endtask
`endif

`ifndef SC_HUB_BUS_AXI4
  task automatic run_t432();
    logic [31:0] csr_word;

    write_csr_word(16'h018, 32'h0000_0001);
    read_csr_word(16'h018, csr_word);
    if (csr_word !== 32'h0000_0000) begin
      $error("sc_hub_tb_top: T432 expected OOO_CTRL readback=0 when OOO is compile-time disabled, act=0x%08h",
             csr_word);
    end
  endtask

  task automatic run_t077();
    uplink_ready = 1'b0;
    driver_inst.send_read(24'h0000A0, 8);
    wait_clks(80);
    if (uplink_valid !== 1'b1) begin
      $error("sc_hub_tb_top: uplink_valid did not assert while upload was stalled");
    end
    uplink_ready = 1'b1;
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h0000A0, 8);
  endtask

  task automatic run_t078();
    fork
      begin : toggle_upload_ready_t078
        forever begin
          uplink_ready = 1'b0;
          wait_clks(2);
          uplink_ready = 1'b1;
          wait_clks(2);
        end
      end
      begin
        driver_inst.send_read(24'h000100, 64);
        monitor_inst.wait_reply(captured_reply);
        disable toggle_upload_ready_t078;
      end
    join
    uplink_ready = 1'b1;
    expect_read_reply(captured_reply, 24'h000100, 64);
  endtask

  task automatic run_t079();
    bit saw_half_full;

    uplink_ready = 1'b0;
    driver_inst.send_read(24'h000200, 256);
    saw_half_full = 1'b0;
    repeat (1200) begin
      @(posedge clk);
      if (dut_inst.bp_half_full === 1'b1) begin
        saw_half_full = 1'b1;
        break;
      end
    end
    if (!saw_half_full) begin
      $error("sc_hub_tb_top: BP FIFO never reached half-full during blocked 256-word read reply");
    end
    if (link_ready !== 1'b0) begin
      $error("sc_hub_tb_top: download_ready stayed high while a half-full-or-more upload reply was blocked");
    end
    uplink_ready = 1'b1;
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000200, 256);
    wait_clks(32);
    if (link_ready !== 1'b1) begin
      $error("sc_hub_tb_top: download_ready did not reassert after blocked reply drained");
    end
  endtask

  task automatic run_t080();
    sc_reply_t first_reply;
    sc_reply_t second_reply;

    uplink_ready = 1'b0;
    driver_inst.send_read(24'h000300, 256);
    wait_clks(400);

    uplink_ready = 1'b1;
    wait_clks(8);
    uplink_ready = 1'b0;

    driver_inst.send_read(24'h000400, 256);
    wait_clks(400);

`ifdef SC_HUB_BUS_AXI4
    if (dut_inst.pkt_tx_inst.bp_overflow_sticky !== 1'b0) begin
      $error("sc_hub_tb_top: BP FIFO overflowed while filling to capacity on AXI4");
    end
`else
    if (dut_inst.pkt_tx_inst.bp_overflow_sticky !== 1'b0) begin
      $error("sc_hub_tb_top: BP FIFO overflowed while filling to capacity on AVMM");
    end
`endif

    uplink_ready = 1'b1;
    monitor_inst.wait_reply(first_reply);
    expect_read_reply(first_reply, 24'h000300, 256);
    monitor_inst.wait_reply(second_reply);
    expect_read_reply(second_reply, 24'h000400, 256);
  endtask

  task automatic run_t081();
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, 8, 32'h8100_0000);

    fork
      begin
        wait (avm_write === 1'b1);
        force avmm_bfm_inst.avm_waitrequest = 1'b1;
        wait_clks(50);
        release avmm_bfm_inst.avm_waitrequest;
      end
      begin
        driver_inst.send_write(24'h000500, 8, wr_words);
        monitor_inst.wait_reply(captured_reply);
      end
    join

    expect_write_reply(captured_reply, 24'h000500, 8);
    check_bfm_words(24'h000500, wr_words);
  endtask

  task automatic run_t082();
    avmm_bfm_inst.rd_latency_cfg = 100;
    driver_inst.send_read(24'h000520, 4);
    monitor_inst.wait_reply(captured_reply);
    avmm_bfm_inst.rd_latency_cfg = 1;
    expect_read_reply(captured_reply, 24'h000520, 4);
  endtask

  task automatic run_t083();
    sc_reply_t reply_a;
    sc_reply_t reply_b;
    sc_reply_t reply_c;

    uplink_ready = 1'b0;
    driver_inst.send_read(24'h000600, 1);
    wait_clks(32);
    driver_inst.send_read(24'h000620, 16);
    wait_clks(64);
    driver_inst.send_read(24'h000660, 64);
    wait_clks(160);

    fork
      begin : slow_drain_t083
        forever begin
          uplink_ready = 1'b1;
          wait_clks(1);
          uplink_ready = 1'b0;
          wait_clks(2);
        end
      end
      begin
        monitor_inst.wait_reply(reply_a);
        monitor_inst.wait_reply(reply_b);
        monitor_inst.wait_reply(reply_c);
        disable slow_drain_t083;
      end
    join
    uplink_ready = 1'b1;

    expect_read_reply(reply_a, 24'h000600, 1);
    expect_read_reply(reply_b, 24'h000620, 16);
    expect_read_reply(reply_c, 24'h000660, 64);
  endtask

  task automatic run_t087();
    fork
      begin : toggle_upload_ready_t087
        int unsigned cycle_count;
        cycle_count = 0;
        forever begin
          @(posedge clk);
          cycle_count++;
          uplink_ready = (cycle_count % 7) < 2;
        end
      end
      begin
        for (int unsigned idx = 0; idx < 128; idx++) begin
          driver_inst.send_read(24'h001000 + idx, 1);
          monitor_inst.wait_reply(captured_reply);
          expect_read_reply(captured_reply, 24'h001000 + idx, 1);
        end
        disable toggle_upload_ready_t087;
      end
    join
    uplink_ready = 1'b1;
  endtask

  task automatic run_t088();
    logic [31:0] raw_words[$];
    logic [3:0]  raw_dataks[$];

    uplink_ready = 1'b0;
    driver_inst.send_read(24'h001100, 256);
    wait (link_ready === 1'b0);

    raw_words.push_back(32'h1F00_02BC);
    raw_dataks.push_back(4'b0001);
    raw_words.push_back(32'h0000_1104);
    raw_dataks.push_back(4'b0000);
    raw_words.push_back(32'h0000_0001);
    raw_dataks.push_back(4'b0000);
    raw_words.push_back(32'h0000_009C);
    raw_dataks.push_back(4'b0001);

    for (int unsigned idx = 0; idx < raw_words.size(); idx++) begin
      drive_word_ignore_ready(raw_words[idx], raw_dataks[idx]);
    end
    driver_inst.drive_idle();

    uplink_ready = 1'b1;
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h001100, 256);
    monitor_inst.assert_no_reply(400ns);

    driver_inst.send_read(24'h001104, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h001104, 1);
  endtask

  task automatic run_t089();
    logic [31:0] csr_word;
    sc_cmd_t     cmd;

    clear_hub_counters();
    set_local_feb_type(FEB_TYPE_SCIFI);
    cmd = make_cmd(SC_READ, 24'h001200, 1);
    cmd.mask_s = 1'b1;
    send_cmd(cmd);
    monitor_inst.assert_no_reply(400ns);
    read_csr_word(16'h00F, csr_word);
    if (csr_word !== 32'd0) begin
      $error("sc_hub_tb_top: local SciFi mute should ignore read exp EXT_PKT_RD=0 act=%0d",
             csr_word);
    end
  endtask

  task automatic run_t090();
    logic [31:0] csr_word;
    sc_cmd_t     cmd;

    clear_hub_counters();
    set_local_feb_type(FEB_TYPE_SCIFI);
    cmd = make_cmd(SC_WRITE, 24'h001220, 1);
    cmd.mask_r       = 1'b1;
    cmd.data_words[0] = 32'h9000_0001;
    send_cmd(cmd);
    wait (avm_writeresponsevalid === 1'b1);
    wait_clks(2);
    monitor_inst.assert_no_reply(400ns);
    if (avmm_bfm_inst.mem[16'h1220] !== 32'h9000_0001) begin
      $error("sc_hub_tb_top: muted write did not update downstream AVMM memory");
    end
    read_csr_word(16'h010, csr_word);
    if (csr_word !== 32'd1) begin
      $error("sc_hub_tb_top: muted mask_r write did not increment EXT_PKT_WR count exp=1 act=%0d",
             csr_word);
    end
  endtask

  task automatic run_t091();
    logic [31:0] csr_word;
    sc_cmd_t     cmd;

    clear_hub_counters();
    set_local_feb_type(FEB_TYPE_SCIFI);
    cmd = make_cmd(SC_READ, 24'h001240, 1);
    cmd.mask_m = 1'b1;
    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_nonincrementing_read_reply(captured_reply, 24'h001240, 1);
    read_csr_word(16'h00F, csr_word);
    if (csr_word !== 32'd1) begin
      $error("sc_hub_tb_top: non-local M mask should still execute read exp EXT_PKT_RD=1 act=%0d",
             csr_word);
    end
  endtask

  task automatic run_t092();
    logic [31:0] csr_word;
    sc_cmd_t     cmd;

    clear_hub_counters();
    set_local_feb_type(FEB_TYPE_SCIFI);
    cmd = make_cmd(SC_READ, 24'h001260, 1);
    cmd.mask_t = 1'b1;
    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_nonincrementing_read_reply(captured_reply, 24'h001260, 1);
    read_csr_word(16'h00F, csr_word);
    if (csr_word !== 32'd1) begin
      $error("sc_hub_tb_top: non-local T mask should still execute read exp EXT_PKT_RD=1 act=%0d",
             csr_word);
    end
  endtask

  task automatic run_t093();
    sc_cmd_t cmd;

    set_local_feb_type(FEB_TYPE_SCIFI);
    cmd = make_cmd(SC_READ, 24'h001280, 1);
    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_nonincrementing_read_reply(captured_reply, 24'h001280, 1);
  endtask

  task automatic run_t094();
    logic [31:0] csr_word;
    sc_cmd_t     cmd;

    clear_hub_counters();
    set_local_feb_type(FEB_TYPE_SCIFI);

    cmd = make_cmd(SC_READ, 24'h0012A0, 1);
    cmd.mask_s = 1'b1;
    send_cmd(cmd);
    monitor_inst.assert_no_reply(400ns);

    cmd.mask_s = 1'b0;
    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_nonincrementing_read_reply(captured_reply, 24'h0012A0, 1);
    monitor_inst.assert_no_reply(400ns);

    read_csr_word(16'h00F, csr_word);
    if (csr_word !== 32'd1) begin
      $error("sc_hub_tb_top: local mute should suppress execution, only unmuted read should count exp=1 act=%0d", csr_word);
    end
  endtask

  task automatic run_t095();
    sc_cmd_t cmd;

    cmd = make_cmd(SC_READ, 24'h001300, 4);
    driver_inst.drive_word(make_preamble_word(cmd), 4'b0001);
    driver_inst.drive_word({24'h0, K285_CONST}, 4'b0001);
    driver_inst.drive_word(make_addr_word(cmd), 4'b0000);
    driver_inst.drive_word({24'h0, K285_CONST}, 4'b0001);
    driver_inst.drive_word(make_length_word(cmd), 4'b0000);
    driver_inst.drive_word({24'h0, K285_CONST}, 4'b0001);
    driver_inst.drive_word({24'h0, K284_CONST}, 4'b0001);
    driver_inst.drive_idle();

    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h001300, 4);
  endtask

  task automatic run_t096();
    logic [31:0] wr_words[$];
    sc_cmd_t     cmd;

    fill_write_words(wr_words, 4, 32'h9600_0000);
    cmd = make_cmd(SC_WRITE, 24'h001320, 4);

    driver_inst.drive_word(make_preamble_word(cmd), 4'b0001);
    driver_inst.drive_word(make_addr_word(cmd), 4'b0000);
    driver_inst.drive_word(make_length_word(cmd), 4'b0000);
    for (int unsigned idx = 0; idx < wr_words.size(); idx++) begin
      driver_inst.drive_word(wr_words[idx], 4'b0000);
      if (idx + 1 < wr_words.size()) begin
        driver_inst.drive_word({24'h0, K285_CONST}, 4'b0001);
      end
    end
    driver_inst.drive_word({24'h0, K284_CONST}, 4'b0001);
    driver_inst.drive_idle();

    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h001320, 4);
    check_bfm_words(24'h001320, wr_words);
  endtask

  task automatic run_t097();
    sc_cmd_t cmd;

    cmd = make_cmd(SC_BURST_READ, 24'h001340, 8);
    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h001340, 8);
    if (captured_reply.sc_type !== SC_BURST_READ) begin
      $error("sc_hub_tb_top: burst-read reply sc_type mismatch exp=%0d act=%0d",
             SC_BURST_READ, captured_reply.sc_type);
    end
  endtask

  task automatic run_t098();
    logic [31:0] wr_words[$];
    sc_cmd_t     cmd;

    fill_write_words(wr_words, 8, 32'h9800_0000);
    cmd = make_cmd(SC_BURST_WRITE, 24'h001360, 8);
    foreach (cmd.data_words[idx]) begin
      if (idx < wr_words.size()) begin
        cmd.data_words[idx] = wr_words[idx];
      end
    end

    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h001360, 8);
    check_bfm_words(24'h001360, wr_words);
    if (captured_reply.sc_type !== SC_BURST_WRITE) begin
      $error("sc_hub_tb_top: burst-write reply sc_type mismatch exp=%0d act=%0d",
             SC_BURST_WRITE, captured_reply.sc_type);
    end
  endtask

  task automatic run_t099();
    sc_cmd_t cmd;

    cmd = make_cmd(SC_READ, 24'h001380, 1);
    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h001380, 1);
    if (captured_reply.sc_type !== SC_READ) begin
      $error("sc_hub_tb_top: single-read reply sc_type mismatch exp=%0d act=%0d",
             SC_READ, captured_reply.sc_type);
    end
  endtask

  task automatic run_t100();
    logic [31:0] wr_words[$];
    sc_cmd_t     cmd;

    wr_words.push_back(32'hA000_0001);
    cmd = make_cmd(SC_WRITE, 24'h0013A0, 1);
    cmd.data_words[0] = wr_words[0];

    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h0013A0, 1);
    check_bfm_words(24'h0013A0, wr_words);
    if (captured_reply.sc_type !== SC_WRITE) begin
      $error("sc_hub_tb_top: single-write reply sc_type mismatch exp=%0d act=%0d",
             SC_WRITE, captured_reply.sc_type);
    end
  endtask

  task automatic run_t101();
    logic [31:0] expected_word;

`ifdef SC_HUB_BUS_AXI4
    expected_word = axi4_bfm_inst.mem[18'h31234];
`else
    expected_word = avmm_bfm_inst.mem[18'h31234];
`endif

    driver_inst.send_read(24'hFF1234, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_ok(captured_reply, 24'hFF1234, 1);
    if (captured_reply.payload_words != 1 || captured_reply.payload[0] !== expected_word) begin
      $error("sc_hub_tb_top: high address bits were not ignored exp=0x%08h act_words=%0d act=0x%08h",
             expected_word,
             captured_reply.payload_words,
             captured_reply.payload[0]);
    end
  endtask

  task automatic run_t129();
    sc_cmd_t cmd;

    cmd = make_cmd(SC_READ_NONINCREMENTING, 24'h0013C0, 4);
    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_nonincrementing_read_reply(captured_reply, 24'h0013C0, 4);
    if (captured_reply.sc_type !== SC_READ_NONINCREMENTING) begin
      $error("sc_hub_tb_top: nonincrementing read reply sc_type mismatch exp=%0d act=%0d",
             SC_READ_NONINCREMENTING, captured_reply.sc_type);
    end
  endtask

  task automatic run_t130();
    logic [31:0] wr_words[$];
    logic [31:0] next_addr_before;
    sc_cmd_t     cmd;

`ifdef SC_HUB_BUS_AXI4
    next_addr_before = axi4_bfm_inst.mem[18'h013E1];
`else
    next_addr_before = avmm_bfm_inst.mem[18'h013E1];
`endif

    fill_write_words(wr_words, 4, 32'hA110_0000);
    cmd = make_cmd(SC_WRITE_NONINCREMENTING, 24'h0013E0, 4);
    foreach (cmd.data_words[idx]) begin
      if (idx < wr_words.size()) begin
        cmd.data_words[idx] = wr_words[idx];
      end
    end

    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h0013E0, 4);

`ifdef SC_HUB_BUS_AXI4
    if (axi4_bfm_inst.mem[18'h013E0] !== wr_words[wr_words.size() - 1]) begin
      $error("sc_hub_tb_top: nonincrementing write did not leave last word at fixed address exp=0x%08h act=0x%08h",
             wr_words[wr_words.size() - 1], axi4_bfm_inst.mem[18'h013E0]);
    end
    if (axi4_bfm_inst.mem[18'h013E1] !== next_addr_before) begin
      $error("sc_hub_tb_top: nonincrementing write incorrectly touched next address exp=0x%08h act=0x%08h",
             next_addr_before, axi4_bfm_inst.mem[18'h013E1]);
    end
`else
    if (avmm_bfm_inst.mem[18'h013E0] !== wr_words[wr_words.size() - 1]) begin
      $error("sc_hub_tb_top: nonincrementing write did not leave last word at fixed address exp=0x%08h act=0x%08h",
             wr_words[wr_words.size() - 1], avmm_bfm_inst.mem[18'h013E0]);
    end
    if (avmm_bfm_inst.mem[18'h013E1] !== next_addr_before) begin
      $error("sc_hub_tb_top: nonincrementing write incorrectly touched next address exp=0x%08h act=0x%08h",
             next_addr_before, avmm_bfm_inst.mem[18'h013E1]);
    end
`endif
  endtask

  task automatic run_t102();
    int unsigned expected_beats;
    int unsigned beat_index;
    bit          saw_sop;
    bit          saw_eop;

    expected_beats = 5;
    beat_index     = 0;
    saw_sop        = 1'b0;
    saw_eop        = 1'b0;

    driver_inst.send_read(24'h0013C0, 1);

    while (!saw_eop) begin
      @(posedge clk);
      if (uplink_valid && uplink_ready) begin
        if (beat_index == 0) begin
          if (uplink_data[35:32] !== 4'b0001 || uplink_data[7:0] !== K285_CONST ||
              uplink_sop !== 1'b1 || uplink_eop !== 1'b0) begin
            $error("sc_hub_tb_top: reply SOP beat format mismatch datak=0x%0h data=0x%08h sop=%0b eop=%0b",
                   uplink_data[35:32], uplink_data[31:0], uplink_sop, uplink_eop);
          end
          saw_sop = 1'b1;
        end else if (beat_index == expected_beats - 1) begin
          if (uplink_data[35:32] !== 4'b0001 || uplink_data[7:0] !== K284_CONST ||
              uplink_sop !== 1'b0 || uplink_eop !== 1'b1) begin
            $error("sc_hub_tb_top: reply EOP beat format mismatch datak=0x%0h data=0x%08h sop=%0b eop=%0b",
                   uplink_data[35:32], uplink_data[31:0], uplink_sop, uplink_eop);
          end
        end else begin
          if (uplink_data[35:32] !== 4'b0000 || uplink_sop !== 1'b0 || uplink_eop !== 1'b0) begin
            $error("sc_hub_tb_top: reply middle beat carried K-code or packet flag beat=%0d datak=0x%0h sop=%0b eop=%0b",
                   beat_index, uplink_data[35:32], uplink_sop, uplink_eop);
          end
        end
        saw_eop = uplink_eop;
        beat_index++;
      end
    end

    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h0013C0, 1);
    if (!saw_sop || beat_index != expected_beats) begin
      $error("sc_hub_tb_top: reply framing beat count mismatch exp=%0d act=%0d saw_sop=%0b",
             expected_beats, beat_index, saw_sop);
    end
  endtask

  task automatic run_t103();
    bit saw_preamble;

    saw_preamble = 1'b0;
    driver_inst.send_read(24'h0013E0, 1);

    while (!saw_preamble) begin
      @(posedge clk);
      if (uplink_valid && uplink_ready && uplink_sop) begin
        if (uplink_data[31:26] !== 6'b000111) begin
          $error("sc_hub_tb_top: reply preamble type mismatch exp=000111 act=%b",
                 uplink_data[31:26]);
        end
        saw_preamble = 1'b1;
      end
    end

    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h0013E0, 1);
  endtask

  task automatic run_t104();
    sc_cmd_t cmd;
    logic [31:0] addr_word;

    cmd = make_cmd(SC_READ, 24'h001400, 1);
    driver_inst.drive_word(make_preamble_word(cmd), 4'b0001);
    addr_word = make_addr_word(cmd);
    addr_word[29] = 1'b1;
    driver_inst.drive_word(addr_word, 4'b0000);
    driver_inst.drive_word(make_length_word(cmd), 4'b0000);
    driver_inst.drive_word({24'h0, K284_CONST}, 4'b0001);
    driver_inst.drive_idle();

    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h001400, 1);
  endtask

  task automatic run_t105();
    logic [31:0] csr_word;

    driver_inst.send_read(24'h001420, 2);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h001420, 2);
    read_csr_word(16'h00F, csr_word);
    if (csr_word !== 32'd1) begin
      $error("sc_hub_tb_top: pre-reset EXT_PKT_RD count mismatch exp=1 act=%0d", csr_word);
    end

    pulse_reset(10);
    wait_clks(4);

    read_csr_word(16'h003, csr_word);
    if (csr_word[5:0] !== 6'b010000) begin
      $error("sc_hub_tb_top: STATUS after idle reset mismatch exp[5:0]=010000 act=%b",
             csr_word[5:0]);
    end
    read_csr_word(16'h00F, csr_word);
    if (csr_word !== 32'd0) begin
      $error("sc_hub_tb_top: EXT_PKT_RD count not cleared by hardware reset act=%0d", csr_word);
    end
    read_csr_word(16'h017, csr_word);
    if (csr_word !== 32'd0) begin
      $error("sc_hub_tb_top: PKT_DROP_CNT not cleared by hardware reset act=%0d", csr_word);
    end
  endtask

  task automatic run_t106();
    avmm_bfm_inst.rd_latency_cfg = 8;
    driver_inst.send_read(24'h001440, 16);
    wait (avm_read === 1'b1);
    wait_clks(2);
    pulse_reset(10);
    avmm_bfm_inst.rd_latency_cfg = 1;
    wait_clks(4);

    driver_inst.send_read(24'h001450, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h001450, 1);
  endtask

  task automatic run_t107();
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, 16, 32'hA700_0000);
    driver_inst.send_write(24'h001460, 16, wr_words);
    wait (avm_write === 1'b1);
    wait_clks(2);
    pulse_reset(10);
    wait_clks(4);

    wr_words.delete();
    wr_words.push_back(32'hA700_F001);
    driver_inst.send_write(24'h001470, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h001470, 1);
    check_bfm_words(24'h001470, wr_words);
  endtask

  task automatic run_t108();
    uplink_ready = 1'b1;
    driver_inst.send_read(24'h001480, 16);
    wait (uplink_valid === 1'b1 && uplink_sop === 1'b1);
    wait_clks(2);
    pulse_reset(10);
    wait_clks(4);

    driver_inst.send_read(24'h001490, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h001490, 1);
  endtask

  task automatic run_t109();
    logic [31:0] csr_word;
    sc_cmd_t     cmd;

    uplink_ready = 1'b0;
    driver_inst.send_read(24'h0014A0, 8);
    wait (dut_inst.bp_usedw != '0);

    cmd = make_cmd(SC_WRITE, 24'h0014C0, 4);
    driver_inst.drive_word(make_preamble_word(cmd), 4'b0001);
    driver_inst.drive_word(make_addr_word(cmd), 4'b0000);
    driver_inst.drive_word(make_length_word(cmd), 4'b0000);
    driver_inst.drive_word(32'hA900_0000, 4'b0000);
    driver_inst.drive_idle();
    wait (dut_inst.dl_fifo_usedw != '0);

    pulse_reset(10);
    uplink_ready = 1'b1;
    wait_clks(4);

    read_csr_word(16'h00A, csr_word);
    if (csr_word[5:0] !== 6'b100000) begin
      $error("sc_hub_tb_top: FIFO_STATUS after reset mismatch exp[5:0]=100000 act=%b",
             csr_word[5:0]);
    end
    read_csr_word(16'h00D, csr_word);
    if (csr_word !== 32'd0) begin
      $error("sc_hub_tb_top: DOWN_USEDW not cleared by reset act=%0d", csr_word);
    end
    read_csr_word(16'h00E, csr_word);
    if (csr_word !== 32'd0) begin
      $error("sc_hub_tb_top: UP_USEDW not cleared by reset act=%0d", csr_word);
    end
  endtask

  task automatic run_t110();
    sc_cmd_t cmd;

    uplink_ready = 1'b0;
    driver_inst.send_read(24'h001500, 8);
    wait (dut_inst.bp_usedw != '0);

    cmd = make_cmd(SC_WRITE, csr_addr(16'h002), 1);
    cmd.mask_r       = 1'b1;
    cmd.data_words[0] = 32'h0000_0004;
    send_cmd(cmd);
    wait_clks(16);

    if (dut_inst.bp_usedw != '0 || dut_inst.dl_fifo_usedw != '0 ||
        dut_inst.core_inst.rd_fifo_empty !== 1'b1) begin
      $error("sc_hub_tb_top: software reset did not clear FIFOs bp_usedw=%0d dl_usedw=%0d rd_empty=%0b",
             dut_inst.bp_usedw, dut_inst.dl_fifo_usedw, dut_inst.core_inst.rd_fifo_empty);
    end

    uplink_ready = 1'b1;
    driver_inst.send_read(24'h001510, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h001510, 1);
  endtask

  task automatic run_t111();
    for (int unsigned idx = 1; idx <= 64; idx++) begin
      pulse_reset(4);
      wait_clks(idx);
      driver_inst.send_read(24'h001520 + idx, 1);
      monitor_inst.wait_reply(captured_reply);
      expect_read_reply(captured_reply, 24'h001520 + idx, 1);
    end
  endtask

  task automatic run_t112();
    avmm_bfm_inst.rd_latency_cfg = 8;
    for (int unsigned idx = 0; idx < 64; idx++) begin
      driver_inst.send_read(24'h001600 + idx, 4);
      wait (avm_read === 1'b1);
      wait_clks(1);
      pulse_reset(4);
      wait_clks(2);
      avmm_bfm_inst.rd_latency_cfg = 1;
      driver_inst.send_read(24'h001680 + idx, 1);
      monitor_inst.wait_reply(captured_reply);
      expect_read_reply(captured_reply, 24'h001680 + idx, 1);
      avmm_bfm_inst.rd_latency_cfg = 8;
    end
    avmm_bfm_inst.rd_latency_cfg = 1;
  endtask

  task automatic run_t113();
    longint unsigned start_cycle;
    longint unsigned total_cycles;

    start_cycle = cycle_counter;
    for (int unsigned idx = 0; idx < 10; idx++) begin
      driver_inst.send_read(24'h001700 + idx, 1);
      monitor_inst.wait_reply(captured_reply);
      expect_read_reply(captured_reply, 24'h001700 + idx, 1);
    end
    total_cycles = cycle_counter - start_cycle;
    if (total_cycles >= 1000) begin
      $error("sc_hub_tb_top: back-to-back single reads exceeded cycle budget act=%0d", total_cycles);
    end
  endtask

  task automatic run_t114();
    logic [31:0]     wr_words[$];
    longint unsigned start_cycle;
    longint unsigned total_cycles;

    start_cycle = cycle_counter;
    for (int unsigned idx = 0; idx < 10; idx++) begin
      wr_words.delete();
      wr_words.push_back(32'hB140_0000 + idx);
      driver_inst.send_write(24'h001720 + idx, 1, wr_words);
      monitor_inst.wait_reply(captured_reply);
      expect_write_reply(captured_reply, 24'h001720 + idx, 1);
      check_bfm_words(24'h001720 + idx, wr_words);
    end
    total_cycles = cycle_counter - start_cycle;
    if (total_cycles >= 1000) begin
      $error("sc_hub_tb_top: back-to-back single writes exceeded cycle budget act=%0d", total_cycles);
    end
  endtask

  task automatic run_t115();
    logic [31:0] wr_words[$];

    for (int unsigned idx = 0; idx < 128; idx++) begin
      wr_words.delete();
      wr_words.push_back(32'hB150_0000 + idx);
      driver_inst.send_write(24'h001740 + idx, 1, wr_words);
      monitor_inst.wait_reply(captured_reply);
      expect_write_reply(captured_reply, 24'h001740 + idx, 1);

      driver_inst.send_read(24'h001740 + idx, 1);
      monitor_inst.wait_reply(captured_reply);
      expect_single_word_reply(captured_reply, 24'h001740 + idx, wr_words[0]);
    end
  endtask

  task automatic run_t116();
    logic [31:0] wr_words[$];
    logic [31:0] csr_word;

    driver_inst.send_read(24'h0017C0, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h0017C0, 1);

    wr_words.push_back(32'hB160_0001);
    driver_inst.send_write(24'h0017C4, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h0017C4, 1);

    read_csr_word(16'h000, csr_word);
    if (csr_word !== HUB_UID_CONST) begin
      $error("sc_hub_tb_top: CSR UID mismatch during interleaved traffic exp=0x%08h act=0x%08h",
             HUB_UID_CONST, csr_word);
    end

    wr_words[0] = 32'hB160_0002;
    driver_inst.send_write(24'h0017C8, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h0017C8, 1);

    driver_inst.send_read(24'h0017C4, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_single_word_reply(captured_reply, 24'h0017C4, 32'hB160_0001);
  endtask

  task automatic run_t117();
    longint unsigned start_cycle;
    longint unsigned latency_cycles;

    for (int unsigned idx = 0; idx < 64; idx++) begin
      start_cycle = cycle_counter;
      driver_inst.send_read(24'h001800 + idx, 1);
      monitor_inst.wait_reply(captured_reply);
      latency_cycles = cycle_counter - start_cycle;
      expect_read_reply(captured_reply, 24'h001800 + idx, 1);
      if (latency_cycles >= 100) begin
        $error("sc_hub_tb_top: single-read latency exceeded budget idx=%0d act=%0d",
               idx, latency_cycles);
      end
    end
  endtask

  task automatic run_t118();
    logic [31:0]     wr_words[$];
    longint unsigned start_cycle;
    longint unsigned latency_cycles;

    for (int unsigned idx = 0; idx < 64; idx++) begin
      wr_words.delete();
      wr_words.push_back(32'hB180_0000 + idx);
      start_cycle = cycle_counter;
      driver_inst.send_write(24'h001840 + idx, 1, wr_words);
      monitor_inst.wait_reply(captured_reply);
      latency_cycles = cycle_counter - start_cycle;
      expect_write_reply(captured_reply, 24'h001840 + idx, 1);
      if (latency_cycles >= 100) begin
        $error("sc_hub_tb_top: single-write latency exceeded budget idx=%0d act=%0d",
               idx, latency_cycles);
      end
    end
  endtask

  task automatic run_t119();
    longint unsigned start_cycle;
    longint unsigned total_cycles;

    start_cycle = cycle_counter;
    driver_inst.send_read(24'h001880, 256);
    monitor_inst.wait_reply(captured_reply);
    total_cycles = cycle_counter - start_cycle;
    expect_read_reply(captured_reply, 24'h001880, 256);
    if (total_cycles >= 700) begin
      $error("sc_hub_tb_top: 256-word read throughput exceeded cycle budget act=%0d", total_cycles);
    end
  endtask

  task automatic run_t120();
    logic [31:0]     wr_words[$];
    longint unsigned start_cycle;
    longint unsigned total_cycles;

    fill_write_words(wr_words, 256, 32'hB1A0_0000);
    start_cycle = cycle_counter;
    driver_inst.send_write(24'h0018C0, 256, wr_words);
    monitor_inst.wait_reply(captured_reply);
    total_cycles = cycle_counter - start_cycle;
    expect_write_reply(captured_reply, 24'h0018C0, 256);
    check_bfm_words(24'h0018C0, wr_words);
    if (total_cycles >= 700) begin
      $error("sc_hub_tb_top: 256-word write throughput exceeded cycle budget act=%0d", total_cycles);
    end
  endtask

  task automatic run_t121();
    wait_clks(100000);
    driver_inst.send_read(24'h001900, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h001900, 1);
  endtask

  task automatic run_t122();
    sc_reply_t reply_queue_item;

    uplink_ready = 1'b0;
    for (int unsigned idx = 0; idx < 16; idx++) begin
      driver_inst.send_read(24'h001920 + idx, 1);
    end
    wait_clks(32);
    uplink_ready = 1'b1;

    for (int unsigned idx = 0; idx < 16; idx++) begin
      monitor_inst.wait_reply(reply_queue_item);
      expect_read_reply(reply_queue_item, 24'h001920 + idx, 1);
    end
  endtask
`endif

  task automatic run_t123();
    int unsigned burst_lengths[$] = '{1, 2, 3, 4, 8, 16, 32, 64, 128, 255, 256};
    logic [23:0] rd_addr;
    logic [23:0] wr_addr;

    rd_addr = 24'h001A80;
    wr_addr = 24'h002A80;
    foreach (burst_lengths[idx]) begin
      run_burst_len_case(1'b0, rd_addr, burst_lengths[idx], 32'h0);
      run_burst_len_case(1'b1, wr_addr, burst_lengths[idx], 32'h1230_0000 + idx * 32'h100);
      rd_addr = rd_addr + burst_lengths[idx] + 24'd4;
      wr_addr = wr_addr + burst_lengths[idx] + 24'd4;
    end
  endtask

  task automatic run_t124();
    logic [31:0] csr_word;

    driver_inst.send_read(24'h000000, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000000, 1);

    driver_inst.send_read(24'h000001, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000001, 1);

    driver_inst.send_read(24'h000100, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000100, 1);

    driver_inst.send_read(24'h001000, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h001000, 1);

    driver_inst.send_read(24'h007FFF, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h007FFF, 1);

    driver_inst.send_read(24'h00FE7F, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h00FE7F, 1);
    read_csr_word(16'h0000, csr_word);
    if (^csr_word === 1'bX) begin
      $error("sc_hub_tb_top: T124 CSR base read returned unknown data");
    end
    read_csr_word(16'h001F, csr_word);
    if (^csr_word === 1'bX) begin
      $error("sc_hub_tb_top: T124 CSR top-of-window read returned unknown data");
    end
    driver_inst.send_read(24'h00FEA0, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h00FEA0, 1);

    driver_inst.send_read(24'h00FFFF, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h00FFFF, 1);
  endtask

  task automatic run_t125();
    int unsigned latencies[$] = '{1, 2, 4, 8, 16, 32, 64, 100, 199};
    logic [31:0] wr_words[$];

    foreach (latencies[idx]) begin
`ifdef SC_HUB_BUS_AXI4
      reset_axi4_rd_latencies(latencies[idx]);
      set_axi4_wr_latency(latencies[idx]);
`else
      reset_avmm_rd_latencies(latencies[idx]);
      set_avmm_wr_latency(latencies[idx]);
`endif
      driver_inst.send_read(24'h001C00 + idx, 1);
      monitor_inst.wait_reply(captured_reply);
      expect_read_reply(captured_reply, 24'h001C00 + idx, 1);

      wr_words.delete();
      wr_words.push_back(32'h1250_0000 + idx);
      driver_inst.send_write(24'h001D00 + idx, 1, wr_words);
      monitor_inst.wait_reply(captured_reply);
      expect_write_reply(captured_reply, 24'h001D00 + idx, 1);
      check_bfm_words(24'h001D00 + idx, wr_words);
    end

`ifdef SC_HUB_BUS_AXI4
    reset_axi4_rd_latencies(1);
    set_axi4_wr_latency(1);
`else
    reset_avmm_rd_latencies(1);
    set_avmm_wr_latency(1);
`endif
  endtask

  task automatic run_t126();
`ifdef SC_HUB_BUS_AXI4
    run_t504();
    run_t505();
    run_t506();
    run_t507();
    run_t508();
`else
    run_t500();
    run_t501();
    run_t502();
    run_t503();
    run_t509();
`endif
  endtask

  task automatic run_t127();
    logic [31:0] wr_words[$];
    sc_cmd_t      muted_cmd;
    logic [31:0]  start_drop_count;
    logic [31:0]  end_drop_count;

    read_pkt_drop_count(start_drop_count);
    for (int unsigned gap = 0; gap < 16; gap++) begin
      wait_clks(gap);
      driver_inst.send_burst_read(24'h001E00 + gap * 16, 3);
      monitor_inst.wait_reply(captured_reply);
      expect_read_reply(captured_reply, 24'h001E00 + gap * 16, 3);

      wait_clks(gap);
      fill_write_words(wr_words, 3, 32'h1270_0000 + gap * 32'h10);
      driver_inst.send_burst_write(24'h002E00 + gap * 16, 3, wr_words);
      monitor_inst.wait_reply(captured_reply);
      expect_write_reply(captured_reply, 24'h002E00 + gap * 16, 3);
      check_bfm_words(24'h002E00 + gap * 16, wr_words);

      wait_clks(gap);
      driver_inst.send_read(24'h003E00 + gap, 1);
      monitor_inst.wait_reply(captured_reply);
      expect_read_reply(captured_reply, 24'h003E00 + gap, 1);

      wait_clks(gap);
      wr_words.delete();
      wr_words.push_back(32'h1271_0000 + gap);
      driver_inst.send_write(24'h004E00 + gap, 1, wr_words);
      monitor_inst.wait_reply(captured_reply);
      expect_write_reply(captured_reply, 24'h004E00 + gap, 1);
      check_bfm_words(24'h004E00 + gap, wr_words);

      wait_clks(gap);
      driver_inst.send_read(csr_addr(16'h0000), 1);
      monitor_inst.wait_reply(captured_reply);
      expect_reply_header_rsp(captured_reply, csr_addr(16'h0000), 1, 2'b00);

      wait_clks(gap);
      wr_words.delete();
      wr_words.push_back(32'h1272_0000 + gap);
      driver_inst.send_write(csr_addr(16'h0006), 1, wr_words);
      monitor_inst.wait_reply(captured_reply);
      expect_write_reply(captured_reply, csr_addr(16'h0006), 1);

      wait_clks(gap);
      muted_cmd = make_cmd(SC_READ, 24'h005E00 + gap, 1);
      muted_cmd.mask_r = 1'b1;
      send_cmd(muted_cmd);
      monitor_inst.assert_no_reply(400ns);

      wait_clks(gap);
      drive_word_ignore_ready(make_preamble_word(make_cmd(SC_WRITE, 24'h006E00 + gap, 2)), 4'b0001);
      drive_word_ignore_ready(make_addr_word(make_cmd(SC_WRITE, 24'h006E00 + gap, 2)), 4'b0000);
      drive_word_ignore_ready(make_length_word(make_cmd(SC_WRITE, 24'h006E00 + gap, 2)), 4'b0000);
      drive_word_ignore_ready(32'hDEAD_0000 + gap, 4'b0000);
      driver_inst.drive_idle();
      monitor_inst.assert_no_reply(400ns);
    end
    read_pkt_drop_count(end_drop_count);
    if (end_drop_count - start_drop_count != 16) begin
      $error("sc_hub_tb_top: T127 expected 16 malformed packet drops act_delta=%0d",
             end_drop_count - start_drop_count);
    end
  endtask

  task automatic run_t128();
    int unsigned lcg_state;
    int unsigned malformed_count;
    int unsigned start_drop_count;
    int unsigned end_drop_count;
    logic [31:0] wr_words[$];
    logic [31:0] exp_words[$];
    logic [23:0] start_address;
    int unsigned rw_length;

    lcg_state = 32'h1ACE_B00C;
    malformed_count = 0;
    read_pkt_drop_count(start_drop_count);

    for (int unsigned idx = 0; idx < 100; idx++) begin
      lcg_state     = lcg_state * 32'd1664525 + 32'd1013904223;
      start_address = 24'h010000 + ((lcg_state >> 8) & 24'h0003FF);
      rw_length     = ((lcg_state >> 4) & 8'h7) + 1;

      if ((idx % 10) == 9) begin
        malformed_count++;
        drive_word_ignore_ready(make_preamble_word(make_cmd(SC_WRITE, start_address, rw_length)), 4'b0001);
        drive_word_ignore_ready(make_addr_word(make_cmd(SC_WRITE, start_address, rw_length)), 4'b0000);
        drive_word_ignore_ready(make_length_word(make_cmd(SC_WRITE, start_address, rw_length)), 4'b0000);
        for (int unsigned word_idx = 0; word_idx < rw_length; word_idx++) begin
          drive_word_ignore_ready(32'h1280_0000 + idx + word_idx, 4'b0000);
        end
        driver_inst.drive_idle();
        monitor_inst.assert_no_reply(400ns);
      end else if (lcg_state[0]) begin
        fill_write_words(wr_words, rw_length, 32'h1281_0000 + idx * 32'h10);
        if (rw_length > 1) begin
          driver_inst.send_burst_write(start_address, rw_length, wr_words);
        end else begin
          driver_inst.send_write(start_address, rw_length, wr_words);
        end
        monitor_inst.wait_reply(captured_reply);
        expect_write_reply(captured_reply, start_address, rw_length);
        check_bfm_words(start_address, wr_words);
      end else begin
        read_bfm_words(start_address, rw_length, exp_words);
        if (rw_length > 1) begin
          driver_inst.send_burst_read(start_address, rw_length);
        end else begin
          driver_inst.send_read(start_address, rw_length);
        end
        monitor_inst.wait_reply(captured_reply);
        expect_reply_words(captured_reply, start_address, exp_words);
      end
      wait_clks(lcg_state[11:8]);
    end

    read_pkt_drop_count(end_drop_count);
    if (end_drop_count - start_drop_count != malformed_count) begin
      $error("sc_hub_tb_top: T128 pkt-drop mismatch exp=%0d act=%0d",
             malformed_count,
             end_drop_count - start_drop_count);
    end
  endtask

`ifndef SC_HUB_BUS_AXI4
  task automatic run_t200();
    logic [31:0] wr_words[$];
    int unsigned waited_cycles;

    clear_hub_counters();
    fill_write_words(wr_words, 8, 32'h2000_0000);

    force avm_waitrequest = 1'b1;
    fork
      begin
        driver_inst.send_write(24'h000200, 8, wr_words);
      end
    join_none

    waited_cycles = 0;
    while (dut_inst.dl_fifo_usedw < 10'd8 && waited_cycles < 256) begin
      @(posedge clk);
      waited_cycles++;
    end
    if (dut_inst.dl_fifo_usedw != 10'd8) begin
      $error("sc_hub_tb_top: T200 expected ext_down payload to hold 8 words act=%0d",
             dut_inst.dl_fifo_usedw);
    end
    release avm_waitrequest;
    wait fork;

    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000200, 8);
    check_bfm_words(24'h000200, wr_words);
    wait_clks(8);
    if (dut_inst.dl_fifo_usedw != 10'd0) begin
      $error("sc_hub_tb_top: T200 payload queue did not drain after write completion act=%0d",
             dut_inst.dl_fifo_usedw);
    end
    if ($unsigned(dut_inst.core_inst.ext_pkt_write_count) != 32'd1 ||
        $unsigned(dut_inst.core_inst.ext_word_write_count) != 32'd8) begin
      $error("sc_hub_tb_top: T200 write counters mismatch pkt=%0d word=%0d",
             dut_inst.core_inst.ext_pkt_write_count,
             dut_inst.core_inst.ext_word_write_count);
    end
  endtask

  task automatic run_t201();
    int unsigned waited_cycles;

    clear_hub_counters();
    uplink_ready = 1'b0;
    driver_inst.send_read(24'h000210, 16);

    waited_cycles = 0;
    while ($unsigned(dut_inst.bp_usedw) < 16 && waited_cycles < 512) begin
      @(posedge clk);
      waited_cycles++;
    end
    if ($unsigned(dut_inst.bp_usedw) != 16) begin
      $error("sc_hub_tb_top: T201 expected ext_up payload queue to hold 16 words act=%0d",
             dut_inst.bp_usedw);
    end

    uplink_ready = 1'b1;
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000210, 16);
    waited_cycles = 0;
    while ($unsigned(dut_inst.bp_usedw) != 0 && waited_cycles < 256) begin
      @(posedge clk);
      waited_cycles++;
    end
    if ($unsigned(dut_inst.bp_usedw) != 0) begin
      $error("sc_hub_tb_top: T201 upload payload queue did not drain act=%0d",
             dut_inst.bp_usedw);
    end
    if ($unsigned(dut_inst.core_inst.ext_pkt_read_count) != 32'd1 ||
        $unsigned(dut_inst.core_inst.ext_word_read_count) != 32'd16) begin
      $error("sc_hub_tb_top: T201 read counters mismatch pkt=%0d word=%0d",
             dut_inst.core_inst.ext_pkt_read_count,
             dut_inst.core_inst.ext_word_read_count);
    end
  endtask

  task automatic run_t202();
    bit bus_activity_seen;

    bus_activity_seen = 1'b0;
    force avm_waitrequest = 1'b1;
    fork
      begin
        repeat (64) begin
          @(posedge clk);
          if (avm_read === 1'b1 || avm_write === 1'b1) begin
            bus_activity_seen = 1'b1;
          end
        end
      end
      begin
        driver_inst.send_read(csr_addr(16'h000), 1);
        monitor_inst.wait_reply(captured_reply);
      end
    join
    release avm_waitrequest;

    expect_single_word_reply(captured_reply, csr_addr(16'h000), HUB_UID_CONST);
    if (bus_activity_seen) begin
      $error("sc_hub_tb_top: T202 internal CSR read incorrectly drove the external AVMM bus");
    end
  endtask

  task automatic run_t203();
    logic [31:0] wr_words[$];
    logic [31:0] scratch_word;
    bit          bus_activity_seen;

    wr_words.push_back(32'h2030_DEAD);
    bus_activity_seen = 1'b0;
    force avm_waitrequest = 1'b1;
    fork
      begin
        repeat (64) begin
          @(posedge clk);
          if (avm_read === 1'b1 || avm_write === 1'b1) begin
            bus_activity_seen = 1'b1;
          end
        end
      end
      begin
    driver_inst.send_write(csr_addr(16'h006), 1, wr_words);
        monitor_inst.wait_reply(captured_reply);
      end
    join
    release avm_waitrequest;

    expect_write_reply(captured_reply, csr_addr(16'h006), 1);
    read_csr_word(16'h006, scratch_word);
    if (scratch_word !== wr_words[0]) begin
      $error("sc_hub_tb_top: T203 scratch update mismatch exp=0x%08h act=0x%08h",
             wr_words[0],
             scratch_word);
    end
    if (bus_activity_seen) begin
      $error("sc_hub_tb_top: T203 internal CSR write incorrectly drove the external AVMM bus");
    end
  endtask

  task automatic run_t204();
    logic [31:0] wr_words[$];
    int unsigned waited_cycles;

    clear_hub_counters();
    fill_write_words(wr_words, 64, 32'h2040_0000);

    force avm_waitrequest = 1'b1;
    fork
      begin
        driver_inst.send_write(24'h000240, 64, wr_words);
      end
    join_none

    waited_cycles = 0;
    while (dut_inst.dl_fifo_usedw < 10'd64 && waited_cycles < 512) begin
      @(posedge clk);
      waited_cycles++;
    end
    if (dut_inst.dl_fifo_usedw != 10'd64) begin
      $error("sc_hub_tb_top: T204 expected queued payload depth of 64 words act=%0d",
             dut_inst.dl_fifo_usedw);
    end

    release avm_waitrequest;
    wait fork;
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000240, 64);
    check_bfm_words(24'h000240, wr_words);
    waited_cycles = 0;
    while (dut_inst.dl_fifo_usedw != 0 && waited_cycles < 256) begin
      @(posedge clk);
      waited_cycles++;
    end
    if (dut_inst.dl_fifo_usedw != 0) begin
      $error("sc_hub_tb_top: T204 payload queue did not return to empty act=%0d",
             dut_inst.dl_fifo_usedw);
    end
  endtask

  task automatic run_t205();
    logic [31:0] wr_words[$];
    logic [23:0] base_addr;
    int unsigned waited_cycles;

    clear_hub_counters();
    base_addr = 24'h000280;
    force avm_waitrequest = 1'b1;

    for (int unsigned idx = 0; idx < 4; idx++) begin
      fill_write_words(wr_words, 128, 32'h2050_0000 + idx * 32'h100);
      driver_inst.send_write(base_addr + (idx * 24'h0100), 128, wr_words);
    end

    waited_cycles = 0;
    while (dut_inst.dl_fifo_usedw < 10'd512 && waited_cycles < 2048) begin
      @(posedge clk);
      waited_cycles++;
    end
    if (dut_inst.dl_fifo_usedw != 10'd512) begin
      $error("sc_hub_tb_top: T205 expected payload queue full at 512 words act=%0d",
             dut_inst.dl_fifo_usedw);
    end

    fork
      begin
        fill_write_words(wr_words, 128, 32'h2054_0000);
        driver_inst.send_write(base_addr + 24'h0400, 128, wr_words);
      end
    join_none
    wait_link_ready_value(1'b0, "T205 payload full backpressure", 1024);
    if (dut_inst.dl_fifo_usedw != 10'd512) begin
      $error("sc_hub_tb_top: T205 payload queue changed while 5th write was backpressured act=%0d",
             dut_inst.dl_fifo_usedw);
    end
    if (dut_inst.dl_fifo_overflow !== 1'b0) begin
      $error("sc_hub_tb_top: T205 observed unexpected payload overflow at full-queue boundary");
    end
    if (dut_inst.pkt_drop_count !== 16'd0) begin
      $error("sc_hub_tb_top: T205 observed unexpected packet drop count act=%0d",
             dut_inst.pkt_drop_count);
    end

    release avm_waitrequest;
    wait_clks(8);
  endtask

  task automatic run_t206();
    logic [31:0] wr_words[$];

    avmm_bfm_inst.set_default_rd_latency(1);
    avmm_bfm_inst.set_rd_latency_for_addr(16'h0260, 32);
    avmm_bfm_inst.set_rd_latency_for_addr(16'h0268, 2);

    wr_words.push_back(32'h2060_0001);
    driver_inst.send_read(24'h000260, 1);
    driver_inst.send_write(24'h000264, 1, wr_words);
    driver_inst.send_read(24'h000268, 1);
    wr_words[0] = 32'h2060_0002;
    driver_inst.send_write(24'h00026C, 1, wr_words);

    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000260, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000264, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000268, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h00026C, 1);

    avmm_bfm_inst.set_rd_latency_for_addr(16'h0260, 1);
    avmm_bfm_inst.set_rd_latency_for_addr(16'h0268, 1);
  endtask

  task automatic run_t207();
    logic [23:0] addr_list[0:7];
    int unsigned lat_list[0:7];
    sc_reply_t   reply_queue_item;

    addr_list[0] = 24'h000270;
    addr_list[1] = 24'h000271;
    addr_list[2] = 24'h000272;
    addr_list[3] = 24'h000273;
    addr_list[4] = 24'h000274;
    addr_list[5] = 24'h000275;
    addr_list[6] = 24'h000276;
    addr_list[7] = 24'h000277;
    lat_list[0]  = 30;
    lat_list[1]  = 2;
    lat_list[2]  = 24;
    lat_list[3]  = 4;
    lat_list[4]  = 18;
    lat_list[5]  = 6;
    lat_list[6]  = 12;
    lat_list[7]  = 8;

    avmm_bfm_inst.set_default_rd_latency(1);
    for (int unsigned idx = 0; idx < 8; idx++) begin
      avmm_bfm_inst.set_rd_latency_for_addr(addr_list[idx][17:0], lat_list[idx]);
      driver_inst.send_read(addr_list[idx], 1);
    end

    for (int unsigned idx = 0; idx < 8; idx++) begin
      monitor_inst.wait_reply(reply_queue_item);
      expect_read_reply(reply_queue_item, addr_list[idx], 1);
      avmm_bfm_inst.set_rd_latency_for_addr(addr_list[idx][17:0], 1);
    end
  endtask

  task automatic run_t208();
    logic [31:0] wr_words[$];
    bit          simultaneous_pressure_seen;

    simultaneous_pressure_seen = 1'b0;
    clear_hub_counters();
    force avm_waitrequest = 1'b1;
    force_avalon_bp_usedw(16);

    fill_write_words(wr_words, 16, 32'h2080_0000);
    driver_inst.send_write(24'h000280, 16, wr_words);
    driver_inst.send_read(csr_addr(16'h000), 1);
    wait_clks(16);

    simultaneous_pressure_seen =
      (dut_inst.dl_fifo_usedw != 0) &&
      ($unsigned(dut_inst.bp_usedw) != 0) &&
      ((dut_inst.core_inst.tracked_pkt_count != 0) || (dut_inst.core_inst.core_state != 0));

    if (!simultaneous_pressure_seen) begin
      $error("sc_hub_tb_top: T208 expected simultaneous payload/reply/command pressure dl=%0d bp=%0d tracked=%0d",
             dut_inst.dl_fifo_usedw,
             dut_inst.bp_usedw,
             dut_inst.core_inst.tracked_pkt_count);
    end

    release avm_waitrequest;
    release_avalon_bp_usedw();
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000280, 16);
    monitor_inst.wait_reply(captured_reply);
    expect_single_word_reply(captured_reply, csr_addr(16'h000), HUB_UID_CONST);
  endtask

  task automatic run_t209();
    int unsigned waited_cycles;

    clear_hub_counters();
    uplink_ready = 1'b0;
    driver_inst.send_read(24'h0002A0, 64);

    waited_cycles = 0;
    while ($unsigned(dut_inst.bp_usedw) < 64 && waited_cycles < 1024) begin
      @(posedge clk);
      waited_cycles++;
    end
    if ($unsigned(dut_inst.bp_usedw) != 64) begin
      $error("sc_hub_tb_top: T209 expected 64-word reply payload allocation act=%0d",
             dut_inst.bp_usedw);
    end

    uplink_ready = 1'b1;
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h0002A0, 64);
    waited_cycles = 0;
    while ($unsigned(dut_inst.bp_usedw) != 0 && waited_cycles < 256) begin
      @(posedge clk);
      waited_cycles++;
    end
    if ($unsigned(dut_inst.bp_usedw) != 0) begin
      $error("sc_hub_tb_top: T209 upload payload allocation did not drain act=%0d",
             dut_inst.bp_usedw);
    end
  endtask

  task automatic run_t424();
    logic [31:0] wr_words[$];
    int unsigned waited_cycles;

    fill_write_words(wr_words, 16, 32'h4240_0000);
    driver_inst.send_write(24'h004240, 16, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h004240, 16);

    uplink_ready = 1'b0;
    driver_inst.send_read(24'h004250, 16);
    wait_clks(16);
    uplink_ready = 1'b1;
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h004250, 16);

    force avm_waitrequest = 1'b1;
    fill_write_words(wr_words, 64, 32'h4241_0000);
    fork
      begin
        driver_inst.send_write(24'h004260, 64, wr_words);
      end
    join_none
    waited_cycles = 0;
    while (dut_inst.dl_fifo_usedw < 10'd64 && waited_cycles < 1024) begin
      @(posedge clk);
      waited_cycles++;
    end
    if (dut_inst.dl_fifo_usedw != 10'd64) begin
      $error("sc_hub_tb_top: T424 expected large post-fragmentation write to allocate 64 payload words act=%0d",
             dut_inst.dl_fifo_usedw);
    end
    release avm_waitrequest;
    wait fork;
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h004260, 64);
    check_bfm_words(24'h004260, wr_words);
  endtask
`endif

  task automatic run_t400();
    run_burst_len_case(1'b0, 24'h011000, 3, 32'h0);
  endtask

  task automatic run_t401();
    run_burst_len_case(1'b1, 24'h011100, 5, 32'h1401_0000);
  endtask

  task automatic run_t402();
    run_burst_len_case(1'b0, 24'h011200, 7, 32'h0);
  endtask

  task automatic run_t403();
    run_burst_len_case(1'b1, 24'h011300, 13, 32'h1403_0000);
  endtask

  task automatic run_t404();
    run_burst_len_case(1'b0, 24'h011400, 127, 32'h0);
  endtask

  task automatic run_t405();
    run_burst_len_case(1'b1, 24'h011500, 129, 32'h1405_0000);
  endtask

  task automatic run_t406();
    run_burst_len_case(1'b0, 24'h011600, 255, 32'h0);
  endtask

`ifdef SC_HUB_BUS_AXI4
  task automatic run_t407();
    logic [31:0] exp_words[$];

    axi_ar_count    = 0;
    axi_r_count     = 0;
    axi_rlast_count = 0;
    axi_last_arlen  = '0;
    axi_last_arid   = '0;
    axi_last_rid    = '0;
    read_bfm_words(24'h011700, 3, exp_words);
    driver_inst.send_burst_read(24'h011700, 3);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_words(captured_reply, 24'h011700, exp_words);
    expect_axi4_read_summary(3, 8'd2);
  endtask

  task automatic run_t408();
    logic [31:0] wr_words[$];

    axi_aw_count      = 0;
    axi_w_count       = 0;
    axi_b_count       = 0;
    axi_wlast_count   = 0;
    axi_last_awlen    = '0;
    axi_last_awid     = '0;
    axi_last_bid      = '0;
    axi_last_wstrb    = '0;
    axi_w_before_aw_violation = 1'b0;
    fill_write_words(wr_words, 7, 32'h1408_0000);
    driver_inst.send_burst_write(24'h011800, 7, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h011800, 7);
    check_bfm_words(24'h011800, wr_words);
    expect_axi4_write_summary(7, 8'd6);
  endtask

  task automatic run_t409();
    logic [31:0] exp_words[$];

    axi_ar_count    = 0;
    axi_r_count     = 0;
    axi_rlast_count = 0;
    axi_last_arlen  = '0;
    axi_last_arid   = '0;
    axi_last_rid    = '0;
    read_bfm_words(24'h011900, 255, exp_words);
    driver_inst.send_burst_read(24'h011900, 255);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_words(captured_reply, 24'h011900, exp_words);
    expect_axi4_read_summary(255, 8'd254);
  endtask
`endif

  task automatic run_t410();
    int unsigned prime_lengths[$] = '{1, 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31};
    logic [23:0] rd_addr;

    rd_addr = 24'h011A00;
    foreach (prime_lengths[idx]) begin
      run_burst_len_case(1'b0, rd_addr, prime_lengths[idx], 32'h0);
      rd_addr = rd_addr + prime_lengths[idx] + 24'd4;
    end
  endtask

  task automatic run_t411();
    run_burst_len_case(1'b1, 24'h011B00, 1, 32'h1411_0000);
    run_burst_len_case(1'b1, 24'h011C00, 256, 32'h1411_1000);
  endtask

  task automatic run_t412();
    logic [23:0] wr_addr;

    wr_addr = 24'h011D00;
    for (int unsigned idx = 0; idx < 100; idx++) begin
      run_burst_len_case(1'b1, wr_addr, 1, 32'h1412_0000 + idx);
      wr_addr = wr_addr + 24'd4;
      run_burst_len_case(1'b1, wr_addr, 255, 32'h1412_1000 + idx * 32'h100);
      wr_addr = wr_addr + 24'd260;
    end
  endtask

  task automatic run_t413();
    run_burst_len_case(1'b0, 24'h012F00, 250, 32'h0);
  endtask

  task automatic run_t414();
    run_burst_len_case(1'b1, 24'h013000, 2, 32'h1414_0000);
  endtask

`ifndef SC_HUB_BUS_AXI4
  task automatic run_t415();
    logic [23:0] start_address;

    start_address = 24'h004150;
    stall_avalon_reads(start_address, AVALON_DUT_EXT_TRACK_LIMIT - 1);
    if (dut_inst.rx_ready !== 1'b1) begin
      $error("sc_hub_tb_top: T415 expected rx_ready=1 with %0d tracked packets act=%0b",
             AVALON_DUT_EXT_TRACK_LIMIT - 1,
             dut_inst.rx_ready);
    end

    driver_inst.send_read(start_address + (AVALON_DUT_EXT_TRACK_LIMIT - 1), 1);
    wait_avalon_tracked_count(AVALON_DUT_EXT_TRACK_LIMIT, "T415 full admission");
    if (dut_inst.rx_ready !== 1'b0) begin
      $error("sc_hub_tb_top: T415 expected rx_ready=0 after the last slot was consumed act=%0b",
             dut_inst.rx_ready);
    end

    drain_avalon_read_queue(start_address, AVALON_DUT_EXT_TRACK_LIMIT);
  endtask

  task automatic run_t416();
    logic [23:0] start_address;

    start_address = 24'h004160;
    stall_avalon_reads(start_address, AVALON_DUT_EXT_TRACK_LIMIT);
    if (dut_inst.core_inst.tracked_pkt_count != AVALON_DUT_EXT_TRACK_LIMIT) begin
      $error("sc_hub_tb_top: T416 tracked count mismatch exp=%0d act=%0d",
             AVALON_DUT_EXT_TRACK_LIMIT,
             dut_inst.core_inst.tracked_pkt_count);
    end
    if (dut_inst.rx_ready !== 1'b0) begin
      $error("sc_hub_tb_top: T416 expected rx_ready=0 when tracked queue is full act=%0b",
             dut_inst.rx_ready);
    end
    wait_clks(8);
    if (dut_inst.rx_ready !== 1'b0) begin
      $error("sc_hub_tb_top: T416 expected rx_ready to remain low while bus launch is stalled act=%0b",
             dut_inst.rx_ready);
    end

    drain_avalon_read_queue(start_address, AVALON_DUT_EXT_TRACK_LIMIT);
  endtask

  task automatic run_t422();
    run_t416();
  endtask

  task automatic run_t417();
    logic [23:0] start_address;

    if (AVALON_DUT_EXT_PLD_DEPTH < 512) begin
      $error("sc_hub_tb_top: T417 requires EXT_PLD_DEPTH >= 512 act=%0d",
             AVALON_DUT_EXT_PLD_DEPTH);
    end

    start_address = 24'h004170;
    force dut_inst.bus_cmd_ready = 1'b0;
    send_stalled_avalon_write(start_address, 255, 32'h4170_0000);
    send_stalled_avalon_write(start_address + 24'h000100, 256, 32'h4171_0000);
    wait_clks(1);
    if (dut_inst.dl_fifo_usedw != 9'd511) begin
      $error("sc_hub_tb_top: T417 expected dl_fifo_usedw=511 act=%0d",
             dut_inst.dl_fifo_usedw);
    end

    send_stalled_avalon_write(start_address + 24'h000200, 1, 32'h4172_0000);
    wait_clks(1);
    if (dut_inst.dl_fifo_usedw != 10'd512) begin
      $error("sc_hub_tb_top: T417 expected exact-fill dl_fifo_usedw=512 act=%0d",
             dut_inst.dl_fifo_usedw);
    end

    release dut_inst.bus_cmd_ready;
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, start_address, 255);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, start_address + 24'h000100, 256);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, start_address + 24'h000200, 1);
  endtask

  task automatic run_t418();
    logic [23:0] start_address;
    logic        stalled_write_done;

    if (AVALON_DUT_EXT_PLD_DEPTH < 512) begin
      $error("sc_hub_tb_top: T418 requires EXT_PLD_DEPTH >= 512 act=%0d",
             AVALON_DUT_EXT_PLD_DEPTH);
    end

    start_address = 24'h004180;
    stalled_write_done = 1'b0;
    force dut_inst.bus_cmd_ready = 1'b0;
    send_stalled_avalon_write(start_address, 256, 32'h4180_0000);
    send_stalled_avalon_write(start_address + 24'h000100, 256, 32'h4181_0000);
    wait_clks(1);
    if (dut_inst.dl_fifo_usedw != 10'd512) begin
      $error("sc_hub_tb_top: T418 expected full dl_fifo_usedw=512 act=%0d",
             dut_inst.dl_fifo_usedw);
    end

    fork
      begin : t418_stalled_write_thread
        driver_inst.send_precise_stalled_single_write(start_address + 24'h000200, 32'h4182_0000);
        stalled_write_done = 1'b1;
      end
    join_none
    wait_link_ready_value(1'b0, "T418 payload backpressure");
    wait_clks(8);
    if (dut_inst.dl_fifo_usedw != 10'd512) begin
      $error("sc_hub_tb_top: T418 payload usedw changed while blocked act=%0d",
             dut_inst.dl_fifo_usedw);
    end

    release dut_inst.bus_cmd_ready;
    repeat (256) begin
      if (stalled_write_done == 1'b1) begin
        break;
      end
      @(posedge clk);
    end
    if (stalled_write_done != 1'b1) begin
      $error("sc_hub_tb_top: T418 stalled write did not resume after releasing bus_cmd_ready");
      disable t418_stalled_write_thread;
      return;
    end

    monitor_inst.wait_reply_cycles(captured_reply, 10_000);
    if (captured_reply.echoed_length === 16'hffff) begin
      return;
    end
    expect_write_reply(captured_reply, start_address, 256);
    monitor_inst.wait_reply_cycles(captured_reply, 10_000);
    if (captured_reply.echoed_length === 16'hffff) begin
      return;
    end
    expect_write_reply(captured_reply, start_address + 24'h000100, 256);
    monitor_inst.wait_reply_cycles(captured_reply, 10_000);
    if (captured_reply.echoed_length === 16'hffff) begin
      return;
    end
    expect_write_reply(captured_reply, start_address + 24'h000200, 1);
  endtask

  task automatic run_t419();
    logic [23:0] start_address;
    logic        stalled_write_done;

    if (AVALON_DUT_EXT_PLD_DEPTH < 512) begin
      $error("sc_hub_tb_top: T419 requires EXT_PLD_DEPTH >= 512 act=%0d",
             AVALON_DUT_EXT_PLD_DEPTH);
    end

    start_address = 24'h004190;
    stalled_write_done = 1'b0;
    force dut_inst.bus_cmd_ready = 1'b0;
    send_stalled_avalon_write(start_address, 255, 32'h4190_0000);
    send_stalled_avalon_write(start_address + 24'h000100, 255, 32'h4191_0000);
    wait_clks(1);
    if (dut_inst.dl_fifo_usedw != 9'd510) begin
      $error("sc_hub_tb_top: T419 expected dl_fifo_usedw=510 act=%0d",
             dut_inst.dl_fifo_usedw);
    end

    fork
      begin : t419_stalled_write_thread
        send_stalled_avalon_write(start_address + 24'h000200, 4, 32'h4192_0000);
        stalled_write_done = 1'b1;
      end
    join_none
    wait_link_ready_value(1'b0, "T419 payload backpressure");
    wait_clks(8);
    if (dut_inst.dl_fifo_usedw != 9'd510) begin
      $error("sc_hub_tb_top: T419 payload usedw changed while blocked act=%0d",
             dut_inst.dl_fifo_usedw);
    end

    release dut_inst.bus_cmd_ready;
    repeat (256) begin
      if (stalled_write_done == 1'b1) begin
        break;
      end
      @(posedge clk);
    end
    if (stalled_write_done != 1'b1) begin
      $error("sc_hub_tb_top: T419 stalled write did not resume after releasing bus_cmd_ready");
      disable t419_stalled_write_thread;
      return;
    end

    monitor_inst.wait_reply_cycles(captured_reply, 10_000);
    if (captured_reply.echoed_length === 16'hffff) begin
      return;
    end
    expect_write_reply(captured_reply, start_address, 255);
    monitor_inst.wait_reply_cycles(captured_reply, 10_000);
    if (captured_reply.echoed_length === 16'hffff) begin
      return;
    end
    expect_write_reply(captured_reply, start_address + 24'h000100, 255);
    monitor_inst.wait_reply_cycles(captured_reply, 10_000);
    if (captured_reply.echoed_length === 16'hffff) begin
      return;
    end
    expect_write_reply(captured_reply, start_address + 24'h000200, 4);
  endtask

  task automatic run_t420();
    sc_reply_t read_reply;

    force_avalon_bp_usedw(AVALON_DUT_BP_FIFO_DEPTH - 1);
    driver_inst.send_read(24'h000420, 1);
    wait_avalon_read_pulse("T420 reserved payload credit");
    release_avalon_bp_usedw();
    monitor_inst.wait_reply(read_reply);
    expect_read_reply(read_reply, 24'h000420, 1);
  endtask

  task automatic run_t421();
    sc_reply_t read_reply;

    force_avalon_bp_usedw(AVALON_DUT_BP_FIFO_DEPTH);
    fork
      begin
        driver_inst.send_read(24'h000421, 1);
      end
    join_none
    wait_clks(16);
    if (avm_read !== 1'b0) begin
      $error("sc_hub_tb_top: T421 expected avm_read to stay low while reply credit is exhausted");
    end

    release_avalon_bp_usedw();
    wait fork;
    monitor_inst.wait_reply(read_reply);
    expect_read_reply(read_reply, 24'h000421, 1);
  endtask

  task automatic run_t423();
    for (int unsigned idx = 0; idx < 300; idx++) begin
      driver_inst.send_read(24'h004230 + idx, 1);
      monitor_inst.wait_reply(captured_reply);
      expect_read_reply(captured_reply, 24'h004230 + idx, 1);
    end
  endtask

  task automatic run_t425();
    bit saw_below_threshold_fill;

    uplink_ready = 1'b0;
    driver_inst.send_read(24'h004250, 251);
    saw_below_threshold_fill = 1'b0;
    repeat (1200) begin
      @(posedge clk);
      if ($unsigned(dut_inst.bp_usedw) >= 16'd255) begin
        saw_below_threshold_fill = 1'b1;
        break;
      end
    end
    if (!saw_below_threshold_fill) begin
      $error("sc_hub_tb_top: T425 BP FIFO never reached threshold-1 occupancy");
    end
    if (dut_inst.bp_half_full !== 1'b0) begin
      $error("sc_hub_tb_top: T425 bp_half_full asserted below the threshold act=%0b",
             dut_inst.bp_half_full);
    end
    if (link_ready !== 1'b1) begin
      $error("sc_hub_tb_top: T425 download_ready deasserted before the half-full threshold");
    end

    uplink_ready = 1'b1;
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h004250, 251);
  endtask

  task automatic run_t426();
    run_t079();
  endtask

  task automatic run_t218();
    sc_reply_t reply_queue_item;

    write_csr_word(16'h018, 32'h0000_0000);
    avmm_bfm_inst.set_default_rd_latency(2);
    avmm_bfm_inst.set_rd_latency_for_addr(16'h001A00, 50);
    avmm_bfm_inst.set_rd_latency_for_addr(16'h001A10, 2);
    avmm_bfm_inst.set_rd_latency_for_addr(16'h001A20, 35);
    avmm_bfm_inst.set_rd_latency_for_addr(16'h001A30, 12);

    driver_inst.send_read(24'h001A00, 1);
    driver_inst.send_read(24'h001A10, 1);
    driver_inst.send_read(24'h001A20, 1);
    driver_inst.send_read(24'h001A30, 1);

    monitor_inst.wait_reply(reply_queue_item);
    expect_read_reply(reply_queue_item, 24'h001A00, 1);
    monitor_inst.wait_reply(reply_queue_item);
    expect_read_reply(reply_queue_item, 24'h001A10, 1);
    monitor_inst.wait_reply(reply_queue_item);
    expect_read_reply(reply_queue_item, 24'h001A20, 1);
    monitor_inst.wait_reply(reply_queue_item);
    expect_read_reply(reply_queue_item, 24'h001A30, 1);
  endtask

  task automatic run_t220();
    logic [31:0] original_word;
    logic [31:0] expected_word;

    original_word = 32'h1234_5678;
    expected_word = (original_word & ~32'h0000_00FF) | (32'h0000_00AB & 32'h0000_00FF);
    avmm_bfm_inst.mem[16'h0000] = original_word;

    driver_inst.send_atomic_rmw(24'h000000, 32'h0000_00FF, 32'h0000_00AB,
                                SC_ORDER_RELAXED, 4'h0, 8'h00);
    monitor_inst.wait_reply(captured_reply);
    expect_atomic_ok_reply(captured_reply, 24'h000000, original_word,
                           SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00);
    if (avmm_bfm_inst.mem[16'h0000] !== expected_word) begin
      $error("sc_hub_tb_top: T220 atomic update mismatch exp=0x%08h act=0x%08h",
             expected_word,
             avmm_bfm_inst.mem[16'h0000]);
    end
  endtask

  task automatic run_t221();
    run_t442();
  endtask

  task automatic run_t222();
    logic [31:0] original_word;
    logic [31:0] expected_word;
    sc_reply_t   atomic_reply;
    sc_reply_t   read_reply;

    original_word = 32'h2222_00AA;
    expected_word = (original_word & ~32'h0000_00FF) | 32'h0000_0011;
    avmm_bfm_inst.mem[16'h0222] = original_word;
    avmm_bfm_inst.set_default_rd_latency(1);
    avmm_bfm_inst.set_rd_latency_for_addr(16'h0222, 50);

    driver_inst.send_atomic_rmw(24'h000222, 32'h0000_00FF, 32'h0000_0011,
                                SC_ORDER_RELAXED, 4'h0, 8'h00);
    wait_clks(4);
    driver_inst.send_read(24'h000222, 1);

    monitor_inst.wait_reply(atomic_reply);
    expect_atomic_ok_reply(atomic_reply, 24'h000222, original_word,
                           SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00);
    monitor_inst.wait_reply(read_reply);
    expect_single_word_reply(read_reply, 24'h000222, expected_word);
    if (avmm_bfm_inst.mem[16'h0222] !== expected_word) begin
      $error("sc_hub_tb_top: T222 atomic lock exclusion final value mismatch exp=0x%08h act=0x%08h",
             expected_word,
             avmm_bfm_inst.mem[16'h0222]);
    end

    avmm_bfm_inst.set_rd_latency_for_addr(16'h0222, 1);
  endtask

  task automatic run_t223();
    logic [31:0] original_word;
    logic [31:0] expected_word;
    sc_reply_t   csr_reply;
    sc_reply_t   atomic_reply;

    original_word = 32'h2233_00CC;
    expected_word = (original_word & ~32'h0000_00FF) | 32'h0000_005A;
    avmm_bfm_inst.mem[16'h0223] = original_word;
    avmm_bfm_inst.set_default_rd_latency(1);
    avmm_bfm_inst.set_rd_latency_for_addr(16'h0223, 50);

    driver_inst.send_atomic_rmw(24'h000223, 32'h0000_00FF, 32'h0000_005A,
                                SC_ORDER_RELAXED, 4'h0, 8'h00);
    wait_clks(4);
    driver_inst.send_read(csr_addr(16'h000), 1);

    monitor_inst.wait_reply(csr_reply);
    expect_single_word_reply(csr_reply, csr_addr(16'h000), HUB_UID_CONST);
    monitor_inst.wait_reply(atomic_reply);
    expect_atomic_ok_reply(atomic_reply, 24'h000223, original_word,
                           SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00);
    if (avmm_bfm_inst.mem[16'h0223] !== expected_word) begin
      $error("sc_hub_tb_top: T223 atomic+CSR bypass final value mismatch exp=0x%08h act=0x%08h",
             expected_word,
             avmm_bfm_inst.mem[16'h0223]);
    end

    avmm_bfm_inst.set_rd_latency_for_addr(16'h0223, 1);
  endtask

  task automatic run_t224();
    logic [31:0] original_word;

    original_word = 32'hCAFE_FEED;
    avmm_bfm_inst.mem[16'h0100] = original_word;
    inject_rd_error = 1'b1;
    driver_inst.send_atomic_rmw(24'h000100, 32'h0000_FFFF, 32'h0000_1234,
                                SC_ORDER_RELAXED, 4'h0, 8'h00);
    monitor_inst.wait_reply(captured_reply);
    inject_rd_error = 1'b0;

    expect_reply_header_rsp(captured_reply, 24'h000100, 1, 2'b10);
    expect_reply_metadata(captured_reply, SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00, 1'b1);
    if (captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T224 expected atomic read error to suppress payload, act_words=%0d",
             captured_reply.payload_words);
    end
    if (avmm_bfm_inst.mem[16'h0100] !== original_word) begin
      $error("sc_hub_tb_top: T224 atomic read error incorrectly modified memory exp=0x%08h act=0x%08h",
             original_word,
             avmm_bfm_inst.mem[16'h0100]);
    end
  endtask

  task automatic run_t225();
    logic [31:0] original_word;
    logic [31:0] expected_word;

    original_word = 32'hABCD_4321;
    expected_word = (original_word & ~32'h0000_FFFF) | (32'h0000_1234 & 32'h0000_FFFF);
    avmm_bfm_inst.mem[16'h0100] = original_word;

    driver_inst.send_atomic_rmw(24'h000100, 32'h0000_FFFF, 32'h0000_1234,
                                SC_ORDER_RELAXED, 4'h0, 8'h00);
    monitor_inst.wait_reply(captured_reply);
    expect_atomic_ok_reply(captured_reply, 24'h000100, original_word,
                           SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00);
    if (avmm_bfm_inst.mem[16'h0100] !== expected_word) begin
      $error("sc_hub_tb_top: T225 atomic reply-format test saw wrong post-write value exp=0x%08h act=0x%08h",
             expected_word,
             avmm_bfm_inst.mem[16'h0100]);
    end
  endtask


  task automatic run_t227();
    logic [31:0] original_word;
    logic [31:0] expected_word;

    original_word = 32'hFFFF_0000;
    expected_word = 32'h1234_5678;
    avmm_bfm_inst.mem[16'h0200] = original_word;

    driver_inst.send_atomic_rmw(24'h000200, 32'hFFFF_FFFF, 32'h1234_5678,
                                SC_ORDER_RELAXED, 4'h0, 8'h00);
    monitor_inst.wait_reply(captured_reply);
    expect_atomic_ok_reply(captured_reply, 24'h000200, original_word,
                           SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00);
    if (avmm_bfm_inst.mem[16'h0200] !== expected_word) begin
      $error("sc_hub_tb_top: T227 full-mask atomic overwrite mismatch exp=0x%08h act=0x%08h",
             expected_word,
             avmm_bfm_inst.mem[16'h0200]);
    end
  endtask

  task automatic run_t228();
    logic [31:0] original_word;

    original_word = 32'h55AA_00FF;
    avmm_bfm_inst.mem[16'h0200] = original_word;

    driver_inst.send_atomic_rmw(24'h000200, 32'h0000_0000, 32'hFFFF_FFFF,
                                SC_ORDER_RELAXED, 4'h0, 8'h00);
    monitor_inst.wait_reply(captured_reply);
    expect_atomic_ok_reply(captured_reply, 24'h000200, original_word,
                           SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00);
    if (avmm_bfm_inst.mem[16'h0200] !== original_word) begin
      $error("sc_hub_tb_top: T228 zero-mask atomic should be a no-op exp=0x%08h act=0x%08h",
             original_word,
             avmm_bfm_inst.mem[16'h0200]);
    end
  endtask

  task automatic run_t229();
    logic [31:0] original_word;
    logic [31:0] expected_word;

    original_word = 32'h0F0F_00F0;
    expected_word = (original_word & ~32'h0000_00FF) | (32'h0000_005A & 32'h0000_00FF);
    avmm_bfm_inst.mem[16'h0300] = original_word;

    driver_inst.send_atomic_rmw(24'h000300, 32'h0000_00FF, 32'h0000_005A,
                                SC_ORDER_RELAXED, 4'h0, 8'h00);
    monitor_inst.wait_reply(captured_reply);
    expect_atomic_ok_reply(captured_reply, 24'h000300, original_word,
                           SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00);
    if (avmm_bfm_inst.mem[16'h0300] !== expected_word) begin
      $error("sc_hub_tb_top: T229 relaxed atomic post-write mismatch exp=0x%08h act=0x%08h",
             expected_word,
             avmm_bfm_inst.mem[16'h0300]);
    end
  endtask

  task automatic run_t230();
    logic [31:0] normal_words[$];
    logic [31:0] ordered_words[$];
    longint unsigned normal_cycles;
    longint unsigned ordered_cycles;
    longint unsigned start_cycle;

    normal_words.push_back(32'h2300_0001);
    ordered_words.push_back(32'h2300_0002);

    start_cycle = cycle_counter;
    driver_inst.send_write(24'h000230, 1, normal_words);
    monitor_inst.wait_reply(captured_reply);
    normal_cycles = cycle_counter - start_cycle;
    expect_write_reply(captured_reply, 24'h000230, 1);

    start_cycle = cycle_counter;
    driver_inst.send_ordered_write(24'h000231, 1, ordered_words,
                                   SC_ORDER_RELAXED, 4'h0, 8'h00);
    monitor_inst.wait_reply(captured_reply);
    ordered_cycles = cycle_counter - start_cycle;
    expect_reply_header_rsp(captured_reply, 24'h000231, 1, 2'b00);
    expect_reply_metadata(captured_reply, SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00, 1'b0);
    if (captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T230 ordered RELAXED write unexpectedly returned payload");
    end
    if (ordered_cycles > (normal_cycles + 1)) begin
      $error("sc_hub_tb_top: T230 observed extra latency for RELAXED ordered write normal=%0d ordered=%0d",
             normal_cycles,
             ordered_cycles);
    end
  endtask

  task automatic run_t231();
    logic [31:0] wr_words[$];
    sc_reply_t   release_reply;

    for (int unsigned idx = 0; idx < 4; idx++) begin
      wr_words.delete();
      wr_words.push_back(32'h2310_0000 + idx);
      driver_inst.send_ordered_write(24'h000231 + idx, 1, wr_words,
                                     SC_ORDER_RELAXED, 4'h1, 8'h01 + idx);
    end
    wr_words.delete();
    driver_inst.send_ordered_write(24'h000235, 0, wr_words,
                                   SC_ORDER_RELEASE, 4'h1, 8'h10);

    for (int unsigned idx = 0; idx < 4; idx++) begin
      monitor_inst.wait_reply(captured_reply);
      expect_reply_header_rsp(captured_reply, 24'h000231 + idx, 1, 2'b00);
      expect_reply_metadata(captured_reply, SC_ORDER_RELAXED, 4'h1, 8'h01 + idx, 2'b00, 1'b0);
      if (captured_reply.payload_words != 0) begin
        $error("sc_hub_tb_top: T231 relaxed write reply unexpectedly returned payload at idx=%0d",
               idx);
      end
    end

    monitor_inst.wait_reply(release_reply);
    expect_reply_header_rsp(release_reply, 24'h000235, 0, 2'b00);
    expect_reply_metadata(release_reply, SC_ORDER_RELEASE, 4'h1, 8'h10, 2'b00, 1'b0);
    if (release_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T231 release barrier unexpectedly returned payload");
    end
  endtask

  task automatic run_t232();
    logic [31:0] wr_words[$];
    sc_reply_t   release_reply;

    for (int unsigned idx = 0; idx < 4; idx++) begin
      wr_words.delete();
      wr_words.push_back(32'h2320_0000 + idx);
      driver_inst.send_ordered_write(24'h000232 + idx, 1, wr_words,
                                     SC_ORDER_RELAXED, 4'h1, 8'h11 + idx);
    end
    wr_words.delete();
    driver_inst.send_ordered_write(24'h000236, 0, wr_words,
                                   SC_ORDER_RELEASE, 4'h1, 8'h20);
    for (int unsigned idx = 0; idx < 4; idx++) begin
      wr_words.delete();
      wr_words.push_back(32'h2321_0000 + idx);
      driver_inst.send_ordered_write(24'h000238 + idx, 1, wr_words,
                                     SC_ORDER_RELAXED, 4'h1, 8'h21 + idx);
    end

    for (int unsigned idx = 0; idx < 4; idx++) begin
      monitor_inst.wait_reply(captured_reply);
      expect_reply_header_rsp(captured_reply, 24'h000232 + idx, 1, 2'b00);
      expect_reply_metadata(captured_reply, SC_ORDER_RELAXED, 4'h1, 8'h11 + idx, 2'b00, 1'b0);
    end
    monitor_inst.wait_reply(release_reply);
    expect_reply_header_rsp(release_reply, 24'h000236, 0, 2'b00);
    expect_reply_metadata(release_reply, SC_ORDER_RELEASE, 4'h1, 8'h20, 2'b00, 1'b0);
    if (release_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T232 release barrier unexpectedly returned payload");
    end
    for (int unsigned idx = 0; idx < 4; idx++) begin
      monitor_inst.wait_reply(captured_reply);
      expect_reply_header_rsp(captured_reply, 24'h000238 + idx, 1, 2'b00);
      expect_reply_metadata(captured_reply, SC_ORDER_RELAXED, 4'h1, 8'h21 + idx, 2'b00, 1'b0);
    end
  endtask

  task automatic run_t233();
    sc_reply_t acquire_reply;
    sc_reply_t relaxed_reply;

    avmm_bfm_inst.set_default_rd_latency(2);
    avmm_bfm_inst.set_rd_latency_for_addr(16'h0233, 50);

    driver_inst.send_ordered_read(24'h000233, 1, SC_ORDER_ACQUIRE, 4'h2, 8'h01);
    for (int unsigned idx = 0; idx < 10; idx++) begin
      driver_inst.send_ordered_read(24'h000240 + idx, 1, SC_ORDER_RELAXED, 4'h2, 8'h10 + idx);
    end

    monitor_inst.wait_reply(acquire_reply);
    expect_reply_header_rsp(acquire_reply, 24'h000233, 1, 2'b00);
    expect_reply_metadata(acquire_reply, SC_ORDER_ACQUIRE, 4'h2, 8'h01, 2'b00, 1'b0);
    if (acquire_reply.payload_words != 1 ||
        acquire_reply.payload[0] !== expected_bus_word(24'h000233, 0)) begin
      $error("sc_hub_tb_top: T233 acquire payload mismatch words=%0d data=0x%08h",
             acquire_reply.payload_words,
             acquire_reply.payload[0]);
    end

    for (int unsigned idx = 0; idx < 10; idx++) begin
      monitor_inst.wait_reply(relaxed_reply);
      expect_reply_header_rsp(relaxed_reply, 24'h000240 + idx, 1, 2'b00);
      expect_reply_metadata(relaxed_reply, SC_ORDER_RELAXED, 4'h2, 8'h10 + idx, 2'b00, 1'b0);
      if (relaxed_reply.payload_words != 1 ||
          relaxed_reply.payload[0] !== expected_bus_word(24'h000240 + idx, 0)) begin
        $error("sc_hub_tb_top: T233 younger read payload mismatch idx=%0d words=%0d data=0x%08h",
               idx,
               relaxed_reply.payload_words,
               relaxed_reply.payload[0]);
      end
    end

    avmm_bfm_inst.set_default_rd_latency(1);
  endtask

  task automatic run_t234();
    logic [31:0] wr_words[$];
    sc_reply_t   release_reply;
    sc_reply_t   acquire_reply;

    wr_words.push_back(32'h2340_0001);
    driver_inst.send_ordered_write(24'h000234, 1, wr_words,
                                   SC_ORDER_RELEASE, 4'h1, 8'h21);
    monitor_inst.wait_reply(release_reply);
    expect_reply_header_rsp(release_reply, 24'h000234, 1, 2'b00);
    expect_reply_metadata(release_reply, SC_ORDER_RELEASE, 4'h1, 8'h21, 2'b00, 1'b0);
    if (release_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T234 release write unexpectedly returned payload");
    end

    driver_inst.send_ordered_read(24'h000234, 1, SC_ORDER_ACQUIRE, 4'h1, 8'h22);
    monitor_inst.wait_reply(acquire_reply);
    expect_reply_header_rsp(acquire_reply, 24'h000234, 1, 2'b00);
    expect_reply_metadata(acquire_reply, SC_ORDER_ACQUIRE, 4'h1, 8'h22, 2'b00, 1'b0);
    if (acquire_reply.payload_words != 1 || acquire_reply.payload[0] !== wr_words[0]) begin
      $error("sc_hub_tb_top: T234 acquire did not observe prior release write exp=0x%08h act_words=%0d act=0x%08h",
             wr_words[0],
             acquire_reply.payload_words,
             acquire_reply.payload[0]);
    end
  endtask

  task automatic run_t235();
    sc_reply_t reply;
    bit        seen_cross[0:3];
    int        acquire_pos;

    avmm_bfm_inst.set_default_rd_latency(2);
    avmm_bfm_inst.set_rd_latency_for_addr(16'h0235, 100);
    for (int unsigned idx = 0; idx < 4; idx++) begin
      seen_cross[idx] = 1'b0;
    end

    driver_inst.send_ordered_read(24'h000235, 1, SC_ORDER_ACQUIRE, 4'h0, 8'h01);
    for (int unsigned idx = 0; idx < 4; idx++) begin
      driver_inst.send_ordered_read(24'h000250 + (idx * 16), 1,
                                    SC_ORDER_RELAXED, 4'h1, 8'h10 + idx);
    end

    acquire_pos = -1;
    for (int unsigned idx = 0; idx < 5; idx++) begin
      monitor_inst.wait_reply(reply);
      if (reply.start_address == 24'h000235) begin
        acquire_pos = idx;
        expect_reply_header_rsp(reply, 24'h000235, 1, 2'b00);
        expect_reply_metadata(reply, SC_ORDER_ACQUIRE, 4'h0, 8'h01, 2'b00, 1'b0);
      end else begin
        int unsigned dom1_idx;
        if (reply.start_address < 24'h000250 || reply.start_address > 24'h000280) begin
          $error("sc_hub_tb_top: T235 unexpected cross-domain reply addr=0x%06h", reply.start_address);
        end
        dom1_idx = (reply.start_address - 24'h000250) / 16;
        if (dom1_idx > 3) begin
          $error("sc_hub_tb_top: T235 computed invalid cross-domain reply index=%0d addr=0x%06h",
                 dom1_idx, reply.start_address);
        end else begin
          if (seen_cross[dom1_idx]) begin
            $error("sc_hub_tb_top: T235 duplicate cross-domain reply for idx=%0d addr=0x%06h",
                   dom1_idx, reply.start_address);
          end
          seen_cross[dom1_idx] = 1'b1;
          expect_reply_header_rsp(reply, 24'h000250 + (dom1_idx * 16), 1, 2'b00);
          expect_reply_metadata(reply, SC_ORDER_RELAXED, 4'h1, 8'h10 + dom1_idx, 2'b00, 1'b0);
        end
      end
    end

    if (acquire_pos != 4) begin
      $error("sc_hub_tb_top: T235 expected all cross-domain RELAXED replies before the slow ACQUIRE (acquire_pos=%0d)",
             acquire_pos);
    end
    for (int unsigned idx = 0; idx < 4; idx++) begin
      if (!seen_cross[idx]) begin
        $error("sc_hub_tb_top: T235 missing cross-domain reply idx=%0d", idx);
      end
    end

    avmm_bfm_inst.set_default_rd_latency(1);
  endtask

  task automatic run_t236();
    logic [31:0] wr_words[$];
    logic [31:0] expected_word;
    sc_reply_t   release_reply;
    sc_reply_t   atomic_reply;

    wr_words.push_back(32'h2360_00AA);
    expected_word = (wr_words[0] & ~32'h0000_FF00) | 32'h0000_5500;
    driver_inst.send_ordered_write(24'h000236, 1, wr_words,
                                   SC_ORDER_RELEASE, 4'h1, 8'h31);
    monitor_inst.wait_reply(release_reply);
    expect_reply_header_rsp(release_reply, 24'h000236, 1, 2'b00);
    expect_reply_metadata(release_reply, SC_ORDER_RELEASE, 4'h1, 8'h31, 2'b00, 1'b0);

    driver_inst.send_atomic_rmw(24'h000236, 32'h0000_FF00, 32'h0000_5500,
                                SC_ORDER_RELAXED, 4'h1, 8'h32);
    monitor_inst.wait_reply(atomic_reply);
    expect_atomic_ok_reply(atomic_reply, 24'h000236, wr_words[0],
                           SC_ORDER_RELAXED, 4'h1, 8'h32, 2'b00);
    if (avmm_bfm_inst.mem[16'h0236] !== expected_word) begin
      $error("sc_hub_tb_top: T236 release+atomic combined mismatch exp=0x%08h act=0x%08h",
             expected_word,
             avmm_bfm_inst.mem[16'h0236]);
    end
  endtask

  task automatic run_t241();
    logic [31:0] wr_words[$];
    sc_reply_t   release_reply;

    driver_inst.send_ordered_read(24'h000241, 1, SC_ORDER_RELAXED, 4'h1, 8'h01);
    driver_inst.send_ordered_read(24'h000242, 1, SC_ORDER_RELAXED, 4'h1, 8'h02);
    wr_words.delete();
    driver_inst.send_ordered_write(24'h000243, 0, wr_words,
                                   SC_ORDER_RELEASE, 4'h1, 8'h03);
    driver_inst.send_ordered_read(24'h000244, 1, SC_ORDER_RELAXED, 4'h1, 8'h04);

    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h000241, 1, 2'b00);
    expect_reply_metadata(captured_reply, SC_ORDER_RELAXED, 4'h1, 8'h01, 2'b00, 1'b0);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h000242, 1, 2'b00);
    expect_reply_metadata(captured_reply, SC_ORDER_RELAXED, 4'h1, 8'h02, 2'b00, 1'b0);
    monitor_inst.wait_reply(release_reply);
    expect_reply_header_rsp(release_reply, 24'h000243, 0, 2'b00);
    expect_reply_metadata(release_reply, SC_ORDER_RELEASE, 4'h1, 8'h03, 2'b00, 1'b0);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h000244, 1, 2'b00);
    expect_reply_metadata(captured_reply, SC_ORDER_RELAXED, 4'h1, 8'h04, 2'b00, 1'b0);
  endtask

  task automatic run_t242();
    sc_reply_t acquire_reply;
    sc_reply_t relaxed_reply;
    bit        saw_second_launch_before_first_done;
    logic [15:0] first_launch_addr;
    logic [15:0] second_launch_addr;
    time       first_launch_time;
    time       second_launch_time;
    time       first_done_time;
    int unsigned wait_cycles;

    avmm_bfm_inst.set_default_rd_latency(2);

    driver_inst.send_ordered_read(24'h000242, 1, SC_ORDER_ACQUIRE, 4'h1, 8'h01);
    driver_inst.send_ordered_read(24'h000243, 1, SC_ORDER_RELAXED, 4'h1, 8'h02);

    wait_avalon_read_pulse("T242 first launch");
    first_launch_addr = avm_address;
    first_launch_time = $time;
    first_done_time   = 0;
    second_launch_time = 0;
    second_launch_addr = '0;
    saw_second_launch_before_first_done = 1'b0;
    wait_cycles = 0;

    while (first_done_time == 0 && wait_cycles < 128) begin
      @(posedge clk);
      wait_cycles++;
      if (avm_readdatavalid === 1'b1) begin
        first_done_time = $time;
      end
      if (first_done_time == 0 && avm_read === 1'b1) begin
        saw_second_launch_before_first_done = 1'b1;
        second_launch_addr = avm_address;
        second_launch_time = $time;
      end
    end
    if (first_launch_addr !== 16'h0242) begin
      $error("sc_hub_tb_top: T242 expected first launch to target 0x0242 act=0x%04h at %0t",
             first_launch_addr,
             first_launch_time);
    end
    if (first_done_time == 0) begin
      $error("sc_hub_tb_top: T242 timed out waiting for acquire completion after first launch at %0t",
             first_launch_time);
    end
    if (saw_second_launch_before_first_done) begin
      $error("sc_hub_tb_top: T242 younger same-domain read launched before acquire completed first=0x%04h@%0t second=0x%04h@%0t",
             first_launch_addr,
             first_launch_time,
             second_launch_addr,
             second_launch_time);
    end

    monitor_inst.wait_reply(acquire_reply);
    expect_reply_header_rsp(acquire_reply, 24'h000242, 1, 2'b00);
    expect_reply_metadata(acquire_reply, SC_ORDER_ACQUIRE, 4'h1, 8'h01, 2'b00, 1'b0);
    monitor_inst.wait_reply(relaxed_reply);
    expect_reply_header_rsp(relaxed_reply, 24'h000243, 1, 2'b00);
    expect_reply_metadata(relaxed_reply, SC_ORDER_RELAXED, 4'h1, 8'h02, 2'b00, 1'b0);

  endtask


  task automatic run_t244();
    logic [31:0] wr_words[$];
    sc_reply_t   release_reply;

    force dut_inst.bus_cmd_ready = 1'b0;
    for (int unsigned idx = 0; idx < 4; idx++) begin
      wr_words.delete();
      wr_words.push_back(32'h2440_0000 + idx);
      driver_inst.send_ordered_write(24'h000244 + idx, 1, wr_words,
                                     SC_ORDER_RELAXED, 4'h1, 8'h40 + idx);
    end
    wr_words.delete();
    driver_inst.send_ordered_write(24'h000248, 0, wr_words,
                                   SC_ORDER_RELEASE, 4'h1, 8'h44);
    wait_avalon_tracked_count(5, "T244 queued writes");
    monitor_inst.assert_no_reply(200ns);

    release dut_inst.bus_cmd_ready;
    for (int unsigned idx = 0; idx < 4; idx++) begin
      monitor_inst.wait_reply(captured_reply);
      expect_reply_header_rsp(captured_reply, 24'h000244 + idx, 1, 2'b00);
      expect_reply_metadata(captured_reply, SC_ORDER_RELAXED, 4'h1, 8'h40 + idx, 2'b00, 1'b0);
    end
    monitor_inst.wait_reply(release_reply);
    expect_reply_header_rsp(release_reply, 24'h000248, 0, 2'b00);
    expect_reply_metadata(release_reply, SC_ORDER_RELEASE, 4'h1, 8'h44, 2'b00, 1'b0);
  endtask

  task automatic run_t245();
    sc_reply_t reply;
    bit        seen_domain[0:15];
    int        acquire_pos;

    avmm_bfm_inst.set_default_rd_latency(2);
    avmm_bfm_inst.set_rd_latency_for_addr(16'h0245, 100);

    for (int unsigned idx = 0; idx < 16; idx++) begin
      seen_domain[idx] = 1'b0;
    end

    driver_inst.send_ordered_read(24'h000245, 1, SC_ORDER_ACQUIRE, 4'h0, 8'h01);
    for (int unsigned idx = 1; idx < 16; idx++) begin
      driver_inst.send_ordered_read(24'h000300 + (idx * 16), 1,
                                    SC_ORDER_RELAXED, idx[3:0], 8'h20 + idx);
    end

    acquire_pos = -1;
    for (int unsigned idx = 0; idx < 16; idx++) begin
      monitor_inst.wait_reply(reply);
      if (reply.start_address == 24'h000245) begin
        acquire_pos    = idx;
        seen_domain[0] = 1'b1;
        expect_reply_header_rsp(reply, 24'h000245, 1, 2'b00);
        expect_reply_metadata(reply, SC_ORDER_ACQUIRE, 4'h0, 8'h01, 2'b00, 1'b0);
      end else begin
        int unsigned dom_idx;
        dom_idx = (reply.start_address - 24'h000300) / 16;
        if (dom_idx == 0 || dom_idx > 15) begin
          $error("sc_hub_tb_top: T245 unexpected cross-domain reply addr=0x%06h",
                 reply.start_address);
        end else begin
          if (seen_domain[dom_idx]) begin
            $error("sc_hub_tb_top: T245 duplicate reply for ordering domain %0d addr=0x%06h",
                   dom_idx, reply.start_address);
          end
          seen_domain[dom_idx] = 1'b1;
          expect_reply_header_rsp(reply, 24'h000300 + (dom_idx * 16), 1, 2'b00);
          expect_reply_metadata(reply, SC_ORDER_RELAXED, dom_idx[3:0], 8'h20 + dom_idx, 2'b00, 1'b0);
        end
      end
    end

    if (acquire_pos != 15) begin
      $error("sc_hub_tb_top: T245 expected the slow dom0 ACQUIRE to retire last (acquire_pos=%0d)",
             acquire_pos);
    end
    for (int unsigned idx = 0; idx < 16; idx++) begin
      if (!seen_domain[idx]) begin
        $error("sc_hub_tb_top: T245 missing reply for ordering domain %0d", idx);
      end
    end

    avmm_bfm_inst.set_default_rd_latency(1);
  endtask

  task automatic run_t248();
    logic [31:0] csr_word;

    if (!AVALON_DUT_OOO_ENABLE) begin
      $error("sc_hub_tb_top: T248 requires SC_HUB_TB_AVALON_OOO_ENABLED and OOO_ENABLE=true");
    end

    write_csr_word(16'h018, 32'h0000_0001);
    read_csr_word(16'h018, csr_word);
    if (csr_word !== 32'h0000_0001) begin
      $error("sc_hub_tb_top: T248 expected OOO_CTRL readback=1 after enable write act=0x%08h",
             csr_word);
    end
    driver_inst.send_read(24'h000248, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000248, 1);

    write_csr_word(16'h018, 32'h0000_0000);
    read_csr_word(16'h018, csr_word);
    if (csr_word !== 32'h0000_0000) begin
      $error("sc_hub_tb_top: T248 expected OOO_CTRL readback=0 after disable write act=0x%08h",
             csr_word);
    end
    driver_inst.send_read(24'h000249, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000249, 1);
  endtask

  task automatic run_t427();
    if (AVALON_DUT_OUTSTANDING_LIMIT != 1 || AVALON_DUT_OUTSTANDING_INT_RESERVED != 0) begin
      $error("sc_hub_tb_top: T427 requires OUTSTANDING_LIMIT=1 and OUTSTANDING_INT_RESERVED=0, act_limit=%0d act_reserved=%0d",
             AVALON_DUT_OUTSTANDING_LIMIT,
             AVALON_DUT_OUTSTANDING_INT_RESERVED);
    end

    for (int unsigned idx = 0; idx < 10; idx++) begin
      driver_inst.send_read(24'h004270 + idx, 1);
      monitor_inst.wait_reply(captured_reply);
      expect_read_reply(captured_reply, 24'h004270 + idx, 1);
      if (dut_inst.core_inst.tracked_pkt_count > 1) begin
        $error("sc_hub_tb_top: T427 expected at most one tracked packet act=%0d",
               dut_inst.core_inst.tracked_pkt_count);
      end
    end
  endtask

  task automatic run_t428();
    logic [31:0] wr_words[$];
    logic [31:0] original_words[$];
    sc_reply_t   reply;
    bit          saw_write_ack;
    bit          saw_ext_read;
    bit          saw_csr_read;
    int unsigned waited_cycles;

    fill_write_words(wr_words, 64, 32'h4280_0000);
    read_bfm_words(24'h004280, 64, original_words);

    saw_write_ack = 1'b0;
    saw_ext_read  = 1'b0;
    saw_csr_read  = 1'b0;

    force dut_inst.bus_cmd_ready = 1'b0;
    fork
      begin
        send_stalled_avalon_write(24'h004280, 64, 32'h4280_0000);
      end
    join_none

    waited_cycles = 0;
    while (dut_inst.dl_fifo_usedw < 10'd64 && waited_cycles < 512) begin
      @(posedge clk);
      waited_cycles++;
    end
    if (dut_inst.dl_fifo_usedw != 10'd64) begin
      $error("sc_hub_tb_top: T428 expected dl_fifo_usedw=64 under stalled external write act=%0d",
             dut_inst.dl_fifo_usedw);
    end

    driver_inst.send_read(24'h0042F0, 1);
    driver_inst.send_read(csr_addr(16'h000), 1);
    wait_avalon_tracked_count(3, "T428 mixed queued traffic");

    force_avalon_bp_usedw(460);
    wait_clks(4);

    release dut_inst.bus_cmd_ready;
    release_avalon_bp_usedw();

    for (int unsigned idx = 0; idx < 3; idx++) begin
      monitor_inst.wait_reply(reply);
      if (reply.start_address == 24'h004280) begin
        expect_write_reply(reply, 24'h004280, 64);
        saw_write_ack = 1'b1;
      end else if (reply.start_address == 24'h0042F0) begin
        expect_read_reply(reply, 24'h0042F0, 1);
        saw_ext_read = 1'b1;
      end else if (reply.start_address == csr_addr(16'h000)) begin
        expect_single_word_reply(reply, csr_addr(16'h000), HUB_UID_CONST);
        saw_csr_read = 1'b1;
      end else begin
        $error("sc_hub_tb_top: T428 unexpected reply addr=0x%06h len=%0d rsp=%0b",
               reply.start_address,
               reply.echoed_length,
               reply.response);
      end
    end

    if (!saw_write_ack || !saw_ext_read || !saw_csr_read) begin
      $error("sc_hub_tb_top: T428 missing mixed-traffic replies write=%0b ext_read=%0b csr=%0b",
             saw_write_ack,
             saw_ext_read,
             saw_csr_read);
    end

    waited_cycles = 0;
    while ((dut_inst.bp_usedw != 0 || dut_inst.dl_fifo_usedw != 0 ||
            dut_inst.core_inst.tracked_pkt_count != 0) && waited_cycles < 2048) begin
      @(posedge clk);
      waited_cycles++;
    end
    if (dut_inst.bp_usedw != 0 || dut_inst.dl_fifo_usedw != 0 ||
        dut_inst.core_inst.tracked_pkt_count != 0) begin
      $error("sc_hub_tb_top: T428 expected mixed-pressure drain to quiesce bp=%0d dl=%0d tracked=%0d",
             dut_inst.bp_usedw,
             dut_inst.dl_fifo_usedw,
             dut_inst.core_inst.tracked_pkt_count);
    end
    check_bfm_words(24'h004280, wr_words);
  endtask

  task automatic run_t429();
    sc_cmd_t      write_cmd;
    logic [31:0]  wr_words[$];
    logic [31:0]  original_words[$];
    logic [15:0]  pkt_drop_before;
    logic [15:0]  pkt_drop_after;
    int unsigned  dl_usedw_before;
    int unsigned  dl_usedw_after;

    fill_write_words(wr_words, 4, 32'h4290_0000);
    read_bfm_words(24'h004290, 4, original_words);
    write_cmd = make_cmd(SC_WRITE, 24'h004290, 4);
    foreach (wr_words[idx]) begin
      write_cmd.data_words[idx] = wr_words[idx];
    end

    pkt_drop_before = dut_inst.pkt_drop_count;
    dl_usedw_before = dut_inst.dl_fifo_usedw;

    driver_inst.drive_word(make_preamble_word(write_cmd), 4'b0001);
    driver_inst.drive_word(make_addr_word(write_cmd), 4'b0000);
    driver_inst.drive_word(make_length_word(write_cmd), 4'b0000);
    foreach (wr_words[idx]) begin
      driver_inst.drive_word(wr_words[idx], 4'b0000);
    end

    force dut_inst.pkt_rx_inst.pkt_queue_count = 16;
    wait_clks(1);
    driver_inst.drive_word_ignore_ready({24'h0, K284_CONST}, 4'b0001);
    release dut_inst.pkt_rx_inst.pkt_queue_count;
    driver_inst.drive_idle();

    wait_clks(8);
    dl_usedw_after = dut_inst.dl_fifo_usedw;
    pkt_drop_after = dut_inst.pkt_drop_count;
    monitor_inst.assert_no_reply(200ns);

    if (dl_usedw_after !== dl_usedw_before) begin
      $error("sc_hub_tb_top: T429 expected payload revert on header push failure usedw_before=%0d usedw_after=%0d",
             dl_usedw_before,
             dl_usedw_after);
    end
    if (pkt_drop_after !== pkt_drop_before + 1) begin
      $error("sc_hub_tb_top: T429 expected PKT_DROP_CNT increment on header push failure before=%0d after=%0d",
             pkt_drop_before,
             pkt_drop_after);
    end
    check_bfm_words(24'h004290, original_words);
  endtask

  task automatic run_t434();
    logic [31:0] wr_words[$];

    driver_inst.send_ordered_write(24'h004340, 0, wr_words,
                                   SC_ORDER_RELEASE, 4'h1, 8'h34);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h004340, 0, 2'b00);
    expect_reply_metadata(captured_reply, SC_ORDER_RELEASE, 4'h1, 8'h34, 2'b00, 1'b0);
    if (captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T434 pure release barrier unexpectedly returned payload");
    end
  endtask

  task automatic run_t435();
    clear_hub_counters();
    inject_decode_error = 1'b1;
    driver_inst.send_ordered_read(24'h004350, 1, SC_ORDER_ACQUIRE, 4'h1, 8'h35);
    monitor_inst.wait_reply(captured_reply);
    inject_decode_error = 1'b0;

    expect_reply_header_rsp(captured_reply, 24'h004350, 1, 2'b11);
    expect_reply_metadata(captured_reply, SC_ORDER_ACQUIRE, 4'h1, 8'h35, 2'b00, 1'b0);
    if (captured_reply.payload_words != 1 || captured_reply.payload[0] !== 32'hDEAD_BEEF) begin
      $error("sc_hub_tb_top: T435 expected DECODEERROR acquire reply payload act_words=%0d act=0x%08h",
             captured_reply.payload_words,
             captured_reply.payload[0]);
    end

    driver_inst.send_ordered_read(24'h004351, 1, SC_ORDER_RELAXED, 4'h1, 8'h36);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h004351, 1, 2'b00);
    expect_reply_metadata(captured_reply, SC_ORDER_RELAXED, 4'h1, 8'h36, 2'b00, 1'b0);
    expect_err_flag_and_count(HUB_ERR_DECERR_BIT, 32'h0000_0001, "T435");
  endtask

  task automatic run_t436();
    sc_cmd_t         cmd;
    logic [31:0]     words[$];
    logic [3:0]      dataks[$];
    logic [31:0]     addr_word;

    cmd = make_cmd(SC_READ, 24'h004360, 1);
    addr_word = make_addr_word(cmd);
    addr_word[31:30] = 2'b11;

    words.push_back(make_preamble_word(cmd));
    dataks.push_back(4'b0001);
    words.push_back(addr_word);
    dataks.push_back(4'b0000);
    words.push_back(make_length_word(cmd));
    dataks.push_back(4'b0000);
    words.push_back({24'h0, K284_CONST});
    dataks.push_back(4'b0001);

    driver_inst.send_raw(words, dataks);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h004360, 1, 2'b00);
    expect_reply_metadata(captured_reply, SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00, 1'b0);
    if (captured_reply.payload_words != 1 ||
        captured_reply.payload[0] !== expected_bus_word(24'h004360, 0)) begin
      $error("sc_hub_tb_top: T436 reserved ORDER packet did not collapse to RELAXED semantics");
    end
  endtask

  task automatic run_t437();
    run_t245();
  endtask

  task automatic run_t438();
    sc_reply_t reply;
    logic [7:0] expected_epoch[0:3];

    expected_epoch[0] = 8'hFE;
    expected_epoch[1] = 8'hFF;
    expected_epoch[2] = 8'h00;
    expected_epoch[3] = 8'h01;

    driver_inst.send_ordered_read(24'h000438, 1, SC_ORDER_RELAXED, 4'h1, expected_epoch[0]);
    driver_inst.send_ordered_read(24'h000448, 1, SC_ORDER_RELAXED, 4'h1, expected_epoch[1]);
    driver_inst.send_ordered_read(24'h000458, 1, SC_ORDER_RELAXED, 4'h1, expected_epoch[2]);
    driver_inst.send_ordered_read(24'h000468, 1, SC_ORDER_RELAXED, 4'h1, expected_epoch[3]);

    for (int unsigned idx = 0; idx < 4; idx++) begin
      monitor_inst.wait_reply(reply);
      expect_reply_header_rsp(reply, 24'h000438 + (idx * 16), 1, 2'b00);
      expect_reply_metadata(reply, SC_ORDER_RELAXED, 4'h1, expected_epoch[idx], 2'b00, 1'b0);
    end
  endtask

  task automatic run_t439();
    sc_cmd_t      release_cmd;
    logic [31:0]  wr_words[$];
    logic [31:0]  original_words[$];
    logic [15:0]  pkt_drop_before;
    logic [15:0]  pkt_drop_after;
    logic [31:0]  ord_drain_before;
    logic [31:0]  ord_drain_after;
    int unsigned  dl_usedw_before;
    int unsigned  dl_usedw_after;

    fill_write_words(wr_words, 4, 32'h4390_0000);
    read_bfm_words(24'h004390, 4, original_words);
    release_cmd = make_ordered_cmd(SC_WRITE, 24'h004390, 4,
                                   SC_ORDER_RELEASE, 4'h3, 8'h39);
    foreach (wr_words[idx]) begin
      release_cmd.data_words[idx] = wr_words[idx];
    end

    pkt_drop_before = dut_inst.pkt_drop_count;
    ord_drain_before = dut_inst.core_inst.ord_drain_count;
    dl_usedw_before = dut_inst.dl_fifo_usedw;

    driver_inst.drive_word(make_preamble_word(release_cmd), 4'b0001);
    driver_inst.drive_word(make_addr_word(release_cmd), 4'b0000);
    driver_inst.drive_word(make_length_word(release_cmd), 4'b0000);
    foreach (wr_words[idx]) begin
      driver_inst.drive_word(wr_words[idx], 4'b0000);
    end

    force dut_inst.pkt_rx_inst.pkt_queue_count = 16;
    wait_clks(1);
    driver_inst.drive_word_ignore_ready({24'h0, K284_CONST}, 4'b0001);
    release dut_inst.pkt_rx_inst.pkt_queue_count;
    driver_inst.drive_idle();

    wait_clks(8);
    dl_usedw_after = dut_inst.dl_fifo_usedw;
    pkt_drop_after = dut_inst.pkt_drop_count;
    monitor_inst.assert_no_reply(200ns);

    if (dl_usedw_after !== dl_usedw_before) begin
      $error("sc_hub_tb_top: T439 expected payload revert on RELEASE header push failure usedw_before=%0d usedw_after=%0d",
             dl_usedw_before,
             dl_usedw_after);
    end
    if (pkt_drop_after !== pkt_drop_before + 1) begin
      $error("sc_hub_tb_top: T439 expected PKT_DROP_CNT increment on dropped RELEASE before=%0d after=%0d",
             pkt_drop_before,
             pkt_drop_after);
    end
    check_bfm_words(24'h004390, original_words);
    ord_drain_after = dut_inst.core_inst.ord_drain_count;
    if (ord_drain_after !== ord_drain_before) begin
      $error("sc_hub_tb_top: T439 dropped RELEASE should not arm ordering drain before=%0d after=%0d",
             ord_drain_before,
             ord_drain_after);
    end
  endtask

  task automatic run_t440();
    logic [31:0] original_word;
    logic [31:0] expected_word;
    sc_reply_t   read_reply;
    sc_reply_t   atomic_reply;

    original_word = 32'h4400_00AA;
    expected_word = (original_word & ~32'h0000_FF00) | 32'h0000_5500;
    avmm_bfm_inst.mem[16'h0440] = original_word;
    avmm_bfm_inst.set_default_rd_latency(1);
    avmm_bfm_inst.set_rd_latency_for_addr(16'h0440, 50);

    driver_inst.send_read(24'h000440, 1);
    wait_clks(4);
    driver_inst.send_atomic_rmw(24'h000440, 32'h0000_FF00, 32'h0000_5500,
                                SC_ORDER_RELAXED, 4'h0, 8'h00);

    monitor_inst.wait_reply(read_reply);
    expect_single_word_reply(read_reply, 24'h000440, original_word);
    monitor_inst.wait_reply(atomic_reply);
    expect_atomic_ok_reply(atomic_reply, 24'h000440, original_word,
                           SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00);
    if (avmm_bfm_inst.mem[16'h0440] !== expected_word) begin
      $error("sc_hub_tb_top: T440 read-then-atomic final value mismatch exp=0x%08h act=0x%08h",
             expected_word,
             avmm_bfm_inst.mem[16'h0440]);
    end

    avmm_bfm_inst.set_rd_latency_for_addr(16'h0440, 1);
  endtask

  task automatic run_t441();
    logic [31:0] original_word;

    original_word = 32'h4410_0001;
    avmm_bfm_inst.mem[16'h0441] = original_word;
    clear_hub_counters();
    avmm_bfm_inst.set_default_rd_latency(1);
    avmm_bfm_inst.set_rd_latency_for_addr(16'h0441, 300);

    driver_inst.send_atomic_rmw(24'h000441, 32'h0000_FFFF, 32'h0000_005A,
                                SC_ORDER_RELAXED, 4'h0, 8'h00);
    monitor_inst.wait_reply(captured_reply);

    expect_reply_header_rsp(captured_reply, 24'h000441, 1, 2'b11);
    expect_reply_metadata(captured_reply, SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00, 1'b1);
    if (captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T441 expected timed-out atomic reply without payload");
    end
    if (avmm_bfm_inst.mem[16'h0441] !== original_word) begin
      $error("sc_hub_tb_top: T441 timed-out atomic should not modify memory exp=0x%08h act=0x%08h",
             original_word,
             avmm_bfm_inst.mem[16'h0441]);
    end
    expect_err_flag_and_count(HUB_ERR_RD_TIMEOUT_BIT, 32'h0000_0001, "T441");
    avmm_bfm_inst.set_rd_latency_for_addr(16'h0441, 1);
  endtask

  task automatic run_t442();
    logic [31:0] original_word;
    logic [31:0] first_expected_word;
    logic [31:0] second_expected_word;
    sc_reply_t   first_reply;
    sc_reply_t   second_reply;

    original_word       = 32'h0000_0000;
    first_expected_word = (original_word & ~32'h0000_00FF) | 32'h0000_0011;
    second_expected_word = (first_expected_word & ~32'h0000_FF00) | 32'h0000_2200;
    avmm_bfm_inst.mem[16'h0442] = original_word;

    driver_inst.send_atomic_rmw(24'h000442, 32'h0000_00FF, 32'h0000_0011,
                                SC_ORDER_RELAXED, 4'h0, 8'h00);
    driver_inst.send_atomic_rmw(24'h000442, 32'h0000_FF00, 32'h0000_2200,
                                SC_ORDER_RELAXED, 4'h0, 8'h00);

    monitor_inst.wait_reply(first_reply);
    expect_atomic_ok_reply(first_reply, 24'h000442, original_word,
                           SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00);
    monitor_inst.wait_reply(second_reply);
    expect_atomic_ok_reply(second_reply, 24'h000442, first_expected_word,
                           SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00);

    if (avmm_bfm_inst.mem[16'h0442] !== second_expected_word) begin
      $error("sc_hub_tb_top: T442 chained atomic mismatch exp=0x%08h act=0x%08h",
             second_expected_word,
             avmm_bfm_inst.mem[16'h0442]);
    end
  endtask

  task automatic run_t443();
    logic [31:0] wr_words[$];
    logic [31:0] scratch_word;
    sc_reply_t   csr_read_reply;
    sc_reply_t   csr_write_reply;

    wr_words.push_back(32'h4430_0001);
    driver_inst.send_read(csr_addr(16'h000), 1);
    driver_inst.send_write(csr_addr(16'h006), 1, wr_words);

    monitor_inst.wait_reply(csr_read_reply);
    expect_single_word_reply(csr_read_reply, csr_addr(16'h000), HUB_UID_CONST);
    monitor_inst.wait_reply(csr_write_reply);
    expect_write_reply(csr_write_reply, csr_addr(16'h006), 1);

    read_csr_word(16'h006, scratch_word);
    if (scratch_word !== wr_words[0]) begin
      $error("sc_hub_tb_top: T443 scratch CSR write did not complete after back-to-back internal slot use exp=0x%08h act=0x%08h",
             wr_words[0],
             scratch_word);
    end
  endtask

  task automatic run_t237();
    driver_inst.send_ordered_read(24'h000000, 1, SC_ORDER_ACQUIRE, 4'h3, 8'd42);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h000000, 1, 2'b00);
    expect_reply_metadata(captured_reply, SC_ORDER_ACQUIRE, 4'h3, 8'd42, 2'b00, 1'b0);
    if (captured_reply.payload_words != 1 ||
        captured_reply.payload[0] !== expected_bus_word(24'h000000, 0)) begin
      $error("sc_hub_tb_top: T237 acquire reply payload mismatch words=%0d data=0x%08h",
             captured_reply.payload_words,
             captured_reply.payload[0]);
    end
  endtask

  task automatic run_t238();
    driver_inst.send_read(24'h000000, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000000, 1);
  endtask

  task automatic run_t239();
    logic [31:0] wr_words[$];
    longint unsigned start_cycle;
    longint unsigned total_cycles;

    wr_words.push_back(32'h2390_0001);
    start_cycle = cycle_counter;
    driver_inst.send_ordered_write(24'h000239, 1, wr_words,
                                   SC_ORDER_RELEASE, 4'h1, 8'h01);
    monitor_inst.wait_reply(captured_reply);
    total_cycles = cycle_counter - start_cycle;
    expect_reply_header_rsp(captured_reply, 24'h000239, 1, 2'b00);
    expect_reply_metadata(captured_reply, SC_ORDER_RELEASE, 4'h1, 8'h01, 2'b00, 1'b0);
    if (captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T239 release write unexpectedly returned payload");
    end
    if (total_cycles > 40) begin
      $error("sc_hub_tb_top: T239 zero-outstanding release took too long act=%0d cycles",
             total_cycles);
    end
  endtask

  task automatic run_t240();
    logic [31:0] first_words[$];
    logic [31:0] second_words[$];
    sc_reply_t first_reply;
    sc_reply_t second_reply;

    first_words.push_back(32'h2400_0001);
    second_words.push_back(32'h2400_0002);

    driver_inst.send_ordered_write(24'h000240, 1, first_words,
                                   SC_ORDER_RELEASE, 4'h1, 8'h01);
    monitor_inst.wait_reply(first_reply);
    expect_reply_header_rsp(first_reply, 24'h000240, 1, 2'b00);
    expect_reply_metadata(first_reply, SC_ORDER_RELEASE, 4'h1, 8'h01, 2'b00, 1'b0);

    driver_inst.send_ordered_write(24'h000241, 1, second_words,
                                   SC_ORDER_RELEASE, 4'h1, 8'h02);
    monitor_inst.wait_reply(second_reply);
    expect_reply_header_rsp(second_reply, 24'h000241, 1, 2'b00);
    expect_reply_metadata(second_reply, SC_ORDER_RELEASE, 4'h1, 8'h02, 2'b00, 1'b0);
    check_bfm_words(24'h000240, first_words);
    check_bfm_words(24'h000241, second_words);
  endtask

  task automatic run_t246();
    logic [31:0] wr_words[$];

    wr_words.push_back(32'h2460_0001);
    driver_inst.send_ordered_write(24'h000246, 1, wr_words,
                                   SC_ORDER_RELEASE, 4'h1, 8'h11, 2'b10);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h000246, 1, 2'b00);
    expect_reply_metadata(captured_reply, SC_ORDER_RELEASE, 4'h1, 8'h11, 2'b10, 1'b0);
    if (captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T246 release write unexpectedly returned payload");
    end
  endtask

  task automatic run_t247();
    run_t439();
  endtask

  task automatic run_t249();
    logic [31:0] wr_words[$];
    logic [31:0] drain_count_word;
    logic [31:0] hold_count_word;

    wr_words.push_back(32'h2490_0001);
    driver_inst.send_ordered_write(24'h000249, 1, wr_words,
                                   SC_ORDER_RELEASE, 4'h1, 8'h01);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h000249, 1, 2'b00);
    expect_reply_metadata(captured_reply, SC_ORDER_RELEASE, 4'h1, 8'h01, 2'b00, 1'b0);

    wr_words[0] = 32'h2490_0002;
    driver_inst.send_ordered_write(24'h00024A, 1, wr_words,
                                   SC_ORDER_RELEASE, 4'h1, 8'h02);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h00024A, 1, 2'b00);
    expect_reply_metadata(captured_reply, SC_ORDER_RELEASE, 4'h1, 8'h02, 2'b00, 1'b0);

    driver_inst.send_ordered_read(24'h00024B, 1, SC_ORDER_ACQUIRE, 4'h2, 8'h03);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h00024B, 1, 2'b00);
    expect_reply_metadata(captured_reply, SC_ORDER_ACQUIRE, 4'h2, 8'h03, 2'b00, 1'b0);

    driver_inst.send_ordered_read(24'h00024C, 1, SC_ORDER_ACQUIRE, 4'h2, 8'h04);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h00024C, 1, 2'b00);
    expect_reply_metadata(captured_reply, SC_ORDER_ACQUIRE, 4'h2, 8'h04, 2'b00, 1'b0);

    driver_inst.send_ordered_read(24'h00024D, 1, SC_ORDER_ACQUIRE, 4'h2, 8'h05);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h00024D, 1, 2'b00);
    expect_reply_metadata(captured_reply, SC_ORDER_ACQUIRE, 4'h2, 8'h05, 2'b00, 1'b0);

    read_csr_word(16'h019, drain_count_word);
    read_csr_word(16'h01A, hold_count_word);
    if (drain_count_word !== 32'd2) begin
      $error("sc_hub_tb_top: T249 release_drain_counter mismatch exp=2 act=%0d",
             drain_count_word);
    end
    if (hold_count_word !== 32'd3) begin
      $error("sc_hub_tb_top: T249 acquire_hold_counter mismatch exp=3 act=%0d",
             hold_count_word);
    end
  endtask

  task automatic run_t444();
    sc_reply_t csr_reply;

    if (AVALON_DUT_OUTSTANDING_INT_RESERVED != 0) begin
      $error("sc_hub_tb_top: T444 requires OUTSTANDING_INT_RESERVED=0 act=%0d",
             AVALON_DUT_OUTSTANDING_INT_RESERVED);
    end

    stall_avalon_reads(24'h004440, AVALON_DUT_OUTSTANDING_LIMIT);
    fork : t444_csr_issue
      begin
        driver_inst.send_read(csr_addr(16'h000), 1);
      end
    join_none
    wait_clks(16);
    if (avm_read !== 1'b0) begin
      $error("sc_hub_tb_top: T444 expected CSR read to wait while ext slots were saturated");
    end

    release dut_inst.bus_cmd_ready;
    for (int unsigned idx = 0; idx < AVALON_DUT_OUTSTANDING_LIMIT; idx++) begin
      monitor_inst.wait_reply(captured_reply);
      expect_read_reply(captured_reply, 24'h004440 + idx, 1);
    end
    wait fork;
    monitor_inst.wait_reply(csr_reply);
    expect_single_word_reply(csr_reply, csr_addr(16'h000), HUB_UID_CONST);
  endtask

  task automatic run_t445();
    if (AVALON_DUT_OUTSTANDING_INT_RESERVED != AVALON_DUT_OUTSTANDING_LIMIT) begin
      $error("sc_hub_tb_top: T445 requires OUTSTANDING_INT_RESERVED=OUTSTANDING_LIMIT act_reserved=%0d act_limit=%0d",
             AVALON_DUT_OUTSTANDING_INT_RESERVED,
             AVALON_DUT_OUTSTANDING_LIMIT);
    end

    driver_inst.send_read(csr_addr(16'h000), 1);
    monitor_inst.wait_reply(captured_reply);
    expect_single_word_reply(captured_reply, csr_addr(16'h000), HUB_UID_CONST);

    fork : t445_ext_attempt
      begin
        driver_inst.send_read(24'h004450, 1);
      end
    join_none
    wait_clks(32);
    if (dut_inst.core_inst.tracked_pkt_count != 0) begin
      $error("sc_hub_tb_top: T445 external read should not be admitted when all slots are reserved act=%0d",
             dut_inst.core_inst.tracked_pkt_count);
    end
    if (avm_read !== 1'b0) begin
      $error("sc_hub_tb_top: T445 external read unexpectedly reached the bus");
    end
    disable t445_ext_attempt;
    driver_inst.drive_idle();
    wait_clks(4);

    driver_inst.send_read(csr_addr(16'h000), 1);
    monitor_inst.wait_reply(captured_reply);
    expect_single_word_reply(captured_reply, csr_addr(16'h000), HUB_UID_CONST);
  endtask

  task automatic run_t446();
    logic stalled_write_done;

    if (AVALON_DUT_EXT_PLD_DEPTH != 64) begin
      $error("sc_hub_tb_top: T446 requires EXT_PLD_DEPTH=64 act=%0d",
             AVALON_DUT_EXT_PLD_DEPTH);
    end

    stalled_write_done = 1'b0;
    force dut_inst.bus_cmd_ready = 1'b0;
    send_stalled_avalon_write(24'h004460, 64, 32'h4460_0000);
    wait_clks(1);
    if (dut_inst.dl_fifo_usedw != 10'd64) begin
      $error("sc_hub_tb_top: T446 expected exact-fill dl_fifo_usedw=64 act=%0d",
             dut_inst.dl_fifo_usedw);
    end

    fork
      begin : t446_stalled_write_thread
        driver_inst.send_precise_stalled_single_write(24'h004560, 32'h4461_0000);
        stalled_write_done = 1'b1;
      end
    join_none
    wait_link_ready_value(1'b0, "T446 payload backpressure");
    wait_clks(8);
    if (dut_inst.dl_fifo_usedw != 10'd64) begin
      $error("sc_hub_tb_top: T446 payload usedw changed while blocked act=%0d",
             dut_inst.dl_fifo_usedw);
    end

    release dut_inst.bus_cmd_ready;
    repeat (256) begin
      if (stalled_write_done == 1'b1) begin
        break;
      end
      @(posedge clk);
    end
    if (stalled_write_done != 1'b1) begin
      $error("sc_hub_tb_top: T446 stalled single-word write did not resume after releasing bus_cmd_ready");
      disable t446_stalled_write_thread;
      return;
    end

    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h004460, 64);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h004560, 1);
  endtask

  task automatic run_t447();
    if (AVALON_DUT_EXT_PLD_DEPTH != 64) begin
      $error("sc_hub_tb_top: T447 requires EXT_PLD_DEPTH=64 act=%0d",
             AVALON_DUT_EXT_PLD_DEPTH);
    end

    fork : t447_stalled_write_thread
      begin
        send_stalled_avalon_write(24'h004470, 65, 32'h4470_0000);
      end
    join_none
    wait_link_ready_value(1'b0, "T447 payload depth stall");
    wait_clks(16);
    if (dut_inst.dl_fifo_usedw != 10'd0) begin
      $error("sc_hub_tb_top: T447 expected no payload commit while oversized packet is blocked act=%0d",
             dut_inst.dl_fifo_usedw);
    end
    disable t447_stalled_write_thread;
    driver_inst.drive_idle();
    wait_clks(4);
  endtask

  task automatic run_t448();
    driver_inst.send_read(24'h00FE7F, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h00FE7F, 1);
  endtask

  task automatic run_t449();
    driver_inst.send_read(24'h00FEA0, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h00FEA0, 1);
  endtask

  task automatic run_t500();
    clear_hub_counters();
    run_t061();
    expect_err_flag_and_count(HUB_ERR_SLVERR_BIT, 32'h0000_0001, "T500");
    driver_inst.send_read(24'h000050, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000050, 1);
  endtask

  task automatic run_t501();
    clear_hub_counters();
    run_t062();
    expect_err_flag_and_count(HUB_ERR_DECERR_BIT, 32'h0000_0001, "T501");
  endtask

  task automatic run_t502();
    clear_hub_counters();
    run_t063();
    expect_err_flag_and_count(HUB_ERR_SLVERR_BIT, 32'h0000_0001, "T502");
  endtask

  task automatic run_t503();
    clear_hub_counters();
    run_t064();
    expect_err_flag_and_count(HUB_ERR_DECERR_BIT, 32'h0000_0001, "T503");
  endtask

  task automatic run_t509();
    clear_hub_counters();
    run_t027();
    expect_err_flag_and_count(HUB_ERR_PKT_DROP_BIT, 32'h0000_0001, "T509");
  endtask

  task automatic run_t510();
    clear_hub_counters();
    run_t028();
    expect_err_flag_and_count(HUB_ERR_PKT_DROP_BIT, 32'h0000_0001, "T510");
  endtask

  task automatic run_t511();
    clear_hub_counters();
    run_t036();
    expect_err_flag_and_count(HUB_ERR_PKT_DROP_BIT, 32'h0000_0001, "T511");
  endtask

  task automatic run_t512();
    logic [31:0] words[$];
    logic [3:0]  dataks[$];
    logic [31:0] pkt_drop_count;

    clear_hub_counters();

    for (int unsigned drop_idx = 0; drop_idx < 10; drop_idx++) begin
      words.delete();
      dataks.delete();
      for (int unsigned idx = 0; idx < 8; idx++) begin
        words.push_back(32'hD120_0000 + (drop_idx * 16) + idx);
        dataks.push_back(4'b0000);
      end
      words.insert(0, 32'h0000_0008);
      dataks.insert(0, 4'b0000);
      words.insert(0, 32'h0000_0000);
      dataks.insert(0, 4'b0000);
      words.insert(0, 32'h1F00_02BC);
      dataks.insert(0, 4'b0001);
      driver_inst.send_raw(words, dataks);
      monitor_inst.assert_no_reply(400ns);
    end

    driver_inst.send_read(24'h000512, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000512, 1);

    read_pkt_drop_count(pkt_drop_count);
    if (pkt_drop_count !== 32'd10) begin
      $error("sc_hub_tb_top: T512 expected PKT_DROP_CNT=10 act=%0d", pkt_drop_count);
    end
    expect_err_flag_and_count(HUB_ERR_PKT_DROP_BIT, 32'h0000_000A, "T512");
  endtask

  task automatic run_t513();
    clear_hub_counters();
    inject_decode_error = 1'b1;
    for (int unsigned idx = 0; idx < 260; idx++) begin
      driver_inst.send_read(24'h00A000 + idx, 1);
      monitor_inst.wait_reply(captured_reply);
      if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
          captured_reply.response != 2'b11 || captured_reply.payload_words != 1 ||
          captured_reply.payload[0] !== 32'hDEAD_BEEF) begin
        $error("sc_hub_tb_top: T513 decode-error reply mismatch idx=%0d rsp=%0b data=0x%08h",
               idx,
               captured_reply.response,
               captured_reply.payload[0]);
      end
    end
    inject_decode_error = 1'b0;
    expect_err_flag_and_count(HUB_ERR_DECERR_BIT, 32'h0000_00FF, "T513");
  endtask

  task automatic run_t514();
    logic [31:0] err_flags_word;
    logic [31:0] clear_word;

    clear_hub_counters();
    run_t061();
    read_csr_word(16'h004, err_flags_word);
    if (err_flags_word[HUB_ERR_SLVERR_BIT] !== 1'b1) begin
      $error("sc_hub_tb_top: T514 expected ERR_FLAGS.slverr set before W1C act=0x%08h",
             err_flags_word);
    end

    clear_word = '0;
    clear_word[HUB_ERR_SLVERR_BIT] = 1'b1;
    write_csr_word(16'h004, clear_word);
    read_csr_word(16'h004, err_flags_word);
    if (err_flags_word[HUB_ERR_SLVERR_BIT] !== 1'b0) begin
      $error("sc_hub_tb_top: T514 expected ERR_FLAGS.slverr cleared by W1C act=0x%08h",
             err_flags_word);
    end

    run_t061();
    expect_err_flag_and_count(HUB_ERR_SLVERR_BIT, 32'h0000_0002, "T514");
  endtask

  task automatic run_t515();
    logic [31:0] pkt_drop_count;
    logic [31:0] err_flags_word;
    logic [31:0] err_count_word;

    clear_hub_counters();
    run_t061();
    run_t027();

    read_pkt_drop_count(pkt_drop_count);
    if (pkt_drop_count !== 32'd1) begin
      $error("sc_hub_tb_top: T515 expected PKT_DROP_CNT=1 act=%0d", pkt_drop_count);
    end

    read_err_status(err_flags_word, err_count_word);
    if (err_flags_word[HUB_ERR_SLVERR_BIT] !== 1'b1 ||
        err_flags_word[HUB_ERR_PKT_DROP_BIT] !== 1'b1) begin
      $error("sc_hub_tb_top: T515 expected SLVERR and PKT_DROP flags act=0x%08h",
             err_flags_word);
    end
    if (err_count_word !== 32'h0000_0002) begin
      $error("sc_hub_tb_top: T515 expected ERR_COUNT=2 act=0x%08h", err_count_word);
    end
  endtask

  task automatic run_t516();
    clear_hub_counters();
    run_t069();
    expect_err_flag_and_count(HUB_ERR_DECERR_BIT, 32'h0000_0040, "T516");
    driver_inst.send_read(24'h000516, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000516, 1);
  endtask

  task automatic run_t517();
    clear_hub_counters();
    run_t065();
    expect_err_flag_and_count(HUB_ERR_RD_TIMEOUT_BIT, 32'h0000_0001, "T517");
    driver_inst.send_read(24'h000517, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000517, 1);
  endtask

  task automatic run_t518();
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, 8, 32'h5180_0000);
    clear_hub_counters();

    force avm_waitrequest = 1'b1;
    driver_inst.send_write(24'h000518, 8, wr_words);
    wait (avm_write === 1'b1);
    wait_clks(16);
    monitor_inst.assert_no_reply(400ns);

    issue_masked_soft_reset();
    wait_clks(8);
    if (avm_write !== 1'b0 || avm_read !== 1'b0) begin
      $error("sc_hub_tb_top: T518 expected bus strobes deasserted after software reset read=%0b write=%0b",
             avm_read,
             avm_write);
    end
    release avm_waitrequest;
    wait_clks(8);

    driver_inst.send_read(24'h000618, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000618, 1);
  endtask

  task automatic run_t519();
    clear_hub_counters();
    run_t068();
    expect_err_flag_and_count(HUB_ERR_RD_TIMEOUT_BIT, 32'h0000_0001, "T519");
    driver_inst.send_read(24'h00051A, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h00051A, 1);
  endtask

  task automatic run_t520();
    logic [31:0] wr_words[$];
    logic [31:0] original_words[0:7];
    int unsigned changed_words;

    fill_write_words(wr_words, 8, 32'h5200_0000);
    for (int unsigned idx = 0; idx < 8; idx++) begin
      original_words[idx] = 32'h9520_0000 + idx;
      avmm_bfm_inst.mem[16'h0520 + idx] = original_words[idx];
    end

    clear_hub_counters();
    fork
      begin : t520_force_waitrequest
        int unsigned beat_count;
        beat_count = 0;
        forever begin
          @(posedge clk);
          if (avm_write === 1'b1 && avm_waitrequest === 1'b0) begin
            beat_count++;
            if (beat_count >= 4) begin
              force avm_waitrequest = 1'b1;
              disable t520_force_waitrequest;
            end
          end
        end
      end
      begin
        driver_inst.send_write(24'h000520, 8, wr_words);
      end
    join

    wait (avm_write === 1'b1);
    wait_clks(16);
    monitor_inst.assert_no_reply(400ns);
    issue_masked_soft_reset();
    wait_clks(8);
    if (avm_write !== 1'b0 || avm_read !== 1'b0) begin
      $error("sc_hub_tb_top: T520 expected bus strobes deasserted after software reset read=%0b write=%0b",
             avm_read,
             avm_write);
    end
    release avm_waitrequest;
    wait_clks(8);

    changed_words = 0;
    for (int unsigned idx = 0; idx < 8; idx++) begin
      if (avmm_bfm_inst.mem[16'h0520 + idx] !== original_words[idx]) begin
        changed_words++;
      end
    end
    if (changed_words == 0) begin
      $error("sc_hub_tb_top: T520 expected at least one partially visible write beat in stalled burst window");
    end

    driver_inst.send_read(24'h000620, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000620, 1);
  endtask

  task automatic run_t522();
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, 64, 32'h5220_0000);
    force avm_waitrequest = 1'b1;
    driver_inst.send_write(24'h000522, 64, wr_words);
    wait_clks(8);
    if (dut_inst.dl_fifo_usedw != 9'd64) begin
      $error("sc_hub_tb_top: T522 expected dl_fifo_usedw=64 before reset act=%0d",
             dut_inst.dl_fifo_usedw);
    end

    issue_masked_soft_reset();
    wait_clks(8);
    if (dut_inst.dl_fifo_usedw != 9'd0 || dut_inst.core_inst.tracked_pkt_count != 0) begin
      $error("sc_hub_tb_top: T522 reset did not reclaim queued payload/packets usedw=%0d tracked=%0d",
             dut_inst.dl_fifo_usedw,
             dut_inst.core_inst.tracked_pkt_count);
    end
    release avm_waitrequest;
  endtask

  task automatic run_t523();
    sc_reply_t reply;
    int unsigned txn_count;
    int unsigned txn_kind_by_addr[int unsigned];
    logic [3:0] txn_domain_by_addr[int unsigned];
    logic [7:0] txn_epoch_by_addr[int unsigned];
    bit         seen_by_addr[int unsigned];
    int unsigned addr_key;
    int unsigned waited_cycles;

    if (!AVALON_DUT_OOO_ENABLE) begin
      $error("sc_hub_tb_top: T523 requires SC_HUB_TB_AVALON_OOO_ENABLED and OOO_ENABLE=true");
    end

    clear_hub_counters();
    write_csr_word(16'h018, 32'h0000_0001);
    txn_count = 1024;
    t523_issue_count_dbg = 0;
    t523_reply_count_dbg = 0;
    t523_txn_count_dbg   = txn_count;
    t523_write_reply_count_dbg   = 0;
    t523_read_reply_count_dbg    = 0;
    t523_ordered_reply_count_dbg = 0;
    for (int unsigned idx = 0; idx < txn_count; idx++) begin
      logic [31:0] wr_words[$];
      logic [23:0] txn_addr;
      int unsigned slot_idx;

      slot_idx = idx / 3;

      if (idx % 3 == 0) begin
        txn_addr = 24'h001000 + (slot_idx * 8);
        addr_key = txn_addr;
        txn_kind_by_addr[addr_key] = 0;
        fill_write_words(wr_words, 4, 32'h5230_0000 + (idx * 16));
        driver_inst.send_write(txn_addr, 4, wr_words);
        t523_issue_count_dbg = idx + 1;
      end else if (idx % 3 == 1) begin
        txn_addr = 24'h004001 + (slot_idx * 8);
        addr_key = txn_addr;
        txn_kind_by_addr[addr_key] = 1;
        driver_inst.send_read(txn_addr, 1);
        t523_issue_count_dbg = idx + 1;
      end else begin
        txn_addr = 24'h007002 + (slot_idx * 8);
        addr_key = txn_addr;
        txn_kind_by_addr[addr_key]   = 2;
        txn_domain_by_addr[addr_key] = idx[3:0];
        txn_epoch_by_addr[addr_key]  = idx[7:0];
        driver_inst.send_ordered_read(txn_addr, 1, SC_ORDER_RELAXED, idx[3:0], idx[7:0]);
        t523_issue_count_dbg = idx + 1;
      end
    end

    for (int unsigned idx = 0; idx < txn_count; idx++) begin
      logic [23:0] expected_addr;

      monitor_inst.wait_reply(reply);
      t523_reply_count_dbg = idx + 1;
      addr_key = int'(reply.start_address);
      if (!txn_kind_by_addr.exists(addr_key)) begin
        $error("sc_hub_tb_top: T523 unexpected reply addr=0x%06h", reply.start_address);
      end else if (seen_by_addr.exists(addr_key)) begin
        $error("sc_hub_tb_top: T523 duplicate reply addr=0x%06h", reply.start_address);
      end else begin
        seen_by_addr[addr_key] = 1'b1;
        expected_addr = reply.start_address;
        case (txn_kind_by_addr[addr_key])
          0: begin
            t523_write_reply_count_dbg++;
            expect_write_reply(reply, expected_addr, 4);
          end
          1: begin
            t523_read_reply_count_dbg++;
            expect_read_reply(reply, expected_addr, 1);
          end
          2: begin
            t523_ordered_reply_count_dbg++;
            expect_reply_header_rsp(reply, expected_addr, 1, 2'b00);
            expect_reply_metadata(reply, SC_ORDER_RELAXED,
                                  txn_domain_by_addr[addr_key],
                                  txn_epoch_by_addr[addr_key],
                                  2'b00, 1'b0);
            if (reply.payload_words != 1 ||
                reply.payload[0] !== expected_bus_word(expected_addr, 0)) begin
              $error("sc_hub_tb_top: T523 ordered-read payload mismatch addr=0x%06h words=%0d data=0x%08h",
                     expected_addr,
                     reply.payload_words,
                     reply.payload[0]);
            end
          end
          default: begin
            $error("sc_hub_tb_top: T523 unexpected reply kind=%0d addr=0x%06h",
                   txn_kind_by_addr[addr_key],
                   expected_addr);
          end
        endcase
      end
    end

    if (seen_by_addr.num() != txn_count) begin
      $error("sc_hub_tb_top: T523 missing replies exp=%0d act=%0d",
             txn_count,
             seen_by_addr.num());
    end

    waited_cycles = 0;
    while (
      (dut_inst.core_inst.tracked_pkt_count != 0 ||
       dut_inst.core_inst.pending_pkt_count != 0 ||
       dut_inst.core_inst.rd_fifo_usedw != 0 ||
       dut_inst.dl_fifo_usedw != 0 ||
       dut_inst.bp_usedw != 0) &&
      waited_cycles < 1024
    ) begin
      @(posedge clk);
      waited_cycles++;
    end
    if (dut_inst.core_inst.tracked_pkt_count != 0 ||
        dut_inst.core_inst.pending_pkt_count != 0 ||
        dut_inst.core_inst.rd_fifo_usedw != 0 ||
        dut_inst.dl_fifo_usedw != 0 ||
        dut_inst.bp_usedw != 0) begin
      $error("sc_hub_tb_top: T523 quiesce leak detected tracked=%0d pending=%0d rd_fifo=%0d dl_fifo=%0d bp=%0d",
             dut_inst.core_inst.tracked_pkt_count,
             dut_inst.core_inst.pending_pkt_count,
             dut_inst.core_inst.rd_fifo_usedw,
             dut_inst.dl_fifo_usedw,
             dut_inst.bp_usedw);
    end
  endtask

  task automatic run_t524();
    sc_cmd_t      write_cmd;
    logic [31:0]  wr_words[$];
    logic [23:0]  write_addr;

    write_addr = 24'h0052C0;
    clear_hub_counters();
    fill_write_words(wr_words, 4, 32'h5240_0000);
    write_cmd = make_cmd(SC_WRITE, write_addr, 4);

    driver_inst.drive_word(make_preamble_word(write_cmd), 4'b0001);
    driver_inst.drive_word(make_addr_word(write_cmd), 4'b0000);
    driver_inst.drive_word(make_length_word(write_cmd), 4'b0000);
    foreach (wr_words[idx]) begin
      driver_inst.drive_word(wr_words[idx], 4'b0000);
    end

    force dut_inst.pkt_rx_inst.pkt_queue_count = 16;
    force dut_inst.pkt_valid = 1'b0;
    force dut_inst.rx_ready = 1'b0;
    force dut_inst.pkt_rx_inst.fifo_rollback = 1'b0;
    driver_inst.drive_word({24'h0, K284_CONST}, 4'b0001);
    release dut_inst.rx_ready;
    release dut_inst.pkt_valid;
    release dut_inst.pkt_rx_inst.pkt_queue_count;
    wait_clks(1);
    release dut_inst.pkt_rx_inst.fifo_rollback;
    driver_inst.drive_idle();
    wait_clks(8);
    if (dut_inst.dl_fifo_usedw == 0) begin
      $error("sc_hub_tb_top: T524 simulated admission-revert failure did not leave payload allocated");
    end
    if (dut_inst.pkt_rx_inst.pkt_queue_count == 0 &&
        dut_inst.core_inst.tracked_pkt_count == 0 &&
        dut_inst.core_inst.pending_pkt_count == 0) begin
      $error("sc_hub_tb_top: T524 simulated admission-revert failure did not leave any queued state to recover");
    end

    issue_masked_soft_reset();
    wait_clks(8);
    if (dut_inst.dl_fifo_usedw != 0) begin
      $error("sc_hub_tb_top: T524 soft reset did not reclaim leaked payload act=%0d",
             dut_inst.dl_fifo_usedw);
    end

    wait_clks(8);
    if (dut_inst.pkt_rx_inst.pkt_queue_count != 0 ||
        dut_inst.core_inst.tracked_pkt_count != 0 ||
        dut_inst.core_inst.pending_pkt_count != 0 ||
        dut_inst.dl_fifo_usedw != 0) begin
      $error("sc_hub_tb_top: T524 expected clean reset recovery after simulated revert failure rx_q=%0d tracked=%0d pending=%0d dl_fifo=%0d",
             dut_inst.pkt_rx_inst.pkt_queue_count,
             dut_inst.core_inst.tracked_pkt_count,
             dut_inst.core_inst.pending_pkt_count,
             dut_inst.dl_fifo_usedw);
      end
  endtask

  task automatic run_t528();
    logic [31:0] original_word;

    original_word = 32'h5280_00A5;
    avmm_bfm_inst.mem[16'h0528] = original_word;
    avmm_bfm_inst.set_rd_latency_for_addr(16'h0528, 300);

    driver_inst.send_atomic_rmw(24'h000528, 32'h0000_FFFF, 32'h0000_55AA,
                                SC_ORDER_RELAXED, 4'h0, 8'h00);
    wait (avm_read === 1'b1);
    wait_clks(2);
    pulse_reset(10);
    wait_clks(4);
    avmm_bfm_inst.set_rd_latency_for_addr(16'h0528, 1);

    if (avmm_bfm_inst.mem[16'h0528] !== original_word) begin
      $error("sc_hub_tb_top: T528 reset during atomic should not commit write exp=0x%08h act=0x%08h",
             original_word,
             avmm_bfm_inst.mem[16'h0528]);
    end

    driver_inst.send_read(24'h000528, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_single_word_reply(captured_reply, 24'h000528, original_word);
  endtask

  task automatic run_t529();
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, 4, 32'h5290_0000);
    force avm_waitrequest = 1'b1;
    driver_inst.send_ordered_write(24'h000529, 4, wr_words,
                                   SC_ORDER_RELEASE, 4'h1, 8'h29);
    wait_clks(8);
    pulse_reset(10);
    wait_clks(4);
    if (dut_inst.core_inst.tracked_pkt_count != 0) begin
      $error("sc_hub_tb_top: T529 reset should clear tracked packet state act=%0d",
             dut_inst.core_inst.tracked_pkt_count);
    end
    release avm_waitrequest;

    driver_inst.send_read(24'h000629, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000629, 1);
  endtask

  task automatic run_t540();
    if (AVALON_DUT_OUTSTANDING_INT_RESERVED != 0) begin
      $error("sc_hub_tb_top: T540 requires OUTSTANDING_INT_RESERVED=0 act=%0d",
             AVALON_DUT_OUTSTANDING_INT_RESERVED);
    end

    force avm_waitrequest = 1'b1;
    stall_avalon_reads(24'h005400, AVALON_DUT_OUTSTANDING_LIMIT);
    fork
      begin
        driver_inst.send_read(csr_addr(16'h000), 1);
      end
    join_none
    wait_clks(16);
    if (avm_read !== 1'b0) begin
      $error("sc_hub_tb_top: T540 expected CSR path blocked while ext saturates all slots");
    end
    release avm_waitrequest;
    rst = 1'b1;
    repeat (4) @(posedge clk);
    rst = 1'b0;
    wait fork;
  endtask

  task automatic run_t541();
    if (AVALON_DUT_OUTSTANDING_INT_RESERVED != 0) begin
      $error("sc_hub_tb_top: T541 requires OUTSTANDING_INT_RESERVED=0 act=%0d",
             AVALON_DUT_OUTSTANDING_INT_RESERVED);
    end

    driver_inst.send_read(24'h005410, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h005410, 1);
    driver_inst.send_read(csr_addr(16'h000), 1);
    monitor_inst.wait_reply(captured_reply);
    expect_single_word_reply(captured_reply, csr_addr(16'h000), HUB_UID_CONST);
  endtask

  task automatic run_t542();
    if (AVALON_DUT_EXT_PLD_DEPTH != 1) begin
      $error("sc_hub_tb_top: T542 requires EXT_PLD_DEPTH=1 act=%0d",
             AVALON_DUT_EXT_PLD_DEPTH);
    end

    fork
      begin
        send_stalled_avalon_write(24'h005420, 2, 32'h5420_0000);
      end
    join_none
    wait_link_ready_value(1'b0, "T542 payload depth stall");
    wait_clks(16);
    if (dut_inst.dl_fifo_usedw != 9'd0) begin
      $error("sc_hub_tb_top: T542 expected no payload commit while blocked act=%0d",
             dut_inst.dl_fifo_usedw);
    end
    disable fork;
  endtask

  task automatic run_t543();
    if (AVALON_DUT_EXT_PLD_DEPTH != 32) begin
      $error("sc_hub_tb_top: T543 requires EXT_PLD_DEPTH=32 act=%0d",
             AVALON_DUT_EXT_PLD_DEPTH);
    end

    fork
      begin
        send_stalled_avalon_write(24'h005430, 33, 32'h5430_0000);
      end
    join_none
    wait_link_ready_value(1'b0, "T543 payload depth stall");
    wait_clks(16);
    if (dut_inst.dl_fifo_usedw != 9'd0) begin
      $error("sc_hub_tb_top: T543 expected no payload commit while blocked act=%0d",
             dut_inst.dl_fifo_usedw);
    end
    disable fork;
  endtask

  task automatic run_t544();
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, 1, 32'h5440_0000);
    driver_inst.send_write(24'h005440, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h005440, 1);

    driver_inst.send_read(24'h005440, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_single_word_reply(captured_reply, 24'h005440, wr_words[0]);

    driver_inst.send_read(csr_addr(16'h000), 1);
    monitor_inst.wait_reply(captured_reply);
    expect_single_word_reply(captured_reply, csr_addr(16'h000), HUB_UID_CONST);
  endtask

  task automatic run_t546();
    sc_cmd_t      truncated_cmd;
    logic [31:0]  original_words[$];
    logic [31:0]  fifo_cfg_word;
    logic [31:0]  pkt_drop_before;
    logic [31:0]  pkt_drop_after;
    bit           saw_drop;

    read_bfm_words(24'h005460, 16, original_words);
    read_csr_word(16'h009, fifo_cfg_word);
    if (fifo_cfg_word[0] !== 1'b1) begin
      $error("sc_hub_tb_top: T546 expected download store-and-forward bit fixed high before disable attempt act=0x%08h",
             fifo_cfg_word);
    end

    write_csr_word(16'h009, 32'h0000_0000);
    read_csr_word(16'h009, fifo_cfg_word);
    if (fifo_cfg_word[0] !== 1'b1) begin
      $error("sc_hub_tb_top: T546 expected FIFO_CFG bit0 to stay high because download store-and-forward is not runtime-disableable act=0x%08h",
             fifo_cfg_word);
    end

    read_pkt_drop_count(pkt_drop_before);
    truncated_cmd = make_cmd(SC_WRITE, 24'h005460, 16);
    driver_inst.drive_word(make_preamble_word(truncated_cmd), 4'b0001);
    driver_inst.drive_word(make_addr_word(truncated_cmd), 4'b0000);
    driver_inst.drive_word(make_length_word(truncated_cmd), 4'b0000);
    for (int unsigned idx = 0; idx < 8; idx++) begin
      driver_inst.drive_word(32'h5460_0000 + idx, 4'b0000);
    end
    driver_inst.drive_idle();

    saw_drop = 1'b0;
    repeat (128) begin
      @(posedge clk);
      if (dut_inst.pkt_drop_pulse == 1'b1) begin
        saw_drop = 1'b1;
      end
    end
    if (!saw_drop) begin
      $error("sc_hub_tb_top: T546 truncated write did not raise pkt_drop_pulse under fixed store-and-forward protection");
    end

    read_pkt_drop_count(pkt_drop_after);
    if (pkt_drop_after !== pkt_drop_before + 1) begin
      $error("sc_hub_tb_top: T546 expected PKT_DROP_CNT increment after truncated protected write before=%0d after=%0d",
             pkt_drop_before,
             pkt_drop_after);
    end
    check_bfm_words(24'h005460, original_words);
  endtask

  task automatic run_t547();
    logic [31:0] wr_words[$];
    logic [31:0] fifo_cfg_word;

    read_csr_word(16'h009, fifo_cfg_word);
    if (fifo_cfg_word[0] !== 1'b1) begin
      $error("sc_hub_tb_top: T547 expected download store-and-forward bit fixed high before disable attempt act=0x%08h",
             fifo_cfg_word);
    end

    write_csr_word(16'h009, 32'h0000_0000);
    read_csr_word(16'h009, fifo_cfg_word);
    if (fifo_cfg_word[0] !== 1'b1) begin
      $error("sc_hub_tb_top: T547 expected FIFO_CFG bit0 to stay high because download store-and-forward is not runtime-disableable act=0x%08h",
             fifo_cfg_word);
    end

    fill_write_words(wr_words, 4, 32'h5470_0000);
    driver_inst.send_write(24'h005470, 4, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h005470, 4);
    check_bfm_words(24'h005470, wr_words);
  endtask

  task automatic run_t548();
    logic [31:0] expected_word;

    if (driver_inst.clk !== clk || monitor_inst.clk !== clk || dut_inst.i_clk !== clk) begin
      $error("sc_hub_tb_top: T548 expected packet path and hub core to share the same clock signal");
    end
`ifdef SC_HUB_BUS_AXI4
    if (axi4_bfm_inst.clk !== clk) begin
      $error("sc_hub_tb_top: T548 expected AXI4 bus model to share the hub clock because the DUT has no internal CDC bridge");
    end
    expected_word = axi4_bfm_inst.mem[16'h5480];
`else
    if (avmm_bfm_inst.clk !== clk) begin
      $error("sc_hub_tb_top: T548 expected Avalon bus model to share the hub clock because the DUT has no internal CDC bridge");
    end
    expected_word = avmm_bfm_inst.mem[16'h5480];
`endif

    driver_inst.send_read(24'h005480, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_single_word_reply(captured_reply, 24'h005480, expected_word);
  endtask

  task automatic run_t549();
    logic pre_link_ready;
    logic pre_uplink_valid;
`ifdef SC_HUB_BUS_AXI4
    logic pre_axi_awvalid;
    logic pre_axi_arvalid;
    logic pre_axi_wvalid;
`else
    logic pre_avm_read;
    logic pre_avm_write;
`endif

    rst = 1'b1;
    repeat (2) @(posedge clk);
    pre_link_ready   = link_ready;
    pre_uplink_valid = uplink_valid;
`ifdef SC_HUB_BUS_AXI4
    pre_axi_awvalid = axi_awvalid;
    pre_axi_arvalid = axi_arvalid;
    pre_axi_wvalid  = axi_wvalid;
`else
    pre_avm_read  = avm_read;
    pre_avm_write = avm_write;
`endif

    @(negedge clk);
    rst = 1'b0;
    #0.1;
    if (link_ready !== pre_link_ready || uplink_valid !== pre_uplink_valid) begin
      $error("sc_hub_tb_top: T549 reset release changed hub outputs before the next rising clock edge");
    end
`ifdef SC_HUB_BUS_AXI4
    if (axi_awvalid !== pre_axi_awvalid || axi_arvalid !== pre_axi_arvalid || axi_wvalid !== pre_axi_wvalid) begin
      $error("sc_hub_tb_top: T549 reset release changed AXI4 bus controls before the next rising clock edge");
    end
`else
    if (avm_read !== pre_avm_read || avm_write !== pre_avm_write) begin
      $error("sc_hub_tb_top: T549 reset release changed Avalon bus controls before the next rising clock edge");
    end
`endif

    repeat (2) @(posedge clk);
    driver_inst.send_read(24'h005490, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_ok(captured_reply, 24'h005490, 1);
  endtask

`ifndef SC_HUB_BUS_AXI4
  task automatic run_t550();
    logic [31:0] swb_words[$];
    logic [3:0]  swb_dataks[$];
    logic [31:0] expected_words[$];

    clear_hub_counters();
    avmm_bfm_inst.mem[18'h0] <= 32'hDEAD_0000;
    avmm_bfm_inst.mem[18'h1] <= 32'hDEAD_0001;
    avmm_bfm_inst.mem[18'h2] <= 32'hDEAD_0002;

    swb_words.delete();
    swb_dataks.delete();
    expected_words.delete();

    swb_words.push_back(32'h1D00_02BC);
    swb_dataks.push_back(4'b0001);
    swb_words.push_back(32'h0000_0000);
    swb_dataks.push_back(4'b0000);
    swb_words.push_back(32'h0000_0003);
    swb_dataks.push_back(4'b0000);
    swb_words.push_back(32'h0000_0000);
    swb_dataks.push_back(4'b0000);
    swb_words.push_back(32'h0000_0001);
    swb_dataks.push_back(4'b0000);
    swb_words.push_back(32'h0000_0006);
    swb_dataks.push_back(4'b0000);
    swb_words.push_back(32'h0000_009C);
    swb_dataks.push_back(4'b0001);

    expected_words.push_back(32'h0000_0000);
    expected_words.push_back(32'h0000_0001);
    expected_words.push_back(32'h0000_0006);

    driver_inst.send_swb_style_raw(swb_words, swb_dataks, 1);
    monitor_inst.wait_reply_cycles(captured_reply, 512);
    if (captured_reply.echoed_length === 16'hffff) begin
      report_sc_debug_state("T550 no reply after SWB-style packet");
      return;
    end

    expect_write_reply(captured_reply, 24'h000000, 3);
    check_bfm_words(24'h000000, expected_words);
    if ($unsigned(dut_inst.core_inst.ext_pkt_write_count) != 32'd1 ||
        $unsigned(dut_inst.core_inst.ext_word_write_count) != 32'd3 ||
        dut_inst.core_inst.last_ext_write_addr != 32'h0000_0002 ||
        dut_inst.core_inst.last_ext_write_data != 32'h0000_0006) begin
      report_sc_debug_state("T550 post-reply diagnostics mismatch");
      $error("sc_hub_tb_top: T550 external write diagnostics mismatch pkt=%0d words=%0d last_addr=0x%08h last_data=0x%08h",
             dut_inst.core_inst.ext_pkt_write_count,
             dut_inst.core_inst.ext_word_write_count,
             dut_inst.core_inst.last_ext_write_addr,
             dut_inst.core_inst.last_ext_write_data);
    end

    report_sc_debug_state("T550 completed SWB-style packet");
  endtask

  task automatic run_t551();
    logic [31:0] swb_words[$];
    logic [3:0]  swb_dataks[$];
    logic [31:0] expected_words[$];
    logic [31:0] pkt_drop_count;
    int unsigned wait_cycles;

    clear_hub_counters();
    avmm_bfm_inst.mem[18'h0] <= 32'hDEAD_1000;
    avmm_bfm_inst.mem[18'h1] <= 32'hDEAD_1001;
    avmm_bfm_inst.mem[18'h2] <= 32'hDEAD_1002;

    swb_words.delete();
    swb_dataks.delete();
    expected_words.delete();

    swb_words.push_back(32'h1D00_02BC);
    swb_dataks.push_back(4'b0001);
    swb_words.push_back(32'h0000_0000);
    swb_dataks.push_back(4'b0000);
    swb_words.push_back(32'h0000_0003);
    swb_dataks.push_back(4'b0000);
    swb_words.push_back(32'h0000_0000);
    swb_dataks.push_back(4'b0000);
    swb_words.push_back(32'h0000_0001);
    swb_dataks.push_back(4'b0000);
    swb_words.push_back(32'h0000_0006);
    swb_dataks.push_back(4'b0000);
    swb_words.push_back(32'h0000_009C);
    swb_dataks.push_back(4'b0001);

    expected_words.push_back(32'h0000_0000);
    expected_words.push_back(32'h0000_0001);
    expected_words.push_back(32'h0000_0006);

    force dut_inst.pkt_rx_inst.payload_space_granted = 1'b0;
    driver_inst.send_swb_style_raw(swb_words, swb_dataks, 1);
    wait_clks(4);
    release dut_inst.pkt_rx_inst.payload_space_granted;
    monitor_inst.assert_no_reply(400ns);
    for (wait_cycles = 0; wait_cycles < 64; wait_cycles++) begin
      if (dut_inst.pkt_rx_inst.rx_state == 0 &&
          dut_inst.pkt_in_progress == 1'b0 &&
          dut_inst.pkt_valid == 1'b0) begin
        break;
      end
      wait_clks(1);
    end

    if (wait_cycles == 64 ||
        dut_inst.pkt_rx_inst.rx_state != 0 ||
        dut_inst.pkt_in_progress != 1'b0 ||
        dut_inst.pkt_valid != 1'b0 ||
        dut_inst.core_inst.ext_pkt_write_count != 32'd0) begin
      report_sc_debug_state("T551 expected recovery after WAITING_WRITE_SPACE violation");
      $error("sc_hub_tb_top: T551 expected RX to drop the packet and recover after ignored backpressure");
    end

    read_pkt_drop_count(pkt_drop_count);
    if (pkt_drop_count == 32'd0) begin
      report_sc_debug_state("T551 missing pkt_drop_count after recovery");
      $error("sc_hub_tb_top: T551 expected pkt_drop_count to increment after WAITING_WRITE_SPACE violation");
    end

    driver_inst.send_swb_style_raw(swb_words, swb_dataks, 1);
    monitor_inst.wait_reply_cycles(captured_reply, 512);
    if (captured_reply.echoed_length === 16'hffff) begin
      report_sc_debug_state("T551 no reply after recovery");
      return;
    end

    expect_write_reply(captured_reply, 24'h000000, 3);
    check_bfm_words(24'h000000, expected_words);
    if (dut_inst.core_inst.ext_pkt_write_count != 32'd1 ||
        dut_inst.core_inst.ext_word_write_count != 32'd3 ||
        dut_inst.core_inst.last_ext_write_addr != 32'h0000_0002 ||
        dut_inst.core_inst.last_ext_write_data != 32'h0000_0006) begin
      report_sc_debug_state("T551 post-recovery diagnostics mismatch");
      $error("sc_hub_tb_top: T551 expected the follow-up SWB-style write to complete after recovery");
    end

    report_sc_debug_state("T551 recovered after WAITING_WRITE_SPACE violation");
  endtask

  task automatic run_t552();
    sc_cmd_t       cmd;
    logic [31:0]   wr_words[$];
    logic [31:0]   csr_word;
    logic [23:0]   start_addr;
    int unsigned   iter;
    int unsigned   expected_pkt_wr;
    int unsigned   expected_pkt_rd;
    int unsigned   expected_word_wr;
    int unsigned   expected_word_rd;

    clear_hub_counters();
    expected_pkt_wr  = 0;
    expected_pkt_rd  = 0;
    expected_word_wr = 0;
    expected_word_rd = 0;

    for (iter = 0; iter < 24; iter++) begin
      start_addr = 24'h000180 + (iter * 8);
      wr_words.delete();
      for (int unsigned idx = 0; idx < 3; idx++) begin
        wr_words.push_back(32'h5200_0000 + (iter << 8) + idx);
      end

      cmd = make_cmd(SC_WRITE, start_addr, wr_words.size());
      send_swb_style_cmd(cmd, wr_words, (iter % 3) + 1);
      monitor_inst.wait_reply_cycles(captured_reply, 512);
      expect_write_reply(captured_reply, start_addr, wr_words.size());
      check_bfm_words(start_addr, wr_words);
      expected_pkt_wr  += 1;
      expected_word_wr += wr_words.size();

      cmd = make_cmd(SC_READ, start_addr, wr_words.size());
      send_swb_style_cmd(cmd, {}, (iter % 2) + 1);
      monitor_inst.wait_reply_cycles(captured_reply, 512);
      expect_reply_header_ok(captured_reply, start_addr, wr_words.size());
      if (captured_reply.payload_words != wr_words.size()) begin
        $error("sc_hub_tb_top: T552 payload count mismatch at iter=%0d exp=%0d act=%0d",
               iter, wr_words.size(), captured_reply.payload_words);
      end
      for (int unsigned idx = 0; idx < wr_words.size() && idx < captured_reply.payload_words; idx++) begin
        if (captured_reply.payload[idx] !== wr_words[idx]) begin
          $error("sc_hub_tb_top: T552 readback[%0d] mismatch at iter=%0d exp=0x%08h act=0x%08h",
                 idx, iter, wr_words[idx], captured_reply.payload[idx]);
        end
      end
      expected_pkt_rd  += 1;
      expected_word_rd += wr_words.size();

      if ((iter % 6) == 5) begin
        read_csr_word(HUB_CSR_WO_EXT_PKT_WR_CONST, csr_word);
        if (csr_word != expected_pkt_wr) begin
          $error("sc_hub_tb_top: T552 EXT_PKT_WR mismatch at iter=%0d exp=%0d act=%0d",
                 iter, expected_pkt_wr, csr_word);
        end

        read_csr_word(HUB_CSR_WO_EXT_WORD_WR_CONST, csr_word);
        if (csr_word != expected_word_wr) begin
          $error("sc_hub_tb_top: T552 EXT_WORD_WR mismatch at iter=%0d exp=%0d act=%0d",
                 iter, expected_word_wr, csr_word);
        end

        read_csr_word(HUB_CSR_WO_EXT_PKT_RD_CONST, csr_word);
        if (csr_word != expected_pkt_rd) begin
          $error("sc_hub_tb_top: T552 EXT_PKT_RD mismatch at iter=%0d exp=%0d act=%0d",
                 iter, expected_pkt_rd, csr_word);
        end

        read_csr_word(HUB_CSR_WO_EXT_WORD_RD_CONST, csr_word);
        if (csr_word != expected_word_rd) begin
          $error("sc_hub_tb_top: T552 EXT_WORD_RD mismatch at iter=%0d exp=%0d act=%0d",
                 iter, expected_word_rd, csr_word);
        end

        read_pkt_drop_count(csr_word);
        if (csr_word != 32'd0) begin
          report_sc_debug_state("T552 unexpected packet drop during long run");
          $error("sc_hub_tb_top: T552 expected pkt_drop_count to remain zero during long run");
        end
      end
    end

    wait_clks(16);
    if (dut_inst.pkt_rx_inst.rx_state != 0 ||
        dut_inst.pkt_in_progress != 1'b0 ||
        dut_inst.pkt_valid != 1'b0 ||
        dut_inst.core_inst.pending_pkt_count != 0 ||
        dut_inst.core_inst.pending_ext_count != 0) begin
      report_sc_debug_state("T552 expected quiescent end state");
      $error("sc_hub_tb_top: T552 expected the hub to quiesce after the long SWB-style run");
    end

    report_sc_debug_state("T552 completed long SWB-style cross run");
  endtask

  task automatic run_t553();
    logic [23:0] start_addr;
    logic [31:0] csr_word;
    bit          seen_reply[0:9];
    int unsigned rsp_idx;
    int unsigned addr_idx;
    int unsigned payload_idx;
    int unsigned expected_pkt_rd;
    int unsigned expected_word_rd;

    clear_hub_counters();
    for (addr_idx = 0; addr_idx < 10; addr_idx++) begin
      seen_reply[addr_idx] = 1'b0;
    end

    for (addr_idx = 0; addr_idx < 10; addr_idx++) begin
      start_addr = 24'h000040 + (addr_idx * 4);
      driver_inst.send_read(start_addr, 4);
    end

    expected_pkt_rd  = 10;
    expected_word_rd = 40;
    for (rsp_idx = 0; rsp_idx < 10; rsp_idx++) begin
      monitor_inst.wait_reply_cycles(captured_reply, 1024);
      if (captured_reply.echoed_length === 16'hffff) begin
        report_sc_debug_state("T553 timed out waiting for outstanding read reply");
        $error("sc_hub_tb_top: T553 missing reply rsp_idx=%0d", rsp_idx);
        return;
      end

      if ((captured_reply.start_address < 24'h000040) ||
          (captured_reply.start_address > 24'h000064) ||
          (captured_reply.start_address[1:0] != 2'b00)) begin
        report_sc_debug_state("T553 unexpected reply address");
        $error("sc_hub_tb_top: T553 unexpected reply address=0x%06h",
               captured_reply.start_address);
      end

      addr_idx = (captured_reply.start_address - 24'h000040) / 4;
      if (addr_idx > 9) begin
        report_sc_debug_state("T553 reply address index out of range");
        $error("sc_hub_tb_top: T553 reply address index out of range addr=0x%06h idx=%0d",
               captured_reply.start_address, addr_idx);
      end else begin
        if (seen_reply[addr_idx]) begin
          report_sc_debug_state("T553 duplicate outstanding read reply");
          $error("sc_hub_tb_top: T553 duplicate reply for addr=0x%06h",
                 captured_reply.start_address);
        end
        seen_reply[addr_idx] = 1'b1;
      end

      expect_reply_header_ok(captured_reply, captured_reply.start_address, 4);
      if (captured_reply.payload_words != 4) begin
        $error("sc_hub_tb_top: T553 payload count mismatch addr=0x%06h exp=4 act=%0d",
               captured_reply.start_address,
               captured_reply.payload_words);
      end
      for (payload_idx = 0; payload_idx < 4 && payload_idx < captured_reply.payload_words; payload_idx++) begin
        if (captured_reply.payload[payload_idx] !== avmm_bfm_inst.mem[captured_reply.start_address[17:0] + payload_idx]) begin
          $error("sc_hub_tb_top: T553 payload[%0d] mismatch addr=0x%06h exp=0x%08h act=0x%08h",
                 payload_idx,
                 captured_reply.start_address,
                 avmm_bfm_inst.mem[captured_reply.start_address[17:0] + payload_idx],
                 captured_reply.payload[payload_idx]);
        end
      end
    end

    for (addr_idx = 0; addr_idx < 10; addr_idx++) begin
      if (!seen_reply[addr_idx]) begin
        report_sc_debug_state("T553 missing reply after receive loop");
        $error("sc_hub_tb_top: T553 never observed reply for addr=0x%06h",
               24'h000040 + (addr_idx * 4));
      end
    end

    read_csr_word(HUB_CSR_WO_EXT_PKT_RD_CONST, csr_word);
    if (csr_word != expected_pkt_rd) begin
      $error("sc_hub_tb_top: T553 EXT_PKT_RD mismatch exp=%0d act=%0d",
             expected_pkt_rd, csr_word);
    end

    read_csr_word(HUB_CSR_WO_EXT_WORD_RD_CONST, csr_word);
    if (csr_word != expected_word_rd) begin
      $error("sc_hub_tb_top: T553 EXT_WORD_RD mismatch exp=%0d act=%0d",
             expected_word_rd, csr_word);
    end

    read_pkt_drop_count(csr_word);
    if (csr_word != 32'd0) begin
      report_sc_debug_state("T553 unexpected packet drop during outstanding reads");
      $error("sc_hub_tb_top: T553 expected pkt_drop_count to remain zero");
    end

    if (dut_inst.pkt_rx_inst.rx_state != 0 ||
        dut_inst.pkt_in_progress != 1'b0 ||
        dut_inst.pkt_valid != 1'b0 ||
        dut_inst.core_inst.pending_pkt_count != 0 ||
        dut_inst.core_inst.pending_ext_count != 0) begin
      report_sc_debug_state("T553 expected quiescent end state");
      $error("sc_hub_tb_top: T553 expected the hub to quiesce after outstanding read stress");
    end

    report_sc_debug_state("T553 completed outstanding read stress");
  endtask

  task automatic run_t554();
    localparam int unsigned ROUND_COUNT_CONST           = 32;
    localparam int unsigned OUTSTANDING_READS_CONST     = 10;
    localparam int unsigned OUTSTANDING_READ_WORDS_CONST = 4;
    localparam int unsigned WRITE_READBACKS_CONST       = 4;
    localparam int unsigned WRITE_WORDS_CONST           = 3;

    logic [23:0] read_base_addr;
    logic [23:0] write_base_addr;
    logic [23:0] start_addr;
    logic [31:0] csr_word;
    logic [31:0] wr_words[$];
    bit          seen_reply[0:OUTSTANDING_READS_CONST - 1];
    int unsigned round_idx;
    int unsigned addr_idx;
    int unsigned rsp_idx;
    int unsigned payload_idx;
    int unsigned expected_pkt_rd;
    int unsigned expected_word_rd;
    int unsigned expected_pkt_wr;
    int unsigned expected_word_wr;

    clear_hub_counters();
    expected_pkt_rd  = 0;
    expected_word_rd = 0;
    expected_pkt_wr  = 0;
    expected_word_wr = 0;

    for (round_idx = 0; round_idx < ROUND_COUNT_CONST; round_idx++) begin
      read_base_addr  = 24'h001000 + (round_idx * 24'h000080);
      write_base_addr = 24'h002000 + (round_idx * 24'h000080);
      for (addr_idx = 0; addr_idx < OUTSTANDING_READS_CONST; addr_idx++) begin
        seen_reply[addr_idx] = 1'b0;
      end

      for (addr_idx = 0; addr_idx < OUTSTANDING_READS_CONST; addr_idx++) begin
        start_addr = read_base_addr + (addr_idx * 4);
        driver_inst.send_read(start_addr, OUTSTANDING_READ_WORDS_CONST);
      end

      expected_pkt_rd  = expected_pkt_rd + OUTSTANDING_READS_CONST;
      expected_word_rd = expected_word_rd + (OUTSTANDING_READS_CONST * OUTSTANDING_READ_WORDS_CONST);

      for (rsp_idx = 0; rsp_idx < OUTSTANDING_READS_CONST; rsp_idx++) begin
        monitor_inst.wait_reply_cycles(captured_reply, 2048);
        if (captured_reply.echoed_length === 16'hffff) begin
          report_sc_debug_state("T554 timed out waiting for outstanding read reply");
          $error("sc_hub_tb_top: T554 missing reply round=%0d rsp_idx=%0d",
                 round_idx, rsp_idx);
          return;
        end

        if ((captured_reply.start_address < read_base_addr) ||
            (captured_reply.start_address > (read_base_addr + ((OUTSTANDING_READS_CONST - 1) * 4))) ||
            (captured_reply.start_address[1:0] != 2'b00)) begin
          report_sc_debug_state("T554 unexpected outstanding reply address");
          $error("sc_hub_tb_top: T554 unexpected reply address round=%0d addr=0x%06h",
                 round_idx, captured_reply.start_address);
        end

        addr_idx = (captured_reply.start_address - read_base_addr) / 4;
        if (addr_idx >= OUTSTANDING_READS_CONST) begin
          report_sc_debug_state("T554 outstanding reply index out of range");
          $error("sc_hub_tb_top: T554 reply address index out of range round=%0d addr=0x%06h idx=%0d",
                 round_idx, captured_reply.start_address, addr_idx);
        end else begin
          if (seen_reply[addr_idx]) begin
            report_sc_debug_state("T554 duplicate outstanding read reply");
            $error("sc_hub_tb_top: T554 duplicate reply round=%0d addr=0x%06h",
                   round_idx, captured_reply.start_address);
          end
          seen_reply[addr_idx] = 1'b1;
        end

        expect_reply_header_ok(captured_reply,
                               captured_reply.start_address,
                               OUTSTANDING_READ_WORDS_CONST);
        if (captured_reply.payload_words != OUTSTANDING_READ_WORDS_CONST) begin
          $error("sc_hub_tb_top: T554 payload count mismatch round=%0d addr=0x%06h exp=%0d act=%0d",
                 round_idx,
                 captured_reply.start_address,
                 OUTSTANDING_READ_WORDS_CONST,
                 captured_reply.payload_words);
        end
        for (payload_idx = 0;
             payload_idx < OUTSTANDING_READ_WORDS_CONST && payload_idx < captured_reply.payload_words;
             payload_idx++) begin
          if (captured_reply.payload[payload_idx] !== expected_bus_word(captured_reply.start_address, payload_idx)) begin
            $error("sc_hub_tb_top: T554 payload[%0d] mismatch round=%0d addr=0x%06h exp=0x%08h act=0x%08h",
                   payload_idx,
                   round_idx,
                   captured_reply.start_address,
                   expected_bus_word(captured_reply.start_address, payload_idx),
                   captured_reply.payload[payload_idx]);
          end
        end
      end

      for (addr_idx = 0; addr_idx < OUTSTANDING_READS_CONST; addr_idx++) begin
        if (!seen_reply[addr_idx]) begin
          report_sc_debug_state("T554 missing outstanding reply after receive loop");
          $error("sc_hub_tb_top: T554 never observed reply round=%0d addr=0x%06h",
                 round_idx, read_base_addr + (addr_idx * 4));
        end
      end

      for (addr_idx = 0; addr_idx < WRITE_READBACKS_CONST; addr_idx++) begin
        start_addr = write_base_addr + (addr_idx * 4);
        fill_write_words(wr_words,
                         WRITE_WORDS_CONST,
                         32'h5600_0000 + (round_idx * 32'h100) + (addr_idx * 32'h10));
        driver_inst.send_write(start_addr, WRITE_WORDS_CONST, wr_words);
        monitor_inst.wait_reply(captured_reply);
        expect_write_reply(captured_reply, start_addr, WRITE_WORDS_CONST);

        driver_inst.send_read(start_addr, WRITE_WORDS_CONST);
        monitor_inst.wait_reply(captured_reply);
        expect_reply_header_ok(captured_reply, start_addr, WRITE_WORDS_CONST);
        if (captured_reply.payload_words != WRITE_WORDS_CONST) begin
          $error("sc_hub_tb_top: T554 readback payload count mismatch round=%0d addr=0x%06h exp=%0d act=%0d",
                 round_idx,
                 start_addr,
                 WRITE_WORDS_CONST,
                 captured_reply.payload_words);
        end
        for (payload_idx = 0; payload_idx < WRITE_WORDS_CONST && payload_idx < captured_reply.payload_words; payload_idx++) begin
          if (captured_reply.payload[payload_idx] !== wr_words[payload_idx]) begin
            $error("sc_hub_tb_top: T554 readback[%0d] mismatch round=%0d addr=0x%06h exp=0x%08h act=0x%08h",
                   payload_idx,
                   round_idx,
                   start_addr,
                   wr_words[payload_idx],
                   captured_reply.payload[payload_idx]);
          end
        end
      end

      expected_pkt_wr  = expected_pkt_wr + WRITE_READBACKS_CONST;
      expected_word_wr = expected_word_wr + (WRITE_READBACKS_CONST * WRITE_WORDS_CONST);
      expected_pkt_rd  = expected_pkt_rd + WRITE_READBACKS_CONST;
      expected_word_rd = expected_word_rd + (WRITE_READBACKS_CONST * WRITE_WORDS_CONST);

      if ((((round_idx + 1) % 8) == 0) || (round_idx + 1 == ROUND_COUNT_CONST)) begin
        read_csr_word(HUB_CSR_WO_EXT_PKT_RD_CONST, csr_word);
        if (csr_word != expected_pkt_rd) begin
          report_sc_debug_state("T554 EXT_PKT_RD mismatch during soak");
          $error("sc_hub_tb_top: T554 EXT_PKT_RD mismatch round=%0d exp=%0d act=%0d",
                 round_idx, expected_pkt_rd, csr_word);
        end

        read_csr_word(HUB_CSR_WO_EXT_WORD_RD_CONST, csr_word);
        if (csr_word != expected_word_rd) begin
          report_sc_debug_state("T554 EXT_WORD_RD mismatch during soak");
          $error("sc_hub_tb_top: T554 EXT_WORD_RD mismatch round=%0d exp=%0d act=%0d",
                 round_idx, expected_word_rd, csr_word);
        end

        read_csr_word(HUB_CSR_WO_EXT_PKT_WR_CONST, csr_word);
        if (csr_word != expected_pkt_wr) begin
          report_sc_debug_state("T554 EXT_PKT_WR mismatch during soak");
          $error("sc_hub_tb_top: T554 EXT_PKT_WR mismatch round=%0d exp=%0d act=%0d",
                 round_idx, expected_pkt_wr, csr_word);
        end

        read_csr_word(HUB_CSR_WO_EXT_WORD_WR_CONST, csr_word);
        if (csr_word != expected_word_wr) begin
          report_sc_debug_state("T554 EXT_WORD_WR mismatch during soak");
          $error("sc_hub_tb_top: T554 EXT_WORD_WR mismatch round=%0d exp=%0d act=%0d",
                 round_idx, expected_word_wr, csr_word);
        end

        read_pkt_drop_count(csr_word);
        if (csr_word != 32'd0) begin
          report_sc_debug_state("T554 unexpected packet drop during soak");
          $error("sc_hub_tb_top: T554 expected pkt_drop_count to remain zero during soak");
        end
      end
    end

    wait_clks(16);
    if (dut_inst.pkt_rx_inst.rx_state != 0 ||
        dut_inst.pkt_in_progress != 1'b0 ||
        dut_inst.pkt_valid != 1'b0 ||
        dut_inst.core_inst.pending_pkt_count != 0 ||
        dut_inst.core_inst.pending_ext_count != 0) begin
      report_sc_debug_state("T554 expected quiescent end state");
      $error("sc_hub_tb_top: T554 expected the hub to quiesce after soak traffic");
    end

    report_sc_debug_state("T554 completed long outstanding/readback soak");
  endtask
`endif

  task automatic run_t521();
    run_t517();
  endtask

  task automatic run_t525();
    run_t106();
  endtask

  task automatic run_t526();
    run_t107();
  endtask

  task automatic run_t527();
    run_t108();
  endtask

  task automatic run_t530();
    logic [31:0] wr_words[$];

    fill_write_words(wr_words, 8, 32'h5300_0000);
    clear_hub_counters();

    force avm_waitrequest = 1'b1;
    driver_inst.send_write(24'h000530, 8, wr_words);
    wait (avm_write === 1'b1);
    wait_clks(16);

    issue_masked_soft_reset();
    wait_clks(4);
    if (avm_write !== 1'b0 || avm_read !== 1'b0) begin
      $error("sc_hub_tb_top: T530 expected all bus strobes deasserted after CTRL.reset read=%0b write=%0b",
             avm_read,
             avm_write);
    end
    release avm_waitrequest;
    wait_clks(8);

    driver_inst.send_read(24'h000630, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000630, 1);
  endtask

  task automatic run_t531();
    for (int unsigned gap = 1; gap <= 10; gap++) begin
      issue_masked_soft_reset();
      wait_clks(gap);
      driver_inst.send_read(24'h000531 + gap, 1);
      monitor_inst.wait_reply(captured_reply);
      expect_read_reply(captured_reply, 24'h000531 + gap, 1);
    end
  endtask

  task automatic run_t535();
    logic [31:0] wr_words[$];
    logic [31:0] hub_cap_word;

    require_avalon_ord_disabled("T535");
    read_csr_word(16'h01F, hub_cap_word);
    if (hub_cap_word[1] !== 1'b0) begin
      $error("sc_hub_tb_top: T535 expected HUB_CAP.ORD bit to be 0 when ORD_ENABLE=false, act=0x%08h",
             hub_cap_word);
    end

    wr_words.push_back(32'h5350_0001);
    avmm_bfm_inst.mem[16'h0350] = 32'h1000_0350;
    driver_inst.send_ordered_write(24'h000350, 1, wr_words,
                                   SC_ORDER_RELEASE, 4'h1, 8'h01);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h000350, 1, 2'b10);
    expect_reply_metadata(captured_reply, SC_ORDER_RELEASE, 4'h1, 8'h01, 2'b00, 1'b0);
    if (captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T535 expected SLVERR write reply without payload");
    end
    if (avmm_bfm_inst.mem[16'h0350] !== 32'h1000_0350) begin
      $error("sc_hub_tb_top: T535 unsupported RELEASE write should not update memory act=0x%08h",
             avmm_bfm_inst.mem[16'h0350]);
    end
  endtask

  task automatic run_t536();
    logic [31:0] hub_cap_word;

    require_avalon_ord_disabled("T536");
    read_csr_word(16'h01F, hub_cap_word);
    if (hub_cap_word[1] !== 1'b0) begin
      $error("sc_hub_tb_top: T536 expected HUB_CAP.ORD bit to be 0 when ORD_ENABLE=false, act=0x%08h",
             hub_cap_word);
    end

    driver_inst.send_ordered_read(24'h000360, 1, SC_ORDER_ACQUIRE, 4'h1, 8'h02);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h000360, 1, 2'b10);
    expect_reply_metadata(captured_reply, SC_ORDER_ACQUIRE, 4'h1, 8'h02, 2'b00, 1'b0);
    if (captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T536 expected SLVERR acquire reply without payload");
    end
  endtask

  task automatic run_t537();
    logic [31:0] wr_words[$];
    logic [31:0] hub_cap_word;

    require_avalon_ord_disabled("T537");
    read_csr_word(16'h01F, hub_cap_word);
    if (hub_cap_word[1] !== 1'b0) begin
      $error("sc_hub_tb_top: T537 expected HUB_CAP.ORD bit to be 0 when ORD_ENABLE=false, act=0x%08h",
             hub_cap_word);
    end

    wr_words.push_back(32'h5370_0001);
    driver_inst.send_write(24'h000370, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000370, 1);
    driver_inst.send_read(24'h000370, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_ok(captured_reply, 24'h000370, 1);
    if (captured_reply.payload_words != 1) begin
      $error("sc_hub_tb_top: T537 expected one readback word, act=%0d",
             captured_reply.payload_words);
    end
    if (captured_reply.payload[0] !== wr_words[0]) begin
      $error("sc_hub_tb_top: T537 relaxed traffic mismatch exp=0x%08h act=0x%08h",
             wr_words[0],
             captured_reply.payload[0]);
    end
  endtask

  task automatic run_t538();
    logic [31:0] original_word;
    logic [31:0] hub_cap_word;

    require_avalon_atomic_disabled("T538");
    read_csr_word(16'h01F, hub_cap_word);
    if (hub_cap_word[2] !== 1'b0) begin
      $error("sc_hub_tb_top: T538 expected HUB_CAP.ATOMIC bit to be 0 when ATOMIC_ENABLE=false, act=0x%08h",
             hub_cap_word);
    end

    original_word = 32'h1234_ABCD;
    avmm_bfm_inst.mem[16'h0380] = original_word;
    driver_inst.send_atomic_rmw(24'h000380, 32'h0000_FFFF, 32'h0000_00AA,
                                SC_ORDER_RELAXED, 4'h0, 8'h00);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_rsp(captured_reply, 24'h000380, 1, 2'b10);
    expect_reply_metadata(captured_reply, SC_ORDER_RELAXED, 4'h0, 8'h00, 2'b00, 1'b1);
    if (captured_reply.payload_words != 0) begin
      $error("sc_hub_tb_top: T538 expected unsupported atomic reply without payload");
    end
    if (avmm_bfm_inst.mem[16'h0380] !== original_word) begin
      $error("sc_hub_tb_top: T538 unsupported atomic should not modify memory exp=0x%08h act=0x%08h",
             original_word,
             avmm_bfm_inst.mem[16'h0380]);
    end
  endtask

  task automatic run_t539();
    logic [31:0] wr_words[$];
    logic [31:0] hub_cap_word;

    require_avalon_atomic_disabled("T539");
    read_csr_word(16'h01F, hub_cap_word);
    if (hub_cap_word[2] !== 1'b0) begin
      $error("sc_hub_tb_top: T539 expected HUB_CAP.ATOMIC bit to be 0 when ATOMIC_ENABLE=false, act=0x%08h",
             hub_cap_word);
    end

    wr_words.push_back(32'h5390_0001);
    driver_inst.send_write(24'h000390, 1, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000390, 1);
    driver_inst.send_read(24'h000390, 1);
    monitor_inst.wait_reply(captured_reply);
    expect_reply_header_ok(captured_reply, 24'h000390, 1);
    if (captured_reply.payload_words != 1) begin
      $error("sc_hub_tb_top: T539 expected one readback word, act=%0d",
             captured_reply.payload_words);
    end
    if (captured_reply.payload[0] !== wr_words[0]) begin
      $error("sc_hub_tb_top: T539 non-atomic traffic mismatch exp=0x%08h act=0x%08h",
             wr_words[0],
             captured_reply.payload[0]);
    end
  endtask
`endif

  task automatic run_smoke_basic();
    logic [31:0] wr_words[$];

    wr_words.push_back(32'hCAFE_0001);
    wr_words.push_back(32'hCAFE_0002);
    wr_words.push_back(32'hCAFE_0003);
    wr_words.push_back(32'hCAFE_0004);

    driver_inst.send_read(24'h000020, 4);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h000020, 4);

    driver_inst.send_write(24'h000024, 4, wr_words);
    monitor_inst.wait_reply(captured_reply);
    expect_write_reply(captured_reply, 24'h000024, 4);
    check_bfm_words(24'h000024, wr_words);
  endtask

  initial begin
    clk = 1'b0;
    forever #3.2 clk = ~clk;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      cycle_counter <= 0;
    end else begin
      cycle_counter <= cycle_counter + 1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      t523_core_accept_count_dbg <= 0;
    end else if (test_name == "T523" && dut_inst.pkt_valid && dut_inst.rx_ready) begin
      t523_core_accept_count_dbg <= t523_core_accept_count_dbg + 1;
    end
  end

  initial begin
    rst                 = 1'b1;
    uplink_ready        = 1'b1;
    inject_rd_error     = 1'b0;
    inject_wr_error     = 1'b0;
    inject_decode_error = 1'b0;
    inject_rresp_err    = 1'b0;
    inject_bresp_err    = 1'b0;
    avs_csr_address     = '0;
    avs_csr_read        = 1'b0;
    avs_csr_write       = 1'b0;
    avs_csr_writedata   = '0;
    avs_csr_burstcount  = 1'b0;
    repeat (8) @(posedge clk);
    rst = 1'b0;
  end

`ifdef SC_HUB_BUS_AXI4
  always_ff @(posedge clk) begin
    if (rst) begin
      axi_aw_count               <= 0;
      axi_w_count                <= 0;
      axi_b_count                <= 0;
      axi_ar_count               <= 0;
      axi_r_count                <= 0;
      axi_wlast_count            <= 0;
      axi_rlast_count            <= 0;
      axi_last_awlen             <= '0;
      axi_last_arlen             <= '0;
      axi_last_awsize            <= '0;
      axi_last_arsize            <= '0;
      axi_last_awburst           <= '0;
      axi_last_arburst           <= '0;
      axi_last_awlock            <= 1'b0;
      axi_last_arlock            <= 1'b0;
      axi_last_awid              <= '0;
      axi_last_arid              <= '0;
      axi_last_bid               <= '0;
      axi_last_rid               <= '0;
      axi_last_wstrb             <= '0;
      axi_last_bresp             <= '0;
      axi_last_rresp             <= '0;
      axi_w_before_aw_violation  <= 1'b0;
      axi_arid_log.delete();
      axi_araddr_log.delete();
      axi_rid_log.delete();
    end else begin
      if (axi_awvalid && axi_awready) begin
        axi_aw_count     <= axi_aw_count + 1;
        axi_last_awlen   <= axi_awlen;
        axi_last_awsize  <= axi_awsize;
        axi_last_awburst <= axi_awburst;
        axi_last_awlock  <= axi_awlock;
        axi_last_awid    <= axi_awid;
      end

      if (axi_wvalid && axi_wready) begin
        axi_w_count     <= axi_w_count + 1;
        axi_last_wstrb  <= axi_wstrb;
        if (axi_aw_count == 0) begin
          axi_w_before_aw_violation <= 1'b1;
        end
        if (axi_wlast) begin
          axi_wlast_count <= axi_wlast_count + 1;
        end
      end

      if (axi_bvalid && axi_bready) begin
        axi_b_count    <= axi_b_count + 1;
        axi_last_bid   <= axi_bid;
        axi_last_bresp <= axi_bresp;
      end

      if (axi_arvalid && axi_arready) begin
        axi_ar_count     <= axi_ar_count + 1;
        axi_last_arlen   <= axi_arlen;
        axi_last_arsize  <= axi_arsize;
        axi_last_arburst <= axi_arburst;
        axi_last_arlock  <= axi_arlock;
        axi_last_arid    <= axi_arid;
        axi_arid_log.push_back(axi_arid);
        axi_araddr_log.push_back(axi_araddr);
      end

      if (axi_rvalid && axi_rready) begin
        axi_r_count    <= axi_r_count + 1;
        axi_last_rid   <= axi_rid;
        axi_last_rresp <= axi_rresp;
        axi_rid_log.push_back(axi_rid);
        if (axi_rlast) begin
          axi_rlast_count <= axi_rlast_count + 1;
        end
      end
    end
  end
`endif

  initial begin
    int unsigned timeout_cycles;

    wait (!rst);
    timeout_cycles = (test_name == "T523") ? T523_TIMEOUT_CYCLES : TIMEOUT_CYCLES;
    repeat (timeout_cycles) @(posedge clk);
`ifndef SC_HUB_BUS_AXI4
    if (test_name == "T523") begin
      $display("sc_hub_tb_top: T523 timeout state issued=%0d/%0d core_accept=%0d replies=%0d/%0d tracked=%0d pending=%0d rd_fifo=%0d dl_fifo=%0d bp=%0d rx_q=%0d state=%0d tx_start=%0b tx_ready=%0b tx_valid=%0b tx_data_ready=%0b rd_empty=%0b stream_idx=%0d reply_words=%0d has_data=%0b suppress=%0b rsp=%0b pkt_addr=0x%06h tx_pkt_count=%0d link_ready=%0b dl_ready=%0b pkt_in_progress=%0b rx_state=%0d",
               t523_issue_count_dbg,
               t523_txn_count_dbg,
               t523_core_accept_count_dbg,
               t523_reply_count_dbg,
               t523_txn_count_dbg,
               dut_inst.core_inst.tracked_pkt_count,
               dut_inst.core_inst.pending_pkt_count,
               dut_inst.core_inst.rd_fifo_usedw,
               dut_inst.dl_fifo_usedw,
               dut_inst.bp_usedw,
               dut_inst.pkt_rx_inst.pkt_queue_count,
               dut_inst.core_inst.core_state,
               dut_inst.tx_reply_start,
               dut_inst.tx_reply_ready,
               dut_inst.tx_data_valid,
               dut_inst.tx_data_ready,
               dut_inst.core_inst.rd_fifo_empty,
               dut_inst.core_inst.reply_stream_index,
               dut_inst.core_inst.pkt_info_reg.rw_length,
               dut_inst.core_inst.reply_has_data_reg,
               dut_inst.core_inst.reply_suppress_reg,
               dut_inst.core_inst.response_reg,
               dut_inst.core_inst.pkt_info_reg.start_address,
               dut_inst.pkt_tx_inst.pkt_count,
               link_ready,
               dut_inst.download_ready_int,
               dut_inst.pkt_in_progress,
               dut_inst.pkt_rx_inst.rx_state);
      $display("sc_hub_tb_top: T523 monitor_seen=%0d monitor_q=%0d pkt_drop_cnt=%0d bp_overflow=%0b",
               monitor_inst.reply_seen_count,
               monitor_inst.reply_queue.size(),
               dut_inst.pkt_rx_inst.pkt_drop_count,
               dut_inst.pkt_tx_inst.bp_overflow_sticky);
      $display("sc_hub_tb_top: T523 seen_by_kind wr=%0d rd=%0d ord=%0d",
               t523_write_reply_count_dbg,
               t523_read_reply_count_dbg,
               t523_ordered_reply_count_dbg);
      $display("sc_hub_tb_top: T523 ext_counts pkt_rd=%0d pkt_wr=%0d word_rd=%0d word_wr=%0d last_rd_addr=0x%08h last_wr_addr=0x%08h",
               dut_inst.core_inst.ext_pkt_read_count,
               dut_inst.core_inst.ext_pkt_write_count,
               dut_inst.core_inst.ext_word_read_count,
               dut_inst.core_inst.ext_word_write_count,
               dut_inst.core_inst.last_ext_read_addr,
               dut_inst.core_inst.last_ext_write_addr);
      $display("sc_hub_tb_top: T523 rx_debug enqueue=%0d restart=%0d ignored_preamble=%0d",
               dut_inst.pkt_rx_inst.debug_enqueue_count,
               dut_inst.pkt_rx_inst.debug_restart_count,
               dut_inst.pkt_rx_inst.debug_ignored_preamble_count);
    end
`endif
    $error("sc_hub_tb_top: timeout waiting for TEST_NAME=%s to complete", test_name);
    $finish;
  end

  sc_pkt_driver driver_inst (
    .clk       (clk),
    .rst       (rst),
    .link_ready(link_ready),
    .link_data (link_data),
    .link_datak(link_datak)
  );

  sc_pkt_monitor monitor_inst (
    .clk      (clk),
    .rst      (rst),
    .aso_data (uplink_data),
    .aso_valid(uplink_valid),
    .aso_ready(uplink_ready),
    .aso_sop  (uplink_sop),
    .aso_eop  (uplink_eop)
  );

  sc_hub_scoreboard scoreboard_inst (
    .clk(clk),
    .rst(rst)
  );

  sc_hub_ord_checker ord_checker_inst (
    .clk                (clk),
    .rst                (rst),
    .monitor_enable     (1'b0),
    .sample_valid       (1'b0),
    .sample_order_mode  (2'b00),
    .sample_order_domain (4'h0),
    .sample_order_epoch  (8'h00),
    .sample_retire_valid (1'b0)
  );

  sc_hub_freelist_monitor freelist_monitor_inst (
    .clk            (clk),
    .rst            (rst),
    .monitor_enable (1'b0),
    .sample_done    (1'b0)
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
    .i_download_data            (link_data),
    .i_download_datak           (link_datak),
    .o_download_ready           (link_ready),
    .aso_upload_data            (uplink_data),
    .aso_upload_valid           (uplink_valid),
    .aso_upload_ready           (uplink_ready),
    .aso_upload_startofpacket   (uplink_sop),
    .aso_upload_endofpacket     (uplink_eop),
    .m_axi_awid                 (axi_awid),
    .m_axi_awaddr               (axi_awaddr),
    .m_axi_awlen                (axi_awlen),
    .m_axi_awsize               (axi_awsize),
    .m_axi_awburst              (axi_awburst),
    .m_axi_awlock               (axi_awlock),
    .m_axi_awvalid              (axi_awvalid),
    .m_axi_awready              (axi_awready),
    .m_axi_wdata                (axi_wdata),
    .m_axi_wstrb                (axi_wstrb),
    .m_axi_wlast                (axi_wlast),
    .m_axi_wvalid               (axi_wvalid),
    .m_axi_wready               (axi_wready),
    .m_axi_bid                  (axi_bid),
    .m_axi_bresp                (axi_bresp),
    .m_axi_bvalid               (axi_bvalid),
    .m_axi_bready               (axi_bready),
    .m_axi_arid                 (axi_arid),
    .m_axi_araddr               (axi_araddr),
    .m_axi_arlen                (axi_arlen),
    .m_axi_arsize               (axi_arsize),
    .m_axi_arburst              (axi_arburst),
    .m_axi_arlock               (axi_arlock),
    .m_axi_arvalid              (axi_arvalid),
    .m_axi_arready              (axi_arready),
    .m_axi_rid                  (axi_rid),
    .m_axi_rdata                (axi_rdata),
    .m_axi_rresp                (axi_rresp),
    .m_axi_rlast                (axi_rlast),
    .m_axi_rvalid               (axi_rvalid),
    .m_axi_rready               (axi_rready)
  );

  axi4_slave_bfm axi4_bfm_inst (
    .clk             (clk),
    .rst             (rst),
    .awid            (axi_awid),
    .awaddr          (axi_awaddr),
    .awlen           (axi_awlen),
    .awsize          (axi_awsize),
    .awburst         (axi_awburst),
    .awlock          (axi_awlock),
    .awvalid         (axi_awvalid),
    .awready         (axi_awready),
    .wdata           (axi_wdata),
    .wstrb           (axi_wstrb),
    .wlast           (axi_wlast),
    .wvalid          (axi_wvalid),
    .wready          (axi_wready),
    .bid             (axi_bid),
    .bresp           (axi_bresp),
    .bvalid          (axi_bvalid),
    .bready          (axi_bready),
    .arid            (axi_arid),
    .araddr          (axi_araddr),
    .arlen           (axi_arlen),
    .arsize          (axi_arsize),
    .arburst         (axi_arburst),
    .arlock          (axi_arlock),
    .arvalid         (axi_arvalid),
    .arready         (axi_arready),
    .rid             (axi_rid),
    .rdata           (axi_rdata),
    .rresp           (axi_rresp),
    .rlast           (axi_rlast),
    .rvalid          (axi_rvalid),
    .rready          (axi_rready),
    .inject_rd_error (inject_rd_error),
    .inject_wr_error (inject_wr_error),
    .inject_decode_error(inject_decode_error),
    .inject_rresp_err(inject_rresp_err),
    .inject_bresp_err(inject_bresp_err)
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
    .i_download_data            (link_data),
    .i_download_datak           (link_datak),
    .o_download_ready           (link_ready),
    .aso_upload_data            (uplink_data),
    .aso_upload_valid           (uplink_valid),
    .aso_upload_ready           (uplink_ready),
    .aso_upload_startofpacket   (uplink_sop),
    .aso_upload_endofpacket     (uplink_eop),
    .avm_hub_address            (avm_address),
    .avm_hub_read               (avm_read),
    .avm_hub_readdata           (avm_readdata),
    .avm_hub_writeresponsevalid (avm_writeresponsevalid),
    .avm_hub_response           (avm_response),
    .avm_hub_write              (avm_write),
    .avm_hub_writedata          (avm_writedata),
    .avm_hub_waitrequest        (avm_waitrequest),
    .avm_hub_readdatavalid      (avm_readdatavalid),
    .avm_hub_burstcount         (avm_burstcount),
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
    .clk                  (clk),
    .rst                  (rst),
    .avm_address          (avm_address),
    .avm_read             (avm_read),
    .avm_readdata         (avm_readdata),
    .avm_writeresponsevalid(avm_writeresponsevalid),
    .avm_response         (avm_response),
    .avm_write            (avm_write),
    .avm_writedata        (avm_writedata),
    .avm_waitrequest      (avm_waitrequest),
    .avm_readdatavalid    (avm_readdatavalid),
    .avm_burstcount       (avm_burstcount),
    .inject_rd_error      (inject_rd_error),
    .inject_wr_error      (inject_wr_error),
    .inject_decode_error  (inject_decode_error)
  );
`endif

  sc_hub_assertions assertions_inst (
    .clk         (clk),
    .rst         (rst),
    .link_ready  (link_ready),
    .link_data   (link_data),
    .link_datak  (link_datak),
    .uplink_valid(uplink_valid),
    .uplink_ready(uplink_ready),
    .uplink_data (uplink_data),
    .uplink_sop  (uplink_sop),
    .uplink_eop  (uplink_eop),
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
    .axi_awid    (axi_awid),
    .axi_awaddr  (axi_awaddr),
    .axi_awlen   (axi_awlen),
    .axi_awsize  (axi_awsize),
    .axi_awburst (axi_awburst),
    .axi_awvalid (axi_awvalid),
    .axi_awready (axi_awready),
    .axi_wdata   (axi_wdata),
    .axi_wstrb   (axi_wstrb),
    .axi_wlast   (axi_wlast),
    .axi_wvalid  (axi_wvalid),
    .axi_wready  (axi_wready),
    .axi_bid     (axi_bid),
    .axi_bresp   (axi_bresp),
    .axi_bvalid  (axi_bvalid),
    .axi_bready  (axi_bready),
    .axi_arid    (axi_arid),
    .axi_araddr  (axi_araddr),
    .axi_arlen   (axi_arlen),
    .axi_arsize  (axi_arsize),
    .axi_arburst (axi_arburst),
    .axi_arvalid (axi_arvalid),
    .axi_arready (axi_arready),
    .axi_rid     (axi_rid),
    .axi_rdata   (axi_rdata),
    .axi_rresp   (axi_rresp),
    .axi_rlast   (axi_rlast),
    .axi_rvalid  (axi_rvalid),
    .axi_rready  (axi_rready)
`else
    ,
    .avm_read        (avm_read),
    .avm_write       (avm_write),
    .avm_address     (avm_address),
    .avm_writedata   (avm_writedata),
    .avm_waitrequest (avm_waitrequest),
    .avm_response    (avm_response),
    .avm_burstcount  (avm_burstcount)
`endif
  );

  initial begin
    wait (!rst);
    repeat (4) @(posedge clk);
    if (!$value$plusargs("TEST_NAME=%s", test_name)) begin
      test_name = "smoke_basic";
    end
    $display("sc_hub_tb_top: directed scaffold ready (%s)",
`ifdef SC_HUB_BUS_AXI4
             "AXI4"
`else
             "AVALON"
`endif
    );

    case (test_name)
      "T001": begin
        run_t001();
      end
      "T002": begin
        run_t002();
      end
      "T003": begin
        run_t003();
      end
      "T004": begin
        run_t004();
      end
      "T005": begin
        run_t005();
      end
      "T006": begin
        run_t006();
      end
      "T007": begin
        run_t007();
      end
      "T008": begin
        run_t008();
      end
      "T009": begin
        run_t009();
      end
      "T010": begin
        run_t010();
      end
      "T011": begin
        run_t011();
      end
      "T012": begin
        run_t012();
      end
`ifdef SC_HUB_BUS_AXI4
      "T026": begin
        run_t026();
      end
      "T013": begin
        run_t013();
      end
      "T014": begin
        run_t014();
      end
      "T015": begin
        run_t015();
      end
      "T016": begin
        run_t016();
      end
      "T017": begin
        run_t017();
      end
      "T018": begin
        run_t018();
      end
      "T019": begin
        run_t019();
      end
      "T020": begin
        run_t020();
      end
      "T021": begin
        run_t021();
      end
      "T022": begin
        run_t022();
      end
      "T023": begin
        run_t023();
      end
      "T024": begin
        run_t024();
      end
      "T040": begin
        run_t040();
      end
`endif
      "T025": begin
        run_t025();
      end
      "T027": begin
        run_t027();
      end
      "T028": begin
        run_t028();
      end
      "T029": begin
        run_t029();
      end
      "T030": begin
        run_t030();
      end
      "T031": begin
        run_t031();
      end
      "T032": begin
        run_t032();
      end
      "T033": begin
        run_t033();
      end
      "T034": begin
        run_t034();
      end
      "T035": begin
        run_t035();
      end
      "T036": begin
        run_t036();
      end
      "T037": begin
        run_t037();
      end
      "T038": begin
        run_t038();
      end
      "T039": begin
        run_t039();
      end
      "T041": begin
        run_t041();
      end
      "T042": begin
        run_t042();
      end
      "T043": begin
        run_t043();
      end
      "T044": begin
        run_t044();
      end
      "T045": begin
        run_t045();
      end
      "T046": begin
        run_t046();
      end
      "T047": begin
        run_t047();
      end
      "T048": begin
        run_t048();
      end
      "T049": begin
        run_t049();
      end
      "T050": begin
        run_t050();
      end
      "T051": begin
        run_t051();
      end
      "T052": begin
        run_t052();
      end
      "T053": begin
        run_t053();
      end
      "T054": begin
        run_t054();
      end
      "T055": begin
        run_t055();
      end
      "T056": begin
        run_t056();
      end
      "T057": begin
        run_t057();
      end
      "T058": begin
        run_t058();
      end
      "T059": begin
        run_t059();
      end
      "T060": begin
        run_t060();
      end
      "T061": begin
        run_t061();
      end
      "T062": begin
        run_t062();
      end
      "T063": begin
        run_t063();
      end
      "T064": begin
        run_t064();
      end
      "T065": begin
        run_t065();
      end
      "T066": begin
        run_t066();
      end
      "T067": begin
        run_t067();
      end
      "T068": begin
        run_t068();
      end
      "T069": begin
        run_t069();
      end
      "T070": begin
        run_t070();
      end
      "T123": begin
        run_t123();
      end
      "T124": begin
        run_t124();
      end
      "T125": begin
        run_t125();
      end
      "T126": begin
        run_t126();
      end
      "T127": begin
        run_t127();
      end
      "T128": begin
        run_t128();
      end
`ifdef SC_HUB_BUS_AXI4
      "T071": begin
        run_t071();
      end
      "T072": begin
        run_t072();
      end
      "T073": begin
        run_t073();
      end
      "T074": begin
        run_t074();
      end
      "T075": begin
        run_t075();
      end
      "T076": begin
        run_t076();
      end
      "T084": begin
        run_t084();
      end
      "T085": begin
        run_t085();
      end
      "T086": begin
        run_t086();
      end
      "T089": begin
        run_t089();
      end
      "T090": begin
        run_t090();
      end
      "T091": begin
        run_t091();
      end
      "T092": begin
        run_t092();
      end
      "T093": begin
        run_t093();
      end
      "T094": begin
        run_t094();
      end
      "T129": begin
        run_t129();
      end
      "T130": begin
        run_t130();
      end
      "T210": begin
        run_t210();
      end
      "T211": begin
        run_t211();
      end
      "T212": begin
        run_t212();
      end
      "T213": begin
        run_t213();
      end
      "T214": begin
        run_t214();
      end
      "T215": begin
        run_t215();
      end
      "T216": begin
        run_t216();
      end
      "T217": begin
        run_t217();
      end
      "T219": begin
        run_t219();
      end
      "T226": begin
        run_t226();
      end
      "T243": begin
        sc_reply_t   replies[0:15];
        bit          seen_dom1[0:3];
        bit          dom1_reordered;

        reset_axi4_rd_latencies(1);
        write_ooo_ctrl(1'b1);
        set_axi4_rd_latency(24'h001D00, 50);
        set_axi4_rd_latency(24'h001D10, 8);
        set_axi4_rd_latency(24'h001D20, 2);
        set_axi4_rd_latency(24'h001D30, 6);
        set_axi4_rd_latency(24'h001D40, 4);

        driver_inst.send_ordered_read(24'h001D00, 1, SC_ORDER_ACQUIRE, 4'h0, 8'h01);
        driver_inst.send_ordered_read(24'h001D10, 1, SC_ORDER_RELAXED, 4'h1, 8'h10);
        driver_inst.send_ordered_read(24'h001D20, 1, SC_ORDER_RELAXED, 4'h1, 8'h11);
        driver_inst.send_ordered_read(24'h001D30, 1, SC_ORDER_RELAXED, 4'h1, 8'h12);
        driver_inst.send_ordered_read(24'h001D40, 1, SC_ORDER_RELAXED, 4'h1, 8'h13);
        collect_replies(5, replies);

        seen_dom1      = '{default: 1'b0};
        dom1_reordered = 1'b0;
        for (int unsigned idx = 0; idx < 5; idx++) begin
          if (replies[idx].start_address == 24'h001D00) begin
            if (idx != 4) begin
              $error("sc_hub_tb_top: T243 expected dom0 ACQUIRE reply last act_idx=%0d", idx);
            end
            expect_reply_header_rsp(replies[idx], 24'h001D00, 1, 2'b00);
            expect_reply_metadata(replies[idx], SC_ORDER_ACQUIRE, 4'h0, 8'h01, 2'b00, 1'b0);
          end else begin
            int unsigned dom1_idx;
            dom1_idx = (replies[idx].start_address - 24'h001D10) / 16;
            if (idx == 4 || dom1_idx > 3) begin
              $error("sc_hub_tb_top: T243 unexpected dom1 reply idx=%0d addr=0x%06h",
                     idx, replies[idx].start_address);
            end else begin
              if (seen_dom1[dom1_idx]) begin
                $error("sc_hub_tb_top: T243 duplicate dom1 reply addr=0x%06h",
                       replies[idx].start_address);
              end
              seen_dom1[dom1_idx] = 1'b1;
              if (dom1_idx != idx) begin
                dom1_reordered = 1'b1;
              end
            end
            expect_reply_header_rsp(replies[idx], 24'h001D10 + (dom1_idx * 16), 1, 2'b00);
            expect_reply_metadata(replies[idx], SC_ORDER_RELAXED, 4'h1, 8'h10 + dom1_idx, 2'b00, 1'b0);
          end
        end
        if (!dom1_reordered) begin
          $error("sc_hub_tb_top: T243 expected dom1 replies to complete out of issue order");
        end
      end
      "T430": begin
        run_t430();
      end
      "T431": begin
        run_t431();
      end
      "T433": begin
        sc_reply_t   replies[0:15];
        bit          seen_dom1[0:3];
        bit          dom1_reordered;

        reset_axi4_rd_latencies(1);
        write_ooo_ctrl(1'b1);
        set_axi4_rd_latency(24'h001D00, 50);
        set_axi4_rd_latency(24'h001D10, 8);
        set_axi4_rd_latency(24'h001D20, 2);
        set_axi4_rd_latency(24'h001D30, 6);
        set_axi4_rd_latency(24'h001D40, 4);

        driver_inst.send_ordered_read(24'h001D00, 1, SC_ORDER_ACQUIRE, 4'h0, 8'h01);
        driver_inst.send_ordered_read(24'h001D10, 1, SC_ORDER_RELAXED, 4'h1, 8'h10);
        driver_inst.send_ordered_read(24'h001D20, 1, SC_ORDER_RELAXED, 4'h1, 8'h11);
        driver_inst.send_ordered_read(24'h001D30, 1, SC_ORDER_RELAXED, 4'h1, 8'h12);
        driver_inst.send_ordered_read(24'h001D40, 1, SC_ORDER_RELAXED, 4'h1, 8'h13);
        collect_replies(5, replies);

        seen_dom1      = '{default: 1'b0};
        dom1_reordered = 1'b0;
        for (int unsigned idx = 0; idx < 5; idx++) begin
          if (replies[idx].start_address == 24'h001D00) begin
            if (idx != 4) begin
              $error("sc_hub_tb_top: T433 expected dom0 ACQUIRE reply last act_idx=%0d", idx);
            end
            expect_reply_header_rsp(replies[idx], 24'h001D00, 1, 2'b00);
            expect_reply_metadata(replies[idx], SC_ORDER_ACQUIRE, 4'h0, 8'h01, 2'b00, 1'b0);
          end else begin
            int unsigned dom1_idx;
            dom1_idx = (replies[idx].start_address - 24'h001D10) / 16;
            if (idx == 4 || dom1_idx > 3) begin
              $error("sc_hub_tb_top: T433 unexpected dom1 reply idx=%0d addr=0x%06h",
                     idx, replies[idx].start_address);
            end else begin
              if (seen_dom1[dom1_idx]) begin
                $error("sc_hub_tb_top: T433 duplicate dom1 reply addr=0x%06h",
                       replies[idx].start_address);
              end
              seen_dom1[dom1_idx] = 1'b1;
              if (dom1_idx != idx) begin
                dom1_reordered = 1'b1;
              end
            end
            expect_reply_header_rsp(replies[idx], 24'h001D10 + (dom1_idx * 16), 1, 2'b00);
            expect_reply_metadata(replies[idx], SC_ORDER_RELAXED, 4'h1, 8'h10 + dom1_idx, 2'b00, 1'b0);
          end
        end
        if (!dom1_reordered) begin
          $error("sc_hub_tb_top: T433 expected dom1 replies to complete out of issue order");
        end
      end
      "T407": begin
        run_t407();
      end
      "T408": begin
        run_t408();
      end
      "T409": begin
        run_t409();
      end
      "T504": begin
        run_t504();
      end
      "T505": begin
        run_t505();
      end
      "T506": begin
        run_t506();
      end
      "T507": begin
        run_t507();
      end
      "T508": begin
        run_t508();
      end
      "T532": begin
        run_t532();
      end
      "T533": begin
        run_t533();
      end
      "T534": begin
        run_t534();
      end
      "T535": begin
        run_t535();
      end
      "T536": begin
        run_t536();
      end
      "T537": begin
        run_t537();
      end
      "T538": begin
        run_t538();
      end
      "T539": begin
        run_t539();
      end
      "T545": begin
        run_t545();
      end
`else
      "T077": begin
        run_t077();
      end
      "T078": begin
        run_t078();
      end
      "T079": begin
        run_t079();
      end
      "T080": begin
        run_t080();
      end
      "T081": begin
        run_t081();
      end
      "T082": begin
        run_t082();
      end
      "T083": begin
        run_t083();
      end
      "T087": begin
        run_t087();
      end
      "T088": begin
        run_t088();
      end
      "T089": begin
        run_t089();
      end
      "T090": begin
        run_t090();
      end
      "T091": begin
        run_t091();
      end
      "T092": begin
        run_t092();
      end
      "T093": begin
        run_t093();
      end
      "T094": begin
        run_t094();
      end
      "T095": begin
        run_t095();
      end
      "T096": begin
        run_t096();
      end
      "T097": begin
        run_t097();
      end
      "T098": begin
        run_t098();
      end
      "T099": begin
        run_t099();
      end
      "T100": begin
        run_t100();
      end
      "T101": begin
        run_t101();
      end
      "T102": begin
        run_t102();
      end
      "T103": begin
        run_t103();
      end
      "T104": begin
        run_t104();
      end
      "T105": begin
        run_t105();
      end
      "T106": begin
        run_t106();
      end
      "T107": begin
        run_t107();
      end
      "T108": begin
        run_t108();
      end
      "T109": begin
        run_t109();
      end
      "T110": begin
        run_t110();
      end
      "T111": begin
        run_t111();
      end
      "T112": begin
        run_t112();
      end
      "T113": begin
        run_t113();
      end
      "T114": begin
        run_t114();
      end
      "T115": begin
        run_t115();
      end
      "T129": begin
        run_t129();
      end
      "T130": begin
        run_t130();
      end
      "T116": begin
        run_t116();
      end
      "T117": begin
        run_t117();
      end
      "T118": begin
        run_t118();
      end
      "T119": begin
        run_t119();
      end
      "T120": begin
        run_t120();
      end
      "T121": begin
        run_t121();
      end
      "T122": begin
        run_t122();
      end
      "T415": begin
        run_t415();
      end
      "T416": begin
        run_t416();
      end
      "T417": begin
        run_t417();
      end
      "T418": begin
        run_t418();
      end
      "T419": begin
        run_t419();
      end
      "T420": begin
        run_t420();
      end
      "T421": begin
        run_t421();
      end
      "T425": begin
        run_t425();
      end
      "T426": begin
        run_t426();
      end
      "T218": begin
        run_t218();
      end
      "T200": begin
        run_t200();
      end
      "T201": begin
        run_t201();
      end
      "T202": begin
        run_t202();
      end
      "T203": begin
        run_t203();
      end
      "T204": begin
        run_t204();
      end
      "T205": begin
        run_t205();
      end
      "T206": begin
        run_t206();
      end
      "T207": begin
        run_t207();
      end
      "T208": begin
        run_t208();
      end
      "T209": begin
        run_t209();
      end
      "T220": begin
        run_t220();
      end
      "T221": begin
        run_t221();
      end
      "T222": begin
        run_t222();
      end
      "T223": begin
        run_t223();
      end
      "T224": begin
        run_t224();
      end
      "T225": begin
        run_t225();
      end
      "T227": begin
        run_t227();
      end
      "T228": begin
        run_t228();
      end
      "T229": begin
        run_t229();
      end
      "T230": begin
        run_t230();
      end
      "T231": begin
        run_t231();
      end
      "T232": begin
        run_t232();
      end
      "T233": begin
        run_t233();
      end
      "T234": begin
        run_t234();
      end
      "T235": begin
        run_t235();
      end
      "T236": begin
        run_t236();
      end
      "T427": begin
        run_t427();
      end
      "T428": begin
        run_t428();
      end
      "T429": begin
        run_t429();
      end
      "T434": begin
        run_t434();
      end
      "T435": begin
        run_t435();
      end
      "T436": begin
        run_t436();
      end
      "T437": begin
        run_t437();
      end
      "T438": begin
        run_t438();
      end
      "T439": begin
        run_t439();
      end
      "T440": begin
        run_t440();
      end
      "T441": begin
        run_t441();
      end
      "T442": begin
        run_t442();
      end
      "T443": begin
        run_t443();
      end
      "T237": begin
        run_t237();
      end
      "T238": begin
        run_t238();
      end
      "T239": begin
        run_t239();
      end
      "T240": begin
        run_t240();
      end
      "T241": begin
        run_t241();
      end
      "T242": begin
        run_t242();
      end
      "T245": begin
        run_t245();
      end
      "T244": begin
        run_t244();
      end
      "T246": begin
        run_t246();
      end
      "T247": begin
        run_t247();
      end
      "T248": begin
        run_t248();
      end
      "T249": begin
        run_t249();
      end
      "T444": begin
        run_t444();
      end
      "T445": begin
        run_t445();
      end
      "T446": begin
        run_t446();
      end
      "T447": begin
        run_t447();
      end
      "T448": begin
        run_t448();
      end
      "T449": begin
        run_t449();
      end
      "T500": begin
        run_t500();
      end
      "T501": begin
        run_t501();
      end
      "T502": begin
        run_t502();
      end
      "T503": begin
        run_t503();
      end
      "T509": begin
        run_t509();
      end
      "T510": begin
        run_t510();
      end
      "T511": begin
        run_t511();
      end
      "T512": begin
        run_t512();
      end
      "T513": begin
        run_t513();
      end
      "T514": begin
        run_t514();
      end
      "T515": begin
        run_t515();
      end
      "T516": begin
        run_t516();
      end
      "T517": begin
        run_t517();
      end
      "T518": begin
        run_t518();
      end
      "T519": begin
        run_t519();
      end
      "T520": begin
        run_t520();
      end
      "T521": begin
        run_t521();
      end
      "T525": begin
        run_t525();
      end
      "T526": begin
        run_t526();
      end
      "T527": begin
        run_t527();
      end
      "T530": begin
        run_t530();
      end
      "T531": begin
        run_t531();
      end
      "T432": begin
        run_t432();
      end
      "T400": begin
        run_t400();
      end
      "T401": begin
        run_t401();
      end
      "T402": begin
        run_t402();
      end
      "T403": begin
        run_t403();
      end
      "T404": begin
        run_t404();
      end
      "T405": begin
        run_t405();
      end
      "T406": begin
        run_t406();
      end
      "T410": begin
        run_t410();
      end
      "T411": begin
        run_t411();
      end
      "T412": begin
        run_t412();
      end
      "T413": begin
        run_t413();
      end
      "T414": begin
        run_t414();
      end
      "T422": begin
        run_t422();
      end
      "T423": begin
        run_t423();
      end
      "T424": begin
        run_t424();
      end
      "T535": begin
        run_t535();
      end
      "T536": begin
        run_t536();
      end
      "T537": begin
        run_t537();
      end
      "T538": begin
        run_t538();
      end
      "T539": begin
        run_t539();
      end
      "T522": begin
        run_t522();
      end
      "T523": begin
        run_t523();
      end
      "T524": begin
        run_t524();
      end
      "T528": begin
        run_t528();
      end
      "T529": begin
        run_t529();
      end
      "T540": begin
        run_t540();
      end
      "T541": begin
        run_t541();
      end
      "T542": begin
        run_t542();
      end
      "T543": begin
        run_t543();
      end
      "T544": begin
        run_t544();
      end
      "T546": begin
        run_t546();
      end
      "T547": begin
        run_t547();
      end
      "T548": begin
        run_t548();
      end
      "T549": begin
        run_t549();
      end
      "T550": begin
        run_t550();
      end
      "T551": begin
        run_t551();
      end
      "T552": begin
        run_t552();
      end
      "T553": begin
        run_t553();
      end
      "T554": begin
        run_t554();
      end
`endif
      "smoke_basic": begin
        run_smoke_basic();
      end
      default: begin
        $fatal(1, "sc_hub_tb_top: unknown TEST_NAME=%s", test_name);
      end
    endcase

    repeat (40) @(posedge clk);
    scoreboard_inst.report_summary();
    ord_checker_inst.report_summary();
    freelist_monitor_inst.report_summary();
    $finish;
  end
endmodule
