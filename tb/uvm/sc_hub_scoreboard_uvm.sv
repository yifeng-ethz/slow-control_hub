class sc_hub_scoreboard_uvm extends uvm_component;
  `uvm_component_utils(sc_hub_scoreboard_uvm)

  uvm_analysis_imp_cmd #(sc_pkt_seq_item, sc_hub_scoreboard_uvm) cmd_imp;
  uvm_analysis_imp_rsp #(sc_reply_item, sc_hub_scoreboard_uvm)   rsp_imp;

  sc_hub_uvm_env_cfg cfg;
  logic [31:0]       mem_model [0:65535];
  sc_pkt_seq_item    expected_q[$];
  int unsigned       checks_run;
  int unsigned       checks_failed;

  function new(string name = "sc_hub_scoreboard_uvm", uvm_component parent = null);
    super.new(name, parent);
    cmd_imp = new("cmd_imp", this);
    rsp_imp = new("rsp_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(sc_hub_uvm_env_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = sc_hub_uvm_env_cfg::type_id::create("cfg");
    end
    init_mem_model();
    expected_q.delete();
    checks_run    = 0;
    checks_failed = 0;
  endfunction

  function void init_mem_model();
    logic [31:0] base_word;
    base_word = (cfg.bus_type == SC_HUB_BUS_AXI4) ? 32'h2000_0000 : 32'h1000_0000;
    foreach (mem_model[idx]) begin
      if (sc_hub_ref_model_pkg::is_internal_csr_addr(idx[15:0])) begin
        mem_model[idx] = 32'h0000_0000;
      end else begin
        mem_model[idx] = base_word + idx;
      end
    end
  endfunction

  function automatic logic [31:0] predict_read_word(input logic [15:0] word_addr);
    if (sc_hub_ref_model_pkg::is_internal_csr_addr(word_addr)) begin
      case (word_addr - sc_hub_ref_model_pkg::HUB_CSR_BASE_ADDR_CONST)
        16'h0000: return sc_hub_ref_model_pkg::HUB_ID_CONST;
        16'h0001: return sc_hub_ref_model_pkg::pack_version_word(
                    sc_hub_ref_model_pkg::HUB_VERSION_YY_CONST,
                    sc_hub_ref_model_pkg::HUB_VERSION_MAJOR_CONST,
                    sc_hub_ref_model_pkg::HUB_VERSION_PRE_CONST,
                    sc_hub_ref_model_pkg::HUB_VERSION_MONTH_CONST,
                    sc_hub_ref_model_pkg::HUB_VERSION_DAY_CONST
                  );
        default:  return mem_model[word_addr];
      endcase
    end
    return mem_model[word_addr];
  endfunction

  function sc_reply_item build_expected_reply(sc_pkt_seq_item cmd_item);
    sc_cmd_t       cmd;
    sc_reply_t     reply;
    sc_reply_item  expected_h;
    bit            expect_read_error_payload;

    cmd = cmd_item.to_cmd();
    expect_read_error_payload = 1'b0;

    if (cmd_item.is_write()) begin
      reply = predict_write_reply(cmd, cmd_item.forced_response);
    end else begin
      reply = make_empty_reply();
      reply.echoed_length = cmd.rw_length[15:0];
      reply.response      = 2'b00;
      reply.header_valid  = 1'b1;
      reply.payload_words = cmd.rw_length;
      for (int unsigned idx = 0; idx < cmd_item.rw_length && idx < 256; idx++) begin
        reply.payload[idx] = predict_read_word((cmd_item.start_address + idx) & 16'hFFFF);
      end
      reply.response = cmd_item.forced_response;
      expect_read_error_payload = (cmd_item.forced_response != 2'b00);
    end

    if (cmd_item.forced_response != 2'b00) begin
      reply.payload_words = 0;
      if (cmd_item.expect_error_payload || expect_read_error_payload) begin
        reply.payload_words = 1;
        if (cmd_item.expect_error_payload) begin
          reply.payload[0] = cmd_item.error_payload_word;
        end else if (cmd_item.forced_response == 2'b10) begin
          reply.payload[0] = 32'hBBAD_BEEF;
        end else begin
          reply.payload[0] = 32'hDEAD_BEEF;
        end
      end
    end

    expected_h = sc_reply_item::type_id::create("expected_h", this);
    expected_h.from_struct(cmd, reply);
    return expected_h;
  endfunction

  function void apply_completed_cmd(sc_pkt_seq_item cmd_item, logic [1:0] response);
    logic [15:0] word_addr;
    logic [31:0] old_word;

    if (cmd_item == null || response != 2'b00) begin
      return;
    end

    word_addr = cmd_item.start_address[15:0];
    if (cmd_item.atomic && cmd_item.atomic_mode != SC_ATOMIC_DISABLED) begin
      old_word = mem_model[word_addr];
      mem_model[word_addr] = (old_word & ~cmd_item.atomic_mask) |
                             (cmd_item.atomic_data & cmd_item.atomic_mask);
      return;
    end

    if (cmd_item.is_write()) begin
      for (int unsigned idx = 0; idx < cmd_item.data_words_q.size() && idx < cmd_item.rw_length; idx++) begin
        mem_model[(cmd_item.start_address + idx) & 16'hFFFF] = cmd_item.data_words_q[idx];
      end
    end
  endfunction

  function automatic bit reply_matches_expected(sc_reply_item expected_h, sc_reply_item actual_h);
    if (expected_h == null || actual_h == null) begin
      return 1'b0;
    end

    if (actual_h.header_valid !== expected_h.header_valid) begin
      return 1'b0;
    end
    if (actual_h.sc_type !== expected_h.sc_type) begin
      return 1'b0;
    end
    if (actual_h.fpga_id !== expected_h.fpga_id) begin
      return 1'b0;
    end
    if (actual_h.start_address !== expected_h.start_address) begin
      return 1'b0;
    end
    if (actual_h.order_mode !== expected_h.order_mode) begin
      return 1'b0;
    end
    if (actual_h.order_domain !== expected_h.order_domain) begin
      return 1'b0;
    end
    if (actual_h.order_epoch !== expected_h.order_epoch) begin
      return 1'b0;
    end
    if (actual_h.order_scope !== expected_h.order_scope) begin
      return 1'b0;
    end
    if (actual_h.atomic !== expected_h.atomic) begin
      return 1'b0;
    end
    if (actual_h.echoed_length !== expected_h.echoed_length) begin
      return 1'b0;
    end
    if (actual_h.response !== expected_h.response) begin
      return 1'b0;
    end
    if (actual_h.payload_q.size() != expected_h.payload_q.size()) begin
      return 1'b0;
    end

    for (int unsigned idx = 0; idx < actual_h.payload_q.size(); idx++) begin
      if (actual_h.payload_q[idx] !== expected_h.payload_q[idx]) begin
        return 1'b0;
      end
    end

    return 1'b1;
  endfunction

  function void compare_reply(sc_reply_item expected_h, sc_reply_item actual_h);
    checks_run++;

    if (actual_h.header_valid !== expected_h.header_valid) begin
      checks_failed++;
      `uvm_error(get_type_name(),
                 $sformatf("Header valid mismatch exp=%0b act=%0b", expected_h.header_valid, actual_h.header_valid))
    end

    if (actual_h.echoed_length !== expected_h.echoed_length) begin
      checks_failed++;
      `uvm_error(get_type_name(),
                 $sformatf("Echoed length mismatch exp=%0d act=%0d", expected_h.echoed_length, actual_h.echoed_length))
    end

    if (actual_h.response !== expected_h.response) begin
      checks_failed++;
      `uvm_error(get_type_name(),
                 $sformatf("Response mismatch exp=%0b act=%0b", expected_h.response, actual_h.response))
    end

    if (actual_h.start_address !== expected_h.start_address) begin
      checks_failed++;
      `uvm_error(get_type_name(),
                 $sformatf("Start address mismatch exp=0x%06h act=0x%06h", expected_h.start_address, actual_h.start_address))
    end

    if (actual_h.payload_q.size() != expected_h.payload_q.size()) begin
      checks_failed++;
      `uvm_error(get_type_name(),
                 $sformatf("Payload length mismatch exp=%0d act=%0d", expected_h.payload_q.size(), actual_h.payload_q.size()))
    end

    for (int unsigned idx = 0;
         idx < actual_h.payload_q.size() && idx < expected_h.payload_q.size();
         idx++) begin
      if (actual_h.payload_q[idx] !== expected_h.payload_q[idx]) begin
        checks_failed++;
        `uvm_error(get_type_name(),
                   $sformatf("Payload word[%0d] mismatch exp=0x%08h act=0x%08h",
                             idx, expected_h.payload_q[idx], actual_h.payload_q[idx]))
      end
    end
  endfunction

  function automatic int find_matching_expected_idx(sc_reply_item actual_h);
    sc_reply_item expected_h;

    for (int unsigned idx = 0; idx < expected_q.size(); idx++) begin
      expected_h = build_expected_reply(expected_q[idx]);
      if (reply_matches_expected(expected_h, actual_h)) begin
        return idx;
      end
    end
    return -1;
  endfunction

  function automatic int find_same_address_expected_idx(sc_reply_item actual_h);
    for (int unsigned idx = 0; idx < expected_q.size(); idx++) begin
      if ((expected_q[idx] != null) &&
          (expected_q[idx].start_address == actual_h.start_address)) begin
        return idx;
      end
    end
    return -1;
  endfunction

  function void write_cmd(sc_pkt_seq_item cmd_item);
    if (cmd_item.reply_expected()) begin
      expected_q.push_back(cmd_item.clone_item({cmd_item.get_name(), "_expected"}));
    end
  endfunction

  function void write_rsp(sc_reply_item rsp_item);
    sc_reply_item expected_h;
    sc_pkt_seq_item matched_cmd_h;
    int           expected_idx;
    int           same_addr_idx;

    if (expected_q.size() == 0) begin
      checks_failed++;
      `uvm_error(get_type_name(), $sformatf("Unexpected reply observed: %s", rsp_item.convert2string()))
      return;
    end

    expected_idx = find_matching_expected_idx(rsp_item);
    if (expected_idx >= 0) begin
      matched_cmd_h = expected_q[expected_idx];
      expected_h    = build_expected_reply(matched_cmd_h);
      expected_q.delete(expected_idx);
    end else begin
      same_addr_idx = find_same_address_expected_idx(rsp_item);
      if (same_addr_idx >= 0) begin
        matched_cmd_h = expected_q[same_addr_idx];
        expected_h    = build_expected_reply(matched_cmd_h);
        `uvm_error(get_type_name(),
                   $sformatf("Reply exact-match miss for addr=0x%06h actual=%s expected_same_addr=%s expected_front=%s",
                             rsp_item.start_address,
                             rsp_item.convert2string(),
                             expected_h.convert2string(),
                             build_expected_reply(expected_q[0]).convert2string()))
        expected_q.delete(same_addr_idx);
      end else begin
        `uvm_error(get_type_name(),
                   $sformatf("Reply exact-match miss with no same-address candidate actual=%s expected_front=%s",
                             rsp_item.convert2string(),
                             build_expected_reply(expected_q[0]).convert2string()))
        if (cfg.enable_ooo) begin
          checks_failed++;
          `uvm_error(get_type_name(),
                     $sformatf("No matching expected reply found for OoO response: %s",
                               rsp_item.convert2string()))
          return;
        end
        matched_cmd_h = expected_q.pop_front();
        expected_h    = build_expected_reply(matched_cmd_h);
      end
    end
    compare_reply(expected_h, rsp_item);
    apply_completed_cmd(matched_cmd_h, rsp_item.response);
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(),
              $sformatf("checks_run=%0d checks_failed=%0d pending_expected=%0d",
                        checks_run, checks_failed, expected_q.size()),
              UVM_LOW)
    if (expected_q.size() != 0) begin
      `uvm_error(get_type_name(), "Expected replies remain unmatched at end of simulation")
    end
  endfunction
endclass
