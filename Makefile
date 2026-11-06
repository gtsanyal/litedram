
PYTHON := .venv/bin/python
VCS    := vcs

TB_DIR    := standalone_lpddr5
BUILD_DIR := build/standalone_lpddr5
OBJ_DIR   := $(BUILD_DIR)/vcs_obj

# Xilinx UNISIM library
XILINX_SIM := $(abspath ../xilinx_verilog_sim/src)
#UNISIM_DIR := $(XILINX_SIM)/unisims
UNISIM_DIR := $(XILINX_SIM)/xeclib
GLBL       := $(XILINX_SIM)/glbl.v

# Controller
TOP     := tb_lpddr5_controller
RTL     := $(BUILD_DIR)/lpddr5_controller.v
SIM     := $(BUILD_DIR)/simv_controller

# PHY
PHY_RTL := $(BUILD_DIR)/lpddr5_phy.v
PHY_SIM := $(BUILD_DIR)/simv_phy

# VCS options
VCS_FLAGS := -full64 -sverilog -timescale=1ns/1ps

.PHONY: generate generate-phy sim sim-phy clean-sim

# ------------------------------------------------------------
# Generate controller RTL
# ------------------------------------------------------------
generate:
	$(PYTHON) $(TB_DIR)/generate.py

# ------------------------------------------------------------
# Generate PHY RTL
# ------------------------------------------------------------
generate-phy:
	$(PYTHON) $(TB_DIR)/generate_phy.py

# ------------------------------------------------------------
# Generate, compile, and simulate controller
# ------------------------------------------------------------
sim: generate
	mkdir -p $(OBJ_DIR)/controller
	$(VCS) $(VCS_FLAGS) \
		+incdir+$(TB_DIR) \
		-top $(TOP) \
		-Mdir=$(OBJ_DIR)/controller \
		-o $(abspath $(SIM)) \
		$(TB_DIR)/$(TOP).sv \
		$(RTL)
	./$(SIM)

# ------------------------------------------------------------
# Generate and compile hardware PHY with Xilinx UNISIM
# ------------------------------------------------------------
sim-phy: generate-phy
	mkdir -p $(OBJ_DIR)/phy
	$(VCS) $(VCS_FLAGS) \
		+libext+.v+.sv \
		-y $(UNISIM_DIR) \
		-top lpddr5_phy \
		-Mdir=$(OBJ_DIR)/phy \
		-o $(abspath $(PHY_SIM)) \
		$(PHY_RTL) \
		$(GLBL)

# ------------------------------------------------------------
# Clean simulation files
# ------------------------------------------------------------
clean-sim:
	rm -rf $(OBJ_DIR)
	rm -f $(SIM) $(PHY_SIM)
