PYTHON    := .venv/bin/python
VERILATOR := verilator

TB_DIR    := standalone_lpddr5
BUILD_DIR := build/standalone_lpddr5
OBJ_DIR   := $(BUILD_DIR)/obj_dir

TOP       := tb_lpddr5_controller
RTL       := $(BUILD_DIR)/lpddr5_controller.v
SIM       := $(OBJ_DIR)/V$(TOP)

.PHONY: generate sim clean-sim

# Generate LPDDR5 controller RTL
generate:
	$(PYTHON) $(TB_DIR)/generate.py

# Generate, compile, and run simulation
sim: generate
	$(VERILATOR) --binary --timing -Wno-fatal -Wno-COMBDLY -j 4 \
		-I$(TB_DIR) \
		--top-module $(TOP) \
		--Mdir $(OBJ_DIR) \
		$(TB_DIR)/$(TOP).sv \
		$(RTL)
	./$(SIM)

# Remove simulation build files
clean-sim:
	rm -rf $(OBJ_DIR)

# =============================================================================
# LPDDR4: LiteDRAM controller + LPDDR4StrobePHY + Winbond W66AP6NB model (VCS)
# =============================================================================
#   make lpddr4-generate        generate RTL/CSR map/params (needs the Python venv)
#   make lpddr4-vcs             compile + run with VCS (on a host with VCS)
#   make lpddr4-caen            generate locally, sync to CAEN and run VCS there
#   make lpddr4-probe-caen      run the pin-level Winbond model characterization
#
# Run options: SEED=<n> NRANDOM=<n> DUMP=1 L4_DEFINES="+define+tDQS2DQ=300"
#   (the Winbond model takes tDQS2DQ in ps under VCS; default 500)

L4_DIR      := standalone_lpddr4
L4_BUILD    := build/standalone_lpddr4
L4_SIMDIR   := $(L4_BUILD)/vcs
L4_MODEL    := W66AP6NB_W66BP2NQ_verilog_p
L4_PHY_IO   := litedram/phy/lpddr4/verilog/lpddr4_phy_io.sv

L4_SRCS := \
	$(L4_DIR)/tb/lpddr4_pkg.sv \
	$(L4_DIR)/tb/lpddr4_tb_if.sv \
	$(L4_DIR)/tb/lpddr4_crg.sv \
	$(L4_PHY_IO) \
	$(L4_BUILD)/lpddr4_top.v \
	$(L4_DIR)/tb/tb_lpddr4.sv

VCS        ?= vcs
L4_DEFINES ?=
SEED       ?= 1
NRANDOM    ?= 200
L4_VCS_FLAGS := -full64 -sverilog -timescale=1ps/1fs +define+T1600 \
	+incdir+$(L4_BUILD) +incdir+$(L4_DIR)/tb +incdir+$(L4_MODEL) \
	-debug_access+r -top tb_lpddr4 $(L4_DEFINES)
L4_RUN_FLAGS := +SEED=$(SEED) +NRANDOM=$(NRANDOM) $(if $(DUMP),+DUMP)

CAEN_HOST  ?= caen
CAEN_DIR   ?= lpddr4_sim/litedram
SSH        := ssh -o BatchMode=yes

.PHONY: lpddr4-generate lpddr4-vcs lpddr4-vcs-run lpddr4-caen lpddr4-sync lpddr4-probe-caen lpddr4-clean

lpddr4-generate:
	$(PYTHON) $(L4_DIR)/generate.py --output-dir $(L4_BUILD)

lpddr4-vcs: lpddr4-generate lpddr4-vcs-run

# Compile and run only (no Python needed, e.g. on CAEN after lpddr4-sync).
lpddr4-vcs-run:
	mkdir -p $(L4_SIMDIR)
	$(VCS) $(L4_VCS_FLAGS) -Mdir=$(L4_SIMDIR)/csrc -o $(L4_SIMDIR)/simv -l $(L4_SIMDIR)/compile.log \
		$(L4_MODEL)/W66AP6NB.vcs.svp $(L4_SRCS)
	cd $(L4_SIMDIR) && ./simv $(L4_RUN_FLAGS) -l run.log > /dev/null
	@echo "---- DRAM model errors/warnings ----"
	@grep -E "ERROR|WARN" $(L4_SIMDIR)/run.log | sed -E 's/time [0-9]+ ps://' | sort | uniq -c || true
	@echo "---- testbench summary ----"
	@grep -E "BIOS:|TRAFFIC:|SCOREBOARD|TEST (PASSED|FAILED)|Fatal|Error" $(L4_SIMDIR)/run.log | head -60
	@grep -q "TEST PASSED" $(L4_SIMDIR)/run.log

lpddr4-sync:
	$(SSH) $(CAEN_HOST) 'mkdir -p $(CAEN_DIR)'
	rsync -azR -e "$(SSH)" Makefile $(L4_DIR)/tb $(L4_PHY_IO) \
		$(L4_BUILD)/lpddr4_top.v $(L4_BUILD)/lpddr4_csr.svh $(L4_BUILD)/lpddr4_params.svh \
		$(L4_MODEL)/W66AP6NB.vcs.svp $(L4_MODEL)/Config-AC.v $(L4_DIR)/model_probe \
		$(CAEN_HOST):$(CAEN_DIR)/

lpddr4-caen: lpddr4-generate lpddr4-sync
	$(SSH) $(CAEN_HOST) 'bash -lc "module load vcs >/dev/null 2>&1; cd $(CAEN_DIR) && make lpddr4-vcs-run SEED=$(SEED) NRANDOM=$(NRANDOM) L4_DEFINES=\"$(L4_DEFINES)\" $(if $(DUMP),DUMP=1)"'

lpddr4-probe-caen: lpddr4-sync
	$(SSH) $(CAEN_HOST) 'bash -lc "module load vcs >/dev/null 2>&1; cd $(CAEN_DIR)/$(L4_DIR)/model_probe && \
		vcs -full64 -sverilog -timescale=1ps/1ps +define+T1600 +incdir+../../$(L4_MODEL) \
		../../$(L4_MODEL)/W66AP6NB.vcs.svp tb_model_probe.sv -o simv -l compile.log >/dev/null && \
		./simv -l run.log >/dev/null; grep -E \"^===|beats|ERROR|WARN\" run.log"'

lpddr4-clean:
	rm -rf $(L4_SIMDIR)


# =============================================================================
# LPDDR4 on the Kintex-7 soft PHY (K7LPDDR4PHY, Antmicro LPDDR4 Test Board clocking)
#   + Winbond W66AP6NB model, VCS with Xilinx unisim/SecureIP models
# =============================================================================
#   make lpddr4-k7-generate     generate RTL/CSR map/params (Python venv)
#   make lpddr4-k7-caen         generate, stage Xilinx models, sync to CAEN, run VCS
#   make lpddr4-k7-vcs-run      compile + run (on the VCS host, after sync)
#
# Xilinx simulation models come from a Vivado installation:
#   XILINX_SRC      = $XILINX_VIVADO/data/verilog/src   (unisims, unisims_dr, glbl.v)
#   XILINX_SECUREIP = $XILINX_VIVADO/data/secureip       (B_OSERDESE2, B_ISERDESE2 used by
#                                                         OSERDESE2/ISERDESE2 unisims)

L4K7_DIR        := standalone_lpddr4_k7
L4K7_BUILD      := build/standalone_lpddr4_k7
L4K7_SIMDIR     := $(L4K7_BUILD)/vcs
L4K7_XIL        := $(L4K7_BUILD)/xilinx
XILINX_SRC      ?= ../src
XILINX_SECUREIP ?= ../secureip
L4K7_SECUREIP   := oserdese2 iserdese2

L4K7_SRCS := \
	$(L4K7_DIR)/tb/lpddr4_pkg.sv \
	$(L4K7_DIR)/tb/lpddr4_tb_if.sv \
	$(L4K7_BUILD)/lpddr4_k7_top.v \
	$(L4K7_DIR)/tb/tb_lpddr4_k7.sv

L4K7_VCS_FLAGS := -full64 -sverilog -timescale=1ps/1fs +define+T1600 \
	+incdir+$(L4K7_BUILD) +incdir+$(L4K7_DIR)/tb +incdir+$(L4_MODEL) +incdir+$(L4K7_XIL)/unisims_dr \
	-debug_access+r -top tb_lpddr4_k7 -top glbl $(L4_DEFINES)

.PHONY: lpddr4-k7-generate lpddr4-k7-stage lpddr4-k7-sync lpddr4-k7-caen lpddr4-k7-vcs-run lpddr4-k7-clean

lpddr4-k7-generate:
	$(PYTHON) $(L4K7_DIR)/generate.py --output-dir $(L4K7_BUILD)

# Copy only the Xilinx models used by the generated netlist.
lpddr4-k7-stage: lpddr4-k7-generate
	@test -d $(XILINX_SRC)/unisims || (echo "XILINX_SRC=$(XILINX_SRC) has no unisims/"; exit 1)
	@for ip in $(L4K7_SECUREIP); do test -d $(XILINX_SECUREIP)/$$ip || \
		(echo "Missing $(XILINX_SECUREIP)/$$ip: copy \$$XILINX_VIVADO/data/secureip/$$ip from the Vivado host"; exit 1); done
	rm -rf $(L4K7_XIL) && mkdir -p $(L4K7_XIL)/unisims $(L4K7_XIL)/unisims_dr $(L4K7_XIL)/secureip
	for p in $$(cat $(L4K7_BUILD)/xilinx_primitives.txt); do \
		cp $(XILINX_SRC)/unisims/$$p.v $(L4K7_XIL)/unisims/; \
		for f in $${p}_dr.v B_$${p}_defines.vh; do \
			test -f $(XILINX_SRC)/unisims_dr/$$f && cp $(XILINX_SRC)/unisims_dr/$$f $(L4K7_XIL)/unisims_dr/ || true; \
		done; \
	done
	cp $(XILINX_SRC)/glbl.v $(L4K7_XIL)/
	for ip in $(L4K7_SECUREIP); do cp -R $(XILINX_SECUREIP)/$$ip $(L4K7_XIL)/secureip/; done

lpddr4-k7-sync: lpddr4-k7-stage
	$(SSH) $(CAEN_HOST) 'mkdir -p $(CAEN_DIR)'
	rsync -azR -e "$(SSH)" Makefile $(L4K7_DIR)/tb \
		$(L4K7_BUILD)/lpddr4_k7_top.v $(L4K7_BUILD)/lpddr4_csr.svh $(L4K7_BUILD)/lpddr4_params.svh \
		$(L4K7_BUILD)/xilinx_primitives.txt $(L4K7_XIL) \
		$(L4_MODEL)/W66AP6NB.vcs.svp $(L4_MODEL)/Config-AC.v \
		$(CAEN_HOST):$(CAEN_DIR)/

lpddr4-k7-vcs-run:
	mkdir -p $(L4K7_SIMDIR)
	$(VCS) $(L4K7_VCS_FLAGS) -Mdir=$(L4K7_SIMDIR)/csrc -o $(L4K7_SIMDIR)/simv -l $(L4K7_SIMDIR)/compile.log \
		$(L4_MODEL)/W66AP6NB.vcs.svp \
		$(L4K7_XIL)/glbl.v $(wildcard $(L4K7_XIL)/unisims/*.v) \
		$$(find $(L4K7_XIL)/secureip -name '*.vp' -o -name '*.v' | sort) \
		$(L4K7_SRCS)
	cd $(L4K7_SIMDIR) && ./simv $(L4_RUN_FLAGS) -l run.log > /dev/null
	@echo "---- DRAM model errors/warnings ----"
	@grep -E "ERROR|WARN" $(L4K7_SIMDIR)/run.log | sed -E 's/time [0-9]+ ps://' | sort | uniq -c | sort -rn | head -20 || true
	@echo "---- testbench summary ----"
	@grep -E "TB:|BIOS:|TRAFFIC:|TRAINING:|SCOREBOARD|TEST (PASSED|FAILED)|Fatal|Error-" $(L4K7_SIMDIR)/run.log | head -80
	@grep -q "TEST PASSED" $(L4K7_SIMDIR)/run.log

lpddr4-k7-caen: lpddr4-k7-sync
	$(SSH) $(CAEN_HOST) 'bash -lc "module load vcs >/dev/null 2>&1; cd $(CAEN_DIR) && make lpddr4-k7-vcs-run SEED=$(SEED) NRANDOM=$(NRANDOM) L4_DEFINES=\"$(L4_DEFINES)\" $(if $(DUMP),DUMP=1)"'

lpddr4-k7-clean:
	rm -rf $(L4K7_SIMDIR) $(L4K7_XIL)
