class sc_pkt_ooo_seq extends uvm_sequence #(sc_pkt_seq_item);
  `uvm_object_utils(sc_pkt_ooo_seq)

  logic [23:0] start_address;
  int unsigned issue_count;
  int unsigned rw_length;

  function new(string name = "sc_pkt_ooo_seq");
    super.new(name);
    start_address = 24'h001000;
    issue_count   = 4;
    rw_length     = 8;
  endfunction

  task body();
    sc_pkt_seq_item req_h;

    for (int unsigned idx = 0; idx < issue_count; idx++) begin
      req_h = sc_pkt_seq_item::type_id::create($sformatf("ooo_req_%0d", idx));
      req_h.sc_type       = SC_READ;
      req_h.start_address = start_address + idx * 8;
      req_h.rw_length     = rw_length;
      req_h.force_ooo     = 1'b1;

      start_item(req_h);
      finish_item(req_h);

      req_h = sc_pkt_seq_item::type_id::create($sformatf("ooo_wr_%0d", idx));
      req_h.sc_type       = SC_WRITE;
      req_h.start_address = start_address + idx * 8 + 4;
      req_h.rw_length     = rw_length;
      req_h.force_ooo     = 1'b1;
      for (int unsigned j = 0; j < req_h.rw_length; j++) begin
        req_h.data_words_q.push_back(32'hE000_0000 + idx + j);
      end
      start_item(req_h);
      finish_item(req_h);
    end
  endtask
endclass
