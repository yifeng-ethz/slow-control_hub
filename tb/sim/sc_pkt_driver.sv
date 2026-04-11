module sc_pkt_driver (
  input  logic        clk,
  input  logic        rst,
  input  logic        link_ready,
  output logic [31:0] link_data,
  output logic [3:0]  link_datak
);
  import sc_hub_sim_pkg::*;

  task automatic send_sc_cmd(
    input sc_cmd_t cmd,
    input logic [31:0] data_words []
  );
    int unsigned words_to_send;

    drive_word(make_preamble_word(cmd), 4'b0001);
    drive_word(make_addr_word(cmd), 4'b0000);
    drive_word(make_length_word(cmd), 4'b0000);
    if (cmd.atomic) begin
      words_to_send = data_words.size();
      for (int unsigned idx = 0; idx < words_to_send; idx++) begin
        drive_word(data_words[idx], 4'b0000);
      end
    end else if (cmd_is_write(cmd)) begin
      words_to_send = (data_words.size() < cmd.rw_length) ? data_words.size() : cmd.rw_length;
      for (int unsigned idx = 0; idx < words_to_send; idx++) begin
        drive_word(data_words[idx], 4'b0000);
      end
    end
    drive_word({24'h0, K284_CONST}, 4'b0001);
    drive_idle();
  endtask

  initial begin
    link_data  = '0;
    link_datak = '0;
  end

  task automatic drive_word(input logic [31:0] word, input logic [3:0] datak);
    link_data  <= word;
    link_datak <= datak;
    do begin
      @(posedge clk);
    end while (rst === 1'b1 || link_ready !== 1'b1);
  endtask

  task automatic drive_word_ignore_ready(
    input logic [31:0] word,
    input logic [3:0]  datak
  );
    link_data  <= word;
    link_datak <= datak;
    @(posedge clk);
  endtask

  task automatic drive_word_hold_until_sampled(
    input logic [31:0] word,
    input logic [3:0]  datak
  );
    link_data  <= word;
    link_datak <= datak;
    @(negedge clk);
    while (rst === 1'b1 || link_ready !== 1'b1) begin
      @(negedge clk);
    end
    @(posedge clk);
  endtask

  task automatic drive_idle();
    link_data  <= '0;
    link_datak <= '0;
  endtask

  task automatic send_read(input logic [23:0] start_address, input int unsigned rw_length);
    sc_cmd_t cmd;
    cmd = make_cmd(SC_READ, start_address, rw_length);
    send_sc_cmd(cmd, {});
  endtask

  task automatic send_read_with_fpga_id(
    input logic [15:0] fpga_id,
    input logic [23:0] start_address,
    input int unsigned rw_length
  );
    sc_cmd_t cmd;
    cmd = make_cmd(SC_READ, start_address, rw_length);
    cmd.fpga_id = fpga_id;
    send_sc_cmd(cmd, {});
  endtask

  task automatic send_burst_read(
    input logic [23:0] start_address,
    input int unsigned rw_length
  );
    sc_cmd_t cmd;
    cmd = make_burst_cmd(SC_BURST_READ, start_address, rw_length);
    send_sc_cmd(cmd, {});
  endtask

  task automatic send_nonincrementing_read(
    input logic [23:0] start_address,
    input int unsigned rw_length
  );
    sc_cmd_t cmd;
    cmd = make_cmd(SC_READ_NONINCREMENTING, start_address, rw_length);
    send_sc_cmd(cmd, {});
  endtask

  task automatic send_ordered_read(
    input logic [23:0] start_address,
    input int unsigned rw_length,
    input sc_order_mode_e order_mode,
    input logic [3:0]  order_domain,
    input logic [7:0]  order_epoch,
    input logic [1:0]  order_scope = 2'b00
  );
    sc_cmd_t cmd;
    cmd = make_ordered_cmd(
      SC_BURST_READ,
      start_address,
      rw_length,
      order_mode,
      order_domain,
      order_epoch,
      order_scope
    );
    send_sc_cmd(cmd, {});
  endtask

  task automatic send_write(
    input logic [23:0] start_address,
    input int unsigned rw_length,
    input logic [31:0] data_words []
  );
    sc_cmd_t cmd;
    cmd = make_cmd(SC_WRITE, start_address, rw_length);
    send_sc_cmd(cmd, data_words);
  endtask

  task automatic send_write_with_fpga_id(
    input logic [15:0] fpga_id,
    input logic [23:0] start_address,
    input int unsigned rw_length,
    input logic [31:0] data_words []
  );
    sc_cmd_t cmd;
    cmd = make_cmd(SC_WRITE, start_address, rw_length);
    cmd.fpga_id = fpga_id;
    send_sc_cmd(cmd, data_words);
  endtask

  task automatic send_burst_write(
    input logic [23:0] start_address,
    input int unsigned rw_length,
    input logic [31:0] data_words []
  );
    sc_cmd_t cmd;
    cmd = make_burst_cmd(SC_BURST_WRITE, start_address, rw_length);
    send_sc_cmd(cmd, data_words);
  endtask

  task automatic send_nonincrementing_write(
    input logic [23:0] start_address,
    input int unsigned rw_length,
    input logic [31:0] data_words []
  );
    sc_cmd_t cmd;
    cmd = make_cmd(SC_WRITE_NONINCREMENTING, start_address, rw_length);
    send_sc_cmd(cmd, data_words);
  endtask

  task automatic send_ordered_write(
    input logic [23:0] start_address,
    input int unsigned rw_length,
    input logic [31:0] data_words [],
    input sc_order_mode_e order_mode,
    input logic [3:0]  order_domain,
    input logic [7:0]  order_epoch,
    input logic [1:0]  order_scope = 2'b00
  );
    sc_cmd_t cmd;
    cmd = make_ordered_cmd(
      SC_BURST_WRITE,
      start_address,
      rw_length,
      order_mode,
      order_domain,
      order_epoch,
      order_scope
    );
    send_sc_cmd(cmd, data_words);
  endtask

  task automatic send_atomic_rmw(
    input logic [23:0] start_address,
    input logic [31:0] atomic_mask,
    input logic [31:0] atomic_data,
    input sc_order_mode_e order_mode,
    input logic [3:0]  order_domain,
    input logic [7:0]  order_epoch,
    input logic [1:0]  order_scope = 2'b00
  );
    sc_cmd_t cmd;
    logic [31:0] payload_words[$];

    payload_words.delete();
    payload_words.push_back(atomic_mask);
    payload_words.push_back(atomic_data);
    cmd = make_atomic_cmd(start_address, atomic_mask, atomic_data);
    cmd.order_mode   = order_mode;
    cmd.order_domain = order_domain;
    cmd.order_epoch  = order_epoch;
    cmd.order_scope  = order_scope;
    send_sc_cmd(cmd, payload_words);
  endtask

  task automatic send_malformed(input logic [31:0] words [], input logic [3:0] dataks []);
    for (int unsigned idx = 0; idx < words.size() && idx < dataks.size(); idx++) begin
      drive_word(words[idx], dataks[idx]);
    end
    drive_idle();
  endtask

  task automatic send_precise_stalled_single_write(
    input logic [23:0] start_address,
    input logic [31:0] data_word
  );
    sc_cmd_t cmd;

    cmd = make_cmd(SC_WRITE, start_address, 1);
    drive_word_ignore_ready(make_preamble_word(cmd), 4'b0001);
    drive_word_ignore_ready(make_addr_word(cmd), 4'b0000);
    drive_word_ignore_ready(make_length_word(cmd), 4'b0000);
    drive_word_hold_until_sampled(data_word, 4'b0000);
    drive_word_ignore_ready({24'h0, K284_CONST}, 4'b0001);
    drive_idle();
  endtask

  task automatic send_raw(input logic [31:0] words [], input logic [3:0] dataks []);
    send_malformed(words, dataks);
  endtask

  task automatic send_swb_style_raw(
    input logic [31:0] words [],
    input logic [3:0]  dataks [],
    input int unsigned interword_skip_cycles
  );
    logic [31:0] skip_word;

    skip_word = {24'h0, K285_CONST};
    for (int unsigned idx = 0; idx < words.size() && idx < dataks.size(); idx++) begin
      drive_word_ignore_ready(words[idx], dataks[idx]);
      if (idx + 1 < words.size()) begin
        repeat (interword_skip_cycles) begin
          drive_word_ignore_ready(skip_word, 4'b0001);
        end
      end
    end

    drive_word_ignore_ready(skip_word, 4'b0001);
  endtask
endmodule
