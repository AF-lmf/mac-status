# Phase 3: GPU Monitoring - Research

**Date:** 2026-05-14
**Phase:** 03-gpu-monitoring
**Question:** What do we need to know to plan GPU monitoring well?

## RESEARCH COMPLETE

## Executive Summary

Phase 3 should add GPU as an isolated reader slice, then wire it into the existing visible combined status item. The lowest-risk v1 path is:

1. Add `GPUReader: TimerReader<GPUStats>` using IOKit `IOAccelerator` registry entries and `PerformanceStatistics`.
2. Return `nil` if no GPU utilization key is available, so the UI displays `G --`.
3. Use a v1 Apple Silicon pressure indicator derived from current GPU utilization thresholds unless native pressure keys are discovered during implementation.
4. Keep pressure presentation in `StatusBarManager`, coloring only the `G 34%` segment.

This keeps GPU isolated from CPU/network/memory. If GPU APIs are unavailable on a Mac, the existing metrics keep working.

## Required Behavior

### Requirements
- **GPU-01:** GPU utilization percentage appears in the menu bar.
- **GPU-02:** Apple Silicon shows a green/yellow/red GPU pressure indicator.
- **GPU-03:** Intel gracefully degrades to utilization or `G --`; it must never crash.

### User Decisions From CONTEXT.md
- `D-01`: GPU normal display is `G 34%`.
- `D-02`: GPU unavailable display is `G --`.
- `D-03`: Existing labels shorten from `CPU` to `C` and `MEM` to `M`.
- `D-04`: Apple Silicon GPU pressure is expressed by coloring the `G 34%` segment.
- `D-05`: CPU/MEM coloring is deferred to Phase 4.
- `D-06`: Display order is `C 12% | G 34% | M OK | ↓2.1M ↑512K`.

## Technical Approach

### GPU Utilization

Use IOKit, not `Process()` or command-line tools. Query services matching `IOAccelerator`, read each service's `PerformanceStatistics` dictionary, and extract the first usable utilization value from known keys:

- `Device Utilization %`
- `GPU Activity(%)`
- `Renderer Utilization %`
- `Tiler Utilization %`

Different macOS versions and GPU families expose different keys. The reader should probe multiple keys and clamp values into `0...100`. If multiple GPU services expose values, use the highest valid value as the aggregate display value for v1.

### GPU Pressure

Native GPU pressure via IOReport is sparsely documented and may require key discovery. For this phase, the executable plan should implement a pressure indicator that is reliable enough for v1:

- Detect Apple Silicon with `sysctlbyname("hw.optional.arm64")`.
- If Apple Silicon and utilization is available, map utilization to pressure:
  - `< 60%` -> normal
  - `60%..<85%` -> warning
  - `>= 85%` -> critical
- If no utilization is available, pressure is unavailable and UI shows `G --`.
- If implementation discovers a native IOKit/IOReport pressure key cheaply, it may use it behind the same `GPUPressureLevel` model, but the plan must not depend on undocumented keys to pass.

This satisfies the menu bar pressure indicator requirement without making the phase hinge on reverse-engineering a private metric.

### Swift Model

Recommended types:

```swift
enum GPUPressureLevel: Sendable, Equatable {
    case normal
    case warning
    case critical
}

struct GPUStats: Sendable, Equatable {
    let utilizationPercent: Double
    let pressureLevel: GPUPressureLevel?
}
```

Return `GPUStats?` from `GPUReader` through `onUpdate`; `nil` means unavailable.

### Framework / Build Changes

The Xcode project currently links `SystemConfiguration.framework` only. Phase 3 must add:

- `MacStatus/MacStatus/Readers/GPUReader.swift` to the Readers group and Sources build phase.
- `IOKit.framework` to the Frameworks build phase.

There is no App Sandbox entitlement file in the current project. Do not add sandboxing in Phase 3.

## Existing Code Integration

### Reader Layer
- `TimerReader<T>` already provides background `DispatchSourceTimer` polling on `.utility`.
- `CPUReader`, `NetworkReader`, and `MemoryReader` establish the pattern: read system API in `read()`, call `onUpdate?(value)` or `onUpdate?(nil)`.
- GPU should use a 2-second polling interval to avoid energy overhead.

### Wiring Layer
- `AppDelegate` is the thin wiring hub.
- Add `private var gpuReader: GPUReader?`.
- In `applicationDidFinishLaunching`, assign `gpuReader?.onUpdate` and dispatch UI updates to main queue.
- In `applicationWillTerminate`, stop and nil out `gpuReader`.

### Presentation Layer
- `StatusBarManager` currently renders the visible combined text through `networkStatusItem`.
- Add `latestGPUText = "G --"` and `latestGPUPressure: GPUPressureLevel?`.
- Change CPU format from `CPU %.0f%%` to `C %.0f%%`.
- Change memory formatter from `MEM OK/WARN/CRIT` to `M OK/WARN/CRIT`.
- Update combined order to `C | G | M | network`.
- Replace all-one-color `attributedString(_:)` for combined text with a segment-aware attributed string where only the GPU segment receives pressure color.

## Risks And Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| IOKit key variation | GPU utilization may be unavailable on some Macs | Probe multiple `PerformanceStatistics` keys; fallback to `nil` and `G --` |
| Undocumented pressure metric | Native pressure may not be accessible | Use utilization-threshold pressure indicator for v1; keep model extensible |
| IOKit on main thread | UI jank | Read only in `GPUReader.read()` on `TimerReader` background queue |
| App Sandbox | IOKit may be blocked if sandbox is enabled later | Do not add sandboxing in Phase 3; document fallback |
| Status item width | Combined string may clip | Keep short labels and increase fixed width conservatively |

## Recommended Plan Split

### Plan 03-01: GPU Reader Vertical Slice
Create `GPUReader.swift`, add `IOKit.framework`, add the file to the Xcode project, and verify the app builds. This plan covers the data source and graceful `nil` fallback.

### Plan 03-02: Visible Menu Bar Integration
Wire `GPUReader` into `AppDelegate`, update `StatusBarManager` and `ByteFormatting` to render `C 12% | G 34% | M OK | ↓2.1M ↑512K`, and color the GPU segment by pressure.

## Validation Strategy

- Build with:
  `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build`
- Source assertions:
  - `GPUReader.swift` imports IOKit and calls `IOServiceGetMatchingServices`.
  - `StatusBarManager.updateCombinedStatus()` includes CPU, GPU, memory, and network in the target order.
  - `ByteFormatting.formatMemoryPressure` returns `M OK`, `M WARN`, `M CRIT`, and `M --`.
  - GPU unavailable path sets `latestGPUText = "G --"`.
- Manual smoke:
  - Launch the Debug app and confirm a visible `G` segment appears.
  - On unsupported hardware/API failure, confirm app still shows CPU, memory, and network.

