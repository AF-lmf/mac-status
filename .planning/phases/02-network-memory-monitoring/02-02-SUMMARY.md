---
phase: 02-network-memory-monitoring
plan: 02
subsystem: Memory monitoring
tags: [memory, ram, host_statistics64, host_basic_info, NSStatusItem, menu-bar]
requires: [02-01]
provides: [MEM-01]
affects: [StatusBarManager, AppDelegate]
tech-stack:
  added: []
  patterns: [TimerReader<T>, MemoryStats:Sendable, Mach kernel APIs, NSStatusItem fixed-width]
key-files:
  created:
    - MacStatus/MacStatus/Readers/MemoryReader.swift
  modified:
    - MacStatus/MacStatus/UI/StatusBarManager.swift
    - MacStatus/MacStatus/App/AppDelegate.swift
    - MacStatus/MacStatus.xcodeproj/project.pbxproj
decisions:
  - "MemoryReader extends TimerReader<MemoryStats> with 2-second polling interval (D-10)"
  - "Uses host_basic_info.max_mem for total RAM (NOT memory_size which is capped at 2 GB — PITFALL 1)"
  - "Standard macOS used formula: active+inactive+speculative+wired+compressed-purgeable-external"
  - "Fixed-width NSStatusItem (100pt) for memory display to prevent menu bar jitter (PITFALL P8)"
  - "0.5% tolerance threshold on memory redraws — same as CPU pattern (D-06 inherited from Phase 1)"
  - "getpagesize() POSIX function used instead of vm_page_size C global to satisfy Swift 6 strict concurrency"
metrics:
  duration: "6min"
  completed_date: "2026-05-14T08:33:00Z"
  files_changed: 4
  commits: 2
---

# Phase 2 Plan 2: Memory Monitoring Summary

**One-liner:** Real-time memory usage (used/total) displayed in the macOS menu bar via `host_statistics64(HOST_VM_INFO64)` page statistics and `host_basic_info.max_mem` for total physical RAM — third NSStatusItem alongside CPU and network.

## What Was Built

A complete memory monitoring vertical slice: from Mach kernel page statistics through the standard macOS "used" memory formula to a visible `NSStatusItem` displaying `"MEM 8.2G/16G"`.

### MemoryReader

- **`MemoryStats: Sendable` struct** — holds `usedBytes`, `totalBytes`, `freeBytes`
- **`MemoryReader: TimerReader<MemoryStats>`** — 2-second polling interval (D-10)
- **`setup()`** — reads total physical RAM once via `host_info(HOST_BASIC_INFO).max_mem` (never the 2 GB-capped `memory_size` field — PITFALL 1)
- **`read()`** — queries `host_statistics64(HOST_VM_INFO64)` for page statistics, applies the standard macOS used formula: `active + inactive + speculative + wired + compressed - purgeable - external`
- **Page size** — read via `getpagesize()` POSIX function at module load time, avoiding direct access to the `vm_page_size` C global which triggers Swift 6 strict concurrency errors
- **Error handling** — Mach return codes guarded against `KERN_SUCCESS`; sends `nil` → StatusBarManager displays `"MEM --/--"`

### StatusBarManager Extensions

- **`setupMemoryItem()`** — creates a third `NSStatusItem` with 100pt fixed width (`autosaveName = "com.macstatus.memory"`)
- **`updateMemory(_:)`** — nil-safe display update with 0.5% tolerance-based redraw (same pattern as CPU)
- **`deinit`** — removes `memoryStatusItem` alongside CPU and network items

### AppDelegate Wiring

- **`memoryReader`** property added alongside `cpuReader` and `networkReader`
- **`applicationDidFinishLaunching`** — calls `setupMemoryItem()`, instantiates `MemoryReader()`, wires `onUpdate → statusBarManager.updateMemory`, calls `start()`
- **`applicationWillTerminate`** — calls `memoryReader?.stop()`, sets to `nil`

### Xcode Project

- `MemoryReader.swift` added to Readers group and Sources build phase in `project.pbxproj`

## Commits

| Commit | Type | Message |
|--------|------|---------|
| `27a362c` | feat(02-02) | create MemoryReader with host_statistics64 + host_basic_info |
| `6a4761d` | feat(02-02) | wire MemoryReader into StatusBarManager and AppDelegate |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Swift 6 strict concurrency: `vm_page_size` C global flagged as shared mutable state**

- **Found during:** Task 1 build verification
- **Issue:** Direct access to the C `extern vm_size_t vm_page_size` global triggered Swift 6 strict concurrency error: "reference to var 'vm_page_size' is not concurrency-safe because it involves shared mutable state"
- **Fix:** Replaced `Double(vm_page_size)` with `Double(getpagesize())` — the POSIX function returns the same value without the concurrency issue. The page size is cached in a module-level `let cachedPageSize` for zero-overhead repeated access.
- **Files modified:** `MacStatus/MacStatus/Readers/MemoryReader.swift`
- **Commit:** `6a4761d`

## Verification

- **Build:** `xcodebuild -project MacStatus.xcodeproj -scheme MacStatus build` → BUILD SUCCEEDED with zero errors and zero warnings
- **Swift 6 concurrency:** Zero data-race errors after `getpagesize()` fix
- **Existing functionality:** CPU and network displays unchanged — zero regressions from Phase 1 or Plan 02-01

## Known Stubs

None. All three metrics (CPU, network, memory) are wired end-to-end with live kernel data.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: info_disclosure | MemoryReader.swift | `host_basic_info.max_mem` returns actual physical RAM — using `memory_size` instead would show false "2.0G/2.0G" on any Mac with >2 GB RAM (T-02-07, mitigated by always using `max_mem`) |

## Self-Check

- `MacStatus/MacStatus/Readers/MemoryReader.swift` exists: FOUND
- `MemoryStats` struct defined: FOUND
- `MemoryReader` extends `TimerReader<MemoryStats>`: FOUND
- `StatusBarManager.setupMemoryItem()` exists: FOUND
- `StatusBarManager.updateMemory(_:)` exists: FOUND
- `AppDelegate.memoryReader` wired: FOUND
- Commit `27a362c`: FOUND
- Commit `6a4761d`: FOUND
- `xcodebuild build` succeeds: PASSED
