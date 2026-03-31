class sc_pkt_ordering_seq extends uvm_sequence #(sc_pkt_seq_item);
  `uvm_object_utils(sc_pkt_ordering_seq)

  logic [23:0]    start_address;
  int unsigned    issue_count;
  int unsigned    rw_length;
  sc_order_mode_e order_mode;
  int unsigned    order_domain;
  int unsigned    order_epoch;

  function new(string name = "sc_pkt_ordering_seq");
    super.new(name);
    start_address = 24'h000A00;
    issue_count   = 4;
    rw_length     = 2;
    order_mode    = SC_ORDER_RELEASE;
    order_domain  = 1;
    order_epoch   = 1;
  endfunction

  task body();
    sc_pkt_seq_item req_h;

    for (int unsigned idx = 0; idx < issue_count; idx++) begin
      req_h = sc_pkt_seq_item::type_id::create($sformatf("ordering_req_%0d", idx));
      req_h.sc_type       = (idx[0] == 1'b0) ? SC_WRITE : SC_READ;
      req_h.start_address = start_address + idx * 4;
      req_h.rw_length     = rw_length;
      req_h.ordered       = 1'b1;
      req_h.order_mode    = order_mode;
      req_h.order_domain  = order_domain;
      req_h.order_epoch   = order_epoch + idx;

      if (req_h.is_write()) begin
        for (int unsigned j = 0; j < req_h.rw_length; j++) begin
          req_h.data_words_q.push_back(32'hD000_0000 + idx + j);
        end
      end

      start_item(req_h);
      finish_item(req_h);
    end
  endtask
endclass
