class sc_hub_cov_collector extends uvm_component;
  `uvm_component_utils(sc_hub_cov_collector)

  uvm_analysis_imp_cov_cmd #(sc_pkt_seq_item, sc_hub_cov_collector) cmd_imp;
  uvm_analysis_imp_cov_rsp #(sc_reply_item, sc_hub_cov_collector)   rsp_imp;

  int unsigned cmd_count;
  int unsigned read_count;
  int unsigned write_count;
  int unsigned rsp_ok_count;
  int unsigned rsp_err_count;

  covergroup cmd_cg with function sample(bit is_write,
                                        bit is_internal,
                                        bit is_nonincrement,
                                        bit is_ordered,
                                        bit is_atomic,
                                        bit is_masked,
                                        bit is_malformed,
                                        int unsigned rw_length,
                                        logic [1:0] sc_type);
    option.per_instance = 1;

    cp_type: coverpoint sc_type {
      bins read             = {SC_READ};
      bins write            = {SC_WRITE};
      bins read_nonincrement  = {SC_READ_NONINCREMENTING};
      bins write_nonincrement = {SC_WRITE_NONINCREMENTING};
    }
    cp_internal: coverpoint is_internal { bins external = {0}; bins internal = {1}; }
    cp_ordered: coverpoint is_ordered { bins no = {0}; bins yes = {1}; }
    cp_atomic: coverpoint is_atomic { bins no = {0}; bins yes = {1}; }
    cp_masked: coverpoint is_masked { bins no = {0}; bins yes = {1}; }
    cp_malformed: coverpoint is_malformed { bins no = {0}; bins yes = {1}; }
    cp_length: coverpoint rw_length {
      bins len1 = {1};
      bins len2_4 = {[2:4]};
      bins len5_16 = {[5:16]};
      bins len17_64 = {[17:64]};
      bins len65_256 = {[65:256]};
    }
    cmd_cross: cross cp_type, cp_internal, cp_atomic, cp_ordered;
  endgroup

  covergroup rsp_cg with function sample(bit header_valid,
                                        logic [1:0] response,
                                        int unsigned payload_words,
                                        bit atomic,
                                        bit ordered,
                                        bit write_reply);
    option.per_instance = 1;

    cp_header_valid: coverpoint header_valid { bins bad = {0}; bins good = {1}; }
    cp_response: coverpoint response {
      bins ok     = {2'b00};
      bins badarg = {2'b01};
      bins busy   = {2'b10};
      bins failed = {2'b11};
    }
    cp_payload_words: coverpoint payload_words {
      bins zero = {0};
      bins one = {1};
      bins short = {[2:4]};
      bins burst = {[5:32]};
      bins long_burst = {[33:256]};
    }
    cp_atomic: coverpoint atomic { bins no = {0}; bins yes = {1}; }
    cp_ordered: coverpoint ordered { bins no = {0}; bins yes = {1}; }
    cp_write_reply: coverpoint write_reply { bins no = {0}; bins yes = {1}; }
    rsp_cross: cross cp_response, cp_payload_words, cp_atomic, cp_write_reply;
  endgroup

  function new(string name = "sc_hub_cov_collector", uvm_component parent = null);
    super.new(name, parent);
    cmd_imp = new("cmd_imp", this);
    rsp_imp = new("rsp_imp", this);
    cmd_cg = new();
    rsp_cg = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cmd_count     = 0;
    read_count    = 0;
    write_count   = 0;
    rsp_ok_count  = 0;
    rsp_err_count = 0;
  endfunction

  function void write_cov_cmd(sc_pkt_seq_item cmd_item);
    bit is_write;
    bit is_internal;
    bit is_nonincrement;
    bit is_masked;

    cmd_count++;
    is_write = cmd_item.is_write();
    if (is_write) begin
      write_count++;
    end else begin
      read_count++;
    end

    is_internal = sc_hub_addr_map_pkg::is_internal_csr_addr(cmd_item.start_address);
    is_nonincrement = (cmd_item.sc_type == SC_READ_NONINCREMENTING) ||
                      (cmd_item.sc_type == SC_WRITE_NONINCREMENTING);
    is_masked = cmd_item.mask_m || cmd_item.mask_s || cmd_item.mask_t || cmd_item.mask_r;

    cmd_cg.sample(is_write,
                  is_internal,
                  is_nonincrement,
                  cmd_item.ordered,
                  cmd_item.has_atomic_meta(),
                  is_masked,
                  cmd_item.malformed,
                  cmd_item.rw_length,
                  cmd_item.sc_type);
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
                  write_reply);
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(),
              $sformatf("cmd_count=%0d read_count=%0d write_count=%0d rsp_ok=%0d rsp_err=%0d cmd_cov=%0.2f rsp_cov=%0.2f",
                        cmd_count, read_count, write_count, rsp_ok_count, rsp_err_count,
                        cmd_cg.get_coverage(), rsp_cg.get_coverage()),
              UVM_LOW)
  endfunction
endclass
