package sc_hub_ref_model_pkg;
  import sc_hub_sim_pkg::*;

  localparam int unsigned HUB_CSR_BASE_ADDR_CONST  = 16'hFE80;
  localparam int unsigned HUB_CSR_WINDOW_WORDS_CONST = 32;
  localparam logic [31:0] HUB_ID_CONST             = 32'h5348_0000;
  localparam int unsigned HUB_VERSION_YY_CONST     = 26;
  localparam int unsigned HUB_VERSION_MAJOR_CONST  = 2;
  localparam int unsigned HUB_VERSION_PRE_CONST    = 0;
  localparam int unsigned HUB_VERSION_MONTH_CONST  = 3;
  localparam int unsigned HUB_VERSION_DAY_CONST    = 31;

  function automatic logic [31:0] pack_version_word(
    input int unsigned version_yy,
    input int unsigned version_major,
    input int unsigned version_pre,
    input int unsigned version_month,
    input int unsigned version_day
  );
    logic [31:0] version_word;
    version_word          = '0;
    version_word[31:24]   = version_yy[7:0];
    version_word[23:18]   = version_major[5:0];
    version_word[17:16]   = version_pre[1:0];
    version_word[15:8]    = version_month[7:0];
    version_word[7:0]     = version_day[7:0];
    return version_word;
  endfunction

  function automatic bit is_internal_csr_addr(input logic [15:0] word_addr);
    return (word_addr >= HUB_CSR_BASE_ADDR_CONST) &&
           (word_addr < (HUB_CSR_BASE_ADDR_CONST + HUB_CSR_WINDOW_WORDS_CONST));
  endfunction

  function automatic logic [31:0] predict_csr_read_word(input logic [15:0] word_addr);
    logic [15:0] offset;

    offset = word_addr - HUB_CSR_BASE_ADDR_CONST;
    case (offset)
      16'h0000: return HUB_ID_CONST;
      16'h0001: return pack_version_word(
                  HUB_VERSION_YY_CONST,
                  HUB_VERSION_MAJOR_CONST,
                  HUB_VERSION_PRE_CONST,
                  HUB_VERSION_MONTH_CONST,
                  HUB_VERSION_DAY_CONST
                );
      default:  return 32'h0000_0000;
    endcase
  endfunction

  function automatic sc_reply_t predict_read_reply(
    sc_cmd_t cmd,
    logic [31:0] mem [0:65535]
  );
    sc_reply_t reply;
    reply = make_empty_reply();
    reply.echoed_length = cmd.rw_length[15:0];
    reply.response      = 2'b00;
    reply.header_valid  = 1'b1;
    reply.payload_words = cmd.rw_length;
    for (int unsigned idx = 0; idx < cmd.rw_length && idx < 256; idx++) begin
      if (is_internal_csr_addr((cmd.start_address[15:0] + idx) & 16'hFFFF)) begin
        reply.payload[idx] = predict_csr_read_word((cmd.start_address[15:0] + idx) & 16'hFFFF);
      end else begin
        reply.payload[idx] = mem[(cmd.start_address[15:0] + idx) & 16'hFFFF];
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
