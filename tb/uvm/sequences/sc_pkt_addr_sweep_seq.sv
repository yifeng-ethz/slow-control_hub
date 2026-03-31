class sc_pkt_addr_sweep_seq extends uvm_sequence #(sc_pkt_seq_item);
  `uvm_object_utils(sc_pkt_addr_sweep_seq)

  sc_type_e    sc_type;
  logic [23:0] start_address;
  int unsigned addr_count;
  int unsigned addr_stride;
  int unsigned rw_length;
  int unsigned order_domain;
  int unsigned order_epoch;
  sc_order_mode_e order_mode;

  function new(string name = "sc_pkt_addr_sweep_seq");
    super.new(name);
    sc_type      = SC_READ;
    start_address = 24'h000100;
    addr_count    = 4;
    addr_stride   = 4;
    rw_length     = 1;
    order_domain  = 0;
    order_epoch   = 0;
    order_mode    = SC_ORDER_RELAXED;
  endfunction

  task body();
    sc_pkt_seq_item req_h;
    int unsigned  idx;

    for (idx = 0; idx < addr_count; idx++) begin
      req_h = sc_pkt_seq_item::type_id::create($sformatf("addr_req_%0d", idx));
      req_h.sc_type       = sc_type;
      req_h.start_address = (start_address + idx * addr_stride) & 24'hFFFFFF;
      req_h.rw_length     = rw_length;
      req_h.ordered       = (order_mode != SC_ORDER_RELAXED);
      req_h.order_mode    = order_mode;
      req_h.order_domain  = order_domain;
      req_h.order_epoch   = order_epoch + idx;

      if (req_h.is_write()) begin
        for (int unsigned j = 0; j < req_h.rw_length; j++) begin
          req_h.data_words_q.push_back(32'hA000_0000 + idx + j);
        end
      end

      start_item(req_h);
      finish_item(req_h);
    end
  endtask
endclass
