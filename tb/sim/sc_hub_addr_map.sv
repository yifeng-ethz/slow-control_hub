package sc_hub_addr_map_pkg;
  timeunit 1ns;
  timeprecision 1ps;

  localparam logic [23:0] SCRATCH_PAD_BASE_CONST     = 24'h000000;
  localparam int unsigned SCRATCH_PAD_WORDS_CONST = 1024;
  localparam logic [23:0] CONTROL_CSR_BASE_CONST     = 24'h00FC00;
  localparam int unsigned CONTROL_CSR_WORDS_CONST  = 32;
  localparam logic [23:0] FRAME_RCV_BASE_CONST       = 24'h008000;
  localparam int unsigned FRAME_RCV_WORDS_CONST    = 2048;
  localparam logic [23:0] MTS_PROC_BASE_CONST        = 24'h009000;
  localparam int unsigned MTS_PROC_WORDS_CONST     = 512;
  localparam logic [23:0] RING_BUF_CAM_BASE_CONST    = 24'h00A000;
  localparam int unsigned RING_BUF_CAM_WORDS_CONST  = 2048;
  localparam logic [23:0] FEB_FRAME_ASM_BASE_CONST   = 24'h00B000;
  localparam int unsigned FEB_FRAME_ASM_WORDS_CONST = 512;
  localparam logic [23:0] HISTOGRAM_BASE_CONST       = 24'h00C000;
  localparam int unsigned HISTOGRAM_WORDS_CONST     = 512;
  localparam logic [23:0] INTERNAL_CSR_BASE_CONST    = 24'h00FE80;
  localparam int unsigned INTERNAL_CSR_WORDS_CONST  = 32;

  localparam logic [23:0] SCRATCH_PAD_LIMIT_CONST     = SCRATCH_PAD_BASE_CONST + SCRATCH_PAD_WORDS_CONST - 1;
  localparam logic [23:0] CONTROL_CSR_LIMIT_CONST     = CONTROL_CSR_BASE_CONST + CONTROL_CSR_WORDS_CONST - 1;
  localparam logic [23:0] FRAME_RCV_LIMIT_CONST       = FRAME_RCV_BASE_CONST + FRAME_RCV_WORDS_CONST - 1;
  localparam logic [23:0] MTS_PROC_LIMIT_CONST        = MTS_PROC_BASE_CONST + MTS_PROC_WORDS_CONST - 1;
  localparam logic [23:0] RING_BUF_CAM_LIMIT_CONST    = RING_BUF_CAM_BASE_CONST + RING_BUF_CAM_WORDS_CONST - 1;
  localparam logic [23:0] FEB_FRAME_ASM_LIMIT_CONST   = FEB_FRAME_ASM_BASE_CONST + FEB_FRAME_ASM_WORDS_CONST - 1;
  localparam logic [23:0] HISTOGRAM_LIMIT_CONST       = HISTOGRAM_BASE_CONST + HISTOGRAM_WORDS_CONST - 1;
  localparam logic [23:0] INTERNAL_CSR_LIMIT_CONST    = INTERNAL_CSR_BASE_CONST + INTERNAL_CSR_WORDS_CONST - 1;

  typedef enum logic [3:0] {
    REGION_UNKNOWN      = 4'h0,
    REGION_SCRATCH_PAD  = 4'h1,
    REGION_FRAME_RCV    = 4'h2,
    REGION_MTS_PROC     = 4'h3,
    REGION_RING_BUF_CAM = 4'h4,
    REGION_FEB_FRAME_ASM= 4'h5,
    REGION_HISTOGRAM    = 4'h6,
    REGION_CONTROL_CSR  = 4'h7,
    REGION_INTERNAL_CSR = 4'h8
  } sc_addr_region_e;

  function automatic sc_addr_region_e classify_addr(input logic [23:0] word_addr);
    if (word_addr >= SCRATCH_PAD_BASE_CONST && word_addr <= SCRATCH_PAD_LIMIT_CONST) begin
      return REGION_SCRATCH_PAD;
    end else if (word_addr >= FRAME_RCV_BASE_CONST && word_addr <= FRAME_RCV_LIMIT_CONST) begin
      return REGION_FRAME_RCV;
    end else if (word_addr >= MTS_PROC_BASE_CONST && word_addr <= MTS_PROC_LIMIT_CONST) begin
      return REGION_MTS_PROC;
    end else if (word_addr >= RING_BUF_CAM_BASE_CONST && word_addr <= RING_BUF_CAM_LIMIT_CONST) begin
      return REGION_RING_BUF_CAM;
    end else if (word_addr >= FEB_FRAME_ASM_BASE_CONST && word_addr <= FEB_FRAME_ASM_LIMIT_CONST) begin
      return REGION_FEB_FRAME_ASM;
    end else if (word_addr >= HISTOGRAM_BASE_CONST && word_addr <= HISTOGRAM_LIMIT_CONST) begin
      return REGION_HISTOGRAM;
    end else if (word_addr >= CONTROL_CSR_BASE_CONST && word_addr <= CONTROL_CSR_LIMIT_CONST) begin
      return REGION_CONTROL_CSR;
    end else if (word_addr >= INTERNAL_CSR_BASE_CONST && word_addr <= INTERNAL_CSR_LIMIT_CONST) begin
      return REGION_INTERNAL_CSR;
    end
    return REGION_UNKNOWN;
  endfunction

  function automatic bit is_known_region(input logic [23:0] word_addr);
    return classify_addr(word_addr) != REGION_UNKNOWN;
  endfunction

  function automatic bit is_internal_csr_addr(input logic [23:0] word_addr);
    sc_addr_region_e region;
    region = classify_addr(word_addr);
    return (region == REGION_CONTROL_CSR) || (region == REGION_INTERNAL_CSR);
  endfunction

  function automatic bit is_unmapped_addr(input logic [23:0] word_addr);
    return !is_known_region(word_addr);
  endfunction
endpackage
