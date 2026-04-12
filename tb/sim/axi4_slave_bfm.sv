module axi4_slave_bfm #(
  parameter int MEM_DEPTH         = 262144,
  parameter int RD_LATENCY        = 1,
  parameter int WR_LATENCY        = 1,
  parameter int RD_QUEUE_DEPTH    = 16
) (
  input  logic        clk,
  input  logic        rst,
  input  logic [3:0]  awid,
  input  logic [17:0] awaddr,
  input  logic [7:0]  awlen,
  input  logic [2:0]  awsize,
  input  logic [1:0]  awburst,
  input  logic        awlock,
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
  input  logic [17:0] araddr,
  input  logic [7:0]  arlen,
  input  logic [2:0]  arsize,
  input  logic [1:0]  arburst,
  input  logic        arlock,
  input  logic        arvalid,
  output logic        arready,
  output logic [3:0]  rid,
  output logic [31:0] rdata,
  output logic [1:0]  rresp,
  output logic        rlast,
  output logic        rvalid,
  input  logic        rready,
  input  logic        accept_ar_resp_valid,
  input  logic [1:0]  accept_ar_resp_code,
  input  logic        accept_aw_resp_valid,
  input  logic [1:0]  accept_aw_resp_code,
  input  logic        inject_rd_error,
  input  logic        inject_wr_error,
  input  logic        inject_decode_error,
  input  logic        inject_rresp_err,
  input  logic        inject_bresp_err
);
  typedef struct {
    bit         valid;
    bit         ready;
    logic [3:0] id;
    logic [17:0] addr;
    logic [1:0]  burst;
    logic [1:0]  resp;
    logic [8:0] beats_remaining;
    int unsigned delay_remaining;
    int unsigned order;
    int unsigned ready_order;
  } rd_req_t;

  logic [31:0] mem [0:MEM_DEPTH-1];
  logic [17:0] wr_addr_reg;
  logic [1:0]  wr_burst_reg;
  int unsigned wr_delay;
  bit          wr_resp_pending;
  logic [3:0]  wr_resp_id;
  logic [1:0]  wr_resp_code;
  int unsigned rd_latency_cfg;
  int unsigned wr_latency_cfg;
  int unsigned rd_latency_override [0:MEM_DEPTH-1];
  rd_req_t     rd_pending [0:RD_QUEUE_DEPTH-1];
  bit          rd_stream_active;
  logic [3:0]  rd_stream_id;
  logic [17:0] rd_stream_addr;
  logic [1:0]  rd_stream_burst;
  logic [1:0]  rd_stream_resp_code;
  logic [8:0]  rd_stream_beats_remaining;
  int unsigned rd_order_counter;
  int unsigned rd_ready_counter;

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
    int unsigned best_ready_order;
    best_idx   = -1;
    best_ready_order = '1;
    for (int idx = 0; idx < RD_QUEUE_DEPTH; idx++) begin
      if (rd_pending[idx].valid && rd_pending[idx].ready) begin
        if (best_idx == -1 || rd_pending[idx].ready_order < best_ready_order) begin
          best_idx         = idx;
          best_ready_order = rd_pending[idx].ready_order;
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
    input logic [17:0] addr,
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

  task automatic set_default_wr_latency(
    input int unsigned latency
  );
    wr_latency_cfg = latency;
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
    wr_burst_reg    = 2'b01;
    wr_delay        = 0;
    wr_resp_pending = 1'b0;
    wr_resp_id      = '0;
    wr_resp_code    = 2'b00;
    rd_latency_cfg  = RD_LATENCY;
    wr_latency_cfg  = WR_LATENCY;
    rd_stream_active = 1'b0;
    rd_stream_id     = '0;
    rd_stream_addr   = '0;
    rd_stream_burst  = 2'b01;
    rd_stream_resp_code = 2'b00;
    rd_stream_beats_remaining = '0;
    rd_order_counter = 0;
    rd_ready_counter = 0;
    foreach (mem[idx]) begin
      mem[idx] = 32'h2000_0000 + idx;
    end
    foreach (rd_pending[idx]) begin
      rd_pending[idx].valid           = 1'b0;
      rd_pending[idx].ready           = 1'b0;
      rd_pending[idx].id              = '0;
      rd_pending[idx].addr            = '0;
      rd_pending[idx].burst           = 2'b01;
      rd_pending[idx].resp            = 2'b00;
      rd_pending[idx].beats_remaining = '0;
      rd_pending[idx].delay_remaining = 0;
      rd_pending[idx].order           = 0;
      rd_pending[idx].ready_order     = 0;
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
      wr_resp_pending    <= 1'b0;
      wr_resp_id         <= '0;
      wr_resp_code       <= 2'b00;
      rd_stream_active   <= 1'b0;
      rd_stream_id       <= '0;
      rd_stream_addr     <= '0;
      rd_stream_burst    <= 2'b01;
      rd_stream_resp_code <= 2'b00;
      rd_stream_beats_remaining <= '0;
      rd_order_counter   <= 0;
      rd_ready_counter   <= 0;
      foreach (rd_pending[idx]) begin
        rd_pending[idx].valid           <= 1'b0;
        rd_pending[idx].ready           <= 1'b0;
        rd_pending[idx].id              <= '0;
        rd_pending[idx].addr            <= '0;
        rd_pending[idx].burst           <= 2'b01;
        rd_pending[idx].resp            <= 2'b00;
        rd_pending[idx].beats_remaining <= '0;
        rd_pending[idx].delay_remaining <= 0;
        rd_pending[idx].order           <= 0;
        rd_pending[idx].ready_order     <= 0;
      end
      clear_rd_latency_overrides();
    end else begin
      int free_slot;
      int ready_slot;
      int unsigned next_ready_counter;

      free_slot = find_free_rd_slot();
      next_ready_counter = rd_ready_counter;
      awready <= 1'b1;
      wready  <= 1'b1;
      arready <= (free_slot >= 0);

      if (awvalid && awready) begin
        if ((awaddr >= 18'h01000) && (awaddr < 18'h03000)) begin
          $display("DBG_BFM_AW addr=0x%05h len=%0d burst=%0b", awaddr, awlen + 1, awburst);
        end
        wr_addr_reg  <= awaddr;
        wr_burst_reg <= awburst;
        wr_resp_id   <= awid;
        if (accept_aw_resp_valid) begin
          wr_resp_code <= accept_aw_resp_code;
        end else if (inject_decode_error) begin
          wr_resp_code <= 2'b11;
        end else if (inject_wr_error || inject_bresp_err) begin
          wr_resp_code <= 2'b10;
        end else begin
          wr_resp_code <= 2'b00;
        end
      end

      if (wvalid && wready) begin
        if ((wdata[31:24] == 8'hA5) && (wdata != (32'hA500_0000 + wr_addr_reg))) begin
          $display("DBG_BFM_W_MISMATCH addr=0x%05h data=0x%08h exp=0x%08h burst=%0b last=%0b",
                   wr_addr_reg,
                   wdata,
                   32'hA500_0000 + wr_addr_reg,
                   wr_burst_reg,
                   wlast);
        end
        if ((wr_addr_reg >= 18'h01000) && (wr_addr_reg < 18'h03000) && (wdata[31:24] == 8'hA5)) begin
          $display("DBG_BFM_W addr=0x%05h data=0x%08h last=%0b", wr_addr_reg, wdata, wlast);
        end
        mem[wr_addr_reg % MEM_DEPTH] <= wdata;
        if (wr_burst_reg == 2'b01) begin
          wr_addr_reg <= wr_addr_reg + 1;
        end
        if (wlast) begin
          if (wr_delay >= (wr_latency_cfg - 1)) begin
            bvalid   <= 1'b1;
            bid      <= wr_resp_id;
            bresp    <= wr_resp_code;
            wr_resp_pending <= 1'b0;
            wr_delay <= 0;
          end else begin
            wr_resp_pending <= 1'b1;
            wr_delay <= wr_delay + 1;
          end
        end
      end

      if (bvalid && bready) begin
        bvalid <= 1'b0;
      end

      if (wr_resp_pending && !bvalid && !(wvalid && wready && wlast)) begin
        if (wr_delay >= (wr_latency_cfg - 1)) begin
          bvalid           <= 1'b1;
          bid              <= wr_resp_id;
          bresp            <= wr_resp_code;
          wr_resp_pending  <= 1'b0;
          wr_delay         <= 0;
        end else begin
          wr_delay <= wr_delay + 1;
        end
      end

      if (arvalid && arready && (free_slot >= 0)) begin
        if ((arid == 4'd0) || (arid == 4'd3)) begin
          $display("DBG_BFM_AR_ACCEPT id=%0d addr=0x%05h len=%0d delay=%0d",
                   arid,
                   araddr,
                   arlen + 1,
                   rd_latency_override[araddr % MEM_DEPTH]);
        end
        rd_pending[free_slot].valid           <= 1'b1;
        rd_pending[free_slot].ready           <= 1'b0;
        rd_pending[free_slot].id              <= arid;
        rd_pending[free_slot].addr            <= araddr;
        rd_pending[free_slot].burst           <= arburst;
        if (accept_ar_resp_valid) begin
          rd_pending[free_slot].resp <= accept_ar_resp_code;
        end else if (inject_decode_error) begin
          rd_pending[free_slot].resp <= 2'b11;
        end else if (inject_rd_error || inject_rresp_err) begin
          rd_pending[free_slot].resp <= 2'b10;
        end else begin
          rd_pending[free_slot].resp <= 2'b00;
        end
        rd_pending[free_slot].beats_remaining <= {1'b0, arlen} + 9'd1;
        rd_pending[free_slot].delay_remaining <= rd_latency_override[araddr % MEM_DEPTH];
        rd_pending[free_slot].order           <= rd_order_counter;
        rd_pending[free_slot].ready_order     <= 0;
        rd_order_counter                      <= rd_order_counter + 1;
      end

      foreach (rd_pending[idx]) begin
        if (rd_pending[idx].valid && !rd_pending[idx].ready) begin
          if (rd_pending[idx].delay_remaining == 0) begin
            rd_pending[idx].ready       <= 1'b1;
            rd_pending[idx].ready_order <= next_ready_counter;
            next_ready_counter          = next_ready_counter + 1;
          end else begin
            rd_pending[idx].delay_remaining <= rd_pending[idx].delay_remaining - 1;
          end
        end
      end
      rd_ready_counter <= next_ready_counter;

      if (!rd_stream_active) begin
        ready_slot = find_next_ready_rd_slot();
        if (ready_slot >= 0) begin
          if ((rd_pending[ready_slot].id == 4'd0) || (rd_pending[ready_slot].id == 4'd3)) begin
            $display("DBG_BFM_STREAM_START id=%0d addr=0x%05h beats=%0d ready_order=%0d",
                     rd_pending[ready_slot].id,
                     rd_pending[ready_slot].addr,
                     rd_pending[ready_slot].beats_remaining,
                     rd_pending[ready_slot].ready_order);
          end
          rd_stream_active                 <= 1'b1;
          rd_stream_id                     <= rd_pending[ready_slot].id;
          rd_stream_addr                   <= rd_pending[ready_slot].addr;
          rd_stream_burst                  <= rd_pending[ready_slot].burst;
          rd_stream_resp_code              <= rd_pending[ready_slot].resp;
          rd_stream_beats_remaining        <= rd_pending[ready_slot].beats_remaining;
          rd_pending[ready_slot].valid     <= 1'b0;
          rd_pending[ready_slot].ready     <= 1'b0;
          rd_pending[ready_slot].id        <= '0;
          rd_pending[ready_slot].addr      <= '0;
          rd_pending[ready_slot].burst     <= 2'b01;
          rd_pending[ready_slot].resp      <= 2'b00;
          rd_pending[ready_slot].beats_remaining <= '0;
          rd_pending[ready_slot].delay_remaining <= 0;
          rd_pending[ready_slot].order     <= 0;
          rd_pending[ready_slot].ready_order <= 0;
        end
      end

      if (rd_stream_active && (!rvalid || (rvalid && rready))) begin
        if ((rd_stream_id == 4'd0) || (rd_stream_id == 4'd3)) begin
          $display("DBG_BFM_R id=%0d addr=0x%05h data=0x%08h last=%0b beats=%0d",
                   rd_stream_id,
                   rd_stream_addr,
                   mem[rd_stream_addr % MEM_DEPTH],
                   (rd_stream_beats_remaining == 1),
                   rd_stream_beats_remaining);
        end
        rvalid <= 1'b1;
        rid    <= rd_stream_id;
        rdata  <= mem[rd_stream_addr % MEM_DEPTH];
        rresp  <= rd_stream_resp_code;
        rlast  <= (rd_stream_beats_remaining == 1);
        if (rd_stream_beats_remaining <= 1) begin
          rd_stream_active          <= 1'b0;
          rd_stream_beats_remaining <= '0;
        end else begin
          if (rd_stream_burst == 2'b01) begin
            rd_stream_addr <= rd_stream_addr + 1;
          end
          rd_stream_beats_remaining <= rd_stream_beats_remaining - 1;
        end
      end else if (rvalid && rready) begin
        rvalid <= 1'b0;
        rlast  <= 1'b0;
      end
    end
  end
endmodule
