class sc_hub_base_test extends uvm_test;
  `uvm_component_utils(sc_hub_base_test)

  localparam int unsigned BASE_DRAIN_TIMEOUT_CYCLES = 50000;
  localparam logic [23:0] HUB_CSR_OOO_CTRL_ADDR     = 24'h00FE98;
  localparam logic [23:0] HUB_CSR_FEB_TYPE_ADDR     = 24'h00FE9C;

  sc_hub_uvm_env     env_h;
  sc_hub_uvm_env_cfg cfg;

  function new(string name = "sc_hub_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction


  function automatic string get_string_plusarg(string key, string default_value = "");
    string value;
    if ($value$plusargs({key, "=%s"}, value)) begin
      return value;
    end
    return default_value;
  endfunction

  function automatic feb_type_e parse_feb_type(string value);
    string lower;
    lower = value.tolower();
    case (lower)
      "mupix", "1": return FEB_TYPE_MUPIX;
      "scifi", "2": return FEB_TYPE_SCIFI;
      "tile",  "3": return FEB_TYPE_TILE;
      default:         return FEB_TYPE_ALL;
    endcase
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cfg = sc_hub_uvm_env_cfg::type_id::create("cfg");
`ifdef SC_HUB_BUS_AXI4
    cfg.bus_type = SC_HUB_BUS_AXI4;
`ifdef SC_HUB_TB_AXI4_OOO_DISABLED
    cfg.supports_ooo = 1'b0;
`else
    cfg.supports_ooo = 1'b1;
`endif
`ifdef SC_HUB_TB_AXI4_ORD_DISABLED
    cfg.supports_ordering = 1'b0;
`else
    cfg.supports_ordering = 1'b1;
`endif
`ifdef SC_HUB_TB_AXI4_ATOMIC_DISABLED
    cfg.supports_atomic = 1'b0;
`else
    cfg.supports_atomic = 1'b1;
`endif
`else
    cfg.bus_type = SC_HUB_BUS_AVALON;
`ifdef SC_HUB_TB_AVALON_OOO_ENABLED
    cfg.supports_ooo = 1'b1;
`else
    cfg.supports_ooo = 1'b0;
`endif
`ifdef SC_HUB_TB_AVALON_ORD_DISABLED
    cfg.supports_ordering = 1'b0;
`else
    cfg.supports_ordering = 1'b1;
`endif
`ifdef SC_HUB_TB_AVALON_ATOMIC_DISABLED
    cfg.supports_atomic = 1'b0;
`else
    cfg.supports_atomic = 1'b1;
`endif
`endif
    cfg.supports_hub_cap = 1'b1;
    cfg.local_feb_type = parse_feb_type(get_string_plusarg("SC_HUB_LOCAL_FEB_TYPE", "all"));
    cfg.enable_atomic = cfg.supports_atomic;
    cfg.enable_ordering = cfg.supports_ordering;
    uvm_config_db#(sc_hub_uvm_env_cfg)::set(this, "*", "cfg", cfg);

    env_h = sc_hub_uvm_env::type_id::create("env_h", this);
  endfunction

  task automatic wait_for_testbench_settle();
    while (env_h.pkt_agent_h.driver_h.sc_pkt_vif.rst) begin
      @(posedge env_h.pkt_agent_h.driver_h.sc_pkt_vif.clk);
    end
    repeat (8) @(posedge env_h.pkt_agent_h.driver_h.sc_pkt_vif.clk);
  endtask

  task automatic issue_item(sc_pkt_seq_item item_h);
    sc_pkt_script_seq seq_h;

    if (item_h == null) begin
      `uvm_fatal(get_type_name(), "issue_item called with null item")
    end

    seq_h = sc_pkt_script_seq::type_id::create($sformatf("cfg_seq_%0t", $time));
    seq_h.req_h = item_h;
    seq_h.start(env_h.pkt_agent_h.sequencer_h);
  endtask

  task automatic configure_runtime_ctrls();
    sc_pkt_seq_item item_h;

    item_h = sc_pkt_seq_item::type_id::create("cfg_feb_type_item");
    item_h.sc_type       = SC_WRITE;
    item_h.start_address = HUB_CSR_FEB_TYPE_ADDR;
    item_h.rw_length     = 1;
    item_h.data_words_q.push_back({30'd0, cfg.local_feb_type});
    issue_item(item_h);
    wait_for_drain("cfg_feb_type");

    if (!cfg.supports_ooo) begin
      return;
    end

    item_h = sc_pkt_seq_item::type_id::create("cfg_ooo_ctrl_item");
    item_h.sc_type       = SC_WRITE;
    item_h.start_address = HUB_CSR_OOO_CTRL_ADDR;
    item_h.rw_length     = 1;
    item_h.data_words_q.push_back({31'd0, cfg.enable_ooo});
    issue_item(item_h);
    wait_for_drain("cfg_ooo_ctrl");
  endtask

  task automatic wait_for_drain(input string drain_name = "base");
    int unsigned drain_cycles;
    int unsigned drain_timeout_cycles;

    drain_timeout_cycles = BASE_DRAIN_TIMEOUT_CYCLES;
    void'($value$plusargs("SC_HUB_DRAIN_TIMEOUT_CYCLES=%d", drain_timeout_cycles));

    for (drain_cycles = 0; drain_cycles < drain_timeout_cycles; drain_cycles++) begin
      if ((env_h.scoreboard_h.expected_q.size() == 0) &&
          (env_h.bus_agent_h.monitor_h.pending_cmd_q.size() == 0)) begin
        return;
      end
      @(posedge env_h.pkt_agent_h.driver_h.sc_pkt_vif.clk);
    end

    `uvm_error(get_type_name(),
               $sformatf("%s drain timed out pending_expected=%0d pending_bus_cmd=%0d after %0d cycles",
                         drain_name,
                         env_h.scoreboard_h.expected_q.size(),
                         env_h.bus_agent_h.monitor_h.pending_cmd_q.size(),
                         drain_cycles))
  endtask

  task run_phase(uvm_phase phase);
    sc_pkt_single_seq seq_h;

    phase.raise_objection(this);
    wait_for_testbench_settle();
    configure_runtime_ctrls();
    seq_h = sc_pkt_single_seq::type_id::create("seq_h");
    seq_h.sc_type       = SC_READ;
    seq_h.start_address = 24'h000020;
    seq_h.rw_length     = 4;
    seq_h.start(env_h.pkt_agent_h.sequencer_h);
    wait_for_drain("base");
    phase.drop_objection(this);
  endtask
endclass
