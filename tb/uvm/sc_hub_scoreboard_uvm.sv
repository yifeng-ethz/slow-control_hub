class sc_hub_scoreboard_uvm extends uvm_component;
  `uvm_component_utils(sc_hub_scoreboard_uvm)

  uvm_analysis_imp_cmd #(sc_pkt_seq_item, sc_hub_scoreboard_uvm) cmd_imp;
  uvm_analysis_imp_rsp #(sc_reply_item, sc_hub_scoreboard_uvm)   rsp_imp;

  sc_hub_uvm_env_cfg cfg;
  logic [31:0]       mem_model [0:65535];
  sc_reply_item      expected_q[$];
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
      mem_model[idx] = base_word + idx;
    end
  endfunction

  function sc_reply_item build_expected_reply(sc_pkt_seq_item cmd_item);
    sc_cmd_t       cmd;
    sc_reply_t     reply;
    sc_reply_item  expected_h;

    cmd = cmd_item.to_cmd();

    if (cmd_item.is_write()) begin
      for (int unsigned idx = 0; idx < cmd_item.data_words_q.size() && idx < cmd_item.rw_length; idx++) begin
        mem_model[(cmd_item.start_address + idx) & 16'hFFFF] = cmd_item.data_words_q[idx];
      end
      reply = predict_write_reply(cmd, cmd_item.forced_response);
    end else begin
      reply = predict_read_reply(cmd, mem_model);
      reply.response = cmd_item.forced_response;
    end

    expected_h = sc_reply_item::type_id::create("expected_h", this);
    expected_h.from_struct(cmd, reply);
    return expected_h;
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

  function void write_cmd(sc_pkt_seq_item cmd_item);
    if (cmd_item.reply_expected()) begin
      expected_q.push_back(build_expected_reply(cmd_item));
    end
  endfunction

  function void write_rsp(sc_reply_item rsp_item);
    sc_reply_item expected_h;

    if (expected_q.size() == 0) begin
      checks_failed++;
      `uvm_error(get_type_name(), $sformatf("Unexpected reply observed: %s", rsp_item.convert2string()))
      return;
    end

    expected_h = expected_q.pop_front();
    compare_reply(expected_h, rsp_item);
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
