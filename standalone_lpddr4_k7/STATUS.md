# K7 LPDDR4 flow: status / handoff (2026-11-09)

End-to-end simulation: LiteDRAM controller + **real `K7LPDDR4PHY`** (Xilinx unisims +
SecureIP) + board CRG (S7PLL from clk100, IDELAYCTRL) + **Winbond W66AP6NB** model, under VCS on CAEN.
The working reference flow with the behavioral strobe PHY is `../standalone_lpddr4/` (passes, model Errors=0).

## Blocker
VCS parses/elaborates everything on CAEN except `B_OSERDESE2` / `B_ISERDESE2` (Xilinx SecureIP,
required by the OSERDESE2/ISERDESE2 unisims; not in `../../src`). Copy from the Vivado host:

    scp -r <vivado-host>:$XILINX_VIVADO/data/secureip/{oserdese2,iserdese2} ~/Desktop/sylvester/secureip/

Then check the `.vp` files contain a Synopsys key block, and run `make lpddr4-k7-caen`
(`XILINX_SRC ?= ../src`, `XILINX_SECUREIP ?= ../secureip`).

## Done
* `generate.py`: board-accurate top `lpddr4_k7_top` (sys 50 MHz, sys2x 100, sys8x 400, idelay 200;
  LPDDR4-800 CL=10 CWL=6), `K7LPDDR4PHY(..., boot_clk_div=1)`, `LiteDRAMCore(dfii_sw_control_on_reset=True)`,
  CSR bus ports, writes `xilinx_primitives.txt` (used by `make lpddr4-k7-stage`).
* `basephy.py` boot mode (`boot_clk_div`, CSR `ddrphy_boot_mode`): 50 MHz CK via the same OSERDES,
  so tCKb >= 18 ns is met on real hardware; unit test `test_lpddr4_boot_mode` (18 LPDDR4Tests pass).
* `tb/lpddr4_bios.svh`: init (boot mode, FSP1, ZQ, VRCG, FSP-OP, CKE-low freq switch), read training
  (READ-DQ-CAL, IDELAY x bitslip), MR checks, write leveling, write bitslip x DQ ODELAY. Uses only
  CSRs the LiteX CPU will have, so it can be ported to the BIOS C code.
* Makefile targets: `lpddr4-k7-generate / -stage / -sync / -vcs-run / -caen / -clean`.

## Expected issues on first run
* Base DQSPattern preamble has extra toggles -> possible Winbond model errors.
* tDQSS margin before write leveling; whether the model returns WL feedback on DQ.
* Model accepting the CKE-low frequency switch; sim speed with PLLE2_ADV.
* TB prints PASSED even if the model logs errors (gating on model errors not yet done).

## Later
README for this folder; port init/training to the LiteX BIOS; full SoC build (litex-boards,
RISC-V GCC, Vivado >= 2020.2 per Antmicro rowhammer-tester docs, openocd).
Upstream never simulates the K7 LPDDR4 PHY at primitive level (only Migen/Verilator sim PHY + hardware).
