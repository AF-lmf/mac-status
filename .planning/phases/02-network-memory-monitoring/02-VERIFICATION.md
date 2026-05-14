---
phase: 02-network-memory-monitoring
verified: 2026-05-14T12:15:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Launch the Debug app and inspect the visible menu bar item"
    expected: "One visible item includes CPU, memory pressure, and network text, e.g. 'CPU 12% | MEM OK | ↓1K ↑1K'"
    why_human: "macOS menu bar rendering and available menu bar width require visual confirmation"
---

# Phase 2: Network + Memory Monitoring Verification Report

**Phase Goal:** User can see real-time network speed and memory pressure alongside CPU in the menu bar  
**Verified:** 2026-05-14T12:15:00Z  
**Status:** passed

## Goal Achievement

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User can see network download and upload rates updating in real time with appropriate units | VERIFIED IN CODE | `NetworkReader` polls every 1s, resolves the primary interface via `SCDynamicStoreCopyValue`, reads `if_data` byte counters with `getifaddrs()`, and formats rates through `formatNetworkCompact`. |
| 2 | User can see memory pressure displayed as OK/WARN/CRIT | VERIFIED IN CODE | `MemoryReader` reads `kern.memorystatus_vm_pressure_level` with `sysctlbyname`; `StatusBarManager.updateMemory(_:)` now updates `latestMemoryText` and redraws the visible combined status item. |
| 3 | App correctly detects and monitors the active network interface without manual configuration | VERIFIED IN CODE | `getPrimaryInterface()` reads `State:/Network/Global/IPv4` every cycle and does not hardcode `en0`. |
| 4 | CPU, network, and memory pressure metrics all display concurrently in the menu bar | VERIFIED IN CODE, HUMAN CONFIRMED | `updateCombinedStatus()` renders `latestCPUText`, `latestMemoryText`, and `latestNetworkText` into the single visible `networkStatusItem`; width is fixed at 240pt with single-line clipping. |

**Score:** 4/4 must-haves verified in code.

## Requirements Coverage

| Requirement | Status | Evidence |
|-------------|--------|----------|
| NETW-01 | SATISFIED | Download rate comes from `ifi_ibytes` deltas and displays with the `↓` prefix. |
| NETW-02 | SATISFIED | Upload rate comes from `ifi_obytes` deltas and displays with the `↑` prefix. |
| NETW-03 | SATISFIED | Active interface is resolved through SystemConfiguration, not hardcoded. |
| MEM-01 | SATISFIED IN CODE | Memory pressure is read from `kern.memorystatus_vm_pressure_level` and participates in the visible combined status item. |

## Key Link Verification

| Link | Status | Evidence |
|------|--------|----------|
| NetworkReader -> StatusBarManager | WIRED | `AppDelegate` wires `networkReader?.onUpdate` to `statusBarManager?.updateNetwork(stats)` on the main queue. |
| MemoryReader -> StatusBarManager | WIRED | `AppDelegate` wires `memoryReader?.onUpdate` to `statusBarManager?.updateMemory(stats)` on the main queue. |
| Memory text -> visible menu item | WIRED | `StatusBarManager.updateMemory(_:)` updates `latestMemoryText` and calls `updateCombinedStatus()`. |
| Combined status title | WIRED | `updateCombinedStatus()` sets `networkStatusItem` to `CPU | MEM | network`. |
| Memory failure fallback | WIRED | `MemoryReader.read()` emits `nil` if the pressure `sysctlbyname` call fails, and `updateMemory(nil)` displays `MEM --`. |

## Automated Checks

- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` -> BUILD SUCCEEDED.
- `rg -n "latestMemoryText|updateMemory|updateCombinedStatus|memoryStatusItem|withLength: 240|kern.memorystatus_vm_pressure_level" ...` confirmed:
  - `latestMemoryText` exists.
  - memory updates call `updateCombinedStatus()`.
  - `memoryStatusItem` is no longer present.
  - combined item width is `240`.
  - `MemoryReader` reads `kern.memorystatus_vm_pressure_level`.
- Code review report: `.planning/phases/02-network-memory-monitoring/02-REVIEW.md` has `status: clean`.

## Human Verification

The remaining visual check was completed by the user:

- **Result:** pass
- **Reported:** "能看到；改为内存压力"

After this confirmation, the display was refined to show memory pressure instead of used/total GB.

## Gaps Summary

No Phase 2 gaps remain.

---
_Verified: 2026-05-14T12:15:00Z_
_Verifier: Codex inline verification_
