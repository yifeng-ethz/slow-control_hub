module sc_pkt_monitor (
  input logic        clk,
  input logic        rst,
  input logic [35:0] aso_data,
  input logic        aso_valid,
  input logic        aso_ready,
  input logic        aso_sop,
  input logic        aso_eop
);
  import sc_hub_sim_pkg::*;

  sc_reply_t reply_cache;
  sc_reply_t reply_queue[$];
  event      reply_complete_ev;
  int unsigned word_index;
  int unsigned reply_seen_count;

  initial begin
    reply_cache     = make_empty_reply();
    reply_queue     = {};
    word_index      = 0;
    reply_seen_count = 0;
  end

  always @(posedge clk) begin
    sc_reply_t    next_reply;
    int unsigned  next_word_index;

    if (rst) begin
      reply_cache      <= make_empty_reply();
      reply_queue.delete();
      word_index       <= 0;
      reply_seen_count <= 0;
    end else if (aso_valid && aso_ready) begin
      next_reply      = reply_cache;
      next_word_index = word_index;

      if (aso_sop) begin
        next_reply      = make_empty_reply();
        next_word_index = 0;
      end

      case (next_word_index)
        0: begin
          next_reply.sc_type = sc_type_e'(aso_data[25:24]);
          next_reply.fpga_id = aso_data[23:8];
        end
        1: begin
          next_reply.order_mode    = sc_order_mode_e'((aso_data[31:30] == SC_ORDER_INVALID) ? SC_ORDER_RELAXED : aso_data[31:30]);
          next_reply.atomic        = aso_data[28];
          next_reply.start_address = aso_data[23:0];
        end
        2: begin
          next_reply.header_word   = aso_data[31:0];
          next_reply.order_domain  = aso_data[31:28];
          next_reply.order_epoch   = aso_data[27:20];
          next_reply.order_scope   = 2'b00;
          next_reply.echoed_length = aso_data[15:0];
          next_reply.header_valid  = aso_data[16];
          next_reply.response      = aso_data[19:18];
        end
        default: begin
          if (next_word_index > 2 && !aso_eop && next_reply.payload_words < 256) begin
            next_reply.payload[next_reply.payload_words] = aso_data[31:0];
            next_reply.payload_words                    = next_reply.payload_words + 1;
          end
        end
      endcase

      if (aso_eop) begin
        reply_queue.push_back(next_reply);
        reply_seen_count <= reply_seen_count + 1;
        reply_cache      <= make_empty_reply();
        word_index       <= 0;
        -> reply_complete_ev;
      end else begin
        reply_cache      <= next_reply;
        word_index       <= next_word_index + 1;
      end
    end
  end

  task automatic wait_reply(output sc_reply_t reply);
    while (reply_queue.size() == 0) begin
      @reply_complete_ev;
    end
    reply = reply_queue.pop_front();
  endtask

  task automatic wait_reply_timeout(
    output sc_reply_t reply,
    input  time      timeout_ns
  );
    time timeout_start;
    timeout_start = $time;
    while (reply_queue.size() == 0) begin
      if (($time - timeout_start) >= timeout_ns) begin
        reply = make_empty_reply();
        reply.echoed_length = 16'hffff;
        $error("sc_pkt_monitor: timeout waiting for reply after %0t", timeout_ns);
        return;
      end
      @(posedge clk);
    end
    reply = reply_queue.pop_front();
  endtask

  task automatic wait_reply_cycles(
    output sc_reply_t   reply,
    input  int unsigned timeout_cycles
  );
    int unsigned waited_cycles;

    waited_cycles = 0;
    while (reply_queue.size() == 0) begin
      if (waited_cycles >= timeout_cycles) begin
        reply = make_empty_reply();
        reply.echoed_length = 16'hffff;
        $error("sc_pkt_monitor: timeout waiting for reply after %0d cycles", timeout_cycles);
        return;
      end
      @(posedge clk);
      waited_cycles++;
    end
    reply = reply_queue.pop_front();
  endtask

  task automatic wait_reply_or_error(
    output sc_reply_t reply,
    input  time      timeout_ns,
    input  int unsigned expected_words
  );
    wait_reply_timeout(reply, timeout_ns);
    if (reply.echoed_length !== 16'hffff && reply.payload_words !== expected_words) begin
      $error("sc_pkt_monitor: payload_words mismatch exp=%0d act=%0d",
             expected_words,
             reply.payload_words);
    end
  endtask

  task automatic assert_no_reply(input time timeout_ns);
    fork
      begin
        @reply_complete_ev;
        $error("sc_pkt_monitor: Unexpected reply packet observed");
      end
      begin
        #(timeout_ns);
      end
    join_any
    disable fork;
  endtask

  task automatic assert_reply_count(input int unsigned expected_count);
    if (reply_queue.size() !== expected_count) begin
      $error("sc_pkt_monitor: reply queue mismatch exp=%0d act=%0d",
             expected_count,
             reply_queue.size());
    end
  endtask

  task automatic assert_reply_matches(
    input sc_reply_t expected,
    input sc_reply_t observed
  );
    if (expected.sc_type !== observed.sc_type) begin
      $error("sc_pkt_monitor: sc_type mismatch exp=0x%0h act=0x%0h",
             expected.sc_type, observed.sc_type);
    end
    if (expected.fpga_id !== observed.fpga_id) begin
      $error("sc_pkt_monitor: fpga_id mismatch exp=0x%04h act=0x%04h",
             expected.fpga_id, observed.fpga_id);
    end
    if (expected.start_address !== observed.start_address) begin
      $error("sc_pkt_monitor: start_address mismatch exp=0x%06h act=0x%06h",
             expected.start_address, observed.start_address);
    end
    if (expected.echoed_length !== observed.echoed_length) begin
      $error("sc_pkt_monitor: echoed length mismatch exp=%0d act=%0d",
             expected.echoed_length, observed.echoed_length);
    end
    if (expected.response !== observed.response) begin
      $error("sc_pkt_monitor: response mismatch exp=0x%0h act=0x%0h",
             expected.response, observed.response);
    end
    if (expected.payload_words !== observed.payload_words) begin
      $error("sc_pkt_monitor: payload_words mismatch exp=%0d act=%0d",
             expected.payload_words, observed.payload_words);
    end
    for (int unsigned idx = 0; idx < expected.payload_words && idx < observed.payload_words; idx++) begin
      if (expected.payload[idx] !== observed.payload[idx]) begin
        $error("sc_pkt_monitor: payload[%0d] mismatch exp=0x%08h act=0x%08h",
               idx, expected.payload[idx], observed.payload[idx]);
      end
    end
  endtask

  task automatic assert_reply_order(
    input sc_reply_t expected_seq [],
    input int unsigned timeout_ns_per_reply
  );
    sc_reply_t observed;
    sc_reply_t expected;
    for (int unsigned idx = 0; idx < expected_seq.size(); idx++) begin
      wait_reply_timeout(observed, timeout_ns_per_reply);
      if (observed.echoed_length === 16'hffff) begin
        $error("sc_pkt_monitor: timeout waiting for reply %0d in ordered sequence", idx);
        return;
      end
      expected = expected_seq[idx];
      assert_reply_matches(expected, observed);
    end
  endtask
endmodule
