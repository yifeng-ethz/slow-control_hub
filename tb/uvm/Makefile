.PHONY: compile_uvm run_uvm_smoke run_uvm run_vcd run_uvm_vcd coverage_report clean

compile_uvm:
	$(MAKE) -C .. compile_uvm

run_uvm_smoke:
	$(MAKE) -C .. run_uvm_smoke

run_uvm:
	$(MAKE) -C .. run_uvm

run_vcd:
	$(MAKE) -C .. run_vcd

run_uvm_vcd:
	$(MAKE) -C .. run_uvm_vcd

coverage_report:
	$(MAKE) -C .. coverage_report

clean:
	rm -rf ../work_sc_hub_tb ../work_sc_hub_cov_* ../modelsim.ini
