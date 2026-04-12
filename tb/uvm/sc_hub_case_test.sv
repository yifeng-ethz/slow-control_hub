class sc_hub_case_test extends sc_hub_base_test;
  `uvm_component_utils(sc_hub_case_test)

  string       case_id;
  string       profile;
  int unsigned rng_state;

  function new(string name = "sc_hub_case_test", uvm_component parent = null);
    super.new(name, parent);
    case_id   = "";
    profile   = "";
    rng_state = 32'h1;
  endfunction

  function automatic string get_string_plusarg(string key, string default_value = "");
    string                value;

    if ($value$plusargs({key, "=%s"}, value)) begin
      return value;
    end
    return default_value;
  endfunction

  function automatic int unsigned get_uint_plusarg(string key, int unsigned default_value);
    string value;

    value = get_string_plusarg(key, "");
    if (value == "") begin
      return default_value;
    end
    return int'(value.atoi());
  endfunction

  function automatic bit get_bit_plusarg(string key, bit default_value = 1'b0);
    return (get_uint_plusarg(key, default_value ? 1 : 0) != 0);
  endfunction

  function automatic sc_type_e calc_sc_type(bit is_write, bit nonincrementing = 1'b0);
    if (nonincrementing) begin
      return is_write ? SC_WRITE_NONINCREMENTING : SC_READ_NONINCREMENTING;
    end
    return is_write ? SC_WRITE : SC_READ;
  endfunction

  function automatic logic [1:0] calc_forced_response(string rsp_name);
    string rsp_upper;

    rsp_upper = rsp_name.toupper();
    if (rsp_upper == "SLVERR") begin
      return 2'b10;
    end
    if (rsp_upper == "DECERR" || rsp_upper == "TIMEOUT") begin
      return 2'b11;
    end
    return 2'b00;
  endfunction

  function automatic int unsigned next_lcg();
    rng_state = (rng_state * 32'd1664525) + 32'd1013904223;
    return rng_state;
  endfunction

  function automatic int unsigned next_range(int unsigned min_value, int unsigned max_value);
    int unsigned rand_value;

    if (max_value <= min_value) begin
      return min_value;
    end
    rand_value = next_lcg();
    return min_value + (rand_value % (max_value - min_value + 1));
  endfunction

  function automatic logic [23:0] next_external_addr(string addr_mode, int unsigned txn_idx);
    int unsigned bucket;
    int unsigned window_idx;

    localparam logic [23:0] PERF_ADDR_BASE_CONST   = 24'h000200;
    localparam int unsigned PERF_ADDR_STRIDE_CONST = 16'h0120;
    localparam int unsigned PERF_ADDR_WINDOWS_CONST = 223;

    if (addr_mode == "feb") begin
      bucket = next_lcg() % 6;
      case (bucket)
        0: return SCRATCH_PAD_BASE_CONST + (txn_idx % 256);
        1: return FRAME_RCV_BASE_CONST + (txn_idx % 256);
        2: return RING_BUF_CAM_BASE_CONST + (txn_idx % 256);
        3: return HISTOGRAM_BASE_CONST + (txn_idx % 256);
        4: return CONTROL_CSR_BASE_CONST + (txn_idx % 16);
        default: return FEB_FRAME_ASM_BASE_CONST + (txn_idx % 128);
      endcase
    end

    window_idx = (txn_idx == 0) ? 0 : ((txn_idx - 1) % PERF_ADDR_WINDOWS_CONST);
    return PERF_ADDR_BASE_CONST + (window_idx * PERF_ADDR_STRIDE_CONST);
  endfunction

  function automatic logic [23:0] next_internal_addr(
    input bit          is_write,
    input int unsigned txn_idx,
    input string       internal_mode = "default"
  );
    string mode_lower;

    mode_lower = internal_mode.tolower();
    if (is_write) begin
      if (mode_lower == "csr_sweep") begin
        case (txn_idx % 7)
          0: return INTERNAL_CSR_BASE_CONST + 24'h000001; // META
          1: return INTERNAL_CSR_BASE_CONST + 24'h000002; // CTRL (err_clear / soft_reset)
          2: return INTERNAL_CSR_BASE_CONST + 24'h000004; // ERR_FLAGS clear
          3: return INTERNAL_CSR_BASE_CONST + 24'h000006; // SCRATCH
          4: return INTERNAL_CSR_BASE_CONST + 24'h000009; // FIFO_CFG
          5: return INTERNAL_CSR_BASE_CONST + 24'h000018; // OOO_CTRL
          default: return INTERNAL_CSR_BASE_CONST + 24'h00001C; // FEB_TYPE
        endcase
      end
      return INTERNAL_CSR_BASE_CONST + 24'h000006;
    end

    if (mode_lower == "capmix") begin
      case (txn_idx % 4)
        0: return INTERNAL_CSR_BASE_CONST + 24'h000000;
        1: return INTERNAL_CSR_BASE_CONST + 24'h000001;
        2: return INTERNAL_CSR_BASE_CONST + 24'h00001F;
        default: return INTERNAL_CSR_BASE_CONST + 24'h00001C;
      endcase
    end

    if (mode_lower == "csr_sweep") begin
      case (txn_idx % 8)
        0: return INTERNAL_CSR_BASE_CONST + 24'h000000;
        1: return INTERNAL_CSR_BASE_CONST + 24'h000001;
        2: return INTERNAL_CSR_BASE_CONST + 24'h000002;
        3: return INTERNAL_CSR_BASE_CONST + 24'h000006;
        4: return INTERNAL_CSR_BASE_CONST + 24'h000009;
        5: return INTERNAL_CSR_BASE_CONST + 24'h000018;
        6: return INTERNAL_CSR_BASE_CONST + 24'h00001C;
        default: return INTERNAL_CSR_BASE_CONST + 24'h00001F;
      endcase
    end

    case (txn_idx % 2)
      0: return INTERNAL_CSR_BASE_CONST + 24'h000000;
      default: return INTERNAL_CSR_BASE_CONST + 24'h000001;
    endcase
  endfunction

  function automatic logic [31:0] next_internal_write_data(
    input logic [23:0] word_addr,
    input int unsigned txn_idx,
    input string       internal_mode = "default"
  );
    string mode_lower;
    logic [31:0] data_word;

    mode_lower = internal_mode.tolower();
    data_word  = 32'hA500_0000 + word_addr;
    if (mode_lower != "csr_sweep") begin
      return data_word;
    end

    case (word_addr)
      (INTERNAL_CSR_BASE_CONST + 24'h000001): data_word = {30'd0, logic'(txn_idx % 4)};
      // CTRL: alternate plain hub_enable=1 with hub_enable=1 + err_clear (bit1).
      // bit2 (soft_reset) is intentionally avoided here — it nukes in-flight
      // pending replies and breaks the scoreboard pending queue. Cover that
      // path from a dedicated reset case.
      (INTERNAL_CSR_BASE_CONST + 24'h000002): begin
        case (txn_idx % 2)
          0: data_word = 32'h0000_0001;
          default: data_word = 32'h0000_0003;
        endcase
      end
      // ERR_FLAGS clear: write-1-to-clear mask covering every flag (no
      // scoreboard impact — predict_csr_read_word never models this offset).
      (INTERNAL_CSR_BASE_CONST + 24'h000004): data_word = 32'hFFFF_FFFF;
      (INTERNAL_CSR_BASE_CONST + 24'h000006): data_word = 32'hC300_0000 | txn_idx;
      (INTERNAL_CSR_BASE_CONST + 24'h000009): data_word = {30'd0, 1'b1, logic'(txn_idx[0])};
      (INTERNAL_CSR_BASE_CONST + 24'h000018): data_word = {31'd0, logic'(txn_idx[0])};
      (INTERNAL_CSR_BASE_CONST + 24'h00001C): data_word = {30'd0, logic'(txn_idx % 4)};
      default: begin end
    endcase
    return data_word;
  endfunction

  function automatic bit csr_read_payload_modeled(input int unsigned csr_offset);
    case (csr_offset)
      16'h000, 16'h001, 16'h002, 16'h003,
      16'h006, 16'h009, 16'h018, 16'h01C,
      16'h01F: return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function automatic logic [1:0] calc_stream_forced_response(
    input string       err_mode,
    input int unsigned txn_idx
  );
    string err_mode_lower;

    err_mode_lower = err_mode.tolower();
    if (err_mode_lower == "slverr") begin
      return 2'b10;
    end
    if (err_mode_lower == "decerr" || err_mode_lower == "timeout") begin
      return 2'b11;
    end

    case (txn_idx % 3)
      0: return 2'b10;
      default: return 2'b11;
    endcase
  endfunction

  function automatic sc_pkt_seq_item build_item(
    input logic [23:0] start_address,
    input int unsigned rw_length,
    input bit          is_write,
    input bit          nonincrementing = 1'b0
  );
    sc_pkt_seq_item item_h;

    item_h = sc_pkt_seq_item::type_id::create("item_h");
    item_h.sc_type       = calc_sc_type(is_write, nonincrementing);
    item_h.start_address = start_address;
    item_h.rw_length     = rw_length;
    if (is_write) begin
      for (int unsigned idx = 0; idx < rw_length; idx++) begin
        item_h.data_words_q.push_back(32'hA500_0000 + start_address + idx);
      end
    end
    return item_h;
  endfunction

  task automatic issue_item(sc_pkt_seq_item item_h);
    sc_pkt_script_seq seq_h;

    seq_h = sc_pkt_script_seq::type_id::create($sformatf("seq_%0d", next_lcg()));
    seq_h.req_h = item_h.clone_item($sformatf("req_%0d", next_lcg()));
    seq_h.start(env_h.pkt_agent_h.sequencer_h);
  endtask

  task automatic wait_gap(int unsigned gap_cycles);
    repeat (gap_cycles) @(posedge env_h.pkt_agent_h.driver_h.sc_pkt_vif.clk);
  endtask

  task automatic write_avs_csr_word(input logic [4:0] csr_addr, input logic [31:0] csr_data);
    uvm_hdl_data_t hdl_data;

    hdl_data = csr_addr;
    if (!uvm_hdl_deposit("tb_top.harness.avs_csr_address", hdl_data)) begin
      `uvm_fatal(get_type_name(), "Failed to drive tb_top.harness.avs_csr_address")
    end
    hdl_data = csr_data;
    if (!uvm_hdl_deposit("tb_top.harness.avs_csr_writedata", hdl_data)) begin
      `uvm_fatal(get_type_name(), "Failed to drive tb_top.harness.avs_csr_writedata")
    end
    hdl_data = 0;
    if (!uvm_hdl_deposit("tb_top.harness.avs_csr_read", hdl_data)) begin
      `uvm_fatal(get_type_name(), "Failed to drive tb_top.harness.avs_csr_read")
    end
    hdl_data = 1;
    if (!uvm_hdl_deposit("tb_top.harness.avs_csr_write", hdl_data)) begin
      `uvm_fatal(get_type_name(), "Failed to drive tb_top.harness.avs_csr_write")
    end
    do begin
      @(posedge env_h.pkt_agent_h.driver_h.sc_pkt_vif.clk);
      if (!uvm_hdl_read("tb_top.harness.avs_csr_waitrequest", hdl_data)) begin
        `uvm_fatal(get_type_name(), "Failed to sample tb_top.harness.avs_csr_waitrequest")
      end
    end while (hdl_data[0]);
    hdl_data = 0;
    if (!uvm_hdl_deposit("tb_top.harness.avs_csr_write", hdl_data)) begin
      `uvm_fatal(get_type_name(), "Failed to clear tb_top.harness.avs_csr_write")
    end
    if (!uvm_hdl_deposit("tb_top.harness.avs_csr_address", hdl_data)) begin
      `uvm_fatal(get_type_name(), "Failed to clear tb_top.harness.avs_csr_address")
    end
    if (!uvm_hdl_deposit("tb_top.harness.avs_csr_writedata", hdl_data)) begin
      `uvm_fatal(get_type_name(), "Failed to clear tb_top.harness.avs_csr_writedata")
    end
  endtask

  task automatic read_avs_csr_word(input logic [4:0] csr_addr, output logic [31:0] csr_data);
    uvm_hdl_data_t hdl_data;

    hdl_data = csr_addr;
    if (!uvm_hdl_deposit("tb_top.harness.avs_csr_address", hdl_data)) begin
      `uvm_fatal(get_type_name(), "Failed to drive tb_top.harness.avs_csr_address")
    end
    hdl_data = 0;
    if (!uvm_hdl_deposit("tb_top.harness.avs_csr_write", hdl_data)) begin
      `uvm_fatal(get_type_name(), "Failed to clear tb_top.harness.avs_csr_write")
    end
    hdl_data = 1;
    if (!uvm_hdl_deposit("tb_top.harness.avs_csr_read", hdl_data)) begin
      `uvm_fatal(get_type_name(), "Failed to drive tb_top.harness.avs_csr_read")
    end
    do begin
      @(posedge env_h.pkt_agent_h.driver_h.sc_pkt_vif.clk);
      if (!uvm_hdl_read("tb_top.harness.avs_csr_waitrequest", hdl_data)) begin
        `uvm_fatal(get_type_name(), "Failed to sample tb_top.harness.avs_csr_waitrequest")
      end
    end while (hdl_data[0]);
    hdl_data = 0;
    if (!uvm_hdl_deposit("tb_top.harness.avs_csr_read", hdl_data)) begin
      `uvm_fatal(get_type_name(), "Failed to clear tb_top.harness.avs_csr_read")
    end
    do begin
      @(posedge env_h.pkt_agent_h.driver_h.sc_pkt_vif.clk);
      if (!uvm_hdl_read("tb_top.harness.avs_csr_readdatavalid", hdl_data)) begin
        `uvm_fatal(get_type_name(), "Failed to sample tb_top.harness.avs_csr_readdatavalid")
      end
    end while (hdl_data[0] == 0);
    if (!uvm_hdl_read("tb_top.harness.avs_csr_readdata", hdl_data)) begin
      `uvm_fatal(get_type_name(), "Failed to sample tb_top.harness.avs_csr_readdata")
    end
    csr_data = hdl_data[31:0];
    hdl_data = 0;
    if (!uvm_hdl_deposit("tb_top.harness.avs_csr_address", hdl_data)) begin
      `uvm_fatal(get_type_name(), "Failed to clear tb_top.harness.avs_csr_address")
    end
  endtask

  task automatic wait_for_drain();
    int unsigned drain_cycles;
    int unsigned drain_timeout_cycles;

    drain_timeout_cycles = 50000;
    void'($value$plusargs("SC_HUB_DRAIN_TIMEOUT_CYCLES=%d", drain_timeout_cycles));

    for (drain_cycles = 0; drain_cycles < drain_timeout_cycles; drain_cycles++) begin
      if ((env_h.scoreboard_h.expected_q.size() == 0) &&
          (env_h.bus_agent_h.monitor_h.pending_cmd_q.size() == 0)) begin
        return;
      end
      @(posedge env_h.pkt_agent_h.driver_h.sc_pkt_vif.clk);
    end

    `uvm_error(get_type_name(),
               $sformatf("Case %s drain timed out pending_expected=%0d pending_bus_cmd=%0d",
                         case_id,
                         env_h.scoreboard_h.expected_q.size(),
                         env_h.bus_agent_h.monitor_h.pending_cmd_q.size()))
  endtask

  task automatic wait_for_testbench_settle();
    while (env_h.pkt_agent_h.driver_h.sc_pkt_vif.rst) begin
      @(posedge env_h.pkt_agent_h.driver_h.sc_pkt_vif.clk);
    end
    repeat (8) @(posedge env_h.pkt_agent_h.driver_h.sc_pkt_vif.clk);
  endtask

  task automatic run_burst_len_sweep();
    int unsigned lengths[$] = '{1, 2, 3, 4, 8, 16, 32, 64, 128, 255, 256};
    sc_pkt_seq_item item_h;

    foreach (lengths[idx]) begin
      item_h = build_item(24'h000100 + idx * 16, lengths[idx], 1'b0);
      issue_item(item_h);

      item_h = build_item(24'h000400 + idx * 16, lengths[idx], 1'b1);
      issue_item(item_h);
    end
  endtask

  task automatic run_addr_boundary_sweep();
    logic [23:0] addresses[$] = '{
      24'h000000, 24'h000001, 24'h000100, 24'h001000,
      24'h007FFF, 24'h00FE7F, 24'h00FEA0, 24'h00FFFF
    };
    sc_pkt_seq_item item_h;

    foreach (addresses[idx]) begin
      item_h = build_item(addresses[idx], 1, 1'b0);
      issue_item(item_h);
    end
  endtask

  task automatic run_latency_pair();
    sc_pkt_seq_item item_h;

    item_h = build_item(24'h000220, 4, 1'b0);
    issue_item(item_h);

    item_h = build_item(24'h000260, 4, 1'b1);
    issue_item(item_h);
  endtask

  task automatic run_error_case();
    sc_pkt_seq_item item_h;
    string          err_kind;
    string          err_kind_lower;
    string          err_op;
    bit             is_write;

    err_kind       = get_string_plusarg("SC_HUB_ERR_KIND", "OKAY");
    err_kind_lower = err_kind.tolower();
    err_op         = get_string_plusarg("SC_HUB_ERR_OP", "read");
    is_write       = (err_op.tolower() == "write");
    item_h         = build_item(is_write ? 24'h0002A0 : 24'h000280, 1, is_write);

    if ((err_kind_lower == "missing_trailer") ||
        (err_kind_lower == "data_count_mismatch") ||
        (err_kind_lower == "length_overflow") ||
        (err_kind_lower == "fifo_overflow") ||
        (err_kind_lower == "truncated") ||
        (err_kind_lower == "bad_dtype")) begin
      item_h.malformed      = 1'b1;
      item_h.malformed_kind = err_kind_lower;
      item_h.expect_reply   = 1'b0;
    end else begin
      item_h.forced_response = calc_forced_response(err_kind);
      if (err_kind.toupper() == "TIMEOUT") begin
        item_h.expect_error_payload = 1'b1;
        item_h.error_payload_word   = 32'hEEEE_EEEE;
      end
    end
    issue_item(item_h);
  endtask

  task automatic run_gap_sweep();
    sc_pkt_seq_item item_h;
    logic [23:0]    csr_scratch_addr;

    csr_scratch_addr = INTERNAL_CSR_BASE_CONST + 24'h000006;

    for (int unsigned gap = 0; gap < 16; gap++) begin
      for (int unsigned kind = 0; kind < 8; kind++) begin
        case (kind)
          0: item_h = build_item(24'h000300 + gap * 16, 8, 1'b0);
          1: item_h = build_item(24'h000500 + gap * 16, 8, 1'b1);
          2: item_h = build_item(24'h000700 + gap, 1, 1'b0);
          3: item_h = build_item(24'h000780 + gap, 1, 1'b1);
          4: item_h = build_item(INTERNAL_CSR_BASE_CONST, 1, 1'b0);
          5: item_h = build_item(csr_scratch_addr, 1, 1'b1);
          6: begin
            item_h = build_item(24'h0007C0 + gap, 1, 1'b0);
            item_h.mask_s = 1'b1;
          end
          default: begin
            item_h = build_item(24'h0007E0 + gap, 1, 1'b1);
            item_h.malformed      = 1'b1;
            item_h.malformed_kind = "missing_trailer";
            item_h.expect_reply   = 1'b0;
          end
        endcase
        issue_item(item_h);
        wait_for_drain();
        wait_gap(gap);
      end
    end
  endtask

  task automatic run_perf_stream();
    sc_pkt_seq_item item_h;
    string          addr_mode;
    int unsigned    txn_count_per_point;
    int unsigned    rate_points;
    int unsigned    max_gap;
    int unsigned    burst_min;
    int unsigned    burst_max;
    int unsigned    fixed_len;
    int unsigned    read_pct;
    int unsigned    internal_pct;
    int unsigned    ordering_pct;
    int unsigned    atomic_pct;
    int unsigned    malformed_every;
    int unsigned    nonincrement_pct;
    int unsigned    mask_pct;
    int unsigned    err_every;
    string          err_mode;
    string          internal_mode;
    string          mask_mode;
    int unsigned    order_domains;
    int unsigned    trace_start;
    int unsigned    trace_end;
    bit             force_ooo;
    int unsigned    global_idx;

    rate_points        = get_uint_plusarg("SC_HUB_RATE_POINTS", 1);
    txn_count_per_point= get_uint_plusarg("SC_HUB_TXN_COUNT", 64);
    max_gap            = get_uint_plusarg("SC_HUB_MAX_GAP", 0);
    burst_min          = get_uint_plusarg("SC_HUB_BURST_MIN", 1);
    burst_max          = get_uint_plusarg("SC_HUB_BURST_MAX", burst_min);
    fixed_len          = get_uint_plusarg("SC_HUB_FIXED_LEN", 0);
    read_pct           = get_uint_plusarg("SC_HUB_READ_PCT", 50);
    internal_pct       = get_uint_plusarg("SC_HUB_INTERNAL_PCT", 0);
    ordering_pct       = get_uint_plusarg("SC_HUB_ORDERING_PCT", 0);
    atomic_pct         = get_uint_plusarg("SC_HUB_ATOMIC_PCT", 0);
    malformed_every    = get_uint_plusarg("SC_HUB_MALFORMED_EVERY", 0);
    nonincrement_pct   = get_uint_plusarg("SC_HUB_NONINCREMENT_PCT", 0);
    mask_pct           = get_uint_plusarg("SC_HUB_MASK_PCT", 0);
    err_every          = get_uint_plusarg("SC_HUB_ERR_EVERY", 0);
    err_mode           = get_string_plusarg("SC_HUB_ERR_MODE", "rotate");
    internal_mode      = get_string_plusarg("SC_HUB_INTERNAL_MODE", "default");
    mask_mode          = get_string_plusarg("SC_HUB_MASK_MODE", "rotate");
    order_domains      = get_uint_plusarg("SC_HUB_ORDER_DOMAINS", 1);
    trace_start        = get_uint_plusarg("SC_HUB_TRACE_TXN_START", 0);
    trace_end          = get_uint_plusarg("SC_HUB_TRACE_TXN_END", 0);
    force_ooo          = get_bit_plusarg("SC_HUB_FORCE_OOO", 1'b0);
    addr_mode          = get_string_plusarg("SC_HUB_ADDR_MODE", "linear");
    global_idx         = 0;

    for (int unsigned point_idx = 0; point_idx < rate_points; point_idx++) begin
      int unsigned gap_cycles;

      if (rate_points <= 1) begin
        gap_cycles = max_gap;
      end else begin
        gap_cycles = ((rate_points - 1) - point_idx) * max_gap / (rate_points - 1);
      end

      for (int unsigned txn_idx = 0; txn_idx < txn_count_per_point; txn_idx++) begin
        bit          malformed_pkt;
        bit          internal_pkt;
        bit          atomic_pkt;
        bit          ordered_pkt;
        bit          nonincrement_pkt;
        bit          masked_pkt;
        bit          error_pkt;
        bit          is_write;
        int unsigned pkt_len;
        logic [23:0] pkt_addr;

        global_idx     = global_idx + 1;
        malformed_pkt  = (malformed_every != 0) && ((global_idx % malformed_every) == 0);
        error_pkt      = (!malformed_pkt) && (err_every != 0) && ((global_idx % err_every) == 0);
        internal_pkt   = (!malformed_pkt) && (!error_pkt) && ((next_lcg() % 100) < internal_pct);
        atomic_pkt     = (!malformed_pkt) && (!error_pkt) && (!internal_pkt) && ((next_lcg() % 100) < atomic_pct);
        ordered_pkt    = (!malformed_pkt) && (!error_pkt) && (!atomic_pkt) && ((next_lcg() % 100) < ordering_pct);
        nonincrement_pkt = (!malformed_pkt) && (!atomic_pkt) && ((next_lcg() % 100) < nonincrement_pct);
        masked_pkt     = (!malformed_pkt) && (!error_pkt) && (!internal_pkt) && ((next_lcg() % 100) < mask_pct);
        is_write       = ((next_lcg() % 100) >= read_pct);
        pkt_len        = (fixed_len != 0) ? fixed_len : next_range(burst_min, burst_max);
        if (internal_pkt) begin
          pkt_len          = 1;
          is_write         = (global_idx[0] == 1'b1);
          nonincrement_pkt = 1'b0;
        end
        if (atomic_pkt) begin
          pkt_len          = 1;
          is_write         = 1'b0;
          nonincrement_pkt = 1'b0;
        end
        if (malformed_pkt) begin
          is_write         = 1'b1;
          nonincrement_pkt = 1'b0;
        end

        pkt_addr = internal_pkt ? next_internal_addr(is_write, global_idx, internal_mode)
                                : next_external_addr(addr_mode, global_idx);

        item_h = build_item(pkt_addr, pkt_len, is_write, nonincrement_pkt);
        if (internal_pkt && is_write && item_h.data_words_q.size() != 0) begin
          item_h.data_words_q[0] = next_internal_write_data(pkt_addr, global_idx, internal_mode);
        end
        if (masked_pkt) begin
          string mask_mode_lower;

          mask_mode_lower = mask_mode.tolower();
          case (mask_mode_lower)
            "mupix": item_h.mask_m = 1'b1;
            "scifi": item_h.mask_s = 1'b1;
            "tile":  item_h.mask_t = 1'b1;
            "run":   item_h.mask_r = 1'b1;
            default: begin
              case (global_idx % 4)
                0: item_h.mask_m = 1'b1;
                1: item_h.mask_s = 1'b1;
                2: item_h.mask_t = 1'b1;
                default: item_h.mask_r = 1'b1;
              endcase
            end
          endcase
        end
        if (malformed_pkt) begin
          item_h.malformed      = 1'b1;
          item_h.malformed_kind = "missing_trailer";
          item_h.expect_reply   = 1'b0;
        end else begin
          item_h.force_ooo = force_ooo && !internal_pkt;
          if (error_pkt) begin
            item_h.forced_response = calc_stream_forced_response(err_mode, global_idx);
          end
          if (ordered_pkt) begin
            item_h.ordered      = 1'b1;
            item_h.order_mode   = global_idx[0] ? SC_ORDER_ACQUIRE : SC_ORDER_RELEASE;
            item_h.order_domain = global_idx % (order_domains == 0 ? 1 : order_domains);
            item_h.order_epoch  = global_idx;
          end
          if (atomic_pkt) begin
            item_h.atomic      = 1'b1;
            item_h.atomic_mode = SC_ATOMIC_RMW;
            item_h.atomic_id   = global_idx;
            item_h.atomic_mask = 32'h0000_FFFF;
            item_h.atomic_data = 32'h0000_00AA | global_idx;
          end
        end

        if ((trace_start != 0) &&
            (global_idx >= trace_start) &&
            ((trace_end == 0) || (global_idx <= trace_end))) begin
          `uvm_info(
            get_type_name(),
            $sformatf(
              "TRACE_TXN idx=%0d addr=0x%06h len=%0d sc_type=%0d write=%0b mask[m,s,t,r]=%0b%0b%0b%0b ordered=%0b mode=%0d dom=%0d epoch=%0d atomic=%0b malformed=%0b forced_rsp=%0b",
              global_idx,
              item_h.start_address,
              item_h.rw_length,
              item_h.sc_type,
              is_write,
              item_h.mask_m,
              item_h.mask_s,
              item_h.mask_t,
              item_h.mask_r,
              item_h.ordered,
              item_h.order_mode,
              item_h.order_domain,
              item_h.order_epoch,
              item_h.atomic,
              item_h.malformed,
              item_h.forced_response
            ),
            UVM_LOW
          );
        end

        issue_item(item_h);
        wait_gap(gap_cycles);
      end
    end
  endtask

  task automatic run_csr_full_sweep();
    sc_pkt_seq_item item_h;
    logic [1:0]     meta_sel;

    for (int unsigned csr_offset = 0; csr_offset <= 16'h01F; csr_offset++) begin
      meta_sel = (csr_offset + 3) % 4;
      item_h = build_item(INTERNAL_CSR_BASE_CONST + 24'h000001, 1, 1'b1);
      item_h.data_words_q[0] = {30'd0, meta_sel};
      issue_item(item_h);
      wait_for_drain();

      item_h = build_item(INTERNAL_CSR_BASE_CONST + csr_offset, 1, 1'b0);
      if (csr_offset == 16'h01D || csr_offset == 16'h01E) begin
        item_h.forced_response     = 2'b10;
        item_h.expect_error_payload = 1'b1;
        item_h.error_payload_word   = 32'hEEEE_EEEE;
      end else if (!csr_read_payload_modeled(csr_offset) && csr_offset <= 16'h01C) begin
        item_h.skip_payload_check = 1'b1;
      end
      issue_item(item_h);
      wait_for_drain();
    end
  endtask

  task automatic run_bad_csr_write_case();
    int unsigned    bad_offsets[$] = '{16'h01D, 16'h01E, 16'h01F, 16'h000, 16'h005, 16'h003, 16'h00A};
    sc_pkt_seq_item item_h;

    foreach (bad_offsets[idx]) begin
      item_h = build_item(INTERNAL_CSR_BASE_CONST + bad_offsets[idx], 1, 1'b1);
      item_h.data_words_q[0]   = 32'hCAFE_BABE;
      item_h.forced_response   = (bad_offsets[idx] == 16'h000) ? 2'b00 : 2'b10;
      issue_item(item_h);
      wait_for_drain();
    end

    for (int unsigned csr_offset = 16'h00B; csr_offset <= 16'h017; csr_offset++) begin
      item_h = build_item(INTERNAL_CSR_BASE_CONST + csr_offset, 1, 1'b1);
      item_h.data_words_q[0]   = 32'hCAFE_BABE;
      item_h.forced_response   = 2'b10;
      issue_item(item_h);
      wait_for_drain();
    end
  endtask

  task automatic run_ooo_disable_strict();
    sc_pkt_seq_item item_h;

    item_h = build_item(INTERNAL_CSR_BASE_CONST + 24'h000018, 1, 1'b1);
    item_h.data_words_q[0] = 32'h0000_0000;
    issue_item(item_h);
    wait_for_drain();

    for (int unsigned txn_idx = 0; txn_idx < 100; txn_idx++) begin
      bit          internal_pkt;
      bit          is_write;
      int unsigned pkt_len;
      logic [23:0] pkt_addr;

      internal_pkt = ((next_lcg() % 100) < 20);
      is_write     = ((next_lcg() % 100) >= 50);
      pkt_len      = next_range(1, 4);
      pkt_addr     = next_external_addr("linear", txn_idx + 1);

      if (internal_pkt) begin
        pkt_len = 1;
        if (is_write) begin
          pkt_addr = INTERNAL_CSR_BASE_CONST + 24'h000006;
        end else begin
          case (txn_idx % 4)
            0: pkt_addr = INTERNAL_CSR_BASE_CONST + 24'h000000;
            1: pkt_addr = INTERNAL_CSR_BASE_CONST + 24'h000001;
            2: pkt_addr = INTERNAL_CSR_BASE_CONST + 24'h00001C;
            default: pkt_addr = INTERNAL_CSR_BASE_CONST + 24'h00001F;
          endcase
        end
      end

      item_h = build_item(pkt_addr, pkt_len, is_write);
      item_h.force_ooo    = 1'b0;
      item_h.ordered      = 1'b0;
      item_h.order_mode   = SC_ORDER_RELAXED;
      item_h.order_domain = 0;
      item_h.order_epoch  = 0;
      if (internal_pkt && is_write) begin
        item_h.data_words_q[0] = 32'hD500_0000 | txn_idx;
      end
      issue_item(item_h);
      wait_gap(next_range(1, 3));
    end

    wait_for_drain();
  endtask

  task automatic run_soft_reset_case();
    sc_pkt_seq_item item_h;
    logic [31:0]    avs_word;

    for (int unsigned txn_idx = 0; txn_idx < 16; txn_idx++) begin
      item_h = build_item(24'h000200 + (txn_idx * 16), 1, 1'b1);
      issue_item(item_h);
    end
    wait_for_drain();

    for (int unsigned txn_idx = 0; txn_idx < 16; txn_idx++) begin
      item_h = build_item(24'h000200 + (txn_idx * 16), 1, 1'b0);
      issue_item(item_h);
    end
    wait_for_drain();
    wait_for_drain();

    write_avs_csr_word(5'h02, 32'h0000_0005);
    wait_gap(8);
    wait_for_drain();

    for (int unsigned txn_idx = 0; txn_idx < 16; txn_idx++) begin
      item_h = build_item(24'h000300 + (txn_idx * 16), 1, 1'b1);
      issue_item(item_h);
    end
    for (int unsigned txn_idx = 0; txn_idx < 16; txn_idx++) begin
      item_h = build_item(24'h000300 + (txn_idx * 16), 1, 1'b0);
      issue_item(item_h);
    end
    wait_for_drain();
    read_avs_csr_word(5'h03, avs_word);
    read_avs_csr_word(5'h0B, avs_word);
  endtask

  task automatic run_csr_diversity_case();
    sc_pkt_seq_item item_h;
    int unsigned    atomic_id;
    int unsigned    order_epoch;

    atomic_id   = 1;
    order_epoch = 1;

    cfg.enable_ooo = 1'b1;

    item_h = build_item(INTERNAL_CSR_BASE_CONST + 24'h000018, 1, 1'b1);
    item_h.data_words_q[0] = 32'h0000_0001;
    issue_item(item_h);
    wait_for_drain();

    item_h = build_item(CONTROL_CSR_BASE_CONST + 24'h000004, 1, 1'b1);
    item_h.data_words_q[0] = 32'hC376_0004;
    issue_item(item_h);
    wait_for_drain();

    item_h = build_item(CONTROL_CSR_BASE_CONST + 24'h000004, 1, 1'b0);
    issue_item(item_h);
    wait_for_drain();

    item_h = build_item(CONTROL_CSR_BASE_CONST + 24'h000008, 2, 1'b1, 1'b1);
    item_h.data_words_q[0] = 32'hC376_1008;
    item_h.data_words_q[1] = 32'hC376_1009;
    issue_item(item_h);
    wait_for_drain();

    item_h = build_item(CONTROL_CSR_BASE_CONST + 24'h000008, 2, 1'b0, 1'b1);
    issue_item(item_h);
    wait_for_drain();

    item_h = build_item(24'h0007C0, 2, 1'b0);
    item_h.mask_m = 1'b1;
    item_h.mask_s = 1'b1;
    issue_item(item_h);
    wait_gap(2);

    item_h = build_item(24'h000840, 4, 1'b0);
    issue_item(item_h);
    wait_gap(1);

    item_h = build_item(24'h000860, 4, 1'b1);
    item_h.force_ooo    = 1'b0;
    item_h.ordered      = 1'b1;
    item_h.order_mode   = SC_ORDER_RELEASE;
    item_h.order_domain = 8;
    item_h.order_epoch  = order_epoch++;
    issue_item(item_h);
    wait_for_drain();

    item_h = build_item(INTERNAL_CSR_BASE_CONST + 24'h000006, 2, 1'b1, 1'b1);
    item_h.data_words_q[0] = 32'hC376_A001;
    item_h.data_words_q[1] = 32'hC376_A002;
    item_h.mask_r = 1'b1;
    issue_item(item_h);
    wait_for_drain();

    item_h = build_item(INTERNAL_CSR_BASE_CONST, 2, 1'b0, 1'b1);
    issue_item(item_h);
    wait_for_drain();

    item_h = build_item(24'h000900, 8, 1'b0);
    item_h.force_ooo = 1'b1;
    issue_item(item_h);
    wait_for_drain();

    item_h = build_item(24'h000980, 1, 1'b0);
    item_h.atomic      = 1'b1;
    item_h.atomic_mode = SC_ATOMIC_LOCK;
    item_h.atomic_id   = atomic_id++;
    item_h.atomic_mask = 32'h0000_00FF;
    item_h.atomic_data = 32'h0000_005A;
    issue_item(item_h);
    wait_for_drain();

    item_h = build_item(24'h0009A0, 1, 1'b0);
    item_h.atomic      = 1'b1;
    item_h.atomic_mode = SC_ATOMIC_MIXED;
    item_h.atomic_id   = atomic_id++;
    item_h.atomic_mask = 32'h0000_FFFF;
    item_h.atomic_data = 32'h0000_A55A;
    issue_item(item_h);
    wait_for_drain();

    item_h = build_item(24'h0009C0, 40, 1'b0);
    item_h.forced_response    = 2'b11;
    item_h.expect_error_payload = 1'b0;
    issue_item(item_h);
    wait_for_drain();

    item_h = build_item(24'h000A40, 48, 1'b0);
    item_h.forced_response    = 2'b10;
    item_h.expect_error_payload = 1'b0;
    issue_item(item_h);
    wait_for_drain();

    item_h = build_item(24'h000B00, 1, 1'b0);
    item_h.atomic      = 1'b1;
    item_h.atomic_mode = SC_ATOMIC_LOCK;
    item_h.atomic_id   = atomic_id++;
    item_h.atomic_mask = 32'h0000_FFFF;
    item_h.atomic_data = 32'h0000_00E3;
    item_h.ordered      = 1'b1;
    item_h.order_mode   = SC_ORDER_ACQUIRE;
    item_h.order_domain = 12;
    item_h.order_epoch  = order_epoch++;
    issue_item(item_h);
    wait_for_drain();
  endtask

  task automatic run_burn_in_case();
    sc_pkt_seq_item item_h;
    int unsigned    txn_count;
    int unsigned    global_idx;

    txn_count   = 1200;
    global_idx  = 0;
    cfg.enable_ooo = 1'b1;

    item_h = build_item(INTERNAL_CSR_BASE_CONST + 24'h000018, 1, 1'b1);
    item_h.data_words_q[0] = 32'h0000_0001;
    issue_item(item_h);
    wait_for_drain();

    for (int unsigned txn_idx = 0; txn_idx < txn_count; txn_idx++) begin
      bit          internal_pkt;
      bit          is_write;
      int unsigned pkt_len;
      logic [23:0] pkt_addr;

      global_idx   = global_idx + 1;
      internal_pkt = ((next_lcg() % 100) < 20);
      is_write     = ((next_lcg() % 100) >= 50);
      pkt_len      = next_range(1, 16);

      if (internal_pkt) begin
        pkt_len  = 1;
        if (is_write) begin
          case (global_idx % 4)
            0: pkt_addr = INTERNAL_CSR_BASE_CONST + 24'h000006;
            1: pkt_addr = INTERNAL_CSR_BASE_CONST + 24'h000009;
            2: pkt_addr = INTERNAL_CSR_BASE_CONST + 24'h000018;
            default: pkt_addr = INTERNAL_CSR_BASE_CONST + 24'h00001C;
          endcase
        end else begin
          case (global_idx % 5)
            0: pkt_addr = INTERNAL_CSR_BASE_CONST + 24'h000000;
            1: pkt_addr = INTERNAL_CSR_BASE_CONST + 24'h000006;
            2: pkt_addr = INTERNAL_CSR_BASE_CONST + 24'h000009;
            3: pkt_addr = INTERNAL_CSR_BASE_CONST + 24'h000018;
            default: pkt_addr = INTERNAL_CSR_BASE_CONST + 24'h00001F;
          endcase
        end
      end else begin
        pkt_addr = next_external_addr("linear", global_idx);
      end

      item_h = build_item(pkt_addr, pkt_len, is_write, 1'b0);
      if (internal_pkt && is_write) begin
        case (pkt_addr)
          (INTERNAL_CSR_BASE_CONST + 24'h000006): item_h.data_words_q[0] = 32'hC700_0000 | global_idx;
          (INTERNAL_CSR_BASE_CONST + 24'h000009): item_h.data_words_q[0] = {30'd0, 1'b1, logic'(global_idx[0])};
          (INTERNAL_CSR_BASE_CONST + 24'h000018): item_h.data_words_q[0] = 32'h0000_0001;
          default: item_h.data_words_q[0] = {30'd0, logic'(global_idx % 4)};
        endcase
      end else if (!internal_pkt) begin
        item_h.force_ooo = 1'b1;
      end
      issue_item(item_h);
      wait_gap(next_range(0, 1));
    end
  endtask

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    case_id   = get_string_plusarg("SC_HUB_CASE_ID", "");
    profile   = get_string_plusarg("SC_HUB_PROFILE", "");
    rng_state = get_uint_plusarg("SC_HUB_SEED", 32'h1);
    cfg.enable_ooo = get_bit_plusarg("SC_HUB_CFG_ENABLE_OOO", 1'b0);
    cfg.check_order_epoch_monotonic = get_bit_plusarg("SC_HUB_CHECK_ORDER_EPOCH_MONO", 1'b1);
    cfg.rd_latency = get_uint_plusarg("SC_HUB_RD_LATENCY", cfg.rd_latency);
    cfg.wr_latency = get_uint_plusarg("SC_HUB_WR_LATENCY", cfg.wr_latency);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    wait_for_testbench_settle();
    configure_runtime_ctrls();

    if (profile == "burst_len_sweep") begin
      run_burst_len_sweep();
    end else if (profile == "addr_boundary_sweep") begin
      run_addr_boundary_sweep();
    end else if (profile == "latency_pair") begin
      run_latency_pair();
    end else if (profile == "error_case") begin
      run_error_case();
    end else if (profile == "gap_sweep") begin
      run_gap_sweep();
    end else if (profile == "csr_full_sweep") begin
      run_csr_full_sweep();
    end else if (profile == "bad_csr_write") begin
      run_bad_csr_write_case();
    end else if (profile == "ooo_disable_strict") begin
      run_ooo_disable_strict();
    end else if (profile == "soft_reset") begin
      run_soft_reset_case();
    end else if (profile == "csr_diversity") begin
      run_csr_diversity_case();
    end else if (profile == "burn_in") begin
      run_burn_in_case();
    end else if (profile == "perf_stream") begin
      run_perf_stream();
    end else begin
      `uvm_fatal(get_type_name(),
                 $sformatf("Unsupported SC_HUB_PROFILE='%s' for case '%s'", profile, case_id))
    end

    wait_for_drain();
    phase.drop_objection(this);
  endtask
endclass
