---
phase: 03
slug: gpu-monitoring
status: verified
threats_open: 0
asvs_level: 1
created: 2026-05-14
register_authored_at_plan_time: true
---

# Phase 03 - Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| macOS IOKit -> MacStatus process | `GPUReader` reads `IOAccelerator` registry properties from the OS. | GPU utilization counters, no user data |
| Reader queue -> Main UI | `GPUReader` runs on the `TimerReader` utility queue and dispatches results to `StatusBarManager` on the main queue. | `GPUStats?` |
| Metric state -> Menu bar text | `StatusBarManager` converts CPU, GPU, memory, and network state into one attributed status item. | Local system telemetry only |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-03-01 | Reliability | `GPUReader` IOKit lookup | mitigate | `IOServiceMatching`, `IOServiceGetMatchingServices`, and `PerformanceStatistics` reads are guarded; unavailable data sends `onUpdate?(nil)`. | closed |
| T-03-02 | Resource management | `GPUReader` polling loop | mitigate | The iterator and each service are released with `IOObjectRelease` during every read cycle. | closed |
| T-03-03 | Availability | `GPUReader` polling thread | mitigate | `GPUReader` inherits `TimerReader`, whose `DispatchSourceTimer` runs on a `.utility` serial queue. | closed |
| T-03-04 | Integrity | GPU fallback value | mitigate | Failure paths send `nil`, and `StatusBarManager.updateGPU(nil)` displays `G --` instead of a stale utilization value. | closed |
| T-03-05 | Availability | Combined status item | mitigate | `updateGPU(nil)` updates only GPU text/pressure state and refreshes the existing combined item. | closed |
| T-03-06 | Usability | GPU pressure colors | mitigate | GPU pressure uses AppKit system colors; default text and separators use `NSColor.labelColor`. | closed |
| T-03-07 | Usability | Segment styling | mitigate | Only `latestGPUText` is rendered with `gpuAttributes()`; CPU, memory, network, and separators use base attributes. | closed |
| T-03-08 | Usability | Menu bar layout stability | mitigate | The GPU segment is never hidden and the visible status item uses fixed width `300`. | closed |

---

## Accepted Risks Log

No accepted risks.

---

## Evidence

| Threat ID | Evidence |
|-----------|----------|
| T-03-01 | `GPUReader.read()` uses guarded optional matching/service/property reads and calls `onUpdate?(nil)` on failure. |
| T-03-02 | `GPUReader.read()` has `defer { IOObjectRelease(iterator) }` and releases each `service` in the loop. |
| T-03-03 | `TimerReader` owns `DispatchQueue(label: "com.macstatus.reader", qos: .utility)` and invokes `read()` from its timer event handler. |
| T-03-04 | `GPUReader` sends `nil` when no utilization is found; `StatusBarManager.updateGPU(nil)` sets `latestGPUText = "G --"`. |
| T-03-05 | `AppDelegate` routes `gpuReader?.onUpdate` to `statusBarManager?.updateGPU(stats)` on the main queue; no separate GPU status item is created. |
| T-03-06 | `StatusBarManager.gpuPressureColor()` returns `NSColor.systemGreen`, `systemYellow`, or `systemRed`; `baseAttributes()` uses `NSColor.labelColor`. |
| T-03-07 | `combinedAttributedString()` appends only `latestGPUText` with `gpuAttributes()`; all other segments use `baseAttributes()`. |
| T-03-08 | `setupNetworkItem()` uses `NSStatusBar.system.statusItem(withLength: 300)` and `updateGPU(nil)` keeps `G --` visible. |

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-05-14 | 8 | 8 | 0 | Codex |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-05-14
