class sc_pkt_perf_sweep_seq extends uvm_sequence #(sc_pkt_seq_item);
  `uvm_object_utils(sc_pkt_perf_sweep_seq)

  sc_type_e     sc_type;
  logic [23:0]  start_address;
  int unsigned  burst_len_min;
  int unsigned  burst_len_max;
  int unsigned  burst_len_step;
  int unsigned  repeat_count;

  function new(string name = "sc_pkt_perf_sweep_seq");
    super.new(name);
    sc_type       = SC_BURST_WRITE;
    start_address = 24'h001200;
    burst_len_min = 2;
    burst_len_max = 16;
    burst_len_step = 2;
    repeat_count   = 1;
  endfunction

  task body();
    sc_pkt_seq_item req_h;

    for (int unsigned rep = 0; rep < repeat_count; rep++) begin
      for (int unsigned len = burst_len_min; len <= burst_len_max; len = len + burst_len_step) begin
        req_h = sc_pkt_seq_item::type_id::create($sformatf("perf_req_%0d_%0d", rep, len));
        req_h.sc_type       = sc_type;
        req_h.start_address = start_address + (rep * 4);
        req_h.rw_length     = (len == 0) ? 1 : len;
        req_h.rw_length     = req_h.rw_length > 256 ? 256 : req_h.rw_length;

        for (int unsigned j = 0; j < req_h.rw_length; j++) begin
          req_h.data_words_q.push_back(32'hF000_0000 + rep + len + j);
        end

        start_item(req_h);
        finish_item(req_h);
      end
    end
  endtask
endclass
