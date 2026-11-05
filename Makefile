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