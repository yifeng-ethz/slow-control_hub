QUESTA_HOME ?= /data1/intelFPGA_pro/23.1/questa_fse
UVM_HOME    ?= $(QUESTA_HOME)/verilog_src/uvm-1.2
QUESTA_LICENSE ?= $(QUESTA_HOME)/LR-287689_License.dat
ETH_MENTOR_SERVER ?= 8161@lic-mentor.ethz.ch
TB_LICENSE_CHAIN := $(QUESTA_LICENSE):$(ETH_MENTOR_SERVER)

VLIB = $(QUESTA_HOME)/bin/vlib
VMAP = $(QUESTA_HOME)/bin/vmap
VLOG = $(QUESTA_HOME)/bin/vlog
VCOM = $(QUESTA_HOME)/bin/vcom
VSIM = $(QUESTA_HOME)/bin/vsim
VLOG_OPTS ?=
VCOM_OPTS ?= -suppress 12110
VSIM_OPTS ?=
SIM_DO ?= run -all; quit -f
QUESTA_MODELSIM_INI ?= $(QUESTA_HOME)/modelsim.ini

WORK       ?= work_sc_hub_tb
RTL_DIR    := ..
SIM_DIR    := ./sim
UVM_DIR    := ./uvm
SCRIPT_DIR := ./scripts
BUS_TYPE   ?= AVALON
BUS_DEFINE := $(if $(filter AXI4,$(BUS_TYPE)),+define+SC_HUB_BUS_AXI4,)
TEST_NAME ?= smoke_basic
UVM_TESTNAME ?= sc_hub_base_test
MODELSIM_INI := $(CURDIR)/modelsim.ini
DPI_CPP_PATH ?= /usr/bin/gcc

LM_LICENSE_FILE := $(TB_LICENSE_CHAIN)
MGLS_LICENSE_FILE := $(TB_LICENSE_CHAIN)
export LM_LICENSE_FILE MGLS_LICENSE_FILE

SIM_FILES = \
	$(SIM_DIR)/sc_hub_pkg.sv \
	$(SIM_DIR)/sc_hub_addr_map.sv \
	$(SIM_DIR)/sc_hub_ref_model.sv \
	$(SIM_DIR)/sc_pkt_driver.sv \
	$(SIM_DIR)/sc_pkt_monitor.sv \
	$(SIM_DIR)/avmm_slave_bfm.sv \
	$(SIM_DIR)/axi4_slave_bfm.sv \
	$(SIM_DIR)/sc_hub_scoreboard.sv \
	$(SIM_DIR)/sc_hub_assertions.sv \
	$(SIM_DIR)/sc_hub_ord_checker.sv \
	$(SIM_DIR)/sc_hub_freelist_monitor.sv \
	$(SIM_DIR)/sc_hub_tb_top.sv

UVM_FILES = \
	$(UVM_DIR)/sc_hub_uvm_pkg.sv \
	$(UVM_DIR)/sc_hub_uvm_tb_top.sv

$(WORK):
	$(VLIB) $(WORK)

$(MODELSIM_INI): $(WORK)
	rm -f "$(MODELSIM_INI)"
	cp "$(QUESTA_MODELSIM_INI)" "$(MODELSIM_INI)"
	chmod u+w "$(MODELSIM_INI)"
	$(VMAP) -modelsimini $(MODELSIM_INI) $(WORK) $(WORK) >/dev/null
	@if [ -x "$(DPI_CPP_PATH)" ]; then \
		tmp_file="$(MODELSIM_INI).tmp"; \
		awk ' \
			BEGIN { inserted = 0; seen = 0 } \
			{ \
				if ($$0 ~ /^DpiCppPath[[:space:]]*=/) { \
					if (seen == 0) { \
						print "DpiCppPath = $(DPI_CPP_PATH)"; \
						seen = 1; \
					} \
					next; \
				} \
				print; \
				if ($$0 == "[vsim]" && inserted == 0 && seen == 0) { \
					print "DpiCppPath = $(DPI_CPP_PATH)"; \
					inserted = 1; \
					seen = 1; \
				} \
			} \
			END { \
				if (inserted == 0 && seen == 0) { \
					print "DpiCppPath = $(DPI_CPP_PATH)"; \
				} \
			}' "$(MODELSIM_INI)" > "$$tmp_file"; \
		mv -f "$$tmp_file" "$(MODELSIM_INI)"; \
	fi

compile_rtl: $(MODELSIM_INI)
	$(VCOM) $(VCOM_OPTS) -modelsimini $(MODELSIM_INI) -2008 -work $(WORK) \
		$(RTL_DIR)/sc_hub_pkg.vhd \
		$(RTL_DIR)/fifo/sc_hub_fifo_sc.vhd \
		$(RTL_DIR)/fifo/sc_hub_fifo_sf.vhd \
		$(RTL_DIR)/fifo/sc_hub_fifo_bp.vhd \
		$(RTL_DIR)/sc_hub_pkt_rx.vhd \
		$(RTL_DIR)/sc_hub_pkt_tx.vhd \
		$(RTL_DIR)/sc_hub_avmm_handler.vhd \
		$(RTL_DIR)/sc_hub_axi4_handler.vhd \
		$(RTL_DIR)/sc_hub_axi4_ooo_handler.vhd \
		$(RTL_DIR)/sc_hub_core.vhd \
		$(RTL_DIR)/sc_hub_axi4_core.vhd \
		$(RTL_DIR)/sc_hub_top.vhd \
		$(RTL_DIR)/sc_hub_top_axi4.vhd

compile_sim: compile_rtl
	$(VLOG) $(VLOG_OPTS) -modelsimini $(MODELSIM_INI) -sv -work $(WORK) $(BUS_DEFINE) $(SIM_FILES)

compile_uvm: compile_rtl
	$(VLOG) $(VLOG_OPTS) -modelsimini $(MODELSIM_INI) -sv -work $(WORK) +define+UVM_NO_DPI $(BUS_DEFINE) \
		+incdir+$(UVM_HOME)/src \
		+incdir+$(SIM_DIR) \
		+incdir+$(UVM_DIR) \
		$(UVM_HOME)/src/uvm_pkg.sv \
		$(SIM_DIR)/sc_hub_pkg.sv \
		$(SIM_DIR)/sc_hub_ref_model.sv \
		$(SIM_DIR)/avmm_slave_bfm.sv \
		$(SIM_DIR)/axi4_slave_bfm.sv \
		$(SIM_DIR)/sc_hub_assertions.sv \
		$(UVM_FILES)

run_sim_smoke: compile_sim
	$(VSIM) -modelsimini $(MODELSIM_INI) $(VSIM_OPTS) -c -quiet -nodpiexports -suppress 19 -suppress 3009 -work $(WORK) sc_hub_tb_top +TEST_NAME=$(TEST_NAME) -do "$(SIM_DO)"

run_uvm_smoke: compile_uvm
	$(VSIM) -modelsimini $(MODELSIM_INI) $(VSIM_OPTS) -c -quiet -nodpiexports -suppress 19 -suppress 3009 -work $(WORK) sc_hub_uvm_tb_top +UVM_TESTNAME=$(UVM_TESTNAME) -do "$(SIM_DO)"

run_directed:
	$(SCRIPT_DIR)/run_directed.sh

run_uvm:
	$(SCRIPT_DIR)/run_uvm.sh

run_basic:
	$(SCRIPT_DIR)/run_basic.sh

run_perf:
	$(SCRIPT_DIR)/run_perf.sh

run_edge:
	$(SCRIPT_DIR)/run_edge.sh

run_error:
	$(SCRIPT_DIR)/run_error.sh

run_all:
	$(SCRIPT_DIR)/run_all.sh

coverage_report:
	$(SCRIPT_DIR)/coverage_report.sh

.PHONY: compile_rtl compile_sim compile_uvm run_sim_smoke run_uvm_smoke run_directed run_uvm run_basic run_perf run_edge run_error run_all coverage_report
