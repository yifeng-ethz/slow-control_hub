class sc_hub_base_test extends uvm_test;
  `uvm_component_utils(sc_hub_base_test)

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

  task run_phase(uvm_phase phase);
    sc_pkt_single_seq seq_h;

    phase.raise_objection(this);
    seq_h = sc_pkt_single_seq::type_id::create("seq_h");
    seq_h.sc_type       = SC_READ;
    seq_h.start_address = 24'h000020;
    seq_h.rw_length     = 4;
    seq_h.start(env_h.pkt_agent_h.sequencer_h);
    repeat (200) @(posedge env_h.pkt_agent_h.driver_h.sc_pkt_vif.clk);
    phase.drop_objection(this);
  endtask
endclass
