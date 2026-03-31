class sc_pkt_concurrent_seq extends uvm_sequence #(sc_pkt_seq_item);
  `uvm_object_utils(sc_pkt_concurrent_seq)

  int unsigned issue_count;
  int unsigned rw_length;

  function new(string name = "sc_pkt_concurrent_seq");
    super.new(name);
    issue_count = 6;
    rw_length   = 2;
  endfunction

  task body();
    sc_pkt_seq_item req_h;

    for (int unsigned idx = 0; idx < issue_count; idx++) begin
      req_h = sc_pkt_seq_item::type_id::create($sformatf("concurrent_req_%0d", idx));
      req_h.sc_type = (idx[0] == 1'b0) ? SC_READ : SC_WRITE;
      req_h.start_address = 24'h000400 + idx * 4;
      req_h.rw_length = rw_length;

      if (req_h.is_write()) begin
        for (int unsigned j = 0; j < req_h.rw_length; j++) begin
          req_h.data_words_q.push_back(32'hB000_0000 + idx + j);
        end
      end

      start_item(req_h);
      finish_item(req_h);
    end
  endtask
endclass
