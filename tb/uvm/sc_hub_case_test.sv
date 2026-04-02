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

  function automatic sc_type_e calc_sc_type(bit is_write, int unsigned rw_length);
    if (rw_length <= 1) begin
      return is_write ? SC_WRITE : SC_READ;
    end
    return is_write ? SC_BURST_WRITE : SC_BURST_READ;
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
    input int unsigned txn_idx
  );
    if (is_write) begin
      return INTERNAL_CSR_BASE_CONST + 24'h000006;
    end

    case (txn_idx % 2)
      0: return INTERNAL_CSR_BASE_CONST + 24'h000000;
      default: return INTERNAL_CSR_BASE_CONST + 24'h000001;
    endcase
  endfunction

  function automatic sc_pkt_seq_item build_item(
    input logic [23:0] start_address,
    input int unsigned rw_length,
    input bit          is_write
  );
    sc_pkt_seq_item item_h;

    item_h = sc_pkt_seq_item::type_id::create("item_h");
    item_h.sc_type       = calc_sc_type(is_write, rw_length);
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

  task automatic wait_for_drain();
    int unsigned drain_cycles;

    for (drain_cycles = 0; drain_cycles < 50000; drain_cycles++) begin
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
    string          err_op;
    bit             is_write;

    err_kind = get_string_plusarg("SC_HUB_ERR_KIND", "OKAY");
    err_op   = get_string_plusarg("SC_HUB_ERR_OP", "read");
    is_write = (err_op.tolower() == "write");
    item_h   = build_item(is_write ? 24'h0002A0 : 24'h000280, 1, is_write);
    item_h.forced_response = calc_forced_response(err_kind);
    if (err_kind.toupper() == "TIMEOUT") begin
      item_h.expect_error_payload = 1'b1;
      item_h.error_payload_word   = 32'hEEEE_EEEE;
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
    int unsigned    order_domains;
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
    order_domains      = get_uint_plusarg("SC_HUB_ORDER_DOMAINS", 1);
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
        bit          is_write;
        int unsigned pkt_len;
        logic [23:0] pkt_addr;

        global_idx     = global_idx + 1;
        malformed_pkt  = (malformed_every != 0) && ((global_idx % malformed_every) == 0);
        internal_pkt   = (!malformed_pkt) && ((next_lcg() % 100) < internal_pct);
        atomic_pkt     = (!malformed_pkt) && (!internal_pkt) && ((next_lcg() % 100) < atomic_pct);
        ordered_pkt    = (!malformed_pkt) && (!atomic_pkt) && ((next_lcg() % 100) < ordering_pct);
        is_write       = ((next_lcg() % 100) >= read_pct);
        pkt_len        = (fixed_len != 0) ? fixed_len : next_range(burst_min, burst_max);
        if (internal_pkt) begin
          pkt_len  = 1;
          is_write = (global_idx[0] == 1'b1);
        end
        if (atomic_pkt) begin
          pkt_len  = 1;
          is_write = 1'b0;
        end
        if (malformed_pkt) begin
          is_write = 1'b1;
        end

        pkt_addr = internal_pkt ? next_internal_addr(is_write, global_idx)
                                : next_external_addr(addr_mode, global_idx);

        item_h = build_item(pkt_addr, pkt_len, is_write);
        if (malformed_pkt) begin
          item_h.malformed      = 1'b1;
          item_h.malformed_kind = "missing_trailer";
          item_h.expect_reply   = 1'b0;
        end else begin
          item_h.force_ooo = force_ooo && !internal_pkt;
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

        issue_item(item_h);
        wait_gap(gap_cycles);
      end
    end
  endtask

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    case_id   = get_string_plusarg("SC_HUB_CASE_ID", "");
    profile   = get_string_plusarg("SC_HUB_PROFILE", "");
    rng_state = get_uint_plusarg("SC_HUB_SEED", 32'h1);
    cfg.enable_ooo = get_bit_plusarg("SC_HUB_CFG_ENABLE_OOO", 1'b0);
    cfg.check_order_epoch_monotonic = get_bit_plusarg("SC_HUB_CHECK_ORDER_EPOCH_MONO", 1'b1);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    wait_for_testbench_settle();

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
