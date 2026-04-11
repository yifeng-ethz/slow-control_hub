class sc_hub_sweep_test extends sc_hub_base_test;
  `uvm_component_utils(sc_hub_sweep_test)

  function new(string name = "sc_hub_sweep_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    sc_pkt_addr_sweep_seq    addr_sweep_seq_h;
    sc_pkt_concurrent_seq    concurrent_seq_h;
    sc_pkt_atomic_seq        atomic_seq_h;
    sc_pkt_ordering_seq      ordering_seq_h;
    sc_pkt_mixed_seq         mixed_seq_h;
    sc_pkt_ooo_seq           ooo_seq_h;
    sc_pkt_perf_sweep_seq    perf_sweep_seq_h;
    sc_pkt_csr_seq           csr_seq_h;
    sc_pkt_bp_seq            bp_seq_h;
    sc_pkt_error_seq         error_seq_h;
    int unsigned             pass_idx;
    int unsigned             drain_cycles;

    phase.raise_objection(this);
    wait_for_testbench_settle();

    for (pass_idx = 0; pass_idx < cfg.sweep_iterations; pass_idx++) begin
      if (cfg.enable_addr_sweep) begin
        addr_sweep_seq_h = sc_pkt_addr_sweep_seq::type_id::create("addr_sweep_seq_h");
        addr_sweep_seq_h.sc_type      = (pass_idx[0]) ? SC_WRITE : SC_READ;
        addr_sweep_seq_h.start_address = cfg.sweep_addr_start[23:0] + (pass_idx * cfg.sweep_addr_step * 4);
        addr_sweep_seq_h.rw_length     = cfg.sweep_rw_length;
        addr_sweep_seq_h.addr_count    = ((cfg.sweep_addr_end > cfg.sweep_addr_start) ?
                                          ((cfg.sweep_addr_end - cfg.sweep_addr_start) / cfg.sweep_addr_step) :
                                          1) + 1;
        addr_sweep_seq_h.addr_stride   = cfg.sweep_addr_step;
        addr_sweep_seq_h.order_mode    = (pass_idx[1]) ? SC_ORDER_RELEASE : SC_ORDER_RELAXED;
        addr_sweep_seq_h.start(env_h.pkt_agent_h.sequencer_h);
      end

      if (cfg.enable_concurrent) begin
        concurrent_seq_h = sc_pkt_concurrent_seq::type_id::create("concurrent_seq_h");
        concurrent_seq_h.issue_count = cfg.ooo_issue_count;
        concurrent_seq_h.start(env_h.pkt_agent_h.sequencer_h);
      end

      if (cfg.enable_mixed && ((pass_idx % 2) == 0)) begin
        mixed_seq_h = sc_pkt_mixed_seq::type_id::create("mixed_seq_h");
        mixed_seq_h.start(env_h.pkt_agent_h.sequencer_h);
      end

      if (cfg.enable_atomic) begin
        atomic_seq_h = sc_pkt_atomic_seq::type_id::create("atomic_seq_h");
        atomic_seq_h.start_address = cfg.sweep_addr_start[23:0] + 16'h0040;
        atomic_seq_h.rw_length     = cfg.sweep_rw_length;
        atomic_seq_h.atomic_mode   = (pass_idx[0]) ? SC_ATOMIC_LOCK : SC_ATOMIC_RMW;
        atomic_seq_h.atomic_id     = cfg.ordering_domain + pass_idx;
        atomic_seq_h.atomic_count  = cfg.ooo_issue_count;
        atomic_seq_h.start(env_h.pkt_agent_h.sequencer_h);
      end

      if (cfg.enable_ordering) begin
        ordering_seq_h = sc_pkt_ordering_seq::type_id::create("ordering_seq_h");
        ordering_seq_h.order_mode     = SC_ORDER_RELEASE;
        ordering_seq_h.order_domain   = cfg.ordering_domain;
        ordering_seq_h.order_epoch    = cfg.ordering_epoch_start + pass_idx;
        ordering_seq_h.issue_count    = 4;
        ordering_seq_h.start(env_h.pkt_agent_h.sequencer_h);
      end

      if (cfg.enable_ordering && ((pass_idx % 2) == 1)) begin
        ordering_seq_h = sc_pkt_ordering_seq::type_id::create("ordering_acquire_seq_h");
        ordering_seq_h.order_mode     = SC_ORDER_ACQUIRE;
        ordering_seq_h.order_domain   = cfg.ordering_domain;
        ordering_seq_h.order_epoch    = cfg.ordering_epoch_start + (pass_idx * 2);
        ordering_seq_h.issue_count    = 3;
        ordering_seq_h.start(env_h.pkt_agent_h.sequencer_h);
      end

      if (cfg.enable_ooo) begin
        ooo_seq_h = sc_pkt_ooo_seq::type_id::create("ooo_seq_h");
        ooo_seq_h.issue_count = cfg.ooo_issue_count;
        ooo_seq_h.start(env_h.pkt_agent_h.sequencer_h);
      end

      if (cfg.enable_csr) begin
        csr_seq_h = sc_pkt_csr_seq::type_id::create("csr_seq_h");
        csr_seq_h.start_address = 24'h00FE80 + pass_idx * 4;
        csr_seq_h.start(env_h.pkt_agent_h.sequencer_h);
      end

      if (cfg.enable_bp && ((pass_idx % 3) == 0)) begin
        bp_seq_h = sc_pkt_bp_seq::type_id::create("bp_seq_h");
        bp_seq_h.start_address = cfg.sweep_addr_start[23:0] + 24'h0300 + pass_idx * 4;
        bp_seq_h.rw_length = cfg.sweep_rw_length + (pass_idx % 4);
        bp_seq_h.start(env_h.pkt_agent_h.sequencer_h);
      end

      if (cfg.enable_error && (pass_idx == 0)) begin
        error_seq_h = sc_pkt_error_seq::type_id::create("error_seq_h");
        error_seq_h.start(env_h.pkt_agent_h.sequencer_h);
      end

      if (cfg.enable_perf) begin
        perf_sweep_seq_h = sc_pkt_perf_sweep_seq::type_id::create("perf_sweep_seq_h");
        perf_sweep_seq_h.sc_type         = (pass_idx[0]) ? SC_BURST_WRITE : SC_BURST_READ;
        perf_sweep_seq_h.start_address   = cfg.sweep_addr_start[23:0] + 24'h0100;
        perf_sweep_seq_h.burst_len_min   = cfg.perf_burst_min;
        perf_sweep_seq_h.burst_len_max   = cfg.perf_burst_max;
        perf_sweep_seq_h.burst_len_step  = cfg.perf_burst_step;
        perf_sweep_seq_h.repeat_count    = cfg.perf_repeat;
        perf_sweep_seq_h.start(env_h.pkt_agent_h.sequencer_h);
      end

      repeat (cfg.sweep_idle_cycles) @(posedge env_h.pkt_agent_h.driver_h.sc_pkt_vif.clk);
    end

    wait_for_drain("sweep");
    phase.drop_objection(this);
  endtask
endclass
