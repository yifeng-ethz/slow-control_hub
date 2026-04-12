class sc_hub_cov_collector extends uvm_component;
  `uvm_component_utils(sc_hub_cov_collector)

  localparam real CLK_PERIOD_NS = 6.4;

  localparam int unsigned MASK_NONE  = 0;
  localparam int unsigned MASK_M     = 1;
  localparam int unsigned MASK_S     = 2;
  localparam int unsigned MASK_T     = 3;
  localparam int unsigned MASK_R     = 4;
  localparam int unsigned MASK_MULTI = 5;

  localparam int unsigned DROP_NONE                = 0;
  localparam int unsigned DROP_MISSING_TRAILER     = 1;
  localparam int unsigned DROP_DATA_COUNT_MISMATCH = 2;
  localparam int unsigned DROP_LENGTH_OVERFLOW     = 3;
  localparam int unsigned DROP_FIFO_OVERFLOW       = 4;
  localparam int unsigned DROP_TRUNCATED           = 5;
  localparam int unsigned DROP_BAD_DTYPE           = 6;
  localparam int unsigned DROP_OTHER               = 7;

  localparam int unsigned SEQ_FIRST         = 0;
  localparam int unsigned SEQ_RD_AFTER_RD   = 1;
  localparam int unsigned SEQ_WR_AFTER_WR   = 2;
  localparam int unsigned SEQ_RD_AFTER_WR   = 3;
  localparam int unsigned SEQ_WR_AFTER_RD   = 4;
  localparam int unsigned SEQ_CSR_AFTER_EXT = 5;
  localparam int unsigned SEQ_EXT_AFTER_CSR = 6;

  localparam int unsigned OOO_OFF         = 0;
  localparam int unsigned OOO_ON_INORDER  = 1;
  localparam int unsigned OOO_ON_REORDER  = 2;

  uvm_analysis_imp_cov_cmd #(sc_pkt_seq_item, sc_hub_cov_collector) cmd_imp;
  uvm_analysis_imp_cov_rsp #(sc_reply_item, sc_hub_cov_collector)   rsp_imp;
  uvm_analysis_imp_bus     #(sc_hub_bus_txn, sc_hub_cov_collector)  bus_imp;

  sc_hub_uvm_env_cfg cfg;

  int unsigned cmd_count;
  int unsigned read_count;
  int unsigned write_count;
  int unsigned rsp_ok_count;
  int unsigned rsp_err_count;
  int unsigned bus_count;

  bit          prev_cmd_valid;
  bit          prev_cmd_is_write;
  bit          prev_cmd_is_internal;
  realtime     prev_cmd_time_ns;

  covergroup cmd_cg with function sample(logic [1:0]      sc_type,
                                         sc_addr_region_e addr_region,
                                         int unsigned     mask_class,
                                         int unsigned     malformed_class,
                                         int unsigned     rw_length,
                                         logic [1:0]      order_mode,
                                         int unsigned     order_domain,
                                         int unsigned     seq_kind,
                                         int unsigned     gap_cycles,
                                         int unsigned     bus_type,
                                         bit              atomic);
    option.per_instance = 1;

    cp_type: coverpoint sc_type {
      bins read               = {SC_READ};
      bins write              = {SC_WRITE};
      bins read_nonincrement  = {SC_READ_NONINCREMENTING};
      bins write_nonincrement = {SC_WRITE_NONINCREMENTING};
    }

    cp_addr_range: coverpoint addr_region {
      bins scratch_pad   = {REGION_SCRATCH_PAD};
      bins frame_rcv     = {REGION_FRAME_RCV};
      bins mts_proc      = {REGION_MTS_PROC};
      bins ring_buf_cam  = {REGION_RING_BUF_CAM};
      bins feb_frame_asm = {REGION_FEB_FRAME_ASM};
      bins histogram     = {REGION_HISTOGRAM};
      bins control_csr   = {REGION_CONTROL_CSR};
      bins internal_csr  = {REGION_INTERNAL_CSR};
      bins unmapped      = {REGION_UNKNOWN};
    }

    cp_mask: coverpoint mask_class {
      bins none  = {MASK_NONE};
      bins mupix = {MASK_M};
      bins scifi = {MASK_S};
      bins tile  = {MASK_T};
      bins run   = {MASK_R};
      bins multi = {MASK_MULTI};
    }

    cp_malformed: coverpoint malformed_class {
      bins none                = {DROP_NONE};
      bins missing_trailer     = {DROP_MISSING_TRAILER};
      bins data_count_mismatch = {DROP_DATA_COUNT_MISMATCH};
      bins length_overflow     = {DROP_LENGTH_OVERFLOW};
      bins fifo_overflow       = {DROP_FIFO_OVERFLOW};
      bins truncated           = {DROP_TRUNCATED};
      bins bad_dtype           = {DROP_BAD_DTYPE};
      bins other               = {DROP_OTHER};
    }

    cp_length: coverpoint rw_length {
      bins len1      = {1};
      bins len2_4    = {[2:4]};
      bins len5_16   = {[5:16]};
      bins len17_64  = {[17:64]};
      bins len65_256 = {[65:256]};
    }

    cp_order_mode: coverpoint order_mode {
      bins relaxed = {SC_ORDER_RELAXED};
      bins release_mode = {SC_ORDER_RELEASE};
      bins acquire = {SC_ORDER_ACQUIRE};
    }

    cp_order_domain: coverpoint order_domain {
      bins dom0    = {0};
      bins dom1    = {1};
      bins dom2_7  = {[2:7]};
      bins dom8_15 = {[8:15]};
    }

    cp_seq: coverpoint seq_kind {
      bins first         = {SEQ_FIRST};
      bins rd_after_rd   = {SEQ_RD_AFTER_RD};
      bins wr_after_wr   = {SEQ_WR_AFTER_WR};
      bins rd_after_wr   = {SEQ_RD_AFTER_WR};
      bins wr_after_rd   = {SEQ_WR_AFTER_RD};
      bins csr_after_ext = {SEQ_CSR_AFTER_EXT};
      bins ext_after_csr = {SEQ_EXT_AFTER_CSR};
    }

    cp_gap: coverpoint gap_cycles {
      bins gap0    = {0};
      bins gap1    = {1};
      bins gap2_7  = {[2:7]};
      bins gap8_15 = {[8:15]};
      bins gap16p  = {[16:65535]};
    }

    cp_bus_type: coverpoint bus_type {
      bins avalon = {SC_HUB_BUS_AVALON};
      bins axi4   = {SC_HUB_BUS_AXI4};
    }

    cp_atomic: coverpoint atomic { bins no = {0}; bins yes = {1}; }

    x_type_addr: cross cp_type, cp_addr_range;
    x_type_bus:  cross cp_type, cp_bus_type;
    x_ord_type:  cross cp_order_mode, cp_type;
  endgroup

  covergroup rsp_cg with function sample(bit              header_valid,
                                         logic [1:0]      response,
                                         int unsigned     payload_words,
                                         bit              atomic,
                                         bit              ordered,
                                         bit              write_reply,
                                         sc_addr_region_e addr_region,
                                         int unsigned     bus_type);
    option.per_instance = 1;

    cp_header_valid: coverpoint header_valid { bins bad = {0}; bins good = {1}; }

    cp_response: coverpoint response {
      bins ok     = {2'b00};
      bins badarg = {2'b01};
      bins busy   = {2'b10};
      bins failed = {2'b11};
    }

    cp_payload_words: coverpoint payload_words {
      bins zero       = {0};
      bins one        = {1};
      bins short      = {[2:4]};
      bins burst      = {[5:32]};
      bins long_burst = {[33:256]};
    }

    cp_atomic: coverpoint atomic { bins no = {0}; bins yes = {1}; }
    cp_ordered: coverpoint ordered { bins no = {0}; bins yes = {1}; }
    cp_write_reply: coverpoint write_reply { bins no = {0}; bins yes = {1}; }

    cp_addr_range: coverpoint addr_region {
      bins scratch_pad   = {REGION_SCRATCH_PAD};
      bins frame_rcv     = {REGION_FRAME_RCV};
      bins mts_proc      = {REGION_MTS_PROC};
      bins ring_buf_cam  = {REGION_RING_BUF_CAM};
      bins feb_frame_asm = {REGION_FEB_FRAME_ASM};
      bins histogram     = {REGION_HISTOGRAM};
      bins control_csr   = {REGION_CONTROL_CSR};
      bins internal_csr  = {REGION_INTERNAL_CSR};
      bins unmapped      = {REGION_UNKNOWN};
    }

    cp_bus_type: coverpoint bus_type {
      bins avalon = {SC_HUB_BUS_AVALON};
      bins axi4   = {SC_HUB_BUS_AXI4};
    }

    rsp_cross: cross cp_response, cp_payload_words, cp_atomic, cp_write_reply;
  endgroup

  covergroup bus_cg with function sample(int unsigned     bus_type,
                                         sc_addr_region_e addr_region,
                                         int unsigned     burst_length,
                                         int unsigned     ooo_state,
                                         bit              ordered,
                                         sc_atomic_mode_e atomic_mode,
                                         bit              is_read);
    option.per_instance = 1;

    cp_bus_type: coverpoint bus_type {
      bins avalon = {SC_HUB_BUS_AVALON};
      bins axi4   = {SC_HUB_BUS_AXI4};
    }

    cp_addr_range: coverpoint addr_region {
      bins scratch_pad   = {REGION_SCRATCH_PAD};
      bins frame_rcv     = {REGION_FRAME_RCV};
      bins mts_proc      = {REGION_MTS_PROC};
      bins ring_buf_cam  = {REGION_RING_BUF_CAM};
      bins feb_frame_asm = {REGION_FEB_FRAME_ASM};
      bins histogram     = {REGION_HISTOGRAM};
      bins control_csr   = {REGION_CONTROL_CSR};
      bins internal_csr  = {REGION_INTERNAL_CSR};
      bins unmapped      = {REGION_UNKNOWN};
    }

    cp_burst_length: coverpoint burst_length {
      bins len1      = {1};
      bins len2_4    = {[2:4]};
      bins len5_16   = {[5:16]};
      bins len17_64  = {[17:64]};
      bins len65_256 = {[65:256]};
    }

    cp_ooo_state: coverpoint ooo_state {
      bins off       = {OOO_OFF};
      bins in_order  = {OOO_ON_INORDER};
      bins reordered = {OOO_ON_REORDER};
    }

    cp_ordered: coverpoint ordered { bins no = {0}; bins yes = {1}; }

    cp_atomic_mode: coverpoint atomic_mode {
      bins none  = {SC_ATOMIC_DISABLED};
      bins rmw   = {SC_ATOMIC_RMW};
      bins lock  = {SC_ATOMIC_LOCK};
      bins mixed = {SC_ATOMIC_MIXED};
    }

    cp_dir: coverpoint is_read { bins write = {0}; bins read = {1}; }

    x_ooo_bus: cross cp_bus_type, cp_ooo_state;
    x_addr_dir: cross cp_addr_range, cp_dir;
  endgroup

  function new(string name = "sc_hub_cov_collector", uvm_component parent = null);
    super.new(name, parent);
    cmd_imp = new("cmd_imp", this);
    rsp_imp = new("rsp_imp", this);
    bus_imp = new("bus_imp", this);
    cmd_cg = new();
    rsp_cg = new();
    bus_cg = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(sc_hub_uvm_env_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = sc_hub_uvm_env_cfg::type_id::create("cfg");
    end
    cmd_count        = 0;
    read_count       = 0;
    write_count      = 0;
    rsp_ok_count     = 0;
    rsp_err_count    = 0;
    bus_count        = 0;
    prev_cmd_valid   = 1'b0;
    prev_cmd_is_write = 1'b0;
    prev_cmd_is_internal = 1'b0;
    prev_cmd_time_ns = 0.0;
  endfunction

  function automatic sc_addr_region_e calc_addr_region(input logic [23:0] start_address);
    return sc_hub_addr_map_pkg::classify_addr(start_address);
  endfunction

  function automatic int unsigned calc_mask_class(input sc_pkt_seq_item cmd_item);
    int unsigned mask_count;

    mask_count = int'(cmd_item.mask_m) + int'(cmd_item.mask_s) + int'(cmd_item.mask_t) + int'(cmd_item.mask_r);
    if (mask_count == 0) begin
      return MASK_NONE;
    end
    if (mask_count > 1) begin
      return MASK_MULTI;
    end
    if (cmd_item.mask_m) begin
      return MASK_M;
    end
    if (cmd_item.mask_s) begin
      return MASK_S;
    end
    if (cmd_item.mask_t) begin
      return MASK_T;
    end
    return MASK_R;
  endfunction

  function automatic int unsigned calc_malformed_class(input string malformed_kind);
    string kind;

    kind = malformed_kind.tolower();
    if (kind == "") begin
      return DROP_NONE;
    end
    if (kind == "missing_trailer") begin
      return DROP_MISSING_TRAILER;
    end
    if (kind == "data_count_mismatch") begin
      return DROP_DATA_COUNT_MISMATCH;
    end
    if (kind == "length_overflow") begin
      return DROP_LENGTH_OVERFLOW;
    end
    if (kind == "fifo_overflow") begin
      return DROP_FIFO_OVERFLOW;
    end
    if (kind == "truncated") begin
      return DROP_TRUNCATED;
    end
    if (kind == "bad_dtype") begin
      return DROP_BAD_DTYPE;
    end
    return DROP_OTHER;
  endfunction

  function automatic int unsigned calc_gap_cycles();
    realtime delta_ns;

    if (!prev_cmd_valid) begin
      return 0;
    end
    delta_ns = $realtime - prev_cmd_time_ns;
    if (delta_ns <= 0.0) begin
      return 0;
    end
    return int'((delta_ns / CLK_PERIOD_NS) + 0.5);
  endfunction

  function automatic int unsigned calc_seq_kind(input bit is_write, input bit is_internal);
    if (!prev_cmd_valid) begin
      return SEQ_FIRST;
    end
    if (prev_cmd_is_internal && !is_internal) begin
      return SEQ_EXT_AFTER_CSR;
    end
    if (!prev_cmd_is_internal && is_internal) begin
      return SEQ_CSR_AFTER_EXT;
    end
    if (!prev_cmd_is_write && !is_write) begin
      return SEQ_RD_AFTER_RD;
    end
    if (prev_cmd_is_write && is_write) begin
      return SEQ_WR_AFTER_WR;
    end
    if (prev_cmd_is_write && !is_write) begin
      return SEQ_RD_AFTER_WR;
    end
    return SEQ_WR_AFTER_RD;
  endfunction

  function automatic int unsigned calc_ooo_state(input sc_hub_bus_txn bus_item);
    if ((cfg == null) || !cfg.enable_ooo) begin
      return OOO_OFF;
    end
    if (bus_item.is_ooo) begin
      return OOO_ON_REORDER;
    end
    return OOO_ON_INORDER;
  endfunction

  function void write_cov_cmd(sc_pkt_seq_item cmd_item);
    bit              is_write;
    bit              is_internal;
    logic [1:0]      effective_order_mode;
    sc_addr_region_e addr_region;

    cmd_count++;
    is_write = cmd_item.is_write();
    if (is_write) begin
      write_count++;
    end else begin
      read_count++;
    end

    is_internal = sc_hub_addr_map_pkg::is_internal_csr_addr(cmd_item.start_address);
    addr_region = calc_addr_region(cmd_item.start_address);
    effective_order_mode = cmd_item.has_ordering_meta() ? cmd_item.order_mode : SC_ORDER_RELAXED;

    cmd_cg.sample(cmd_item.sc_type,
                  addr_region,
                  calc_mask_class(cmd_item),
                  calc_malformed_class(cmd_item.malformed ? cmd_item.malformed_kind : ""),
                  cmd_item.rw_length,
                  effective_order_mode,
                  cmd_item.order_domain,
                  calc_seq_kind(is_write, is_internal),
                  calc_gap_cycles(),
                  cfg.bus_type,
                  cmd_item.has_atomic_meta());

    prev_cmd_valid       = 1'b1;
    prev_cmd_is_write    = is_write;
    prev_cmd_is_internal = is_internal;
    prev_cmd_time_ns     = $realtime;
  endfunction

  function void write_cov_rsp(sc_reply_item rsp_item);
    bit write_reply;
    bit ordered_reply;

    if (rsp_item.response == 2'b00) begin
      rsp_ok_count++;
    end else begin
      rsp_err_count++;
    end

    write_reply = (rsp_item.echoed_length != 0) && (rsp_item.payload_q.size() == 0);
    ordered_reply = (rsp_item.order_mode != SC_ORDER_RELAXED) ||
                    (rsp_item.order_domain != 0) ||
                    (rsp_item.order_epoch != 0);

    rsp_cg.sample(rsp_item.header_valid,
                  rsp_item.response,
                  rsp_item.payload_q.size(),
                  rsp_item.atomic,
                  ordered_reply,
                  write_reply,
                  calc_addr_region(rsp_item.start_address),
                  cfg.bus_type);
  endfunction

  function void write_bus(sc_hub_bus_txn bus_item);
    bus_count++;
    bus_cg.sample(cfg.bus_type,
                  calc_addr_region({6'h00, bus_item.address}),
                  bus_item.burst_length,
                  calc_ooo_state(bus_item),
                  bus_item.ordered,
                  bus_item.atomic_mode,
                  bus_item.is_read);
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(),
              $sformatf("cmd_count=%0d read_count=%0d write_count=%0d rsp_ok=%0d rsp_err=%0d bus_count=%0d cmd_cov=%0.2f rsp_cov=%0.2f bus_cov=%0.2f",
                        cmd_count, read_count, write_count, rsp_ok_count, rsp_err_count,
                        bus_count, cmd_cg.get_coverage(), rsp_cg.get_coverage(), bus_cg.get_coverage()),
              UVM_LOW)
  endfunction
endclass
