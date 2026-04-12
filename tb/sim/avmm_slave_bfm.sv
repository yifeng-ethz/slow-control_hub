module avmm_slave_bfm #(
  parameter int MEM_DEPTH  = 262144,
  parameter int RD_LATENCY = 1,
  parameter int WR_LATENCY = 1
) (
  input  logic        clk,
  input  logic        rst,
  input  logic [17:0] avm_address,
  input  logic        avm_read,
  output logic [31:0] avm_readdata,
  output logic        avm_writeresponsevalid,
  output logic [1:0]  avm_response,
  input  logic        avm_write,
  input  logic [31:0] avm_writedata,
  output logic        avm_waitrequest,
  output logic        avm_readdatavalid,
  input  logic [8:0]  avm_burstcount,
  input  logic        accept_rd_resp_valid,
  input  logic [1:0]  accept_rd_resp_code,
  input  logic        accept_wr_resp_valid,
  input  logic [1:0]  accept_wr_resp_code,
  input  logic        inject_rd_error,
  input  logic        inject_wr_error,
  input  logic        inject_decode_error
);
  logic [31:0] mem [0:MEM_DEPTH-1];
  int unsigned rd_delay;
  int unsigned wr_delay;
  logic        read_active;
  logic [17:0] rd_addr_reg;
  int unsigned rd_beats_remaining;
  logic [1:0]  rd_resp_code_reg;
  logic        write_active;
  logic        write_rsp_pending;
  logic [17:0] wr_addr_reg;
  int unsigned wr_beats_remaining;
  logic [1:0]  wr_resp_code_reg;
  int unsigned rd_latency_cfg;
  int unsigned rd_latency_override[0:MEM_DEPTH-1];
  int unsigned wr_latency_cfg;
  bit          trace_bfm;

  task automatic clear_rd_latency_overrides();
    for (int idx = 0; idx < MEM_DEPTH; idx++) begin
      rd_latency_override[idx] = rd_latency_cfg;
    end
  endtask

  task automatic set_rd_latency_for_addr(
    input logic [17:0] addr,
    input int unsigned latency
  );
    rd_latency_override[addr] = latency;
  endtask

  task automatic set_default_rd_latency(
    input int unsigned latency
  );
    rd_latency_cfg = latency;
    clear_rd_latency_overrides();
  endtask

  task automatic set_default_wr_latency(
    input int unsigned latency
  );
    wr_latency_cfg = latency;
  endtask

  function automatic int unsigned rd_delay_for_addr(
    input logic [15:0] addr
  );
    if (rd_latency_override[addr] == 0) begin
      return 0;
    end
    return rd_latency_override[addr] - 1;
  endfunction

  initial begin
    avm_readdata           = '0;
    avm_writeresponsevalid = 1'b0;
    avm_response           = 2'b00;
    avm_waitrequest        = 1'b0;
    avm_readdatavalid      = 1'b0;
    rd_delay               = 0;
    wr_delay               = 0;
    read_active            = 1'b0;
    rd_addr_reg            = '0;
    rd_beats_remaining     = 0;
    rd_resp_code_reg       = 2'b00;
    write_active           = 1'b0;
    write_rsp_pending      = 1'b0;
    wr_addr_reg            = '0;
    wr_beats_remaining     = 0;
    wr_resp_code_reg       = 2'b00;
    rd_latency_cfg         = RD_LATENCY;
    wr_latency_cfg         = WR_LATENCY;
    trace_bfm              = $test$plusargs("SC_HUB_TRACE_AVMM_BFM");
    clear_rd_latency_overrides();
    foreach (mem[idx]) begin
      mem[idx] = 32'h1000_0000 + idx;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      avm_waitrequest        <= 1'b0;
      avm_writeresponsevalid <= 1'b0;
      avm_response           <= 2'b00;
      avm_readdatavalid      <= 1'b0;
      rd_delay               <= 0;
      wr_delay               <= 0;
      read_active            <= 1'b0;
      rd_addr_reg            <= '0;
      rd_beats_remaining     <= 0;
      rd_resp_code_reg       <= 2'b00;
      write_active           <= 1'b0;
      write_rsp_pending      <= 1'b0;
      wr_addr_reg            <= '0;
      wr_beats_remaining     <= 0;
      wr_resp_code_reg       <= 2'b00;
      rd_latency_cfg         <= RD_LATENCY;
      wr_latency_cfg         <= WR_LATENCY;
      for (int idx = 0; idx < MEM_DEPTH; idx++) begin
        rd_latency_override[idx] <= RD_LATENCY;
      end
    end else begin
      avm_waitrequest        <= 1'b0;
      avm_writeresponsevalid <= 1'b0;
      avm_readdatavalid      <= 1'b0;

      if (!read_active && avm_read && !avm_waitrequest) begin
        if (trace_bfm) begin
          $display("TRACE_AVMM_BFM kind=RD_ACCEPT addr=0x%05h burst=%0d",
                   avm_address,
                   (avm_burstcount == 0) ? 1 : avm_burstcount);
        end
        read_active        <= 1'b1;
        rd_addr_reg        <= avm_address;
        rd_beats_remaining <= (avm_burstcount == 0) ? 1 : avm_burstcount;
        rd_delay           <= rd_delay_for_addr(avm_address);
        if (accept_rd_resp_valid) begin
          rd_resp_code_reg <= accept_rd_resp_code;
        end else if (inject_decode_error) begin
          rd_resp_code_reg <= 2'b11;
        end else if (inject_rd_error) begin
          rd_resp_code_reg <= 2'b10;
        end else begin
          rd_resp_code_reg <= 2'b00;
        end
      end else if (read_active) begin
        if (rd_delay == 0) begin
          logic [17:0] curr_rd_addr;
          logic [31:0] curr_rd_data;

          curr_rd_addr = rd_addr_reg;
          curr_rd_data = mem[rd_addr_reg];
          if (trace_bfm) begin
            $display("TRACE_AVMM_BFM kind=RD_DATA addr=0x%05h data=0x%08h beats_left=%0d",
                     curr_rd_addr,
                     curr_rd_data,
                     rd_beats_remaining);
          end
          avm_readdatavalid <= 1'b1;
          avm_readdata      <= curr_rd_data;
          avm_response      <= rd_resp_code_reg;
          if (rd_beats_remaining <= 1) begin
            read_active        <= 1'b0;
            rd_beats_remaining <= 0;
          end else begin
            rd_addr_reg        <= rd_addr_reg + 16'd1;
            rd_beats_remaining <= rd_beats_remaining - 1;
          end
          rd_delay <= 0;
        end else begin
          rd_delay <= rd_delay - 1;
        end
      end

      if (avm_write && !avm_waitrequest) begin
        logic [17:0] curr_wr_addr;

        if (!write_active) begin
          curr_wr_addr = avm_address;
          if (trace_bfm) begin
            $display("TRACE_AVMM_BFM kind=WR_DATA addr=0x%05h data=0x%08h burst=%0d",
                     curr_wr_addr,
                     avm_writedata,
                     (avm_burstcount == 0) ? 1 : avm_burstcount);
          end
          mem[avm_address] <= avm_writedata;
          if (accept_wr_resp_valid) begin
            wr_resp_code_reg <= accept_wr_resp_code;
          end else if (inject_decode_error) begin
            wr_resp_code_reg <= 2'b11;
          end else if (inject_wr_error) begin
            wr_resp_code_reg <= 2'b10;
          end else begin
            wr_resp_code_reg <= 2'b00;
          end
          if (avm_burstcount <= 1) begin
            write_rsp_pending  <= 1'b1;
            wr_delay           <= 0;
            wr_beats_remaining <= 0;
          end else begin
            write_active       <= 1'b1;
            wr_addr_reg        <= avm_address + 16'd1;
            wr_beats_remaining <= avm_burstcount - 1;
          end
        end else begin
          curr_wr_addr = wr_addr_reg;
          if (trace_bfm) begin
            $display("TRACE_AVMM_BFM kind=WR_DATA addr=0x%05h data=0x%08h burst_rem=%0d",
                     curr_wr_addr,
                     avm_writedata,
                     wr_beats_remaining);
          end
          mem[wr_addr_reg] <= avm_writedata;
          if (wr_beats_remaining <= 1) begin
            write_active       <= 1'b0;
            write_rsp_pending  <= 1'b1;
            wr_beats_remaining <= 0;
            wr_delay           <= 0;
          end else begin
            wr_addr_reg        <= wr_addr_reg + 16'd1;
            wr_beats_remaining <= wr_beats_remaining - 1;
          end
        end
      end

      if (write_rsp_pending) begin
        if (wr_delay >= (wr_latency_cfg - 1)) begin
          avm_writeresponsevalid <= 1'b1;
          avm_response           <= wr_resp_code_reg;
          write_rsp_pending <= 1'b0;
          wr_delay          <= 0;
        end else begin
          wr_delay <= wr_delay + 1;
        end
      end
    end
  end
endmodule
