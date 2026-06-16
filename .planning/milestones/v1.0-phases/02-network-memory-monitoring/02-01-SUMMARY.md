---
phase: 02-network-memory-monitoring
plan: 01
subsystem: ui
tags: [swift, appkit, network, getifaddrs, systemconfiguration, bytecountformatter, nsstatusitem]

# Dependency graph
requires:
  - phase: 01-foundation-cpu-monitoring
    provides: TimerReader<T> base class, ReaderProtocol, CPUReader pattern, StatusBarManager pattern, AppDelegate wiring pattern
provides:
  - NetworkReader with getifaddrs() byte counters, SCDynamicStoreCopyValue primary interface detection, 1s delta-based rate calculation
  - ByteFormatting utility with ByteCountFormatter-based formatNetworkCompact and formatMemoryCompact
  - StatusBarManager network NSStatusItem (90pt fixed width, autosaveName, 1 KB/s tolerance)
  - SystemConfiguration.framework integration in Xcode project
affects: [02-02-memory, 04-combined-display, 05-launch-login]

# Tech tracking
tech-stack:
  added: [SystemConfiguration.framework]
  patterns: [NetworkStats Sendable struct, delta-based rate calculation from byte counters, freeifaddrs defer pattern, NSWorkspace.didWakeNotification observer for sleep/wake recovery]
patterns-established:
  - "Delta rate calculation: Store previous byte counters + timestamp, compute (current - previous) / Δt with max(_, 0) wraparound safety"
  - "Primary interface detection: SCDynamicStoreCopyValue('State:/Network/Global/IPv4') every read cycle (not cached)"
  - "Fixed-width NSStatusItem: 90pt for network display to prevent menu bar jitter (PITFALL P8)"

key-files:
  created:
    - MacStatus/MacStatus/Readers/NetworkReader.swift
    - MacStatus/MacStatus/Utils/ByteFormatting.swift
  modified:
    - MacStatus/MacStatus/UI/StatusBarManager.swift
    - MacStatus/MacStatus/App/AppDelegate.swift
    - MacStatus/MacStatus.xcodeproj/project.pbxproj

key-decisions:
  - "Network delta uses max(current - previous, 0) with Int64 conversion to handle 32-bit u_int32_t counter wraparound (PITFALL P2)"
  - "Tolerance threshold of 1 KB/s (1024 bytes/s) absolute for network — not the 0.5% relative threshold from CPU (network rates are jittery)"
  - "Primary interface resolved every read cycle via SCDynamicStoreCopyValue — near-zero overhead, handles Wi-Fi/Ethernet/VPN transitions instantly"
  - "freeifaddrs() in defer block immediately after getifaddrs() — prevents ~86 MB/day memory leak at 1 Hz polling (PITFALL P3)"

requirements-completed: [NETW-01, NETW-02, NETW-03]

# Metrics
duration: 8min
completed: 2026-05-14
---

# Phase 2 Plan 01: NetworkReader — Real-Time Network Rate Display in Menu Bar

**Network throughput monitoring via `getifaddrs()` byte counters with `SystemConfiguration` primary interface detection, displayed as "↓2.1M ↑512K" in a fixed-width NSStatusItem**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-05-14T07:27:00Z
- **Completed:** 2026-05-14T07:35:00Z
- **Tasks:** 2
- **Files modified:** 5 (2 created, 3 modified)

## Accomplishments

- Full `NetworkReader` extending `TimerReader<NetworkStats>` with 1-second polling, `getifaddrs()` byte counters, `SCDynamicStoreCopyValue` primary interface detection, sleep/wake counter reset, and delta-based rate calculation with `Int64` wraparound safety
- `ByteFormatting` utility with `ByteCountFormatter`-based `formatNetworkCompact` ("↓2.1M ↑512K") and `formatMemoryCompact` ("MEM 8.2G/16G") — zero external dependencies
- `StatusBarManager` network status item: 90pt fixed width, `autosaveName`, 1 KB/s tolerance threshold, placeholder "↓-- ↑--" on startup
- `AppDelegate` wiring: `NetworkReader()` instantiation, `onUpdate → DispatchQueue.main.async → updateNetwork`, lifecycle stop in `applicationWillTerminate`
- `SystemConfiguration.framework` linked in Xcode project to resolve `SCDynamicStoreCopyValue`

## Task Commits

Each task was committed atomically:

1. **Task 1: Create NetworkReader + ByteFormatting utility** — `3d1c7f4` (feat)
2. **Task 2: Extend StatusBarManager + wire NetworkReader in AppDelegate + link SystemConfiguration.framework** — `5f927f6` (feat)

## Files Created/Modified

- `MacStatus/MacStatus/Readers/NetworkReader.swift` — `NetworkStats: Sendable` struct + `NetworkReader: TimerReader<NetworkStats>` with getifaddrs, SCDynamicStoreCopyValue, delta calc, sleep/wake recovery (169 lines)
- `MacStatus/MacStatus/Utils/ByteFormatting.swift` — Free formatting functions using ByteCountFormatter for network rates and memory sizes (58 lines)
- `MacStatus/MacStatus/UI/StatusBarManager.swift` — Added `setupNetworkItem()` and `updateNetwork(_:)` with 90pt fixed-width NSStatusItem, 1 KB/s tolerance, deinit cleanup
- `MacStatus/MacStatus/App/AppDelegate.swift` — Added `networkReader` property, wiring in `applicationDidFinishLaunching`, cleanup in `applicationWillTerminate`
- `MacStatus/MacStatus.xcodeproj/project.pbxproj` — Added NetworkReader.swift and ByteFormatting.swift to Groups/Sources; linked SystemConfiguration.framework in Frameworks

## Decisions Made

None — followed plan as specified. All key decisions (1 KB/s tolerance, delta wraparound handling, per-cycle interface detection, sleep/wake reset) were pre-determined in the PLAN.md from RESEARCH.md and CONTEXT.md.

## Deviations from Plan

None — plan executed exactly as written. Tasks 1 and 2 were inherently coupled for build verification (Task 1 files require pbxproj changes from Task 2 to compile), so both were implemented and verified before committing individually.

## Issues Encountered

- **Pre-existing concurrency warnings (3 total, 0 new):** `TimerReader.swift:60` (2 warnings) and `NetworkReader.swift:64` (1 warning) — these are the standard Swift 6 strict concurrency pattern for `[weak self]` captures in Timer and NSWorkspace closures. Same pattern used in Phase 1 CPUReader. Does not affect build or runtime behavior.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `ByteFormatting.swift` includes `formatMemoryCompact(used:total:)` ready for Plan 02-02 (MemoryReader)
- `StatusBarManager` has `updateNetwork` pattern that `updateMemory` will mirror in Plan 02-02
- `AppDelegate` wiring pattern is established for adding MemoryReader in Plan 02-02
- CPU display continues to function normally alongside network — no Phase 1 regression

---
## Self-Check: PASSED

All 6 files confirmed present on disk. Both commits (3d1c7f4, 5f927f6) confirmed in git log.

---
*Phase: 02-network-memory-monitoring*
*Plan: 01*
*Completed: 2026-05-14*
