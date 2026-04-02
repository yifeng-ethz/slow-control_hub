`timescale 1ns/1ps

interface sc_pkt_if(input logic clk);
  logic        rst;
  logic [31:0] data;
  logic [3:0]  datak;
  logic        ready;
endinterface

interface sc_reply_if(input logic clk);
  logic        rst;
  logic [35:0] data;
  logic        valid;
  logic        ready;
  logic        sop;
  logic        eop;
endinterface

interface sc_hub_avmm_if(input logic clk);
  logic        rst;
  logic [15:0] address;
  logic        read;
  logic [31:0] readdata;
  logic        writeresponsevalid;
  logic [1:0]  response;
  logic        write;
  logic [31:0] writedata;
  logic        waitrequest;
  logic        readdatavalid;
  logic [8:0]  burstcount;
  logic        inject_rd_error;
  logic        inject_wr_error;
  logic        inject_decode_error;
endinterface

interface sc_hub_axi4_if(input logic clk);
  logic        rst;
  logic [3:0]  awid;
  logic [15:0] awaddr;
  logic [7:0]  awlen;
  logic [2:0]  awsize;
  logic [1:0]  awburst;
  logic        awlock;
  logic        awvalid;
  logic        awready;
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wlast;
  logic        wvalid;
  logic        wready;
  logic [3:0]  bid;
  logic [1:0]  bresp;
  logic        bvalid;
  logic        bready;
  logic [3:0]  arid;
  logic [15:0] araddr;
  logic [7:0]  arlen;
  logic [2:0]  arsize;
  logic [1:0]  arburst;
  logic        arlock;
  logic        arvalid;
  logic        arready;
  logic [3:0]  rid;
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rlast;
  logic        rvalid;
  logic        rready;
  logic        inject_rd_error;
  logic        inject_wr_error;
  logic        inject_decode_error;
  logic        inject_rresp_err;
  logic        inject_bresp_err;
endinterface

package sc_hub_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import sc_hub_sim_pkg::*;
  import sc_hub_addr_map_pkg::*;
  import sc_hub_ref_model_pkg::*;

  typedef enum int unsigned {
    SC_HUB_BUS_AVALON = 0,
    SC_HUB_BUS_AXI4   = 1
  } sc_hub_bus_e;

  typedef enum logic [1:0] {
    SC_ORDER_RELAXED  = 2'b00,
    SC_ORDER_RELEASE  = 2'b01,
    SC_ORDER_ACQUIRE  = 2'b10
  } sc_order_mode_e;

  typedef enum logic [1:0] {
    SC_ATOMIC_DISABLED = 2'b00,
    SC_ATOMIC_RMW      = 2'b01,
    SC_ATOMIC_LOCK     = 2'b10,
    SC_ATOMIC_MIXED    = 2'b11
  } sc_atomic_mode_e;

  `uvm_analysis_imp_decl(_cmd)
  `uvm_analysis_imp_decl(_rsp)
  `uvm_analysis_imp_decl(_cov_cmd)
  `uvm_analysis_imp_decl(_cov_rsp)
  `uvm_analysis_imp_decl(_bus)

  class sc_reply_item extends uvm_object;
    `uvm_object_utils(sc_reply_item)

    sc_type_e       sc_type;
    logic [15:0]    fpga_id;
    logic [23:0]    start_address;
    logic [1:0]     order_mode;
    logic [3:0]     order_domain;
    logic [7:0]     order_epoch;
    logic [1:0]     order_scope;
    bit             atomic;
    logic [15:0]    echoed_length;
    logic [1:0]     response;
    bit             header_valid;
    logic [31:0]    payload_q[$];

    function new(string name = "sc_reply_item");
      super.new(name);
      payload_q.delete();
    endfunction

    function sc_reply_item clone_item(string name = "sc_reply_item_clone");
      sc_reply_item clone_h;
      clone_h = new(name);
      clone_h.sc_type       = sc_type;
      clone_h.fpga_id       = fpga_id;
      clone_h.start_address = start_address;
      clone_h.order_mode    = order_mode;
      clone_h.order_domain  = order_domain;
      clone_h.order_epoch   = order_epoch;
      clone_h.order_scope   = order_scope;
      clone_h.atomic        = atomic;
      clone_h.echoed_length = echoed_length;
      clone_h.response      = response;
      clone_h.header_valid  = header_valid;
      clone_h.payload_q     = payload_q;
      return clone_h;
    endfunction

    function void from_struct(input sc_cmd_t cmd, input sc_reply_t reply);
      sc_type       = cmd.sc_type;
      fpga_id       = cmd.fpga_id;
      start_address = cmd.start_address;
      order_mode    = cmd.order_mode;
      order_domain  = cmd.order_domain;
      order_epoch   = cmd.order_epoch;
      order_scope   = cmd.order_scope;
      atomic        = cmd.atomic;
      echoed_length = reply.echoed_length;
      response      = reply.response;
      header_valid  = reply.header_valid;
      payload_q.delete();
      for (int unsigned idx = 0; idx < reply.payload_words; idx++) begin
        payload_q.push_back(reply.payload[idx]);
      end
    endfunction

    function string convert2string();
      return $sformatf("sc_type=%0d addr=0x%06h len=%0d rsp=%0b header_valid=%0b order=%0d dom=%0d epoch=%0d atomic=%0b payload_words=%0d",
                       sc_type, start_address, echoed_length, response, header_valid,
                       order_mode, order_domain, order_epoch, atomic, payload_q.size());
    endfunction
  endclass

  `include "sc_hub_uvm_env_cfg.sv"
  `include "sc_pkt_seq_item.sv"
  `include "sc_pkt_driver_uvm.sv"
  `include "sc_pkt_monitor_uvm.sv"
  `include "sc_pkt_agent.sv"
  `include "bus_agent.sv"
  `include "sc_hub_scoreboard_uvm.sv"
  `include "sc_hub_cov_collector.sv"
  `include "sc_hub_ord_checker_uvm.sv"
  `include "sc_hub_uvm_env.sv"
  `include "sequences/sc_pkt_single_seq.sv"
  `include "sequences/sc_pkt_script_seq.sv"
  `include "sequences/sc_pkt_burst_seq.sv"
  `include "sequences/sc_pkt_error_seq.sv"
  `include "sequences/sc_pkt_mixed_seq.sv"
  `include "sequences/sc_pkt_bp_seq.sv"
  `include "sequences/sc_pkt_csr_seq.sv"
  `include "sequences/sc_pkt_addr_sweep_seq.sv"
  `include "sequences/sc_pkt_concurrent_seq.sv"
  `include "sequences/sc_pkt_atomic_seq.sv"
  `include "sequences/sc_pkt_ordering_seq.sv"
  `include "sequences/sc_pkt_ooo_seq.sv"
  `include "sequences/sc_pkt_perf_sweep_seq.sv"
  `include "sc_hub_base_test.sv"
  `include "sc_hub_case_test.sv"
  `include "sc_hub_sweep_test.sv"
endpackage
