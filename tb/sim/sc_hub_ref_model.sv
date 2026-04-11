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

  function automatic logic [31:0] predict_csr_read_word(input logic [17:0] word_addr);
    logic [17:0] offset;

    offset = word_addr - HUB_CSR_BASE_ADDR_CONST;
    case (offset)
      18'h0000: return HUB_UID_CONST;
      18'h0001: return pack_version_word(
                  HUB_VERSION_MAJOR_CONST,
                  HUB_VERSION_MINOR_CONST,
                  HUB_VERSION_PATCH_CONST,
                  HUB_BUILD_CONST
                );
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
