class sc_hub_base_test extends uvm_test;
  `uvm_component_utils(sc_hub_base_test)

  localparam int unsigned BASE_DRAIN_TIMEOUT_CYCLES = 50000;

  sc_hub_uvm_env     env_h;
  sc_hub_uvm_env_cfg cfg;

  function new(string name = "sc_hub_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cfg = sc_hub_uvm_env_cfg::type_id::create("cfg");
`ifdef SC_HUB_BUS_AXI4
    cfg.bus_type = SC_HUB_BUS_AXI4;
`else
    cfg.bus_type = SC_HUB_BUS_AVALON;
`endif
    uvm_config_db#(sc_hub_uvm_env_cfg)::set(this, "*", "cfg", cfg);

    env_h = sc_hub_uvm_env::type_id::create("env_h", this);
  endfunction

  task automatic wait_for_testbench_settle();
    while (env_h.pkt_agent_h.driver_h.sc_pkt_vif.rst) begin
      @(posedge env_h.pkt_agent_h.driver_h.sc_pkt_vif.clk);
    end
    repeat (8) @(posedge env_h.pkt_agent_h.driver_h.sc_pkt_vif.clk);
  endtask

  task automatic wait_for_drain(input string drain_name = "base");
    int unsigned drain_cycles;

    for (drain_cycles = 0; drain_cycles < BASE_DRAIN_TIMEOUT_CYCLES; drain_cycles++) begin
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
    seq_h = sc_pkt_single_seq::type_id::create("seq_h");
    seq_h.sc_type       = SC_READ;
    seq_h.start_address = 24'h000020;
    seq_h.rw_length     = 4;
    seq_h.start(env_h.pkt_agent_h.sequencer_h);
    wait_for_drain("base");
    phase.drop_objection(this);
  endtask
endclass
