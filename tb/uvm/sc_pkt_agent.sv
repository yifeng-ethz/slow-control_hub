class sc_pkt_sequencer extends uvm_sequencer #(sc_pkt_seq_item);
  `uvm_component_utils(sc_pkt_sequencer)

  function new(string name = "sc_pkt_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

class sc_pkt_agent extends uvm_agent;
  `uvm_component_utils(sc_pkt_agent)

  sc_pkt_sequencer  sequencer_h;
  sc_pkt_driver_uvm driver_h;
  sc_pkt_monitor_uvm monitor_h;

  function new(string name = "sc_pkt_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sequencer_h = sc_pkt_sequencer::type_id::create("sequencer_h", this);
    driver_h    = sc_pkt_driver_uvm::type_id::create("driver_h", this);
    monitor_h   = sc_pkt_monitor_uvm::type_id::create("monitor_h", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    driver_h.seq_item_port.connect(sequencer_h.seq_item_export);
  endfunction
endclass
