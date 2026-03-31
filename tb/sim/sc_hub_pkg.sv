package sc_hub_sim_pkg;
  timeunit 1ns;
  timeprecision 1ps;

  localparam logic [7:0] K285_CONST = 8'hBC;
  localparam logic [7:0] K284_CONST = 8'h9C;

  typedef enum logic [1:0] {
    SC_BURST_READ  = 2'b00,
    SC_BURST_WRITE = 2'b01,
    SC_READ        = 2'b10,
    SC_WRITE       = 2'b11
  } sc_type_e;

  typedef enum logic [1:0] {
    SC_ORDER_RELAXED  = 2'b00,
    SC_ORDER_RELEASE  = 2'b01,
    SC_ORDER_ACQUIRE  = 2'b10,
    SC_ORDER_INVALID  = 2'b11
  } sc_order_mode_e;

  typedef struct {
    sc_type_e    sc_type;
    logic [15:0] fpga_id;
    logic [23:0] start_address;
    logic        mask_m;
    logic        mask_s;
    logic        mask_t;
    logic        mask_r;
    int unsigned rw_length;
    sc_order_mode_e order_mode;
    logic [3:0] order_domain;
    logic [7:0] order_epoch;
    logic       atomic;
    logic [31:0] atomic_mask;
    logic [31:0] atomic_data;
    logic        atomic_exclusive;
    logic [31:0] data_words [0:255];
  } sc_cmd_t;

  typedef struct {
    sc_type_e       sc_type;
    logic [15:0]    fpga_id;
    logic [23:0]    start_address;
    logic [31:0]    header_word;
    logic [15:0] echoed_length;
    logic [1:0]  response;
    logic        header_valid;
    int unsigned payload_words;
    logic [31:0] payload [0:255];
  } sc_reply_t;

  function automatic logic [31:0] make_preamble_word(sc_cmd_t cmd);
    return {6'b000111, cmd.sc_type, cmd.fpga_id, K285_CONST};
  endfunction

  function automatic logic [31:0] make_addr_word(sc_cmd_t cmd);
    return {4'b0, cmd.mask_m, cmd.mask_s, cmd.mask_t, cmd.mask_r, cmd.start_address};
  endfunction

  function automatic logic [31:0] make_length_word(sc_cmd_t cmd);
    return {16'h0000, cmd.rw_length[15:0]};
  endfunction

  function automatic bit cmd_is_write(sc_cmd_t cmd);
    return (cmd.sc_type[0] == 1'b1);
  endfunction

  function automatic bit reply_suppressed(sc_cmd_t cmd);
    return (cmd.mask_m || cmd.mask_s || cmd.mask_t || cmd.mask_r);
  endfunction

  function automatic sc_cmd_t make_cmd(
    sc_type_e    sc_type,
    logic [23:0] start_address,
    int unsigned rw_length
  );
    sc_cmd_t cmd;
    cmd.sc_type       = sc_type;
    cmd.fpga_id       = 16'h0002;
    cmd.start_address = start_address;
    cmd.mask_m        = 1'b0;
    cmd.mask_s        = 1'b0;
    cmd.mask_t        = 1'b0;
    cmd.mask_r        = 1'b0;
    cmd.rw_length     = rw_length;
    cmd.order_mode    = SC_ORDER_RELAXED;
    cmd.order_domain  = 4'h0;
    cmd.order_epoch   = 8'h0;
    cmd.atomic        = 1'b0;
    cmd.atomic_mask   = 32'h0;
    cmd.atomic_data   = 32'h0;
    cmd.atomic_exclusive = 1'b0;
    foreach (cmd.data_words[idx]) begin
      cmd.data_words[idx] = 32'h0;
    end
    return cmd;
  endfunction

  function automatic sc_cmd_t make_burst_cmd(
    sc_type_e    sc_type,
    logic [23:0] start_address,
    int unsigned rw_length
  );
    return make_cmd(sc_type, start_address, rw_length);
  endfunction

  function automatic sc_cmd_t make_ordered_cmd(
    sc_type_e      sc_type,
    logic [23:0]   start_address,
    int unsigned   rw_length,
    sc_order_mode_e order_mode,
    logic [3:0]    order_domain,
    logic [7:0]    order_epoch
  );
    sc_cmd_t cmd;

    cmd = make_cmd(sc_type, start_address, rw_length);
    cmd.order_mode   = order_mode;
    cmd.order_domain = order_domain;
    cmd.order_epoch  = order_epoch;
    return cmd;
  endfunction

  function automatic sc_cmd_t make_atomic_cmd(
    logic [23:0] start_address,
    logic [31:0] atomic_mask,
    logic [31:0] atomic_data
  );
    sc_cmd_t cmd;

    cmd = make_cmd(SC_BURST_WRITE, start_address, 1);
    cmd.atomic          = 1'b1;
    cmd.atomic_mask     = atomic_mask;
    cmd.atomic_data     = atomic_data;
    cmd.atomic_exclusive = 1'b1;
    return cmd;
  endfunction

  function automatic sc_reply_t make_empty_reply();
    sc_reply_t reply;
    reply.sc_type       = SC_BURST_READ;
    reply.fpga_id       = '0;
    reply.start_address = '0;
    reply.header_word   = '0;
    reply.echoed_length = '0;
    reply.response      = 2'b00;
    reply.header_valid  = 1'b0;
    reply.payload_words = 0;
    foreach (reply.payload[idx]) begin
      reply.payload[idx] = 32'h0;
    end
    return reply;
  endfunction
endpackage
