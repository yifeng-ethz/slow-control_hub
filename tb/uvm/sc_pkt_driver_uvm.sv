class sc_pkt_driver_uvm extends uvm_driver #(sc_pkt_seq_item);
  `uvm_component_utils(sc_pkt_driver_uvm)

  virtual sc_pkt_if sc_pkt_vif;
  uvm_analysis_port #(sc_pkt_seq_item) sent_ap;

  localparam int unsigned MAX_CMD_WORDS      = 256;
  localparam int unsigned EXTRA_DATA_WORDS    = 2;

  function new(string name = "sc_pkt_driver_uvm", uvm_component parent = null);
    super.new(name, parent);
    sent_ap = new("sent_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual sc_pkt_if)::get(this, "", "sc_pkt_vif", sc_pkt_vif)) begin
      `uvm_fatal(get_type_name(), "Missing sc_pkt_vif")
    end
  endfunction

  task automatic drive_word(input logic [31:0] word, input logic [3:0] datak);
    sc_pkt_vif.data  <= word;
    sc_pkt_vif.datak <= datak;
    do begin
      @(posedge sc_pkt_vif.clk);
    end while (sc_pkt_vif.rst || !sc_pkt_vif.ready);
  endtask

  task automatic drive_idle();
    sc_pkt_vif.data  <= '0;
    sc_pkt_vif.datak <= '0;
  endtask

  function automatic bit item_has_atomic_payload(sc_pkt_seq_item item);
    return (item.atomic && item.atomic_mode != SC_ATOMIC_DISABLED);
  endfunction

  function automatic int unsigned payload_words_for_send(sc_pkt_seq_item item, sc_cmd_t cmd);
    int unsigned words_available;
    int unsigned target_words;

    if (item_has_atomic_payload(item)) begin
      if (!item.malformed) begin
        return 2;
      end

      case (item.malformed_kind)
        "missing_trailer": begin
          return 2;
        end
        "data_count_mismatch", "truncated": begin
          return 1;
        end
        "length_overflow", "fifo_overflow": begin
          return 2;
        end
        default: begin
          return 2;
        end
      endcase
    end

    if (!item.is_write()) begin
      return 0;
    end

    words_available = (item.data_words_q.size() > MAX_CMD_WORDS) ? MAX_CMD_WORDS : item.data_words_q.size();
    target_words    = (item.rw_length > MAX_CMD_WORDS) ? MAX_CMD_WORDS : cmd.rw_length;

    if (!item.malformed) begin
      return (words_available < target_words) ? words_available : target_words;
    end

    case (item.malformed_kind)
      "missing_trailer": begin
        return (words_available < target_words) ? words_available : target_words;
      end
      "data_count_mismatch": begin
        if (target_words > 0) target_words = target_words - 1;
        return (words_available < target_words) ? words_available : target_words;
      end
      "length_overflow": begin
        return (words_available > target_words) ? words_available : target_words;
      end
      "fifo_overflow": begin
        return (words_available + EXTRA_DATA_WORDS <= MAX_CMD_WORDS) ? words_available + EXTRA_DATA_WORDS : MAX_CMD_WORDS;
      end
      "truncated": begin
        if (target_words > 0) target_words = target_words - 1;
        return (words_available < target_words) ? words_available : target_words;
      end
      default: begin
        return (words_available < target_words) ? words_available : target_words;
      end
    endcase
  endfunction

  task automatic drive_payload(sc_pkt_seq_item item, int unsigned payload_words);
    logic [3:0] data_datak;
    logic [31:0] payload_word;

    for (int unsigned idx = 0; idx < payload_words && idx < MAX_CMD_WORDS; idx++) begin
      data_datak = (item.malformed && (item.malformed_kind == "bad_dtype") && (idx == 0)) ? 4'b1111 : 4'b0000;
      if (item_has_atomic_payload(item)) begin
        case (idx)
          0: payload_word = item.atomic_mask;
          1: payload_word = item.atomic_data;
          default: payload_word = 32'hCAFE_0000 + idx;
        endcase
        drive_word(payload_word, data_datak);
      end else if (idx < item.data_words_q.size()) begin
        drive_word(item.data_words_q[idx], data_datak);
      end else begin
        drive_word({32'hBEEF_0000 + idx}, data_datak);
      end
    end
  endtask

  task automatic drive_trailer(sc_pkt_seq_item item);
    if (item.malformed && item.malformed_kind == "missing_trailer") begin
      return;
    end
    drive_word({24'h0, K284_CONST}, 4'b0001);
  endtask

  task automatic drive_item(sc_pkt_seq_item item);
    sc_cmd_t cmd;
    int unsigned payload_words;

    if (item == null) begin
      `uvm_error(get_type_name(), "drive_item called with null item")
      return;
    end

    cmd = item.to_cmd();
    if (item.malformed && item.malformed_kind == "length_overflow") begin
      cmd.rw_length = (item.rw_length < MAX_CMD_WORDS) ? (item.rw_length + 16'h0100) : 16'hffff;
    end

    payload_words = payload_words_for_send(item, cmd);

    drive_word(make_preamble_word(cmd), 4'b0001);
    drive_word(make_addr_word(cmd), 4'b0000);
    drive_word(make_length_word(cmd), 4'b0000);

    if (item.is_write() || item_has_atomic_payload(item)) begin
      drive_payload(item, payload_words);
    end

    drive_trailer(item);
    drive_idle();
  endtask

  task run_phase(uvm_phase phase);
    sc_pkt_seq_item sent_item_h;

    sc_pkt_vif.data  <= '0;
    sc_pkt_vif.datak <= '0;

    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      sent_item_h = req.clone_item({req.get_name(), "_sent"});
      sent_ap.write(sent_item_h);
      seq_item_port.item_done();
    end
  endtask
endclass
