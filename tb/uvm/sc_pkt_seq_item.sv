class sc_pkt_seq_item extends uvm_sequence_item;
  `uvm_object_utils(sc_pkt_seq_item)

  sc_type_e       sc_type;
  logic [23:0]    start_address;
  int unsigned    rw_length;
  bit             mask_m;
  bit             mask_s;
  bit             mask_t;
  bit             mask_r;
  bit             expect_reply;
  bit             malformed;
  logic [1:0]     forced_response;
  bit             expect_error_payload;
  logic [31:0]    error_payload_word;
  string          malformed_kind;
  sc_order_mode_e order_mode;
  int unsigned    order_domain;
  int unsigned    order_epoch;
  bit             ordered;
  bit             atomic;
  sc_atomic_mode_e atomic_mode;
  int unsigned    atomic_id;
  logic [31:0]    atomic_mask;
  logic [31:0]    atomic_data;
  bit             force_ooo;
  logic [31:0]    data_words_q[$];

  function new(string name = "sc_pkt_seq_item");
    super.new(name);
    sc_type         = SC_READ;
    start_address   = '0;
    rw_length       = 1;
    mask_m          = 1'b0;
    mask_s          = 1'b0;
    mask_t          = 1'b0;
    mask_r          = 1'b0;
    expect_reply    = 1'b1;
    malformed       = 1'b0;
    forced_response = 2'b00;
    expect_error_payload = 1'b0;
    error_payload_word   = 32'h0;
    malformed_kind  = "";
    order_mode     = SC_ORDER_RELAXED;
    order_domain   = 0;
    order_epoch    = 0;
    ordered        = 1'b0;
    atomic         = 1'b0;
    atomic_mode    = SC_ATOMIC_DISABLED;
    atomic_id      = 0;
    atomic_mask    = 32'hFFFF_FFFF;
    atomic_data    = 32'h0;
    force_ooo      = 1'b0;
    data_words_q.delete();
  endfunction

  function sc_pkt_seq_item clone_item(string name = "sc_pkt_seq_item_clone");
    sc_pkt_seq_item clone_h;
    clone_h = new(name);
    clone_h.sc_type         = sc_type;
    clone_h.start_address   = start_address;
    clone_h.rw_length       = rw_length;
    clone_h.mask_m          = mask_m;
    clone_h.mask_s          = mask_s;
    clone_h.mask_t          = mask_t;
    clone_h.mask_r          = mask_r;
    clone_h.expect_reply    = expect_reply;
    clone_h.malformed       = malformed;
    clone_h.forced_response = forced_response;
    clone_h.expect_error_payload = expect_error_payload;
    clone_h.error_payload_word   = error_payload_word;
    clone_h.malformed_kind  = malformed_kind;
    clone_h.order_mode      = order_mode;
    clone_h.order_domain    = order_domain;
    clone_h.order_epoch     = order_epoch;
    clone_h.ordered         = ordered;
    clone_h.atomic          = atomic;
    clone_h.atomic_mode     = atomic_mode;
    clone_h.atomic_id       = atomic_id;
    clone_h.atomic_mask     = atomic_mask;
    clone_h.atomic_data     = atomic_data;
    clone_h.force_ooo       = force_ooo;
    clone_h.data_words_q    = data_words_q;
    return clone_h;
  endfunction

  function sc_cmd_t to_cmd();
    sc_cmd_t cmd;
    logic [1:0]                 effective_order_mode;
    bit             effective_atomic;

    effective_order_mode = ordered ? order_mode : SC_ORDER_RELAXED;
    effective_atomic = atomic && (atomic_mode != SC_ATOMIC_DISABLED);

    cmd = make_cmd(sc_type, start_address, rw_length);
    cmd.mask_m = mask_m;
    cmd.mask_s = mask_s;
    cmd.mask_t = mask_t;
    cmd.mask_r = mask_r;
    cmd.order_mode    = sc_hub_sim_pkg::sc_order_mode_e'(effective_order_mode);
    cmd.order_domain  = order_domain[3:0];
    cmd.order_epoch   = order_epoch[7:0];
    cmd.atomic        = effective_atomic;
    cmd.atomic_mask   = atomic_mask;
    cmd.atomic_data   = atomic_data;
    cmd.atomic_exclusive = effective_atomic ? (atomic_mode != SC_ATOMIC_DISABLED) : 1'b0;

    if (cmd.atomic && (data_words_q.size() > 0)) begin
      cmd.atomic_data = data_words_q[0];
    end
    for (int unsigned idx = 0; idx < data_words_q.size() && idx < 256; idx++) begin
      cmd.data_words[idx] = data_words_q[idx];
    end
    return cmd;
  endfunction

  function bit is_write();
    return sc_type[0];
  endfunction

  function bit reply_expected();
    return expect_reply && !(mask_m || mask_s || mask_t || mask_r);
  endfunction

  function bit has_ordering_meta();
    return ordered || order_mode != SC_ORDER_RELAXED || order_domain != 0 || order_epoch != 0;
  endfunction

  function bit has_atomic_meta();
    return atomic && atomic_mode != SC_ATOMIC_DISABLED;
  endfunction

  function string convert2string();
    return $sformatf("sc_type=%0d addr=0x%06h len=%0d expect_reply=%0b malformed=%0b kind=%s ordered=%0b atomic=%0b order_mode=%0d order_domain=%0d order_epoch=%0d atomic_mode=%0d atomic_id=%0d force_ooo=%0b",
                     sc_type, start_address, rw_length, expect_reply, malformed, malformed_kind,
                     ordered, atomic, order_mode, order_domain, order_epoch,
                     atomic_mode, atomic_id, force_ooo);
  endfunction
endclass
