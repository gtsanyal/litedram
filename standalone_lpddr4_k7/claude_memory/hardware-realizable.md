---
name: hardware-realizable
description: User requires every simulation technique to be physically doable on the real Kintex-7 board
metadata:
  node_type: memory
  type: feedback
  originSessionId: da25c705-f2fa-4624-b44b-99739b8c5d53
  modified: 2026-11-09T06:50:40.960Z
---

Never use a simulation-only trick (ideal clock switching, fake delays, TB-forced signals) in the K7 flow; everything must be implementable on the real FPGA. Fix things "the proper way" rather than working around model errors. Winbond W66AP6NB is the target DRAM, not the Micron MT53E256M16D1.

**Why:** user said "I am going to be physically uploading this to a real FPGA which is really connected to this device, so I want to make sure that Im not doing something in simulation which cant actually be done."

**How to apply:** when proposing a fix, state how it maps to hardware (e.g. the boot clock is OSERDES data, not a PLL change). Related: [[k7-lpddr4-flow-status]].
