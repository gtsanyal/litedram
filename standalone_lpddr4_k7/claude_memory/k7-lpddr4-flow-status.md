---
name: k7-lpddr4-flow-status
description: Status of the Kintex-7 + Winbond LPDDR4 VCS simulation; blocked on Xilinx SecureIP files
metadata:
  node_type: memory
  type: project
  originSessionId: da25c705-f2fa-4624-b44b-99739b8c5d53
  modified: 2026-11-09T06:50:40.936Z
---

Goal: end-to-end sim of LiteDRAM + real K7LPDDR4PHY (Xilinx unisims/SecureIP) + Winbond W66AP6NB under VCS on CAEN, then run on the Antmicro LPDDR4 test board (XC7K70T) with a LiteX SoC + CPU BIOS. Full handoff in `standalone_lpddr4_k7/STATUS.md` — read it first.

As of 2026-11-09: everything built and parse-verified on CAEN; blocked on the user copying `$XILINX_VIVADO/data/secureip/{oserdese2,iserdese2}` from their Vivado host to `~/Desktop/sylvester/secureip/`. Next: `make lpddr4-k7-caen`, debug until model Errors=0.

The Winbond model is encrypted only for VCS/Xcelium/ModelSim, so xsim cannot run it; the Vivado host is only a source of Xilinx files and for bitstream builds. All work is uncommitted on master.

**Why:** user will flash real hardware wired to the Winbond part. **How to apply:** see [[hardware-realizable]] and [[caen-access]].
