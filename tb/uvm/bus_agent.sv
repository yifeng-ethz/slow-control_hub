class sc_hub_bus_txn extends uvm_sequence_item;
  `uvm_object_utils(sc_hub_bus_txn)

  bit             is_read;
  bit             is_write;
  logic [17:0]    address;
  int unsigned    burst_length;
  bit             has_cmd_meta;
  bit             ordered;
  sc_order_mode_e  order_mode;
  int unsigned    order_domain;
  int unsigned    order_epoch;
  sc_atomic_mode_e atomic_mode;
  int unsigned    atomic_id;
  bit             force_ooo;
  bit             is_ooo;

  function new(string name = "sc_hub_bus_txn");
    super.new(name);
    is_read      = 1'b0;
    is_write     = 1'b0;
    address      = '0;
    burst_length = 1;
    has_cmd_meta = 1'b0;
    ordered      = 1'b0;
    order_mode   = SC_ORDER_RELAXED;
    order_domain = 0;
    order_epoch  = 0;
    atomic_mode  = SC_ATOMIC_DISABLED;
    atomic_id    = 0;
    force_ooo    = 1'b0;
    is_ooo       = 1'b0;
  endfunction

  function sc_hub_bus_txn clone_item(string name = "sc_hub_bus_txn_clone");
    sc_hub_bus_txn clone_h;
    clone_h = new(name);
    clone_h.is_read      = is_read;
    clone_h.is_write     = is_write;
    clone_h.address      = address;
    clone_h.burst_length = burst_length;
    clone_h.has_cmd_meta = has_cmd_meta;
    clone_h.ordered      = ordered;
    clone_h.order_mode   = order_mode;
    clone_h.order_domain = order_domain;
    clone_h.order_epoch  = order_epoch;
    clone_h.atomic_mode  = atomic_mode;
    clone_h.atomic_id    = atomic_id;
    clone_h.force_ooo    = force_ooo;
    clone_h.is_ooo       = is_ooo;
    return clone_h;
  endfunction
endclass

class bus_slave_monitor_uvm extends uvm_monitor;
  `uvm_component_utils(bus_slave_monitor_uvm)

  localparam int unsigned MAX_PENDING_CMDS = 64;

  uvm_analysis_port #(sc_hub_bus_txn) bus_ap;
  uvm_analysis_imp_cmd #(sc_pkt_seq_item, bus_slave_monitor_uvm) cmd_ap;
  sc_hub_uvm_env_cfg cfg;
  virtual sc_hub_avmm_if avmm_vif;
  virtual sc_hub_axi4_if axi4_vif;

  sc_pkt_seq_item pending_cmd_q[$];
  int unsigned    pending_cmd_overflow_count;
  int unsigned    cmd_meta_match_count;
  int unsigned    cmd_meta_miss_count;
  int unsigned    ooo_from_meta_count;

  function new(string name = "bus_slave_monitor_uvm", uvm_component parent = null);
    super.new(name, parent);
    bus_ap = new("bus_ap", this);
    cmd_ap = new("cmd_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    pending_cmd_q.delete();
    pending_cmd_overflow_count = 0;
    cmd_meta_match_count      = 0;
    cmd_meta_miss_count       = 0;
    ooo_from_meta_count       = 0;

    if (!uvm_config_db#(sc_hub_uvm_env_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = sc_hub_uvm_env_cfg::type_id::create("cfg");
    end

    case (cfg.bus_type)
      SC_HUB_BUS_AXI4: begin
        if (!uvm_config_db#(virtual sc_hub_axi4_if)::get(this, "", "axi4_vif", axi4_vif)) begin
          `uvm_fatal(get_type_name(), "Missing axi4_vif")
        end
      end
      default: begin
        if (!uvm_config_db#(virtual sc_hub_avmm_if)::get(this, "", "avmm_vif", avmm_vif)) begin
          `uvm_fatal(get_type_name(), "Missing avmm_vif")
        end
      end
    endcase
  endfunction

  function void write_cmd(sc_pkt_seq_item req_h);
    sc_pkt_seq_item pending_cmd_h;
    sc_pkt_seq_item atomic_wr_cmd_h;

    if (req_h == null) begin
      return;
    end

    if (req_h.malformed || sc_hub_ref_model_pkg::is_internal_csr_addr(req_h.start_address[17:0])) begin
      return;
    end

    pending_cmd_h = req_h.clone_item("pending_cmd");
    pending_cmd_q.push_back(pending_cmd_h);
    if (req_h.has_atomic_meta()) begin
      atomic_wr_cmd_h = req_h.clone_item("pending_atomic_wr_cmd");
      atomic_wr_cmd_h.sc_type = SC_WRITE;
      atomic_wr_cmd_h.rw_length = 1;
      pending_cmd_q.push_back(atomic_wr_cmd_h);
    end
    if (pending_cmd_q.size() > MAX_PENDING_CMDS) begin
      void'(pending_cmd_q.pop_front());
      pending_cmd_overflow_count++;
    end
  endfunction

  function automatic sc_pkt_seq_item match_pending_cmd(
    input bit           is_write,
    input logic [17:0]  address,
    input int unsigned  burst_length,
    output bit          matched,
    output bit          out_of_order
  );
    sc_pkt_seq_item matched_cmd_h;
    int unsigned matched_idx;
    bit candidate;

    matched       = 1'b0;
    out_of_order  = 1'b0;
    matched_cmd_h = null;
    matched_idx   = 0;
    candidate     = 1'b0;

    for (int unsigned idx = 0; idx < pending_cmd_q.size(); idx++) begin
      if (pending_cmd_q[idx] == null) begin
        continue;
      end

      if ((pending_cmd_q[idx].is_write() == is_write) &&
          (pending_cmd_q[idx].start_address[17:0] == address) &&
          ((burst_length == 0) || (pending_cmd_q[idx].rw_length == burst_length))) begin
        matched     = 1'b1;
        matched_idx = idx;
        matched_cmd_h = pending_cmd_q[idx];
        candidate   = 1'b1;
        break;
      end
    end

    if (candidate) begin
      out_of_order = (matched_idx != 0);
      for (int unsigned idx = 0; idx <= matched_idx; idx++) begin
        if (idx < matched_idx) begin
          unmatched_cmd_queue_front();
        end else begin
          matched_cmd_h = pending_cmd_q.pop_front();
        end
      end
    end

    if (matched) begin
      cmd_meta_match_count++;
      if (out_of_order) begin
        ooo_from_meta_count++;
      end
    end else begin
      cmd_meta_miss_count++;
    end

    return matched_cmd_h;
  endfunction

  function void unmatched_cmd_queue_front();
    if (pending_cmd_q.size() > 0) begin
      void'(pending_cmd_q.pop_front());
      pending_cmd_overflow_count++;
    end
  endfunction

  task sample_axi4_read();
    sc_hub_bus_txn bus_h;
    sc_pkt_seq_item matched_cmd_h;
    bit has_match;
    bit out_of_order;

    bus_h = sc_hub_bus_txn::type_id::create("bus_h");
    bus_h.is_read      = 1'b1;
    bus_h.is_write     = 1'b0;
    bus_h.address      = axi4_vif.araddr;
    bus_h.burst_length = axi4_vif.arlen + 1;
    matched_cmd_h = match_pending_cmd(bus_h.is_write, bus_h.address, bus_h.burst_length, has_match, out_of_order);

    if (matched_cmd_h != null) begin
      bus_h.has_cmd_meta = 1'b1;
      bus_h.ordered      = matched_cmd_h.ordered;
      bus_h.order_mode   = matched_cmd_h.has_ordering_meta() ? matched_cmd_h.order_mode : SC_ORDER_RELAXED;
      bus_h.order_domain = matched_cmd_h.order_domain;
      bus_h.order_epoch  = matched_cmd_h.order_epoch;
      bus_h.atomic_mode  = matched_cmd_h.has_atomic_meta() ? matched_cmd_h.atomic_mode : SC_ATOMIC_DISABLED;
      bus_h.atomic_id    = matched_cmd_h.atomic_id;
      bus_h.force_ooo    = matched_cmd_h.force_ooo;
      bus_h.is_ooo       = matched_cmd_h.force_ooo || out_of_order;
    end else begin
      bus_h.has_cmd_meta = 1'b0;
      bus_h.ordered      = 1'b0;
      bus_h.order_mode   = SC_ORDER_RELAXED;
      bus_h.order_domain = 0;
      bus_h.order_epoch  = 0;
      bus_h.atomic_mode  = SC_ATOMIC_DISABLED;
      bus_h.atomic_id    = 0;
      bus_h.force_ooo    = 1'b0;
      bus_h.is_ooo       = 1'b0;
      if (!has_match) begin
        `uvm_warning(get_type_name(), "AXI4 read txn had no matching pending command metadata")
      end
    end

    bus_ap.write(bus_h);
  endtask

  task sample_axi4_write();
    sc_hub_bus_txn bus_h;
    sc_pkt_seq_item matched_cmd_h;
    bit has_match;
    bit out_of_order;

    bus_h = sc_hub_bus_txn::type_id::create("bus_h");
    bus_h.is_read      = 1'b0;
    bus_h.is_write     = 1'b1;
    bus_h.address      = axi4_vif.awaddr;
    bus_h.burst_length = axi4_vif.awlen + 1;
    matched_cmd_h = match_pending_cmd(bus_h.is_write, bus_h.address, bus_h.burst_length, has_match, out_of_order);

    if (matched_cmd_h != null) begin
      bus_h.has_cmd_meta = 1'b1;
      bus_h.ordered      = matched_cmd_h.ordered;
      bus_h.order_mode   = matched_cmd_h.has_ordering_meta() ? matched_cmd_h.order_mode : SC_ORDER_RELAXED;
      bus_h.order_domain = matched_cmd_h.order_domain;
      bus_h.order_epoch  = matched_cmd_h.order_epoch;
      bus_h.atomic_mode  = matched_cmd_h.has_atomic_meta() ? matched_cmd_h.atomic_mode : SC_ATOMIC_DISABLED;
      bus_h.atomic_id    = matched_cmd_h.atomic_id;
      bus_h.force_ooo    = matched_cmd_h.force_ooo;
      bus_h.is_ooo       = matched_cmd_h.force_ooo || out_of_order;
    end else begin
      bus_h.has_cmd_meta = 1'b0;
      bus_h.ordered      = 1'b0;
      bus_h.order_mode   = SC_ORDER_RELAXED;
      bus_h.order_domain = 0;
      bus_h.order_epoch  = 0;
      bus_h.atomic_mode  = SC_ATOMIC_DISABLED;
      bus_h.atomic_id    = 0;
      bus_h.force_ooo    = 1'b0;
      bus_h.is_ooo       = 1'b0;
      if (!has_match) begin
        `uvm_warning(get_type_name(), "AXI4 write txn had no matching pending command metadata")
      end
    end

    bus_ap.write(bus_h);
  endtask

  task sample_avmm_read();
    sc_hub_bus_txn bus_h;
    sc_pkt_seq_item matched_cmd_h;
    bit has_match;
    bit out_of_order;

    bus_h = sc_hub_bus_txn::type_id::create("bus_h");
    bus_h.is_read      = 1'b1;
    bus_h.is_write     = 1'b0;
    bus_h.address      = avmm_vif.address;
    bus_h.burst_length = (avmm_vif.burstcount == 0) ? 1 : avmm_vif.burstcount;
    matched_cmd_h = match_pending_cmd(bus_h.is_write, bus_h.address, bus_h.burst_length, has_match, out_of_order);

    if (matched_cmd_h != null) begin
      bus_h.has_cmd_meta = 1'b1;
      bus_h.ordered      = matched_cmd_h.ordered;
      bus_h.order_mode   = matched_cmd_h.has_ordering_meta() ? matched_cmd_h.order_mode : SC_ORDER_RELAXED;
      bus_h.order_domain = matched_cmd_h.order_domain;
      bus_h.order_epoch  = matched_cmd_h.order_epoch;
      bus_h.atomic_mode  = matched_cmd_h.has_atomic_meta() ? matched_cmd_h.atomic_mode : SC_ATOMIC_DISABLED;
      bus_h.atomic_id    = matched_cmd_h.atomic_id;
      bus_h.force_ooo    = matched_cmd_h.force_ooo;
      bus_h.is_ooo       = matched_cmd_h.force_ooo || out_of_order;
    end else begin
      bus_h.has_cmd_meta = 1'b0;
      bus_h.ordered      = 1'b0;
      bus_h.order_mode   = SC_ORDER_RELAXED;
      bus_h.order_domain = 0;
      bus_h.order_epoch  = 0;
      bus_h.atomic_mode  = SC_ATOMIC_DISABLED;
      bus_h.atomic_id    = 0;
      bus_h.force_ooo    = 1'b0;
      bus_h.is_ooo       = 1'b0;
      if (!has_match) begin
        `uvm_warning(get_type_name(), "AVMM read txn had no matching pending command metadata")
      end
    end

    bus_ap.write(bus_h);
  endtask

  task sample_avmm_write();
    sc_hub_bus_txn bus_h;
    sc_pkt_seq_item matched_cmd_h;
    bit has_match;
    bit out_of_order;

    bus_h = sc_hub_bus_txn::type_id::create("bus_h");
    bus_h.is_read      = 1'b0;
    bus_h.is_write     = 1'b1;
    bus_h.address      = avmm_vif.address;
    bus_h.burst_length = (avmm_vif.burstcount == 0) ? 1 : avmm_vif.burstcount;
    matched_cmd_h = match_pending_cmd(bus_h.is_write, bus_h.address, bus_h.burst_length, has_match, out_of_order);

    if (matched_cmd_h != null) begin
      bus_h.has_cmd_meta = 1'b1;
      bus_h.ordered      = matched_cmd_h.ordered;
      bus_h.order_mode   = matched_cmd_h.has_ordering_meta() ? matched_cmd_h.order_mode : SC_ORDER_RELAXED;
      bus_h.order_domain = matched_cmd_h.order_domain;
      bus_h.order_epoch  = matched_cmd_h.order_epoch;
      bus_h.atomic_mode  = matched_cmd_h.has_atomic_meta() ? matched_cmd_h.atomic_mode : SC_ATOMIC_DISABLED;
      bus_h.atomic_id    = matched_cmd_h.atomic_id;
      bus_h.force_ooo    = matched_cmd_h.force_ooo;
      bus_h.is_ooo       = matched_cmd_h.force_ooo || out_of_order;
    end else begin
      bus_h.has_cmd_meta = 1'b0;
      bus_h.ordered      = 1'b0;
      bus_h.order_mode   = SC_ORDER_RELAXED;
      bus_h.order_domain = 0;
      bus_h.order_epoch  = 0;
      bus_h.atomic_mode  = SC_ATOMIC_DISABLED;
      bus_h.atomic_id    = 0;
      bus_h.force_ooo    = 1'b0;
      bus_h.is_ooo       = 1'b0;
      if (!has_match) begin
        `uvm_warning(get_type_name(),
                     $sformatf("AVMM write txn had no matching pending command metadata addr=0x%04h burst=%0d pending_depth=%0d",
                               bus_h.address,
                               bus_h.burst_length,
                               pending_cmd_q.size()))
      end
    end

    bus_ap.write(bus_h);
  endtask

  task run_phase(uvm_phase phase);
    int unsigned avmm_wr_beats_remaining;

    avmm_wr_beats_remaining = 0;
    if (cfg.bus_type == SC_HUB_BUS_AXI4) begin
      forever begin
        @(posedge axi4_vif.clk);
        if (axi4_vif.rst) begin
          pending_cmd_q.delete();
          continue;
        end

        if (axi4_vif.arvalid && axi4_vif.arready) begin
          sample_axi4_read();
        end

        if (axi4_vif.awvalid && axi4_vif.awready) begin
          sample_axi4_write();
        end
      end
    end else begin
      forever begin
        @(posedge avmm_vif.clk);
        if (avmm_vif.rst) begin
          pending_cmd_q.delete();
          avmm_wr_beats_remaining = 0;
          continue;
        end

        if (avmm_vif.read && !avmm_vif.waitrequest) begin
          sample_avmm_read();
        end

        if (avmm_vif.write && !avmm_vif.waitrequest) begin
          if (avmm_wr_beats_remaining == 0) begin
            sample_avmm_write();
            avmm_wr_beats_remaining = (avmm_vif.burstcount == 0) ? 1 : avmm_vif.burstcount;
          end
          if (avmm_wr_beats_remaining != 0) begin
            avmm_wr_beats_remaining--;
          end
        end
      end
    end
  endtask

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(),
              $sformatf("pending_cmd_depth=%0d match_count=%0d miss_count=%0d overflow_count=%0d ooo_from_meta=%0d",
                        pending_cmd_q.size(),
                        cmd_meta_match_count,
                        cmd_meta_miss_count,
                        pending_cmd_overflow_count,
                        ooo_from_meta_count),
              UVM_LOW)
  endfunction
endclass

class bus_agent extends uvm_component;
  `uvm_component_utils(bus_agent)

  sc_hub_uvm_env_cfg     cfg;
  virtual sc_hub_avmm_if avmm_vif;
  virtual sc_hub_axi4_if axi4_vif;
  bus_slave_monitor_uvm  monitor_h;

  function new(string name = "bus_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(sc_hub_uvm_env_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = sc_hub_uvm_env_cfg::type_id::create("cfg");
    end

    void'(uvm_config_db#(virtual sc_hub_axi4_if)::get(this, "", "axi4_vif", axi4_vif));
    void'(uvm_config_db#(virtual sc_hub_avmm_if)::get(this, "", "avmm_vif", avmm_vif));

    case (cfg.bus_type)
      SC_HUB_BUS_AXI4: begin
        if (axi4_vif == null) begin
          `uvm_fatal(get_type_name(), "Missing axi4_vif")
        end
      end
      default: begin
        if (avmm_vif == null) begin
          `uvm_fatal(get_type_name(), "Missing avmm_vif")
        end
      end
    endcase

    monitor_h = bus_slave_monitor_uvm::type_id::create("monitor_h", this);
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(),
              $sformatf("Bus agent configured for %s monitoring",
                        (cfg.bus_type == SC_HUB_BUS_AXI4) ? "AXI4" : "AVALON"),
              UVM_LOW)
  endfunction
endclass
