class sc_pkt_error_seq extends uvm_sequence #(sc_pkt_seq_item);
  `uvm_object_utils(sc_pkt_error_seq)

  sc_type_e    sc_type;
  logic [23:0] start_address;
  int unsigned rw_length;
  bit          expect_reply;
  string       malformed_kind;

  function new(string name = "sc_pkt_error_seq");
    super.new(name);
    sc_type       = SC_WRITE;
    start_address = 24'h000200;
    rw_length     = 4;
    expect_reply  = 1'b0;
    malformed_kind = "missing_trailer";
  endfunction

  task body();
    sc_pkt_seq_item req_h;

    req_h = sc_pkt_seq_item::type_id::create("req_h");
    req_h.sc_type         = sc_type;
    req_h.start_address   = start_address;
    req_h.rw_length       = rw_length;
    req_h.expect_reply    = expect_reply;
    req_h.malformed       = (malformed_kind != "");
    req_h.malformed_kind  = malformed_kind;
    for (int unsigned idx = 0; idx < rw_length; idx++) begin
      req_h.data_words_q.push_back(32'hE100_0000 + idx);
    end

    start_item(req_h);
    finish_item(req_h);
  endtask
endclass
