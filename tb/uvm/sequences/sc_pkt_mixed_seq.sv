class sc_pkt_mixed_seq extends uvm_sequence #(sc_pkt_seq_item);
  `uvm_object_utils(sc_pkt_mixed_seq)

  function new(string name = "sc_pkt_mixed_seq");
    super.new(name);
  endfunction

  task body();
    sc_pkt_seq_item req_h;

    req_h = sc_pkt_seq_item::type_id::create("rd_req_h");
    req_h.sc_type       = SC_READ;
    req_h.start_address = 24'h000300;
    req_h.rw_length     = 2;
    start_item(req_h);
    finish_item(req_h);

    req_h = sc_pkt_seq_item::type_id::create("wr_req_h");
    req_h.sc_type       = SC_WRITE;
    req_h.start_address = 24'h000304;
    req_h.rw_length     = 2;
    req_h.data_words_q.push_back(32'hCAFE_0001);
    req_h.data_words_q.push_back(32'hCAFE_0002);
    start_item(req_h);
    finish_item(req_h);

    req_h = sc_pkt_seq_item::type_id::create("csr_req_h");
    req_h.sc_type       = SC_READ;
    req_h.start_address = 24'h00FE80;
    req_h.rw_length     = 1;
    start_item(req_h);
    finish_item(req_h);
  endtask
endclass
