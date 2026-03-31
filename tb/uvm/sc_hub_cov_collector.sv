class sc_hub_cov_collector extends uvm_component;
  `uvm_component_utils(sc_hub_cov_collector)

  uvm_analysis_imp_cov_cmd #(sc_pkt_seq_item, sc_hub_cov_collector) cmd_imp;
  uvm_analysis_imp_cov_rsp #(sc_reply_item, sc_hub_cov_collector)   rsp_imp;

  int unsigned cmd_count;
  int unsigned read_count;
  int unsigned write_count;
  int unsigned rsp_ok_count;
  int unsigned rsp_err_count;

  function new(string name = "sc_hub_cov_collector", uvm_component parent = null);
    super.new(name, parent);
    cmd_imp = new("cmd_imp", this);
    rsp_imp = new("rsp_imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cmd_count    = 0;
    read_count   = 0;
    write_count  = 0;
    rsp_ok_count = 0;
    rsp_err_count = 0;
  endfunction

  function void write_cov_cmd(sc_pkt_seq_item cmd_item);
    cmd_count++;
    if (cmd_item.is_write()) begin
      write_count++;
    end else begin
      read_count++;
    end
  endfunction

  function void write_cov_rsp(sc_reply_item rsp_item);
    if (rsp_item.response == 2'b00) begin
      rsp_ok_count++;
    end else begin
      rsp_err_count++;
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(),
              $sformatf("cmd_count=%0d read_count=%0d write_count=%0d rsp_ok=%0d rsp_err=%0d",
                        cmd_count, read_count, write_count, rsp_ok_count, rsp_err_count),
              UVM_LOW)
  endfunction
endclass
