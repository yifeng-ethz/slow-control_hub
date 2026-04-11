class sc_hub_ord_checker_uvm extends uvm_component;
  `uvm_component_utils(sc_hub_ord_checker_uvm)

  uvm_analysis_imp_cmd #(sc_pkt_seq_item, sc_hub_ord_checker_uvm) cmd_imp;
  uvm_analysis_imp_bus #(sc_hub_bus_txn, sc_hub_ord_checker_uvm) bus_imp;
  sc_hub_uvm_env_cfg cfg;

  int unsigned ordered_seen_count;
  int unsigned relaxed_seen_count;
  int unsigned atomic_seen_count;
  int unsigned release_seen_count;
  int unsigned acquire_seen_count;
  int unsigned bus_seen_count;
  int unsigned bus_meta_missing_count;
  int unsigned ooo_seen_count;
  int unsigned order_violation_count;
  int unsigned atomic_violation_count;
  int unsigned cmd_seen_count;
  int unsigned bus_violation_count;

  int unsigned cmd_last_order_epoch [0:15];
  int unsigned bus_last_order_epoch [0:15];
  bit          cmd_domain_seen      [0:15];
  bit          bus_domain_seen      [0:15];

  int unsigned cmd_without_meta_ooo;
  int unsigned force_ooo_missing_bus_mark;

  function new(string name = "sc_hub_ord_checker_uvm", uvm_component parent = null);
    super.new(name, parent);
    cmd_imp = new("cmd_imp", this);
    bus_imp = new("bus_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(sc_hub_uvm_env_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = sc_hub_uvm_env_cfg::type_id::create("cfg");
    end
    ordered_seen_count      = 0;
    relaxed_seen_count      = 0;
    atomic_seen_count       = 0;
    release_seen_count      = 0;
    acquire_seen_count      = 0;
    bus_seen_count          = 0;
    bus_meta_missing_count  = 0;
    ooo_seen_count          = 0;
    order_violation_count   = 0;
    atomic_violation_count  = 0;
    cmd_seen_count          = 0;
    bus_violation_count     = 0;
    cmd_without_meta_ooo    = 0;
    force_ooo_missing_bus_mark = 0;

    for (int unsigned idx = 0; idx < 16; idx++) begin
      cmd_last_order_epoch[idx] = 0;
      bus_last_order_epoch[idx] = 0;
      cmd_domain_seen[idx]      = 1'b0;
      bus_domain_seen[idx]      = 1'b0;
    end
  endfunction

  function void check_order_cmd(sc_pkt_seq_item req_h);
    if (req_h.ordered) begin
      ordered_seen_count++;
      if (req_h.order_domain > 15) begin
        order_violation_count++;
        `uvm_error(get_type_name(), $sformatf("Ordering domain out of range: %0d", req_h.order_domain));
        return;
      end
      if (req_h.order_mode != SC_ORDER_RELEASE && req_h.order_mode != SC_ORDER_ACQUIRE) begin
        order_violation_count++;
        `uvm_error(get_type_name(), $sformatf("Unsupported order mode for ordered cmd: %0d", req_h.order_mode));
      end
      if (cfg.check_order_epoch_monotonic &&
          req_h.order_epoch < cmd_last_order_epoch[req_h.order_domain]) begin
        order_violation_count++;
        `uvm_error(get_type_name(),
                   $sformatf("Ordering epoch regression on domain %0d: last=%0d now=%0d",
                             req_h.order_domain, cmd_last_order_epoch[req_h.order_domain], req_h.order_epoch));
      end
      if (req_h.order_mode == SC_ORDER_RELEASE) begin
        release_seen_count++;
      end else if (req_h.order_mode == SC_ORDER_ACQUIRE) begin
        acquire_seen_count++;
      end
      cmd_domain_seen[req_h.order_domain] = 1'b1;
      cmd_last_order_epoch[req_h.order_domain] = req_h.order_epoch;
      return;
    end

    if (req_h.order_mode != SC_ORDER_RELAXED) begin
      order_violation_count++;
      `uvm_error(get_type_name(),
                 $sformatf("Un-ordered item uses non-relaxed order_mode=%0d", req_h.order_mode));
    end
    relaxed_seen_count++;
  endfunction

  function void check_atomic_cmd(sc_pkt_seq_item req_h);
    if (!req_h.atomic && req_h.atomic_mode == SC_ATOMIC_DISABLED) begin
      return;
    end

    atomic_seen_count++;

    if (req_h.atomic_mode == SC_ATOMIC_DISABLED || req_h.atomic_mode > SC_ATOMIC_MIXED) begin
      atomic_violation_count++;
      `uvm_error(get_type_name(), $sformatf("Atomic mode inconsistent with atomic flag for %s", req_h.get_name()));
      return;
    end

    if (!req_h.atomic) begin
      atomic_violation_count++;
      `uvm_warning(get_type_name(), $sformatf("Atomic mode present without atomic flag for %s", req_h.get_name()));
    end

  endfunction

  function void write_cmd(sc_pkt_seq_item req_h);
    if (req_h == null) begin
      return;
    end
    cmd_seen_count++;
    check_order_cmd(req_h);
    check_atomic_cmd(req_h);
    if (req_h.force_ooo) begin
      cmd_without_meta_ooo++;
    end
  endfunction

  function void write_bus(sc_hub_bus_txn req_h);
    if (req_h == null) begin
      return;
    end

    bus_seen_count++;

    if (req_h.burst_length == 0) begin
      bus_violation_count++;
      `uvm_error(get_type_name(), "Bus transaction observed with zero-length burst");
    end

    if (req_h.is_ooo) begin
      ooo_seen_count++;
      if (!req_h.force_ooo) begin
        force_ooo_missing_bus_mark++;
      end
    end

    if (!req_h.has_cmd_meta) begin
      bus_meta_missing_count++;
      return;
    end

    if (req_h.ordered) begin
      if (req_h.order_domain > 15) begin
        order_violation_count++;
        `uvm_error(get_type_name(), $sformatf("Bus txn has invalid ordering domain: %0d", req_h.order_domain));
      end else begin
        if (req_h.order_mode == SC_ORDER_RELEASE) begin
          release_seen_count++;
        end else if (req_h.order_mode == SC_ORDER_ACQUIRE) begin
          acquire_seen_count++;
        end else if (req_h.order_mode != SC_ORDER_RELAXED) begin
          order_violation_count++;
        end

        if (req_h.order_mode != SC_ORDER_RELAXED) begin
          if (cfg.check_order_epoch_monotonic &&
              req_h.order_epoch < bus_last_order_epoch[req_h.order_domain]) begin
            order_violation_count++;
            `uvm_error(get_type_name(),
                       $sformatf("Bus txn ordering epoch regression domain=%0d last=%0d now=%0d",
                                 req_h.order_domain, bus_last_order_epoch[req_h.order_domain], req_h.order_epoch));
          end
          bus_last_order_epoch[req_h.order_domain] = req_h.order_epoch;
          bus_domain_seen[req_h.order_domain] = 1'b1;
        end
      end

    end else if (req_h.order_mode != SC_ORDER_RELAXED) begin
      order_violation_count++;
      `uvm_error(get_type_name(),
                 $sformatf("Bus txn has command meta without ordered flag: order_mode=%0d", req_h.order_mode));
    end

    if (req_h.atomic_mode == SC_ATOMIC_DISABLED) begin
      if (req_h.atomic_id != 0) begin
        atomic_violation_count++;
        `uvm_warning(get_type_name(), $sformatf("Atomic id present with SC_ATOMIC_DISABLED: %0d", req_h.atomic_id));
      end
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(),
              $sformatf("cmd=%0d ordered=%0d relaxed=%0d atomic=%0d release=%0d acquire=%0d bus=%0d ooo=%0d meta_missing=%0d bus_violation=%0d violations(order/atomic/bus)=%0d/%0d/%0d cmd_without_meta_ooo=%0d force_ooo_missing_bus_mark=%0d",
                        cmd_seen_count, ordered_seen_count, relaxed_seen_count, atomic_seen_count,
                        release_seen_count, acquire_seen_count, bus_seen_count, ooo_seen_count,
                        bus_meta_missing_count, bus_violation_count,
                        order_violation_count, atomic_violation_count, bus_violation_count,
                        cmd_without_meta_ooo, force_ooo_missing_bus_mark),
              UVM_LOW)
  endfunction
endclass
