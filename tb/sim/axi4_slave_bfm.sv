module axi4_slave_bfm #(
  parameter int MEM_DEPTH  = 65536,
  parameter int RD_LATENCY = 1,
  parameter int WR_LATENCY = 1
) (
  input  logic        clk,
  input  logic        rst,
  input  logic [3:0]  awid,
  input  logic [15:0] awaddr,
  input  logic [7:0]  awlen,
  input  logic [2:0]  awsize,
  input  logic [1:0]  awburst,
  input  logic        awvalid,
  output logic        awready,
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  input  logic        wlast,
  input  logic        wvalid,
  output logic        wready,
  output logic [3:0]  bid,
  output logic [1:0]  bresp,
  output logic        bvalid,
  input  logic        bready,
  input  logic [3:0]  arid,
  input  logic [15:0] araddr,
  input  logic [7:0]  arlen,
  input  logic [2:0]  arsize,
  input  logic [1:0]  arburst,
  input  logic        arvalid,
  output logic        arready,
  output logic [3:0]  rid,
  output logic [31:0] rdata,
  output logic [1:0]  rresp,
  output logic        rlast,
  output logic        rvalid,
  input  logic        rready,
  input  logic        inject_rresp_err,
  input  logic        inject_bresp_err
);
  logic [31:0] mem [0:MEM_DEPTH-1];
  logic [15:0] rd_addr_reg;
  logic [8:0]  rd_beats_remaining;
  logic [15:0] wr_addr_reg;
  int unsigned rd_delay;
  int unsigned wr_delay;
  int unsigned rd_latency_cfg;
  int unsigned wr_latency_cfg;

  initial begin
    awready            = 1'b1;
    wready             = 1'b1;
    arready            = 1'b1;
    bid                = '0;
    bresp              = 2'b00;
    bvalid             = 1'b0;
    rid                = '0;
    rdata              = '0;
    rresp              = 2'b00;
    rlast              = 1'b0;
    rvalid             = 1'b0;
    rd_addr_reg        = '0;
    rd_beats_remaining = '0;
    wr_addr_reg        = '0;
    rd_delay           = 0;
    wr_delay           = 0;
    rd_latency_cfg     = RD_LATENCY;
    wr_latency_cfg     = WR_LATENCY;
    foreach (mem[idx]) begin
      mem[idx] = 32'h2000_0000 + idx;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      awready            <= 1'b1;
      wready             <= 1'b1;
      arready            <= 1'b1;
      bvalid             <= 1'b0;
      rvalid             <= 1'b0;
      rlast              <= 1'b0;
      rd_beats_remaining <= '0;
      rd_delay           <= 0;
      wr_delay           <= 0;
    end else begin
      awready <= 1'b1;
      wready  <= 1'b1;
      arready <= 1'b1;

      if (awvalid && awready) begin
        wr_addr_reg <= awaddr;
        bid         <= awid;
      end

      if (wvalid && wready) begin
        mem[wr_addr_reg] <= wdata;
        wr_addr_reg      <= wr_addr_reg + 1;
        if (wlast) begin
          if (wr_delay >= (wr_latency_cfg - 1)) begin
            bvalid <= 1'b1;
            bresp  <= inject_bresp_err ? 2'b10 : 2'b00;
            wr_delay <= 0;
          end else begin
            wr_delay <= wr_delay + 1;
          end
        end
      end

      if (bvalid && bready) begin
        bvalid <= 1'b0;
      end

      if (arvalid && arready) begin
        rd_addr_reg        <= araddr;
        rd_beats_remaining <= {1'b0, arlen} + 9'd1;
        rid                <= arid;
      end

      if (rd_beats_remaining != 0 && (!rvalid || (rvalid && rready))) begin
        if (rd_delay >= (rd_latency_cfg - 1)) begin
          rvalid             <= 1'b1;
          rdata              <= mem[rd_addr_reg];
          rresp              <= inject_rresp_err ? 2'b10 : 2'b00;
          rlast              <= (rd_beats_remaining == 1);
          rd_addr_reg        <= rd_addr_reg + 1;
          rd_beats_remaining <= rd_beats_remaining - 1;
          rd_delay           <= 0;
        end else begin
          rd_delay <= rd_delay + 1;
        end
      end else if (rvalid && rready) begin
        rvalid <= 1'b0;
        rlast  <= 1'b0;
      end
    end
  end
endmodule
