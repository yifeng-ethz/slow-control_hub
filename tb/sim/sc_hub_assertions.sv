module sc_hub_assertions (
  input logic clk,
  input logic rst,
  input logic link_ready,
  input logic [31:0] link_data,
  input logic [3:0]  link_datak,
  input logic uplink_valid,
  input logic uplink_ready,
  input logic [35:0] uplink_data,
  input logic uplink_sop,
  input logic uplink_eop
`ifdef SC_HUB_BUS_AXI4
  ,
  input logic        axi_rd_done,
  input logic [3:0]  axi_rd_done_tag,
  input logic [3:0]  axi_awid,
  input logic [15:0] axi_awaddr,
  input logic [7:0]  axi_awlen,
  input logic [2:0]  axi_awsize,
  input logic [1:0]  axi_awburst,
  input logic        axi_awvalid,
  input logic        axi_awready,
  input logic [31:0] axi_wdata,
  input logic [3:0]  axi_wstrb,
  input logic        axi_wlast,
  input logic        axi_wvalid,
  input logic        axi_wready,
  input logic [3:0]  axi_bid,
  input logic [1:0]  axi_bresp,
  input logic        axi_bvalid,
  input logic        axi_bready,
  input logic [3:0]  axi_arid,
  input logic [15:0] axi_araddr,
  input logic [7:0]  axi_arlen,
  input logic [2:0]  axi_arsize,
  input logic [1:0]  axi_arburst,
  input logic        axi_arvalid,
  input logic        axi_arready,
  input logic [3:0]  axi_rid,
  input logic [31:0] axi_rdata,
  input logic [1:0]  axi_rresp,
  input logic        axi_rlast,
  input logic        axi_rvalid,
  input logic        axi_rready
`else
  ,
  input logic        avm_read,
  input logic        avm_write,
  input logic [15:0] avm_address,
  input logic [31:0] avm_writedata,
  input logic        avm_waitrequest,
  input logic [1:0]  avm_response,
  input logic [8:0]  avm_burstcount
`endif
);
  import sc_hub_sim_pkg::*;

  localparam int unsigned MAX_BURST_BYTES = 257;
  localparam int unsigned MAX_REPLY_BEATS  = MAX_BURST_BYTES + 3;

  logic        reply_in_progress;
  logic [8:0]  reply_word_index;
  int unsigned reply_protocol_violations;
  int unsigned reply_word_index_overflow;
  int unsigned reply_missing_eop_count;
  int unsigned reply_control_outside_packet;

`ifdef SC_HUB_BUS_AXI4
  logic       axi4_aw_fire;
  logic       axi4_ar_fire;
  logic       axi4_w_fire;
  logic       axi4_r_fire;
  logic       axi4_b_fire;
  logic [8:0] write_beats_remaining;
  logic       write_txn_inflight;
  logic       write_last_seen;
  logic [8:0] read_beats_remaining [0:15];
  logic       read_txn_inflight    [0:15];
  int unsigned axi_protocol_violations;

  assign axi4_aw_fire = axi_awvalid && axi_awready;
  assign axi4_ar_fire = axi_arvalid && axi_arready;
  assign axi4_w_fire  = axi_wvalid && axi_wready;
  assign axi4_r_fire  = axi_rvalid && axi_rready;
  assign axi4_b_fire  = axi_bvalid && axi_bready;

  function automatic bit any_read_txn_inflight();
    for (int unsigned idx = 0; idx < 16; idx++) begin
      if (read_txn_inflight[idx]) begin
        return 1'b1;
      end
    end
    return 1'b0;
  endfunction
`endif

  // A01-A05 and A09-A17 are protocol-level checks and can be enforced
  // directly from external bus protocol signals.
  // A06, A07, A08, A18 require lock/no-flush/atomic metadata inside RTL;
  // they are not available at this harness boundary.
  // A23-A33 ordering/liveness and A34-A37 free-list checks require
  // core-internal RTL visibility and are therefore not added here.

  property command_data_known_outside_reset;
    @(posedge clk) !rst |-> (!$isunknown(link_data) && !$isunknown(link_datak));
  endproperty

  property no_valid_while_in_reset;
    @(posedge clk) rst |=> !uplink_valid;
  endproperty

  property ready_known_after_reset;
    @(posedge clk) !rst |-> !$isunknown(link_ready);
  endproperty

  property k_char_is_control;
    @(posedge clk)
      (!rst && uplink_valid && uplink_ready && uplink_data[32]) |-> (uplink_sop || uplink_eop);
  endproperty

  property nonk_char_is_payload;
    @(posedge clk)
      (!rst && uplink_valid && uplink_ready && !uplink_data[32]) |->
      (uplink_data[35:32] == 4'h0);
  endproperty

  property reply_end_control_payload_zero;
    @(posedge clk)
      (!rst && uplink_valid && uplink_ready && uplink_eop) |->
      (uplink_data[35:32] == 4'b0001 && uplink_data[31:8] == 24'h0);
  endproperty

  property control_datak_stable;
    @(posedge clk) disable iff (rst)
      (uplink_valid && uplink_ready && uplink_data[32]) |->
      (uplink_data[35:32] === 4'b0001);
  endproperty

  property reply_starts_with_k285;
    @(posedge clk) disable iff (rst)
      (uplink_valid && uplink_ready && uplink_sop) |->
      (uplink_data[35:32] == 4'b0001 && uplink_data[7:0] == K285_CONST);
  endproperty

  property reply_ends_with_k284;
    @(posedge clk) disable iff (rst)
      (uplink_valid && uplink_ready && uplink_eop) |->
      (uplink_data[35:32] == 4'b0001 && uplink_data[7:0] == K284_CONST);
  endproperty

  property reply_resp_header_valid;
    @(posedge clk) disable iff (rst)
      (uplink_valid && uplink_ready && (reply_word_index == 9'd2)) |->
      (uplink_data[16] === 1'b1);
  endproperty

  property no_eop_without_open_reply;
    @(posedge clk) disable iff (rst)
      (uplink_valid && uplink_ready && uplink_eop) |-> reply_in_progress || uplink_sop;
  endproperty

  property no_control_outside_packet;
    @(posedge clk) disable iff (rst)
      (uplink_valid && uplink_ready && (uplink_data[32]) && !reply_in_progress && !uplink_sop) |-> 1'b0;
  endproperty

  property reply_sop_eop_paired;
    @(posedge clk) disable iff (rst)
      (uplink_valid && uplink_ready && uplink_sop && !uplink_eop) |->
      (!reply_in_progress);
  endproperty

  assert property (command_data_known_outside_reset)
    else $error("sc_hub_assertions: link_data/link_datak are X while not in reset");

  assert property (no_valid_while_in_reset)
    else $error("sc_hub_assertions: uplink_valid asserted while in reset");

  assert property (ready_known_after_reset)
    else $error("sc_hub_assertions: o_download_ready is X after reset");

  assert property (k_char_is_control)
    else $error("sc_hub_assertions: control datak asserted outside SOP/EOP beat");

  assert property (nonk_char_is_payload)
    else $error("sc_hub_assertions: payload beat carries non-zero datak");

  assert property (reply_end_control_payload_zero)
    else $error("sc_hub_assertions: reply trailer carried unexpected payload bits");

  assert property (control_datak_stable)
    else $error("sc_hub_assertions: control datak changed while control is active");

  assert property (reply_starts_with_k285)
    else $error("sc_hub_assertions: reply did not start with K285");

  assert property (reply_ends_with_k284)
    else $error("sc_hub_assertions: reply did not end with K284");

  assert property (reply_resp_header_valid)
    else $error("sc_hub_assertions: reply header bit16 was not set when expected");

  assert property (no_eop_without_open_reply)
    else $error("sc_hub_assertions: EOP observed without an open reply");

  assert property (no_control_outside_packet)
    else $error("sc_hub_assertions: control beat observed outside reply packet");

  assert property (reply_sop_eop_paired)
    else $error("sc_hub_assertions: SOP observed while previous reply had no EOP");

  always_ff @(posedge clk) begin
    if (rst) begin
      reply_in_progress         <= 1'b0;
      reply_word_index          <= 9'd0;
      reply_protocol_violations <= 0;
      reply_word_index_overflow <= 0;
      reply_missing_eop_count   <= 0;
      reply_control_outside_packet <= 0;
    end else if (uplink_valid && uplink_ready) begin
      if (uplink_sop) begin
        if (reply_in_progress && !uplink_eop) begin
          reply_protocol_violations  <= reply_protocol_violations + 1;
          reply_missing_eop_count    <= reply_missing_eop_count + 1;
        end
        reply_word_index  <= 9'd1;
        reply_in_progress <= !uplink_eop;
      end else if (reply_in_progress) begin
        if (reply_word_index > (MAX_REPLY_BEATS - 1)) begin
          reply_word_index_overflow  <= reply_word_index_overflow + 1;
          reply_protocol_violations  <= reply_protocol_violations + 1;
        end
        reply_word_index <= reply_word_index + 1'b1;
        if (uplink_eop) begin
          reply_in_progress <= 1'b0;
        end
      end else if (uplink_eop) begin
        reply_protocol_violations <= reply_protocol_violations + 1;
        reply_missing_eop_count   <= reply_missing_eop_count + 1;
      end

      if (uplink_data[32] && !reply_in_progress && !uplink_sop) begin
        reply_control_outside_packet <= reply_control_outside_packet + 1;
      end
    end
  end

`ifdef SC_HUB_BUS_AXI4
  always_ff @(posedge clk) begin
    if (rst) begin
      write_beats_remaining <= 9'd0;
      write_txn_inflight    <= 1'b0;
      write_last_seen       <= 1'b0;
      axi_protocol_violations <= 0;
      for (int unsigned idx = 0; idx < 16; idx++) begin
        read_beats_remaining[idx] <= 9'd0;
        read_txn_inflight[idx]    <= 1'b0;
      end
    end else begin
      if (axi4_aw_fire) begin
        if (write_txn_inflight || any_read_txn_inflight()) begin
          axi_protocol_violations <= axi_protocol_violations + 1;
        end
        write_beats_remaining <= {1'b0, axi_awlen} + 9'd1;
        write_txn_inflight    <= 1'b1;
        write_last_seen       <= 1'b0;
      end

      if (axi4_w_fire) begin
        if (!write_txn_inflight) begin
          axi_protocol_violations <= axi_protocol_violations + 1;
        end else begin
          if (axi_wlast != (write_beats_remaining == 9'd1)) begin
            axi_protocol_violations <= axi_protocol_violations + 1;
          end
          if (axi4_w_fire && axi_wlast) begin
            write_last_seen <= 1'b1;
          end
          if (write_beats_remaining > 0) begin
            write_beats_remaining <= write_beats_remaining - 9'd1;
          end
        end
      end

      if (axi4_r_fire) begin
        if (!read_txn_inflight[axi_rid]) begin
          axi_protocol_violations <= axi_protocol_violations + 1;
        end else begin
          if (axi_rlast != (read_beats_remaining[axi_rid] == 9'd1)) begin
            axi_protocol_violations <= axi_protocol_violations + 1;
          end
          if (read_beats_remaining[axi_rid] > 0) begin
            read_beats_remaining[axi_rid] <= read_beats_remaining[axi_rid] - 9'd1;
          end
          if (axi_rlast) begin
            read_txn_inflight[axi_rid]    <= 1'b0;
            read_beats_remaining[axi_rid] <= 9'd0;
          end
        end
      end

      if (axi_rd_done) begin
        read_txn_inflight[axi_rd_done_tag]    <= 1'b0;
        read_beats_remaining[axi_rd_done_tag] <= 9'd0;
      end

      if (axi4_b_fire) begin
        if (!write_txn_inflight || (!write_last_seen && !axi4_w_fire)) begin
          axi_protocol_violations <= axi_protocol_violations + 1;
        end
        write_txn_inflight    <= 1'b0;
        write_last_seen       <= 1'b0;
        write_beats_remaining <= 9'd0;
      end

      if (axi4_ar_fire) begin
        if (write_txn_inflight || read_txn_inflight[axi_arid]) begin
          axi_protocol_violations <= axi_protocol_violations + 1;
        end
        read_beats_remaining[axi_arid] <= {1'b0, axi_arlen} + 9'd1;
        read_txn_inflight[axi_arid]    <= 1'b1;
      end
    end
  end

  property axi4_arvalid_stable;
    @(posedge clk) disable iff (rst)
      (axi_arvalid && !axi_arready) |=> (axi_arvalid &&
        axi_arid === $past(axi_arid) &&
        axi_araddr === $past(axi_araddr) &&
        axi_arsize === $past(axi_arsize) &&
        axi_arburst === $past(axi_arburst) &&
        axi_arlen === $past(axi_arlen));
  endproperty

  property axi4_awvalid_stable;
    @(posedge clk) disable iff (rst)
      (axi_awvalid && !axi_awready) |=> (axi_awvalid &&
        axi_awid === $past(axi_awid) &&
        axi_awaddr === $past(axi_awaddr) &&
        axi_awsize === $past(axi_awsize) &&
        axi_awburst === $past(axi_awburst) &&
        axi_awlen === $past(axi_awlen));
  endproperty

  property axi4_wvalid_stable;
    @(posedge clk) disable iff (rst)
      (axi_wvalid && !axi_wready) |=> (axi_wvalid &&
        axi_wdata === $past(axi_wdata) &&
        axi_wstrb === $past(axi_wstrb) &&
        axi_wlast === $past(axi_wlast));
  endproperty

  property axi4_burst_type_incr;
    @(posedge clk) disable iff (rst)
      (axi4_aw_fire || axi4_ar_fire) |->
      ((axi4_aw_fire && (axi_awburst == 2'b01)) || (axi4_ar_fire && (axi_arburst == 2'b01)));
  endproperty

  property axi4_size_4byte;
    @(posedge clk) disable iff (rst)
      (axi4_aw_fire || axi4_ar_fire) |->
      ((axi4_aw_fire && (axi_awsize == 3'b010)) || (axi4_ar_fire && (axi_arsize == 3'b010)));
  endproperty

  property axi4_bvalid_after_wlast;
    @(posedge clk) disable iff (rst)
      (axi4_b_fire) |-> write_last_seen;
  endproperty

  property axi4_no_interleave;
    @(posedge clk) disable iff (rst)
      axi4_aw_fire |-> !any_read_txn_inflight() && !write_txn_inflight;
  endproperty

  property axi4_no_reuse_arid;
    @(posedge clk) disable iff (rst)
      axi4_ar_fire |-> !write_txn_inflight && !read_txn_inflight[axi_arid];
  endproperty

  property axi4_no_parallel_aw_ar;
    @(posedge clk) disable iff (rst)
      axi4_aw_fire |-> !axi4_ar_fire;
  endproperty

  assert property (axi4_arvalid_stable)
    else $error("sc_hub_assertions: AR channel changed while ARREADY was low");

  assert property (axi4_awvalid_stable)
    else $error("sc_hub_assertions: AW channel changed while AWREADY was low");

  assert property (axi4_wvalid_stable)
    else $error("sc_hub_assertions: W channel changed while WREADY was low");

  assert property (axi4_burst_type_incr)
    else $error("sc_hub_assertions: AXI burst type is not INCR");

  assert property (axi4_size_4byte)
    else $error("sc_hub_assertions: AXI beat size is not 4-byte");

  assert property (axi4_bvalid_after_wlast)
    else $error("sc_hub_assertions: BVALID seen before final WLAST beat");

  assert property (axi4_no_interleave)
    else $error("sc_hub_assertions: AW issued while prior transaction is in-flight");

  assert property (axi4_no_reuse_arid)
    else $error("sc_hub_assertions: ARID reused while prior transaction with same ID is in-flight");

  assert property (axi4_no_parallel_aw_ar)
    else $error("sc_hub_assertions: AW and AR issued in same cycle");

  // A18 (atomic lock ownership) is not verifiable from the top-level DUT signals.
`else
  property avmm_read_write_mutex;
    @(posedge clk) disable iff (rst) !(avm_read && avm_write);
  endproperty

  property avmm_read_stable_until_accepted;
    @(posedge clk) disable iff (rst)
      (avm_read && avm_waitrequest && $past(avm_read && avm_waitrequest)) |-> (avm_read &&
        avm_address === $past(avm_address) &&
        avm_burstcount === $past(avm_burstcount));
  endproperty

  property avmm_write_stable_until_accepted;
    @(posedge clk) disable iff (rst)
      (avm_write && avm_waitrequest && $past(avm_write && avm_waitrequest)) |-> (avm_write &&
        avm_address === $past(avm_address) &&
        avm_writedata === $past(avm_writedata) &&
        avm_burstcount === $past(avm_burstcount));
  endproperty

  property avmm_burstcount_nonzero;
    @(posedge clk) disable iff (rst)
      (avm_read || avm_write) |-> (avm_burstcount >= 9'd1);
  endproperty

  property avmm_burstcount_max;
    @(posedge clk) disable iff (rst)
      (avm_read || avm_write) |-> (avm_burstcount <= MAX_BURST_BYTES);
  endproperty

  // A06 (flush), A07/A08 (lock) are not exposed at this harness interface.

  assert property (avmm_read_write_mutex)
    else $error("sc_hub_assertions: AVMM read and write asserted together");

  assert property (avmm_read_stable_until_accepted)
    else $error("sc_hub_assertions: AVMM address/burstcount changed while read was stalled");

  assert property (avmm_write_stable_until_accepted)
    else $error("sc_hub_assertions: AVMM address/writedata/burstcount changed while write was stalled");

  assert property (avmm_burstcount_nonzero)
    else $error("sc_hub_assertions: AVMM burstcount is zero while command is active");

  assert property (avmm_burstcount_max)
    else $error("sc_hub_assertions: AVMM burstcount exceeds supported max");
`endif
endmodule
