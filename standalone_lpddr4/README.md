# Standalone LPDDR4: LiteDRAM + LPDDR4StrobePHY + Winbond W66AP6NB

End-to-end simulation of the LiteDRAM controller, an LPDDR4 PHY with physically
accurate pad behavior, and the encrypted Winbond W66AP6NB behavioral model (VCS).

```
 tb (BIOS + traffic)        lpddr4_top (generate.py)                              Winbond W66AP6NB
 ┌──────────────────┐   ┌───────────────────────────────────────────────────┐   ┌───────────────┐
 │ CSR bus  ────────┼──▶│ CSRs ─▶ DFII ─┐                                   │   │               │
 │ native port ─────┼──▶│ crossbar ─▶ controller ─▶ DFI ─▶ LPDDR4StrobePHY ─┼──▶│ CK/CA/CS/CKE  │
 │ scoreboard ◀─────┼───│                                  │ lpddr4_phy_io  │◀─▶│ DQ/DQS/DMI    │
 └──────────────────┘   └───────────────────────────────────────────────────┘   └───────────────┘
   lpddr4_crg: PLL model (50 MHz CK boot clock -> 800 MHz), aligned sys/sys8x/sys8x_ddr clocks
```

## Running

```sh
make lpddr4-caen                    # generate locally, sync to CAEN, run VCS there
make lpddr4-caen SEED=7 NRANDOM=1000
make lpddr4-caen L4_DEFINES="+define+tDQS2DQ=300"   # change the DRAM's tDQS2DQ (ps)
make lpddr4-probe-caen              # pin-level characterization of the Winbond model
make lpddr4-vcs                     # on a host with both the Python venv and VCS
```

`lpddr4-caen` uses the SSH host `caen` (`CAEN_HOST`) in BatchMode, so an authenticated
connection must already exist (ControlMaster socket). The simulation directory on CAEN is
`~/lpddr4_sim/litedram/build/standalone_lpddr4/vcs` (`run.log`, `compile.log`).

## Files

| File | Purpose |
|---|---|
| `generate.py` | Builds `lpddr4_top.v`, `lpddr4_csr.svh` (CSR map), `lpddr4_params.svh` (latencies, geometry, MR values) |
| `../litedram/phy/lpddr4/strobephy.py` | `LPDDR4StrobePHY`: digital PHY (reuses `LPDDR4PHY` command/data path) |
| `../litedram/phy/lpddr4/verilog/lpddr4_phy_io.sv` | IO macro model: pads, TX/RX delay lines, DQS-strobed capture, async FIFO |
| `tb/tb_lpddr4.sv` | Top: CRG + DUT + `W66AP6NB`, runs init, training, traffic |
| `tb/lpddr4_bios.svh` | CSR/DFII access, JEDEC init with FSP switch, PHY training |
| `tb/lpddr4_traffic.svh` | Native-port driver and scoreboard (masked writes, back-to-back reads, random) |
| `tb/lpddr4_crg.sv` | PLL model with boot/operating frequency switch |
| `model_probe/tb_model_probe.sv` | Drives the DRAM pins directly to measure the model's timing |

## What the Winbond model requires (measured with `model_probe`)

| Behavior | Measured |
|---|---|
| Init clock | tCKb >= 18 ns enforced until ZQCAL LATCH: init at a boot clock, program FSP1, switch FSP-OP (with MR13 VRCG=1), then change frequency |
| CS | active high (port is named `cs_n`) |
| Write | first DQS rising edge at CAS-2 + WL*tCK + tDQSS (1 tCK); DQ sampled at **DQS + tDQS2DQ** (500 ps default) |
| Read | first DQS rising edge at CAS-2 + RL*tCK + tDQSCK (3.5 ns); 2 tCK static preamble; DQ edge aligned; 0.5 tCK postamble then Hi-Z |
| MRR | MR value on DQ[7:0], beats 0..3 |
| READ-DQ-CAL | MPC must be followed by CAS-2 with CA all zero; MR32 -> beats 0..7, MR40 -> beats 8..15, LSB first |
| Identity | MR5 = 0x08 (Winbond), MR8 = 0x30 (1Gb, x16) |

## PHY design (`LPDDR4StrobePHY`)

* **Write:** DQS edges aligned to CK rising edges (tDQSS = 1.0 tCK), 2 tCK static preamble,
  0.5 tCK postamble, per-UI output enable. DQ/DMI go through a per-byte TX delay line
  (`wdly_dq<n>`, 25 ps taps) trained so the DQ eye is centered at DQS + tDQS2DQ.
* **Read:** differential DQS receiver, per-byte RX delay (`rdly_dqs<n>`), DQS gate opened in the
  preamble at a trained UI position (`rdly_gate<n>`) and closed by the 16th strobe edge, DQ
  captured on both strobe edges into an async FIFO that is popped at a fixed `read_latency`
  (absorbs tDQSCK).
* **Init:** `LiteDRAMCore(dfii_sw_control_on_reset=True)` keeps RESET_n/CKE low until the BIOS
  runs (otherwise the controller drives RESET_n high right after system reset).

## Training results (default model)

| Step | Window | Chosen |
|---|---|---|
| Read gate | UI 65..68 (the 2 tCK preamble) | 66 |
| Read DQS delay | taps 0..24 (0..600 ps) | 12 (300 ps, ~1/4 tCK) |
| Write DQ delay | taps 20..44 (500..1100 ps) | 32 (800 ps = tDQS2DQ + UI/2) |

## Upstream LiteDRAM changes

* `modules.py`: `W66AP6NB` module (8 banks x 8192 rows x 1024 cols, timings from `Config-AC.v`).
* `phy/lpddr4/commands.py`: training MPCs (READ-FIFO, READ-DQ-CAL, WRITE-FIFO) are now sent as
  MPC + CAS-2 (zero column bits), as JESD209-4 requires; covered by `test_lpddr4_mpc_training_cas2`.
* `dfii.py`, `core/__init__.py`: optional software control on reset.
* `phy/lpddr4/strobephy.py`, `phy/lpddr4/verilog/lpddr4_phy_io.sv`: new PHY.

## Known limitations

* The clock switch produces two expected model warnings ("clock period changed").
* ODT is not modeled by the Winbond model; no periodic ZQ calibration or DQS oscillator
  tracking (tDQS2DQ drift) yet; CA training and write leveling are not needed at 1600 MT/s
  in this setup and are not implemented.
* The vendor's dual-channel `W66BP2NQ.sv` wrapper connects channel B to the channel A pins;
  the single-channel `W66AP6NB` is instantiated directly.
