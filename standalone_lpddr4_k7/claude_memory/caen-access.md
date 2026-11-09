---
name: caen-access
description: "How to run VCS on CAEN — only via the user's existing ssh ControlMaster socket"
metadata:
  node_type: memory
  type: reference
  originSessionId: da25c705-f2fa-4624-b44b-99739b8c5d53
  modified: 2026-11-09T06:50:41.070Z
---

VCS runs on the CAEN host (ssh alias `caen`, run dir `~/lpddr4_sim/litedram`). Login needs interactive Okta, so only use `ssh -o BatchMode=yes caen` over the user's ControlMaster socket (`~/.ssh/my-socket-caen`, ControlPersist 15m). If it fails, ask the user to ssh into caen from another terminal. Makefile targets `lpddr4-caen` / `lpddr4-k7-caen` wrap sync + run.

pip-installing litex-boards from GitHub was denied by the permission classifier; the user can run it themselves with `! .venv/bin/pip install ...`. Don't commit unless asked. Related: [[k7-lpddr4-flow-status]].
