module axi4_slave_bfm #(
  parameter int MEM_DEPTH         = 65536,
  parameter int RD_LATENCY        = 1,
  parameter int WR_LATENCY        = 1,
  parameter int RD_QUEUE_DEPTH    = 16
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
  input  logic        inject_rd_error,
  input  logic        inject_wr_error,
  input  logic        inject_decode_error,
  input  logic        inject_rresp_err,
  input  logic        inject_bresp_err
);
  typedef struct {
    bit         valid;
    logic [3:0] id;
    logic [15:0] addr;
    logic [8:0] beats_remaining;
    int unsigned delay_remaining;
    int unsigned order;
  } rd_req_t;

  logic [31:0] mem [0:MEM_DEPTH-1];
  logic [15:0] wr_addr_reg;
  int unsigned wr_delay;
  int unsigned rd_latency_cfg;
  int unsigned wr_latency_cfg;
  int unsigned rd_latency_override [0:MEM_DEPTH-1];
  rd_req_t     rd_pending [0:RD_QUEUE_DEPTH-1];
  bit          rd_stream_active;
  logic [3:0]  rd_stream_id;
  logic [15:0] rd_stream_addr;
  logic [8:0]  rd_stream_beats_remaining;
  int unsigned rd_order_counter;

  function automatic int find_free_rd_slot();
    for (int idx = 0; idx < RD_QUEUE_DEPTH; idx++) begin
      if (!rd_pending[idx].valid) begin
        return idx;
      end
    end
    return -1;
  endfunction

  function automatic int find_next_ready_rd_slot();
    int best_idx;
    int unsigned best_order;
    best_idx   = -1;
    best_order = '1;
    for (int idx = 0; idx < RD_QUEUE_DEPTH; idx++) begin
      if (rd_pending[idx].valid && rd_pending[idx].delay_remaining == 0) begin
        if (best_idx == -1 || rd_pending[idx].order < best_order) begin
          best_idx   = idx;
          best_order = rd_pending[idx].order;
        end
      end
    end
    return best_idx;
  endfunction

  task automatic clear_rd_latency_overrides();
    for (int idx = 0; idx < MEM_DEPTH; idx++) begin
      rd_latency_override[idx] = rd_latency_cfg;
    end
  endtask

  task automatic set_rd_latency_for_addr(
    input logic [15:0] addr,
    input int unsigned latency
  );
    rd_latency_override[addr % MEM_DEPTH] = latency;
  endtask

  task automatic set_default_rd_latency(
    input int unsigned latency
  );
    rd_latency_cfg = latency;
    clear_rd_latency_overrides();
  endtask

  initial begin
    awready         = 1'b1;
    wready          = 1'b1;
    arready         = 1'b1;
    bid             = '0;
    bresp           = 2'b00;
    bvalid          = 1'b0;
    rid             = '0;
    rdata           = '0;
    rresp           = 2'b00;
    rlast           = 1'b0;
    rvalid          = 1'b0;
    wr_addr_reg     = '0;
    wr_delay        = 0;
    rd_latency_cfg  = RD_LATENCY;
    wr_latency_cfg  = WR_LATENCY;
    rd_stream_active = 1'b0;
    rd_stream_id     = '0;
    rd_stream_addr   = '0;
    rd_stream_beats_remaining = '0;
    rd_order_counter = 0;
    foreach (mem[idx]) begin
      mem[idx] = 32'h2000_0000 + idx;
    end
    foreach (rd_pending[idx]) begin
      rd_pending[idx].valid           = 1'b0;
      rd_pending[idx].id              = '0;
      rd_pending[idx].addr            = '0;
      rd_pending[idx].beats_remaining = '0;
      rd_pending[idx].delay_remaining = 0;
      rd_pending[idx].order           = 0;
    end
    clear_rd_latency_overrides();
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      awready            <= 1'b1;
      wready             <= 1'b1;
      arready            <= 1'b1;
      bvalid             <= 1'b0;
      rvalid             <= 1'b0;
      rlast              <= 1'b0;
      wr_delay           <= 0;
      rd_stream_active   <= 1'b0;
      rd_stream_id       <= '0;
      rd_stream_addr     <= '0;
      rd_stream_beats_remaining <= '0;
      rd_order_counter   <= 0;
      foreach (rd_pending[idx]) begin
        rd_pending[idx].valid           <= 1'b0;
        rd_pending[idx].id              <= '0;
        rd_pending[idx].addr            <= '0;
        rd_pending[idx].beats_remaining <= '0;
        rd_pending[idx].delay_remaining <= 0;
        rd_pending[idx].order           <= 0;
      end
      clear_rd_latency_overrides();
    end else begin
      int free_slot;
      int ready_slot;

      free_slot = find_free_rd_slot();
      awready <= 1'b1;
      wready  <= 1'b1;
      arready <= (free_slot >= 0);

      if (awvalid && awready) begin
        wr_addr_reg <= awaddr;
        bid         <= awid;
      end

      if (wvalid && wready) begin
        mem[wr_addr_reg % MEM_DEPTH] <= wdata;
        wr_addr_reg                  <= wr_addr_reg + 1;
        if (wlast) begin
          if (wr_delay >= (wr_latency_cfg - 1)) begin
            bvalid   <= 1'b1;
            if (inject_decode_error) begin
              bresp <= 2'b11;
            end else if (inject_wr_error || inject_bresp_err) begin
              bresp <= 2'b10;
            end else begin
              bresp <= 2'b00;
            end
            wr_delay <= 0;
          end else begin
            wr_delay <= wr_delay + 1;
          end
        end
      end

      if (bvalid && bready) begin
        bvalid <= 1'b0;
      end

      if (arvalid && arready && (free_slot >= 0)) begin
        rd_pending[free_slot].valid           <= 1'b1;
        rd_pending[free_slot].id              <= arid;
        rd_pending[free_slot].addr            <= araddr;
        rd_pending[free_slot].beats_remaining <= {1'b0, arlen} + 9'd1;
        rd_pending[free_slot].delay_remaining <= rd_latency_override[araddr % MEM_DEPTH];
        rd_pending[free_slot].order           <= rd_order_counter;
        rd_order_counter                      <= rd_order_counter + 1;
      end

      foreach (rd_pending[idx]) begin
        if (rd_pending[idx].valid && rd_pending[idx].delay_remaining > 0) begin
          rd_pending[idx].delay_remaining <= rd_pending[idx].delay_remaining - 1;
        end
      end

      if (!rd_stream_active) begin
        ready_slot = find_next_ready_rd_slot();
        if (ready_slot >= 0) begin
          rd_stream_active                 <= 1'b1;
          rd_stream_id                     <= rd_pending[ready_slot].id;
          rd_stream_addr                   <= rd_pending[ready_slot].addr;
          rd_stream_beats_remaining        <= rd_pending[ready_slot].beats_remaining;
          rd_pending[ready_slot].valid     <= 1'b0;
          rd_pending[ready_slot].id        <= '0;
          rd_pending[ready_slot].addr      <= '0;
          rd_pending[ready_slot].beats_remaining <= '0;
          rd_pending[ready_slot].delay_remaining <= 0;
          rd_pending[ready_slot].order     <= 0;
        end
      end

      if (rd_stream_active && (!rvalid || (rvalid && rready))) begin
        rvalid <= 1'b1;
        rid    <= rd_stream_id;
        rdata  <= mem[rd_stream_addr % MEM_DEPTH];
        if (inject_decode_error) begin
          rresp <= 2'b11;
        end else if (inject_rd_error || inject_rresp_err) begin
          rresp <= 2'b10;
        end else begin
          rresp <= 2'b00;
        end
        rlast  <= (rd_stream_beats_remaining == 1);
        if (rd_stream_beats_remaining <= 1) begin
          rd_stream_active          <= 1'b0;
          rd_stream_beats_remaining <= '0;
        end else begin
          rd_stream_addr            <= rd_stream_addr + 1;
          rd_stream_beats_remaining <= rd_stream_beats_remaining - 1;
        end
      end else if (rvalid && rready) begin
        rvalid <= 1'b0;
        rlast  <= 1'b0;
      end
    end
  end
endmodule
