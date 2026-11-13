# K7 LPDDR4 flow: status / handoff (2026-11-12)

End-to-end simulation: LiteDRAM controller + **real `K7LPDDR4PHY`** (Xilinx unisims +
SecureIP) + board CRG (S7PLL from clk100, IDELAYCTRL) + PCB delay model + **Winbond W66AP6NB**
model, under VCS. **Status: passing** on the ideal board, 36 random-board seeds (11-26, 41-52 +
ideal-board seeds 2-9, ~500-1000 random ops each) and forced long-trace boards; 0 traffic errors,
0 unexpected model errors, post-training tDQSS worst 76 ps (limit 625 ps).

## How to run (vlsipool hosts: everything is local, no CAEN ssh)

    export VCS_HOME=/usr/caen/vcs-2023.12-SP2-1 PATH=/usr/caen/vcs-2023.12-SP2-1/bin:$PATH
    X=/usr/caen/xilinx/2022.1/Vivado/2022.1/data
    make lpddr4-k7-stage XILINX_SRC=$X/verilog/src XILINX_SECUREIP=$X/secureip
    make lpddr4-k7-vcs-run                                   # compile + seed 1, ~12 min wall
    make lpddr4-k7-seeds SEEDS="$(seq -s ' ' 1 16)" PAR=16 NRANDOM=500   # sweep, reuses simv

Testbench plusargs: `+SEED +NRANDOM`; `+BOARD_IDEAL` (zero PCB delays); `+CK_EXTRA_PS=<n>`,
`+BYTE0_EXTRA_PS=<n>`, `+BYTE1_EXTRA_PS=<n>` (long traces); `+WL_NO_RETRY` (old write leveling);
`+NO_MR_PROBE` (skip the unused-MR probe);
`+DUMP_START_NS=<t0> +DUMP_END_NS=<t1>` (VCD of pads + top-level `dut` in a window, then stop).

## Testbench checks
* Scoreboard on the native port (directed, masked, streaming, random).
* PCB model: per-pin transport delays, random per seed: CK/CA 100-600 ps (CA skew +-30), each byte
  DQS 100-600 ps independent of CK, DQ/DMI +-40 ps per bit; board reset at 1 us + 0..40 ns.
* **tDQSS checker** (the Winbond model does not check it): after training, every write DQS 0->1
  edge at the DRAM must be within +-0.25 tCK of a CK rising edge. Gates PASS.
* **CA bus monitor** at the DRAM pins decodes MRW-1/MRW-2/MRR-1; every BIOS `mrw()` / `mrr()` is
  checked to arrive exactly once with the intended MA/OP (error otherwise).
* MRR read-back after init: MR5 (0x08 Winbond), MR8 (0x30), MR1, MR2, MR3, MR11, MR12, MR14.
* Unused-MR probe (default on, `+NO_MR_PROBE` to skip; simulation only, not for the board BIOS):
  on JEDEC-unused MAs (26-31, 33-38, 41-50, 52-63; skips MR9 vendor test, MR10 ZQ reset,
  MR24/25 TRR/PPR, MR39 DRAM test, MR51 LPDDR4X single-ended) reads all, writes a unique pattern
  to all, reads all, writes the inverse, reads all, restores. Each MA must be stored / ignored /
  X; aliasing (an MA returning another MA's pattern), inconsistent read-back, or a change to
  MR0/5/6/7/8 or the programmed MRs is an error. Then reserved values in MR3/MR11 (restored).
  Winbond model: MR27-30, 33-38, 41-50 store all 8 bits, MR31 stores only OP[1:0]
  (undocumented vendor register: never write it on the board), MR26 reads 0, MR52-63 read X
  (`MR_ID_MAX = 51` in Config-AC.v); no aliasing, defined MRs intact. Model behaviour, not
  necessarily the silicon's.

## Fixes (2026-11-10 .. 12)
* **CRG: phase-aligned sys2x reset (hardware bug, port to the board CRG).** DoubleRateLPDDR4PHY's
  sys<->sys2x Serializer/Deserializer counters assume sys2x leaves reset on a sys-aligned edge;
  independent AsyncResetSynchronizers make that 50/50 per power-up (halves of each sys word swapped:
  MPC/CAS-2 10 tCK apart, read data split over sys cycles). Now sys2x rst = sys_rst re-registered in sys2x.
* **BIOS write leveling (port to the BIOS C code).** DQS ODELAY only spans taps 8..31 (3/4 tCK), so
  a CK/DQS PCB mismatch of ~0.7-1.3 ns hid the CK edge; the old code then kept DQS at 8 taps with
  only a WARNING (silently ~0.26 tCK off, which the model accepts). Now: if any byte has no 0->1
  edge, shift CK/CA/CS/CKE/ODT ODELAY (cdly) by 4, 8, .. 24 taps in power-down (CKE low) and sweep
  again; failure is an error. Write leveling now runs before read leveling (CK delay moves reads).
* BIOS `mrw()` waits 300 ns after each MRW (tMRW/tMRD/tMRWCKEL = 10 tCK at the 20 ns boot CK,
  tVRCG_ENABLE = 200 ns, + CSR->pad latency).
* `generate.py`: primitive scan catches cells with `(* attr *)` prefixes (FDPE was missing).

## Remaining model messages (understood, filtered by `lpddr4-k7-seeds`)
* RESET_n/CKE/CK `0->x->0` at 0.6 ns and at PLL lock: OSERDESE2 model X for one cycle before its
  reset applies; on silicon the output is the reset value. Board: RESET_n needs a pull-down during
  FPGA configuration (check the schematic).
* tWLS/tWLH during the write-leveling sweep at the taps where DQS crosses CK (inherent).

## Known limits / not modelled
* Model eyes are ideal (15-16 of 16 taps); no jitter, crosstalk, Vref, temperature drift
  (no periodic retraining / ZQ in the flow).
* Write leveling fails if the two bytes' DQS differ by > ~1.5 ns at the DRAM (reported as error).
* The PHY drives an early DQS edge when the DQS output enable turns on (base DQSPattern preamble
  toggles); the model accepts it, upstream hardware works with it.

## Later
Port to LiteX: sys2x reset fix in the board CRG; init (mrw delays) + training (CK-shift write
leveling, WL before read leveling) in the BIOS C code; full SoC build (litex-boards, RISC-V GCC,
Vivado >= 2020.2, openocd).
