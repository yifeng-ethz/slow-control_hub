class sc_pkt_atomic_seq extends uvm_sequence #(sc_pkt_seq_item);
  `uvm_object_utils(sc_pkt_atomic_seq)

  logic [23:0]  start_address;
  int unsigned  rw_length;
  int unsigned  atomic_count;
  sc_atomic_mode_e atomic_mode;
  int unsigned  atomic_id;

  function new(string name = "sc_pkt_atomic_seq");
    super.new(name);
    start_address = 24'h000800;
    rw_length     = 4;
    atomic_count  = 2;
    atomic_mode   = SC_ATOMIC_RMW;
    atomic_id     = 1;
  endfunction

  task body();
    sc_pkt_seq_item req_h;

    for (int unsigned idx = 0; idx < atomic_count; idx++) begin
      req_h = sc_pkt_seq_item::type_id::create($sformatf("atomic_req_%0d", idx));
      req_h.sc_type        = SC_WRITE;
      req_h.start_address  = start_address + idx * 4;
      req_h.rw_length      = rw_length;
      req_h.atomic         = 1'b1;
      req_h.atomic_mode    = atomic_mode;
      req_h.atomic_id      = atomic_id + idx;
      req_h.order_mode     = SC_ORDER_RELAXED;

      for (int unsigned j = 0; j < req_h.rw_length; j++) begin
        req_h.data_words_q.push_back(32'hC000_0000 + idx + j);
      end

      start_item(req_h);
      finish_item(req_h);
    end
  endtask
endclass
