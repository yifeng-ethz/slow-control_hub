class sc_hub_uvm_env extends uvm_env;
  `uvm_component_utils(sc_hub_uvm_env)

  sc_hub_uvm_env_cfg  cfg;
  sc_pkt_agent        pkt_agent_h;
  bus_agent           bus_agent_h;
  sc_hub_scoreboard_uvm scoreboard_h;
  sc_hub_cov_collector coverage_h;
  sc_hub_ord_checker_uvm ord_checker_h;

  function new(string name = "sc_hub_uvm_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(sc_hub_uvm_env_cfg)::get(this, "", "cfg", cfg)) begin
      cfg = sc_hub_uvm_env_cfg::type_id::create("cfg");
    end

    uvm_config_db#(sc_hub_uvm_env_cfg)::set(this, "*", "cfg", cfg);

    pkt_agent_h  = sc_pkt_agent::type_id::create("pkt_agent_h", this);
    bus_agent_h  = bus_agent::type_id::create("bus_agent_h", this);
    scoreboard_h = sc_hub_scoreboard_uvm::type_id::create("scoreboard_h", this);
    coverage_h   = sc_hub_cov_collector::type_id::create("coverage_h", this);
    ord_checker_h = sc_hub_ord_checker_uvm::type_id::create("ord_checker_h", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    pkt_agent_h.driver_h.sent_ap.connect(scoreboard_h.cmd_imp);
    pkt_agent_h.driver_h.sent_ap.connect(coverage_h.cmd_imp);
    pkt_agent_h.monitor_h.reply_ap.connect(scoreboard_h.rsp_imp);
    pkt_agent_h.monitor_h.reply_ap.connect(coverage_h.rsp_imp);
    pkt_agent_h.driver_h.sent_ap.connect(ord_checker_h.cmd_imp);
    pkt_agent_h.driver_h.sent_ap.connect(bus_agent_h.monitor_h.cmd_ap);
    bus_agent_h.monitor_h.bus_ap.connect(scoreboard_h.bus_imp);
    bus_agent_h.monitor_h.bus_ap.connect(ord_checker_h.bus_imp);
    bus_agent_h.monitor_h.bus_ap.connect(coverage_h.bus_imp);
  endfunction
endclass
