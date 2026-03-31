module avmm_slave_bfm #(
  parameter int MEM_DEPTH  = 65536,
  parameter int RD_LATENCY = 1,
  parameter int WR_LATENCY = 1
) (
  input  logic        clk,
  input  logic        rst,
  input  logic [15:0] avm_address,
  input  logic        avm_read,
  output logic [31:0] avm_readdata,
  output logic        avm_writeresponsevalid,
  output logic [1:0]  avm_response,
  input  logic        avm_write,
  input  logic [31:0] avm_writedata,
  output logic        avm_waitrequest,
  output logic        avm_readdatavalid,
  input  logic [8:0]  avm_burstcount,
  input  logic        inject_rd_error,
  input  logic        inject_wr_error,
  input  logic        inject_decode_error
);
  logic [31:0] mem [0:MEM_DEPTH-1];
  int unsigned rd_delay;
  int unsigned wr_delay;
  logic        read_active;
  logic [15:0] rd_addr_reg;
  int unsigned rd_beats_remaining;
  logic        write_active;
  logic        write_rsp_pending;
  logic [15:0] wr_addr_reg;
  int unsigned wr_beats_remaining;
  int unsigned rd_latency_cfg;
  int unsigned wr_latency_cfg;

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
    write_active           = 1'b0;
    write_rsp_pending      = 1'b0;
    wr_addr_reg            = '0;
    wr_beats_remaining     = 0;
    rd_latency_cfg         = RD_LATENCY;
    wr_latency_cfg         = WR_LATENCY;
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
      write_active           <= 1'b0;
      write_rsp_pending      <= 1'b0;
      wr_addr_reg            <= '0;
      wr_beats_remaining     <= 0;
    end else begin
      avm_waitrequest        <= 1'b0;
      avm_writeresponsevalid <= 1'b0;
      avm_readdatavalid      <= 1'b0;

      if (!read_active && avm_read && !avm_waitrequest) begin
        read_active        <= 1'b1;
        rd_addr_reg        <= avm_address;
        rd_beats_remaining <= (avm_burstcount == 0) ? 1 : avm_burstcount;
        rd_delay           <= 0;
      end else if (read_active) begin
        if (rd_delay >= (rd_latency_cfg - 1)) begin
          avm_readdatavalid <= 1'b1;
          avm_readdata      <= mem[rd_addr_reg];
          if (inject_decode_error) begin
            avm_response <= 2'b11;
          end else if (inject_rd_error) begin
            avm_response <= 2'b10;
          end else begin
            avm_response <= 2'b00;
          end
          if (rd_beats_remaining <= 1) begin
            read_active        <= 1'b0;
            rd_beats_remaining <= 0;
          end else begin
            rd_addr_reg        <= rd_addr_reg + 16'd1;
            rd_beats_remaining <= rd_beats_remaining - 1;
          end
          rd_delay <= 0;
        end else begin
          rd_delay <= rd_delay + 1;
        end
      end

      if (avm_write && !avm_waitrequest) begin
        if (!write_active) begin
          mem[avm_address] <= avm_writedata;
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
          if (inject_decode_error) begin
            avm_response <= 2'b11;
          end else if (inject_wr_error) begin
            avm_response <= 2'b10;
          end else begin
            avm_response <= 2'b00;
          end
          write_rsp_pending <= 1'b0;
          wr_delay          <= 0;
        end else begin
          wr_delay <= wr_delay + 1;
        end
      end
    end
  end
endmodule
