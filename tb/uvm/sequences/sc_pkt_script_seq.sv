class sc_pkt_script_seq extends uvm_sequence #(sc_pkt_seq_item);
  `uvm_object_utils(sc_pkt_script_seq)

  sc_pkt_seq_item req_h;

  function new(string name = "sc_pkt_script_seq");
    super.new(name);
    req_h = null;
  endfunction

  task body();
    if (req_h == null) begin
      `uvm_fatal(get_type_name(), "req_h must be configured before start()")
    end

    start_item(req_h);
    finish_item(req_h);
  endtask
endclass
