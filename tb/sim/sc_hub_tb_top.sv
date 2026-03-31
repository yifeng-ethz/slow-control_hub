`timescale 1ns/1ps

module sc_hub_tb_top;
  import sc_hub_sim_pkg::*;
  import sc_hub_ref_model_pkg::*;

  localparam int unsigned TIMEOUT_CYCLES = 200000;

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

  logic [15:0] avm_address;
  logic        avm_read;
  logic [31:0] avm_readdata;
  logic        avm_writeresponsevalid;
  logic [1:0]  avm_response;
  logic        avm_write;
  logic [31:0] avm_writedata;
  logic        avm_waitrequest;
  logic        avm_readdatavalid;
  logic [8:0]  avm_burstcount;

  logic [3:0]  axi_awid;
  logic [15:0] axi_awaddr;
  logic [7:0]  axi_awlen;
  logic [2:0]  axi_awsize;
  logic [1:0]  axi_awburst;
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
  logic [15:0] axi_araddr;
  logic [7:0]  axi_arlen;
  logic [2:0]  axi_arsize;
  logic [1:0]  axi_arburst;
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
  logic [3:0] axi_last_awid;
  logic [3:0] axi_last_arid;
  logic [3:0] axi_last_bid;
  logic [3:0] axi_last_rid;
  logic [3:0] axi_last_wstrb;
  logic [1:0] axi_last_bresp;
  logic [1:0] axi_last_rresp;
  logic       axi_w_before_aw_violation;
`endif

  sc_reply_t captured_reply;
  string     test_name;
  longint unsigned cycle_counter;

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

  task automatic expect_reply_header_ok(
    input sc_reply_t    reply,
    input logic [23:0]  expected_start_address,
    input int unsigned  expected_length
  );
    scoreboard_inst.expect_header_ok(reply, expected_length);
    if (reply.start_address !== expected_start_address) begin
      $error("sc_hub_tb_top: start address mismatch exp=0x%06h act=0x%06h",
             expected_start_address, reply.start_address);
    end
    if (reply.header_word[31:30] !== 2'b00) begin
      $error("sc_hub_tb_top: header reserved bits[31:30] exp=0 act=0x%0h",
             reply.header_word[31:30]);
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

  task automatic clear_hub_counters();
    write_csr_word(16'h002, 32'h0000_0003);
  endtask

  task automatic trigger_avmm_read_timeout(
    input  logic [23:0] start_address,
    input  int unsigned word_count,
    output sc_reply_t   timeout_reply
  );
    force avm_readdatavalid = 1'b0;
    force avm_response      = 2'b00;
    driver_inst.send_read(start_address, word_count);
    monitor_inst.wait_reply(timeout_reply);
    release avm_readdatavalid;
    release avm_response;
  endtask

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
      if (axi4_bfm_inst.mem[(start_address + idx) & 16'hFFFF] !== expected_words[idx]) begin
        $error("sc_hub_tb_top: AXI4 mem[0x%04h] mismatch exp=0x%08h act=0x%08h",
               (start_address + idx) & 16'hFFFF,
               expected_words[idx],
               axi4_bfm_inst.mem[(start_address + idx) & 16'hFFFF]);
      end
`else
      if (avmm_bfm_inst.mem[(start_address + idx) & 16'hFFFF] !== expected_words[idx]) begin
        $error("sc_hub_tb_top: AVMM mem[0x%04h] mismatch exp=0x%08h act=0x%08h",
               (start_address + idx) & 16'hFFFF,
               expected_words[idx],
               avmm_bfm_inst.mem[(start_address + idx) & 16'hFFFF]);
      end
`endif
    end
  endtask

  task automatic wait_clks(input int unsigned cycle_count);
    repeat (cycle_count) @(posedge clk);
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
    if (avm_write !== 1'b0) begin
      $error("sc_hub_tb_top: AVMM write asserted during write preamble phase");
    end

    driver_inst.drive_word(make_addr_word(cmd), 4'b0000);
    if (avm_write !== 1'b0) begin
      $error("sc_hub_tb_top: AVMM write asserted during write address phase");
    end

    driver_inst.drive_word(make_length_word(cmd), 4'b0000);
    if (avm_write !== 1'b0) begin
      $error("sc_hub_tb_top: AVMM write asserted during write length phase");
    end

    for (int unsigned idx = 0; idx < wr_words.size(); idx++) begin
      driver_inst.drive_word(wr_words[idx], 4'b0000);
      if (avm_write !== 1'b0) begin
        $error("sc_hub_tb_top: AVMM write asserted before trailer at beat %0d", idx);
      end
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
    drive_word_ignore_ready(32'hAA00_0002, 4'b0000);
    release dut_inst.pkt_rx_inst.fifo_full_int;
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
          if (avm_read == 1'b1) begin
            saw_bus_read_before_trailer = 1'b1;
          end
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
    if (csr_word !== 32'h5348_0000) begin
      $error("sc_hub_tb_top: CSR ID mismatch exp=0x53480000 act=0x%08h", csr_word);
    end
  endtask

  task automatic run_t044();
    logic [31:0] csr_word;

    read_csr_word(16'h001, csr_word);
    if (csr_word !== 32'h1A08_031F) begin
      $error("sc_hub_tb_top: CSR VERSION mismatch exp=0x1A08031F act=0x%08h", csr_word);
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
    force dut_inst.dl_fifo_full      = 1'b1;
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

    if (fifo_status_word[0] !== 1'b1 || fifo_status_word[1] !== 1'b0 ||
        fifo_status_word[2] !== 1'b1 || fifo_status_word[3] !== 1'b0) begin
      $error("sc_hub_tb_top: FIFO_STATUS mismatch exp[3:0]=4'b0101 act=0x%0h",
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
    driver_inst.send_read(csr_addr(16'h018), 1);
    monitor_inst.wait_reply(captured_reply);
    if (!captured_reply.header_valid || captured_reply.echoed_length != 16'd1 ||
        captured_reply.response != 2'b10 || captured_reply.payload_words != 1 ||
        captured_reply.payload[0] !== 32'hEEEE_EEEE) begin
      $error("sc_hub_tb_top: invalid CSR offset reply mismatch valid=%0b len=%0d rsp=%0b words=%0d data=0x%08h",
             captured_reply.header_valid,
             captured_reply.echoed_length,
             captured_reply.response,
             captured_reply.payload_words,
             captured_reply.payload[0]);
    end
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
    if (csr_word !== 32'h5348_0000) begin
      $error("sc_hub_tb_top: AXI4 CSR ID mismatch exp=0x53480000 act=0x%08h", csr_word);
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
          if (avm_readdatavalid == 1'b1) begin
            beat_count++;
            if (beat_count >= 4) begin
              force avm_readdatavalid = 1'b0;
              disable force_timeout_after_four_beats;
            end
          end
        end
      end
      begin
        driver_inst.send_read(24'h000090, 8);
        monitor_inst.wait_reply(partial_reply);
      end
    join
    release avm_readdatavalid;

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
        wait (axi_arvalid === 1'b1);
        force axi4_bfm_inst.arready = 1'b0;
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
`endif

`ifndef SC_HUB_BUS_AXI4
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
    cmd = make_cmd(SC_READ, 24'h001200, 1);
    cmd.mask_s = 1'b1;
    send_cmd(cmd);
    monitor_inst.assert_no_reply(400ns);
    read_csr_word(16'h00F, csr_word);
    if (csr_word !== 32'd1) begin
      $error("sc_hub_tb_top: muted mask_s read did not increment EXT_PKT_RD count exp=1 act=%0d",
             csr_word);
    end
  endtask

  task automatic run_t090();
    logic [31:0] csr_word;
    sc_cmd_t     cmd;

    clear_hub_counters();
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
    cmd = make_cmd(SC_READ, 24'h001240, 1);
    cmd.mask_m = 1'b1;
    send_cmd(cmd);
    monitor_inst.assert_no_reply(400ns);
    read_csr_word(16'h00F, csr_word);
    if (csr_word !== 32'd1) begin
      $error("sc_hub_tb_top: muted mask_m read did not increment EXT_PKT_RD count exp=1 act=%0d",
             csr_word);
    end
  endtask

  task automatic run_t092();
    logic [31:0] csr_word;
    sc_cmd_t     cmd;

    clear_hub_counters();
    cmd = make_cmd(SC_READ, 24'h001260, 1);
    cmd.mask_t = 1'b1;
    send_cmd(cmd);
    monitor_inst.assert_no_reply(400ns);
    read_csr_word(16'h00F, csr_word);
    if (csr_word !== 32'd1) begin
      $error("sc_hub_tb_top: muted mask_t read did not increment EXT_PKT_RD count exp=1 act=%0d",
             csr_word);
    end
  endtask

  task automatic run_t093();
    sc_cmd_t cmd;

    cmd = make_cmd(SC_READ, 24'h001280, 1);
    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h001280, 1);
  endtask

  task automatic run_t094();
    logic [31:0] csr_word;
    sc_cmd_t     cmd;

    clear_hub_counters();

    cmd = make_cmd(SC_READ, 24'h0012A0, 1);
    cmd.mask_s = 1'b1;
    send_cmd(cmd);
    monitor_inst.assert_no_reply(400ns);

    cmd.mask_s = 1'b0;
    send_cmd(cmd);
    monitor_inst.wait_reply(captured_reply);
    expect_read_reply(captured_reply, 24'h0012A0, 1);
    monitor_inst.assert_no_reply(400ns);

    read_csr_word(16'h00F, csr_word);
    if (csr_word !== 32'd2) begin
      $error("sc_hub_tb_top: muted+unmuted read count mismatch exp=2 act=%0d", csr_word);
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
    expected_word = axi4_bfm_inst.mem[16'h1234];
`else
    expected_word = avmm_bfm_inst.mem[16'h1234];
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

    cmd = make_cmd(SC_READ, 24'h001400, 1);
    driver_inst.drive_word(make_preamble_word(cmd), 4'b0001);
    driver_inst.drive_word({4'hA, cmd.mask_m, cmd.mask_s, cmd.mask_t, cmd.mask_r, cmd.start_address}, 4'b0000);
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
    if (csr_word !== 32'h5348_0000) begin
      $error("sc_hub_tb_top: CSR ID mismatch during interleaved traffic exp=0x53480000 act=0x%08h",
             csr_word);
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

  initial begin
    rst                 = 1'b1;
    uplink_ready        = 1'b1;
    inject_rd_error     = 1'b0;
    inject_wr_error     = 1'b0;
    inject_decode_error = 1'b0;
    inject_rresp_err    = 1'b0;
    inject_bresp_err    = 1'b0;
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
      axi_last_awid              <= '0;
      axi_last_arid              <= '0;
      axi_last_bid               <= '0;
      axi_last_rid               <= '0;
      axi_last_wstrb             <= '0;
      axi_last_bresp             <= '0;
      axi_last_rresp             <= '0;
      axi_w_before_aw_violation  <= 1'b0;
    end else begin
      if (axi_awvalid && axi_awready) begin
        axi_aw_count     <= axi_aw_count + 1;
        axi_last_awlen   <= axi_awlen;
        axi_last_awsize  <= axi_awsize;
        axi_last_awburst <= axi_awburst;
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
        axi_last_arid    <= axi_arid;
      end

      if (axi_rvalid && axi_rready) begin
        axi_r_count    <= axi_r_count + 1;
        axi_last_rid   <= axi_rid;
        axi_last_rresp <= axi_rresp;
        if (axi_rlast) begin
          axi_rlast_count <= axi_rlast_count + 1;
        end
      end
    end
  end
`endif

  initial begin
    wait (!rst);
    repeat (TIMEOUT_CYCLES) @(posedge clk);
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
    .uplink_eop  (uplink_eop)
`ifdef SC_HUB_BUS_AXI4
    ,
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
    .INVERT_RD_SIG(0)
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
    .arvalid         (axi_arvalid),
    .arready         (axi_arready),
    .rid             (axi_rid),
    .rdata           (axi_rdata),
    .rresp           (axi_rresp),
    .rlast           (axi_rlast),
    .rvalid          (axi_rvalid),
    .rready          (axi_rready),
    .inject_rresp_err(inject_rresp_err),
    .inject_bresp_err(inject_bresp_err)
  );
`else
  sc_hub_top #(
    .INVERT_RD_SIG(0)
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
    .avm_hub_burstcount         (avm_burstcount)
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

  initial begin
    wait (!rst);
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
