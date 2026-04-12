class sc_hub_scoreboard_uvm extends uvm_component;
  `uvm_component_utils(sc_hub_scoreboard_uvm)

  uvm_analysis_imp_cmd #(sc_pkt_seq_item, sc_hub_scoreboard_uvm) cmd_imp;
  uvm_analysis_imp_rsp #(sc_reply_item, sc_hub_scoreboard_uvm)   rsp_imp;
  uvm_analysis_imp_bus #(sc_hub_bus_txn, sc_hub_scoreboard_uvm)  bus_imp;

  sc_hub_uvm_env_cfg cfg;
  logic [31:0]       mem_model [0:262143];
  sc_pkt_seq_item    expected_q[$];
  sc_reply_item      expected_rsp_q[$];
  int unsigned       checks_run;
  int unsigned       checks_failed;

  function new(string name = "sc_hub_scoreboard_uvm", uvm_component parent = null);
    super.new(name, parent);
    cmd_imp = new("cmd_imp", this);
    rsp_imp = new("rsp_imp", this);
    bus_imp = new("bus_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(sc_hub_uvm_env_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = sc_hub_uvm_env_cfg::type_id::create("cfg");
    end
    init_mem_model();
    expected_q.delete();
    expected_rsp_q.delete();
    checks_run    = 0;
    checks_failed = 0;
  endfunction

  function void init_mem_model();
    logic [31:0] base_word;
    base_word = (cfg.bus_type == SC_HUB_BUS_AXI4) ? 32'h2000_0000 : 32'h1000_0000;
    foreach (mem_model[idx]) begin
      if (sc_hub_ref_model_pkg::is_internal_csr_addr(idx[17:0])) begin
        mem_model[idx] = 32'h0000_0000;
      end else begin
        mem_model[idx] = base_word + idx;
      end
    end
    mem_model[sc_hub_ref_model_pkg::HUB_CSR_BASE_ADDR_CONST + 16'h0002] = 32'h0000_0001;
    mem_model[sc_hub_ref_model_pkg::HUB_CSR_BASE_ADDR_CONST + 16'h0009] = 32'h0000_0002;
  endfunction

  function automatic logic [31:0] predict_read_word(input logic [17:0] word_addr);
    logic [1:0] feb_type;
    logic [1:0] meta_page_sel;
    logic       hub_enable;
    logic       upload_store_forward;
    logic       ooo_ctrl_enable;
    logic [31:0] scratch_word;

    if (sc_hub_ref_model_pkg::is_internal_csr_addr(word_addr)) begin
      meta_page_sel        = mem_model[sc_hub_ref_model_pkg::HUB_CSR_BASE_ADDR_CONST + 16'h0001][1:0];
      hub_enable           = mem_model[sc_hub_ref_model_pkg::HUB_CSR_BASE_ADDR_CONST + 16'h0002][0];
      scratch_word         = mem_model[sc_hub_ref_model_pkg::HUB_CSR_BASE_ADDR_CONST + 16'h0006];
      upload_store_forward = mem_model[sc_hub_ref_model_pkg::HUB_CSR_BASE_ADDR_CONST + 16'h0009][1];
      ooo_ctrl_enable      = mem_model[sc_hub_ref_model_pkg::HUB_CSR_BASE_ADDR_CONST + 16'h0018][0];
      feb_type             = mem_model[sc_hub_ref_model_pkg::HUB_CSR_BASE_ADDR_CONST + 16'h001C][1:0];
      return sc_hub_ref_model_pkg::predict_csr_read_word(
        word_addr,
        cfg.supports_ooo,
        cfg.supports_ordering,
        cfg.supports_atomic,
        feb_type,
        meta_page_sel,
        hub_enable,
        scratch_word,
        upload_store_forward,
        ooo_ctrl_enable
      );
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
        logic [17:0] word_addr;

        if (cmd.sc_type[1]) begin
          word_addr = cmd_item.start_address[17:0] & 18'h3FFFF;
        end else begin
          word_addr = (cmd_item.start_address[17:0] + idx) & 18'h3FFFF;
        end
        reply.payload[idx] = predict_read_word(word_addr);
      end
      reply.response = cmd_item.forced_response;
      expect_read_error_payload = (cmd_item.forced_response != 2'b00);
    end

    if (cmd_item.forced_response != 2'b00) begin
      if (cmd_item.is_write()) begin
        reply.payload_words = 0;
      end else if (cmd_item.expect_error_payload) begin
        reply.payload_words = 1;
        reply.payload[0] = cmd_item.error_payload_word;
      end else begin
        logic [31:0] err_word;

        err_word = (cmd_item.forced_response == 2'b10) ? 32'hBBAD_BEEF : 32'hDEAD_BEEF;
        reply.payload_words = cmd.rw_length;
        for (int unsigned idx = 0; idx < cmd.rw_length && idx < 256; idx++) begin
          reply.payload[idx] = err_word;
        end
      end
    end

    expected_h = sc_reply_item::type_id::create("expected_h", this);
    expected_h.from_struct(cmd, reply);
    return expected_h;
  endfunction

  function void apply_completed_cmd(sc_pkt_seq_item cmd_item, logic [1:0] response);
    logic [17:0] word_addr;
    logic [31:0] old_word;

    if (cmd_item == null || response != 2'b00) begin
      return;
    end

    word_addr = cmd_item.start_address[17:0];
    if (cmd_item.atomic && cmd_item.atomic_mode != SC_ATOMIC_DISABLED) begin
      old_word = mem_model[word_addr];
      mem_model[word_addr] = (old_word & ~cmd_item.atomic_mask) |
                             (cmd_item.atomic_data & cmd_item.atomic_mask);
      return;
    end

    if (cmd_item.is_write()) begin
      for (int unsigned idx = 0; idx < cmd_item.data_words_q.size() && idx < cmd_item.rw_length; idx++) begin
        logic [17:0] word_addr;

        if (cmd_item.sc_type[1]) begin
          word_addr = cmd_item.start_address[17:0] & 18'h3FFFF;
        end else begin
          word_addr = (cmd_item.start_address[17:0] + idx) & 18'h3FFFF;
        end
        mem_model[word_addr] = cmd_item.data_words_q[idx];
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

  function void compare_reply(
    sc_reply_item expected_h,
    sc_reply_item actual_h,
    bit           skip_data = 1'b0
  );
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

    if (!skip_data) begin
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
    end
  endfunction

  function automatic int find_matching_expected_idx(sc_reply_item actual_h);
    for (int unsigned idx = 0; idx < expected_rsp_q.size(); idx++) begin
      if ((expected_rsp_q[idx] != null) && reply_matches_expected(expected_rsp_q[idx], actual_h)) begin
        return idx;
      end
    end
    return -1;
  endfunction

  function automatic bit reply_matches_cmd_header(sc_pkt_seq_item cmd_item, sc_reply_item actual_h);
    logic [1:0] expected_order_mode;
    bit         expected_atomic;

    if (cmd_item == null || actual_h == null) begin
      return 1'b0;
    end

    expected_order_mode = cmd_item.ordered ? cmd_item.order_mode : SC_ORDER_RELAXED;
    expected_atomic     = cmd_item.atomic && (cmd_item.atomic_mode != SC_ATOMIC_DISABLED);

    if (actual_h.sc_type != cmd_item.sc_type) begin
      return 1'b0;
    end
    if (actual_h.start_address != cmd_item.start_address) begin
      return 1'b0;
    end
    if (actual_h.echoed_length != cmd_item.rw_length[15:0]) begin
      return 1'b0;
    end
    if (actual_h.response != cmd_item.forced_response) begin
      return 1'b0;
    end
    if (actual_h.order_mode != expected_order_mode) begin
      return 1'b0;
    end
    if (actual_h.order_domain != cmd_item.order_domain[3:0]) begin
      return 1'b0;
    end
    if (actual_h.order_epoch != cmd_item.order_epoch[7:0]) begin
      return 1'b0;
    end
    if (actual_h.atomic != expected_atomic) begin
      return 1'b0;
    end
    return 1'b1;
  endfunction

  function automatic int find_same_address_expected_idx(sc_reply_item actual_h);
    for (int unsigned idx = 0; idx < expected_q.size(); idx++) begin
      if ((expected_q[idx] != null) &&
          reply_matches_cmd_header(expected_q[idx], actual_h)) begin
        return idx;
      end
    end
    return -1;
  endfunction

  function automatic bit cmd_items_match(sc_pkt_seq_item lhs, sc_pkt_seq_item rhs);
    if (lhs == null || rhs == null) begin
      return 1'b0;
    end
    // skip_payload_check is a scoreboard-local compare knob, not protocol state.
    if (lhs.sc_type != rhs.sc_type) begin
      return 1'b0;
    end
    if (lhs.start_address != rhs.start_address) begin
      return 1'b0;
    end
    if (!(lhs.sc_type[1] && rhs.sc_type[1]) && (lhs.rw_length != rhs.rw_length)) begin
      return 1'b0;
    end
    if ({lhs.mask_m, lhs.mask_s, lhs.mask_t, lhs.mask_r} != {rhs.mask_m, rhs.mask_s, rhs.mask_t, rhs.mask_r}) begin
      return 1'b0;
    end
    if (lhs.expect_reply != rhs.expect_reply) begin
      return 1'b0;
    end
    if (lhs.forced_response != rhs.forced_response) begin
      return 1'b0;
    end
    if (lhs.expect_error_payload != rhs.expect_error_payload) begin
      return 1'b0;
    end
    if (lhs.error_payload_word != rhs.error_payload_word) begin
      return 1'b0;
    end
    if (lhs.ordered != rhs.ordered) begin
      return 1'b0;
    end
    if (lhs.order_mode != rhs.order_mode || lhs.order_domain != rhs.order_domain || lhs.order_epoch != rhs.order_epoch) begin
      return 1'b0;
    end
    if (lhs.atomic != rhs.atomic || lhs.atomic_mode != rhs.atomic_mode || lhs.atomic_id != rhs.atomic_id) begin
      return 1'b0;
    end
    if (lhs.atomic_mask != rhs.atomic_mask || lhs.atomic_data != rhs.atomic_data) begin
      return 1'b0;
    end
    if (lhs.force_ooo != rhs.force_ooo) begin
      return 1'b0;
    end
    if (lhs.data_words_q.size() != rhs.data_words_q.size()) begin
      return 1'b0;
    end
    for (int unsigned idx = 0; idx < lhs.data_words_q.size(); idx++) begin
      if (lhs.data_words_q[idx] != rhs.data_words_q[idx]) begin
        return 1'b0;
      end
    end
    return 1'b1;
  endfunction

  function automatic int find_pending_cmd_idx(sc_pkt_seq_item cmd_item, bit require_unsnapped = 1'b0);
    for (int unsigned idx = 0; idx < expected_q.size(); idx++) begin
      if (!cmd_items_match(expected_q[idx], cmd_item)) begin
        continue;
      end
      if (require_unsnapped && expected_rsp_q[idx] != null) begin
        continue;
      end
      return idx;
    end
    return -1;
  endfunction

  function automatic string expected_desc(int idx);
    if (idx < 0 || idx >= expected_q.size()) begin
      return "<none>";
    end
    if (expected_rsp_q[idx] != null) begin
      return expected_rsp_q[idx].convert2string();
    end
    return {expected_q[idx].convert2string(), " snapshot=pending"};
  endfunction

  function void write_cmd(sc_pkt_seq_item cmd_item);
    sc_pkt_seq_item queued_cmd_h;
    sc_cmd_t        cmd;

    if (cmd_item == null) begin
      return;
    end
    if (!cmd_item.expect_reply) begin
      return;
    end

    cmd = cmd_item.to_cmd();
    if (sc_hub_sim_pkg::reply_suppressed(cmd, cfg.local_feb_type)) begin
      return;
    end

    queued_cmd_h = cmd_item.clone_item({cmd_item.get_name(), "_expected"});
    expected_q.push_back(queued_cmd_h);
    expected_rsp_q.push_back(null);
  endfunction

  function void write_bus(sc_hub_bus_txn bus_item);
    int             pending_idx;
    sc_reply_item   snap_h;
    sc_pkt_seq_item bus_cmd_h;

    if (bus_item == null || bus_item.cmd_meta_h == null) begin
      return;
    end

    pending_idx = find_pending_cmd_idx(bus_item.cmd_meta_h, 1'b1);
    if (pending_idx >= 0) begin
      if (expected_q[pending_idx].is_write() &&
          !(expected_q[pending_idx].atomic && (expected_q[pending_idx].atomic_mode != SC_ATOMIC_DISABLED))) begin
        apply_completed_cmd(expected_q[pending_idx], 2'b00);
      end
      snap_h = build_expected_reply(expected_q[pending_idx]);
      expected_rsp_q[pending_idx] = snap_h.clone_item({snap_h.get_name(), "_bus_snapshot"});
      return;
    end

    if (bus_item.cmd_meta_h.is_write() &&
        !(bus_item.cmd_meta_h.atomic && (bus_item.cmd_meta_h.atomic_mode != SC_ATOMIC_DISABLED))) begin
      bus_cmd_h = bus_item.cmd_meta_h.clone_item("bus_cmd_h");
      if (bus_cmd_h.sc_type[1] && (bus_cmd_h.data_words_q.size() > bus_cmd_h.rw_length)) begin
        bus_cmd_h.rw_length = bus_cmd_h.data_words_q.size();
      end
      apply_completed_cmd(bus_cmd_h, 2'b00);
    end
  endfunction

  function void write_rsp(sc_reply_item rsp_item);
    sc_reply_item   expected_h;
    sc_pkt_seq_item matched_cmd_h;
    int             expected_idx;
    int             same_addr_idx;
    bit             skip_data;

    if (expected_q.size() == 0 || expected_rsp_q.size() == 0) begin
      checks_failed++;
      `uvm_error(get_type_name(), $sformatf("Unexpected reply observed: %s", rsp_item.convert2string()))
      return;
    end

    expected_idx = find_matching_expected_idx(rsp_item);
    if (expected_idx >= 0) begin
      matched_cmd_h = expected_q[expected_idx];
      expected_h    = expected_rsp_q[expected_idx];
      expected_q.delete(expected_idx);
      expected_rsp_q.delete(expected_idx);
    end else begin
      same_addr_idx = find_same_address_expected_idx(rsp_item);
      if (same_addr_idx >= 0) begin
        matched_cmd_h = expected_q[same_addr_idx];
        expected_h    = expected_rsp_q[same_addr_idx];
        if (expected_h != null) begin
          `uvm_error(get_type_name(),
                     $sformatf("Reply exact-match miss for addr=0x%06h actual=%s expected_same_addr=%s expected_front=%s",
                               rsp_item.start_address,
                               rsp_item.convert2string(),
                               expected_h.convert2string(),
                               expected_desc(0)))
        end
        expected_q.delete(same_addr_idx);
        expected_rsp_q.delete(same_addr_idx);
      end else begin
        `uvm_error(get_type_name(),
                   $sformatf("Reply exact-match miss with no same-address candidate actual=%s expected_front=%s",
                             rsp_item.convert2string(),
                             expected_desc(0)))
        if (cfg.enable_ooo) begin
          checks_failed++;
          `uvm_error(get_type_name(),
                     $sformatf("No matching expected reply found for OoO response: %s",
                               rsp_item.convert2string()))
          return;
        end
        matched_cmd_h = expected_q.pop_front();
        expected_h    = expected_rsp_q.pop_front();
      end
    end

    if (expected_h == null) begin
      expected_h = build_expected_reply(matched_cmd_h);
    end

    skip_data = (matched_cmd_h != null) ? matched_cmd_h.skip_payload_check : 1'b0;
    compare_reply(expected_h, rsp_item, skip_data);
    apply_completed_cmd(matched_cmd_h, rsp_item.response);
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(),
              $sformatf("checks_run=%0d checks_failed=%0d pending_expected=%0d",
                        checks_run, checks_failed, expected_q.size()),
              UVM_LOW)
    if (expected_q.size() != expected_rsp_q.size()) begin
      `uvm_error(get_type_name(), "Expected command/reply snapshot queues diverged")
    end
    if (expected_q.size() != 0) begin
      `uvm_error(get_type_name(), "Expected replies remain unmatched at end of simulation")
      for (int unsigned idx = 0; idx < expected_q.size() && idx < 4; idx++) begin
        if (idx < expected_rsp_q.size() && expected_rsp_q[idx] != null) begin
          `uvm_info(get_type_name(),
                    $sformatf("pending_expected[%0d]=%s snapshot=%s",
                              idx,
                              expected_q[idx].convert2string(),
                              expected_rsp_q[idx].convert2string()),
                    UVM_LOW)
        end else begin
          `uvm_info(get_type_name(),
                    $sformatf("pending_expected[%0d]=%s snapshot=pending",
                              idx,
                              expected_q[idx].convert2string()),
                    UVM_LOW)
        end
      end
    end
  endfunction
endclass
