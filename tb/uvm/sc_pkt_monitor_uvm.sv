class sc_pkt_monitor_uvm extends uvm_monitor;
  `uvm_component_utils(sc_pkt_monitor_uvm)

  virtual sc_reply_if sc_reply_vif;
  uvm_analysis_port #(sc_reply_item) reply_ap;

  localparam int unsigned MAX_PAYLOAD_WORDS = 256;

  int unsigned reply_seen_count;
  int unsigned malformed_reply_count;
  int unsigned payload_count_mismatch_count;

  function new(string name = "sc_pkt_monitor_uvm", uvm_component parent = null);
    super.new(name, parent);
    reply_ap = new("reply_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual sc_reply_if)::get(this, "", "sc_reply_vif", sc_reply_vif)) begin
      `uvm_fatal(get_type_name(), "Missing sc_reply_vif")
    end
  endfunction

  task run_phase(uvm_phase phase);
    sc_reply_item reply_h;
    int unsigned  word_index;
    int unsigned  expected_payload_words;

    reply_h               = null;
    word_index            = 0;
    expected_payload_words = 0;
    reply_seen_count      = 0;
    malformed_reply_count = 0;
    payload_count_mismatch_count = 0;

    forever begin
      @(posedge sc_reply_vif.clk);
      if (sc_reply_vif.rst) begin
        reply_h               = null;
        word_index            = 0;
        expected_payload_words = 0;
      end else if (sc_reply_vif.valid && sc_reply_vif.ready) begin
        if (sc_reply_vif.sop && reply_h != null && word_index != 0) begin
          malformed_reply_count++;
          `uvm_warning(get_type_name(),
                       "SOP seen before prior reply completed; dropping incomplete reply")
          reply_h    = null;
          word_index = 0;
          expected_payload_words = 0;
        end

        if (sc_reply_vif.sop || (reply_h == null)) begin
          reply_h    = sc_reply_item::type_id::create("reply_h", this);
          word_index = 0;
          expected_payload_words = 0;
        end

        case (word_index)
          0: begin
            reply_h.sc_type = sc_type_e'(sc_reply_vif.data[25:24]);
            reply_h.fpga_id = sc_reply_vif.data[23:8];
          end
          1: begin
            reply_h.order_mode    = sc_order_mode_e'((sc_reply_vif.data[31:30] == SC_ORDER_INVALID) ?
                                                     SC_ORDER_RELAXED : sc_reply_vif.data[31:30]);
            reply_h.atomic        = sc_reply_vif.data[28];
            reply_h.start_address = sc_reply_vif.data[23:0];
          end
          2: begin
            reply_h.order_domain  = sc_reply_vif.data[31:28];
            reply_h.order_epoch   = sc_reply_vif.data[27:20];
            reply_h.order_scope   = (sc_reply_vif.data[19:18] == 2'b11) ? 2'b00 : sc_reply_vif.data[19:18];
            reply_h.echoed_length = sc_reply_vif.data[15:0];
            reply_h.header_valid  = 1'b1;
            reply_h.response      = sc_reply_vif.data[17:16];
            if ((reply_h.sc_type[0] == 1'b0) || reply_h.atomic) begin
              expected_payload_words = sc_reply_vif.data[15:0];
            end else begin
              expected_payload_words = 0;
            end
          end
          default: begin
            if (!sc_reply_vif.eop) begin
              if (expected_payload_words == 0 || reply_h.payload_q.size() < expected_payload_words) begin
                if (reply_h.payload_q.size() < MAX_PAYLOAD_WORDS) begin
                  reply_h.payload_q.push_back(sc_reply_vif.data[31:0]);
                end else begin
                  malformed_reply_count++;
                  `uvm_warning(get_type_name(), "Reply payload exceeded capture limit (256 words)")
                end
              end else begin
                malformed_reply_count++;
                `uvm_warning(get_type_name(), "Reply payload longer than echoed_length")
              end
            end
          end
        endcase

        word_index++;

        if (sc_reply_vif.eop) begin
          if (expected_payload_words > 0 && reply_h.payload_q.size() != expected_payload_words) begin
            payload_count_mismatch_count++;
            `uvm_warning(get_type_name(),
                          $sformatf("Reply payload length mismatch exp=%0d act=%0d",
                                    expected_payload_words, reply_h.payload_q.size()))
          end
          reply_ap.write(reply_h.clone_item({reply_h.get_name(), "_observed"}));
          reply_h    = null;
          word_index = 0;
          expected_payload_words = 0;
          reply_seen_count++;
        end
      end
    end
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(),
              $sformatf("replies=%0d malformed=%0d payload_count_mismatch=%0d",
                        reply_seen_count, malformed_reply_count, payload_count_mismatch_count),
              UVM_LOW)
  endfunction
endclass
