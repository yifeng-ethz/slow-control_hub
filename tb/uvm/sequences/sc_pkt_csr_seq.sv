class sc_pkt_csr_seq extends uvm_sequence #(sc_pkt_seq_item);
  `uvm_object_utils(sc_pkt_csr_seq)

  sc_type_e    sc_type;
  logic [23:0] start_address;
  int unsigned rw_length;

  function new(string name = "sc_pkt_csr_seq");
    super.new(name);
    sc_type      = SC_READ;
    start_address = 24'h00FE80;
    rw_length    = 2;
  endfunction

  task body();
    sc_pkt_seq_item req_h;

    req_h = sc_pkt_seq_item::type_id::create("req_h");
    req_h.sc_type       = sc_type;
    req_h.start_address = start_address;
    req_h.rw_length     = rw_length;
    start_item(req_h);
    finish_item(req_h);
  endtask
endclass
