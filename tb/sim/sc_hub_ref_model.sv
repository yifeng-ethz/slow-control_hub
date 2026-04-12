package sc_hub_ref_model_pkg;
  import sc_hub_sim_pkg::*;

  localparam int unsigned HUB_CSR_BASE_ADDR_CONST    = 16'hFE80;
  localparam int unsigned HUB_CSR_WINDOW_WORDS_CONST = 32;
  localparam logic [31:0] HUB_UID_CONST              = 32'h5343_4842;
  localparam logic [31:0] HUB_ID_CONST               = HUB_UID_CONST;
  localparam int unsigned HUB_VERSION_MAJOR_CONST    = 26;
  localparam int unsigned HUB_VERSION_MINOR_CONST    = 6;
  localparam int unsigned HUB_VERSION_PATCH_CONST    = 1;
  localparam int unsigned HUB_BUILD_CONST            = 12'h411;
  localparam logic [31:0] HUB_VERSION_DATE_CONST     = 32'd20260411;
  localparam logic [31:0] HUB_VERSION_GIT_CONST      = 32'd0;
  localparam logic [31:0] HUB_INSTANCE_ID_CONST      = 32'd0;
  localparam logic [1:0]  HUB_FEB_TYPE_ALL_CONST     = 2'b00;

  function automatic logic [31:0] pack_version_word(
    input int unsigned version_major,
    input int unsigned version_minor,
    input int unsigned version_patch,
    input int unsigned build
  );
    logic [31:0] version_word;
    version_word        = '0;
    version_word[31:24] = version_major[7:0];
    version_word[23:16] = version_minor[7:0];
    version_word[15:12] = version_patch[3:0];
    version_word[11:0]  = build[11:0];
    return version_word;
  endfunction

  function automatic bit is_internal_csr_addr(input logic [17:0] word_addr);
    return (word_addr >= HUB_CSR_BASE_ADDR_CONST) &&
           (word_addr < (HUB_CSR_BASE_ADDR_CONST + HUB_CSR_WINDOW_WORDS_CONST));
  endfunction

  function automatic logic [31:0] pack_hub_cap_word(
    input bit supports_ooo,
    input bit supports_ordering,
    input bit supports_atomic,
    input bit supports_store_forward = 1'b1
  );
    logic [31:0] hub_cap_word;
    hub_cap_word = '0;
    hub_cap_word[0] = supports_ooo;
    hub_cap_word[1] = supports_ordering;
    hub_cap_word[2] = supports_atomic;
    hub_cap_word[3] = supports_store_forward;
    return hub_cap_word;
  endfunction

  function automatic logic [31:0] predict_csr_read_word(
    input logic [17:0] word_addr,
    input bit          supports_ooo = 1'b0,
    input bit          supports_ordering = 1'b0,
    input bit          supports_atomic = 1'b0,
    input logic [1:0]  feb_type = HUB_FEB_TYPE_ALL_CONST,
    input logic [1:0]  meta_page_sel = 2'b00,
    input bit          hub_enable = 1'b1,
    input logic [31:0] scratch_word = 32'h0000_0000,
    input bit          upload_store_forward = 1'b1,
    input bit          ooo_ctrl_enable = 1'b0
  );
    logic [17:0] offset;
    logic [31:0] status_word;
    logic [31:0] fifo_cfg_word;
    logic [31:0] ooo_ctrl_word;

    offset = word_addr - HUB_CSR_BASE_ADDR_CONST;
    status_word = '0;
    status_word[4] = hub_enable;
    fifo_cfg_word = '0;
    fifo_cfg_word[0] = 1'b1;
    fifo_cfg_word[1] = upload_store_forward;
    ooo_ctrl_word = '0;
    if (supports_ooo) begin
      ooo_ctrl_word[0] = ooo_ctrl_enable;
    end

    case (offset)
      18'h0000: return HUB_UID_CONST;
      18'h0001: begin
        case (meta_page_sel)
          2'b00: return pack_version_word(
                   HUB_VERSION_MAJOR_CONST,
                   HUB_VERSION_MINOR_CONST,
                   HUB_VERSION_PATCH_CONST,
                   HUB_BUILD_CONST
                 );
          2'b01: return HUB_VERSION_DATE_CONST;
          2'b10: return HUB_VERSION_GIT_CONST;
          default: return HUB_INSTANCE_ID_CONST;
        endcase
      end
      18'h0002: return {31'd0, hub_enable};
      18'h0003: return status_word;
      18'h0006: return scratch_word;
      18'h0009: return fifo_cfg_word;
      18'h0018: return ooo_ctrl_word;
      18'h001C: return {30'd0, feb_type};
      18'h001F: return pack_hub_cap_word(supports_ooo, supports_ordering, supports_atomic);
      default:  return 32'h0000_0000;
    endcase
  endfunction

  function automatic sc_reply_t predict_read_reply(
    sc_cmd_t cmd,
    logic [31:0] mem [0:262143]
  );
    sc_reply_t reply;
    reply = make_empty_reply();
    reply.echoed_length = cmd.rw_length[15:0];
    reply.response      = 2'b00;
    reply.header_valid  = 1'b1;
    reply.payload_words = cmd.rw_length;
    for (int unsigned idx = 0; idx < cmd.rw_length && idx < 256; idx++) begin
      logic [17:0] word_addr;

      if (cmd_is_nonincrementing(cmd)) begin
        word_addr = cmd.start_address[17:0] & 18'h3FFFF;
      end else begin
        word_addr = (cmd.start_address[17:0] + idx) & 18'h3FFFF;
      end

      if (is_internal_csr_addr(word_addr)) begin
        reply.payload[idx] = predict_csr_read_word(word_addr);
      end else begin
        reply.payload[idx] = mem[word_addr];
      end
    end
    return reply;
  endfunction

  function automatic sc_reply_t predict_write_reply(sc_cmd_t cmd, logic [1:0] response);
    sc_reply_t reply;
    reply = make_empty_reply();
    reply.echoed_length = cmd.rw_length[15:0];
    reply.response      = response;
    reply.header_valid  = 1'b1;
    return reply;
  endfunction
endpackage
