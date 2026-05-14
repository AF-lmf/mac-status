---
quick_id: 260514-s6f
slug: cpu
status: complete
completed: 2026-05-14T12:20:00Z
commit: 438d31c
---

# Quick Task 260514-s6f Summary

## Outcome

Adjusted the visible menu bar display to `CPU | MEM | network` and changed memory from used/total GB to memory pressure.

## Changes

- `MemoryReader` now reads `kern.memorystatus_vm_pressure_level` with `sysctlbyname`.
- Memory pressure maps to compact labels:
  - `1` -> `MEM OK`
  - `2` -> `MEM WARN`
  - `4` -> `MEM CRIT`
  - unknown or unavailable -> `MEM --`
- `StatusBarManager` renders the combined title as `CPU ... | MEM ... | ↓... ↑...`.

## Verification

- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` succeeded.
- `rg` checks confirmed the old used/total memory fields and formatter are gone.
- `sysctl kern.memorystatus_vm_pressure_level` returned `1` on this machine during verification.
