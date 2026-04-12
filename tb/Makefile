QUESTA_PREFER_FE ?= 0
ifeq ($(QUESTA_PREFER_FE),1)
ifneq ($(wildcard /data1/intelFPGA_pro/23.1/questa_fe),)
QUESTA_HOME ?= /data1/intelFPGA_pro/23.1/questa_fe
else
QUESTA_HOME ?= /data1/intelFPGA_pro/23.1/questa_fse
endif
else
ifneq ($(wildcard /data1/intelFPGA_pro/23.1/questa_fse),)
QUESTA_HOME ?= /data1/intelFPGA_pro/23.1/questa_fse
else
QUESTA_HOME ?= /data1/intelFPGA_pro/23.1/questa_fe
endif
endif
QUESTA_FLAVOR := $(notdir $(QUESTA_HOME))
UVM_HOME ?= $(firstword $(wildcard $(QUESTA_HOME)/verilog_src/uvm-1.2 $(QUESTA_HOME)/uvm-1.2))
QUESTA_LICENSE ?= $(firstword $(wildcard $(QUESTA_HOME)/LR-*_License.dat))
ETH_MENTOR_SERVER ?= 8161@lic-mentor.ethz.ch
TB_LICENSE_CHAIN := $(ETH_MENTOR_SERVER)
ifneq ($(wildcard $(QUESTA_LICENSE)),)
TB_LICENSE_CHAIN := $(ETH_MENTOR_SERVER):$(QUESTA_LICENSE)
endif
UVM_DPI_SO ?= $(firstword $(wildcard $(QUESTA_HOME)/uvm-1.2/linux_x86_64/uvm_dpi.so $(QUESTA_HOME)/verilog_src/uvm-1.2/linux_x86_64/uvm_dpi.so))
UVM_DPI_LIB := $(basename $(UVM_DPI_SO))
UVM_VSIM_OPTS :=
ifneq ($(UVM_DPI_SO),)
UVM_VSIM_OPTS += -sv_lib $(UVM_DPI_LIB)
endif

VLIB = $(firstword $(wildcard $(QUESTA_HOME)/bin/vlib $(QUESTA_HOME)/linux_x86_64/vlib))
VMAP = $(firstword $(wildcard $(QUESTA_HOME)/bin/vmap $(QUESTA_HOME)/linux_x86_64/vmap))
VLOG = $(firstword $(wildcard $(QUESTA_HOME)/bin/vlog $(QUESTA_HOME)/linux_x86_64/vlog))
VCOM = $(firstword $(wildcard $(QUESTA_HOME)/bin/vcom $(QUESTA_HOME)/linux_x86_64/vcom))
VSIM = $(firstword $(wildcard $(QUESTA_HOME)/bin/vsim $(QUESTA_HOME)/linux_x86_64/vsim))
VLOG_OPTS ?=
VCOM_OPTS ?= -suppress 12110
VSIM_OPTS ?=
COV ?= 0
COV_CODE ?= sbecft
VLOG_COV_OPTS :=
VCOM_COV_OPTS :=
VSIM_COV_OPTS :=
ifeq ($(COV),1)
VLOG_COV_OPTS += +cover=$(COV_CODE)
VCOM_COV_OPTS += +cover=$(COV_CODE)
VSIM_COV_OPTS += -coverage
endif
SIM_DO ?= run -all; quit -f
VCD_FILE ?= $(TEST_NAME).vcd
UVM_VCD_FILE ?= $(UVM_TESTNAME).vcd
QUESTA_MODELSIM_INI ?= $(QUESTA_HOME)/modelsim.ini

WORK       ?= work_sc_hub_tb
RTL_DIR    := ../rtl
SIM_DIR    := ./sim
UVM_DIR    := ./uvm
SCRIPT_DIR := ./scripts
BUS_TYPE   ?= AVALON
BUS_DEFINE := $(if $(filter AXI4,$(BUS_TYPE)),+define+SC_HUB_BUS_AXI4,)
TEST_NAME ?= smoke_basic
UVM_TESTNAME ?= sc_hub_base_test
SIM_PLUSARGS ?=
MODELSIM_INI := $(CURDIR)/modelsim.ini
DPI_CPP_PATH ?= /usr/bin/gcc

LM_LICENSE_FILE := $(TB_LICENSE_CHAIN)
export LM_LICENSE_FILE
ifeq ($(QUESTA_FLAVOR),questa_fe)
MGLS_LICENSE_FILE := $(TB_LICENSE_CHAIN)
SALT_LICENSE_SERVER := $(ETH_MENTOR_SERVER)
export MGLS_LICENSE_FILE SALT_LICENSE_SERVER
endif

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
	$(UVM_DIR)/sc_hub_uvm_tb_top.sv \
	$(UVM_DIR)/sva/sc_hub_internal_sva.sv \
	$(UVM_DIR)/tb_top.sv

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
	$(VCOM) $(VCOM_OPTS) $(VCOM_COV_OPTS) -modelsimini $(MODELSIM_INI) -2008 -work $(WORK) \
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
		$(RTL_DIR)/sc_hub_payload_ram.vhd \
		$(RTL_DIR)/sc_hub_axi4_core.vhd \
		$(RTL_DIR)/sc_hub_top.vhd \
		$(RTL_DIR)/sc_hub_top_axi4.vhd

compile_sim: compile_rtl
	$(VLOG) $(VLOG_OPTS) $(VLOG_COV_OPTS) -modelsimini $(MODELSIM_INI) -sv -work $(WORK) $(BUS_DEFINE) $(SIM_FILES)

compile_uvm: compile_rtl
	$(VLOG) $(VLOG_OPTS) $(VLOG_COV_OPTS) -mfcu -cuname sc_hub_uvm_dvworkflow_cu -modelsimini $(MODELSIM_INI) -sv -work $(WORK) $(BUS_DEFINE) \
		+incdir+$(UVM_HOME)/src \
		+incdir+$(SIM_DIR) \
		+incdir+$(UVM_DIR) \
		+incdir+$(UVM_DIR)/tests \
		+incdir+$(UVM_DIR)/sva \
		$(UVM_HOME)/src/uvm_pkg.sv \
		$(SIM_DIR)/sc_hub_pkg.sv \
		$(SIM_DIR)/sc_hub_addr_map.sv \
		$(SIM_DIR)/sc_hub_ref_model.sv \
		$(SIM_DIR)/avmm_slave_bfm.sv \
		$(SIM_DIR)/axi4_slave_bfm.sv \
		$(SIM_DIR)/sc_hub_assertions.sv \
		$(UVM_FILES)

run_sim_smoke: compile_sim
	$(VSIM) -modelsimini $(MODELSIM_INI) $(VSIM_OPTS) $(VSIM_COV_OPTS) -c -quiet -suppress 19 -suppress 3009 -work $(WORK) sc_hub_tb_top +TEST_NAME=$(TEST_NAME) $(SIM_PLUSARGS) -do "$(SIM_DO)"

run_uvm_smoke: compile_uvm
	$(VSIM) -modelsimini $(MODELSIM_INI) $(VSIM_OPTS) $(VSIM_COV_OPTS) $(UVM_VSIM_OPTS) -c -quiet -suppress 19 -suppress 3009 -work $(WORK) tb_top +UVM_TESTNAME=$(UVM_TESTNAME) $(SIM_PLUSARGS) -do "$(SIM_DO)"

run_vcd: compile_sim
	$(VSIM) -modelsimini $(MODELSIM_INI) $(VSIM_OPTS) -c -quiet -suppress 19 -suppress 3009 -work $(WORK) sc_hub_tb_top +TEST_NAME=$(TEST_NAME) $(SIM_PLUSARGS) -do "vcd file $(VCD_FILE); vcd add -r /*; run -all; vcd flush; quit -f"

run_uvm_vcd: compile_uvm
	$(VSIM) -modelsimini $(MODELSIM_INI) $(VSIM_OPTS) $(UVM_VSIM_OPTS) -c -quiet -suppress 19 -suppress 3009 -work $(WORK) tb_top +UVM_TESTNAME=$(UVM_TESTNAME) $(SIM_PLUSARGS) -do "vcd file $(UVM_VCD_FILE); vcd add -r /*; run -all; vcd flush; quit -f"

run_directed:
	$(SCRIPT_DIR)/run_directed.sh $(TEST_NAME)

run_uvm:
	$(SCRIPT_DIR)/run_uvm.sh $(UVM_TESTNAME)

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

wave_index:
	$(SCRIPT_DIR)/build_wave_manifest.py

run_cov_closure:
	$(SCRIPT_DIR)/run_cov_closure.sh

license_diag:
	@echo "QUESTA_HOME=$(QUESTA_HOME)"
	@echo "QUESTA_FLAVOR=$(QUESTA_FLAVOR)"
	@echo "LM_LICENSE_FILE=$(LM_LICENSE_FILE)"
	@echo "MGLS_LICENSE_FILE=$(MGLS_LICENSE_FILE)"
	@echo "SALT_LICENSE_SERVER=$(SALT_LICENSE_SERVER)"
	@echo "--- vsim banner ---"
	@$(VSIM) -version
	@echo "--- mtiverification availability ---"
	@$(QUESTA_HOME)/linux_x86_64/lmutil lmdiag -c $(ETH_MENTOR_SERVER) -n mtiverification || true

.PHONY: compile_rtl compile_sim compile_uvm run_sim_smoke run_uvm_smoke run_vcd run_uvm_vcd run_directed run_uvm run_basic run_perf run_edge run_error run_all coverage_report wave_index run_cov_closure license_diag
