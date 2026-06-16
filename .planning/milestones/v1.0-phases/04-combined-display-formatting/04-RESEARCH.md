# Phase 4: Combined Display + Formatting - Research

**Date:** 2026-05-14
**Phase:** 04-combined-display-formatting
**Question:** What do we need to know to plan the final combined menu bar formatting well?

## RESEARCH COMPLETE

## Executive Summary

Phase 4 is a presentation-only polish pass. The existing app already has a single visible combined `NSStatusItem` with CPU, GPU, memory, and network segments in the target order. The remaining work is to make the attributed title match the user-approved color contract:

`C 12% | G 34% | M OK | ↓2.1M ↑512K`

Only the value/status portions are colored. Labels, separators, network text, and normal/default values use `NSColor.labelColor`. CPU and GPU share thresholds: `<60%` default, `60..<85%` yellow, `>=85%` red. Memory uses pressure state: `OK` default, `WARN` yellow, `CRIT` red.

## Existing Implementation

### StatusBarManager

`MacStatus/MacStatus/UI/StatusBarManager.swift` is already the correct integration point:

- `networkStatusItem` is the only visible combined status item.
- `setupNetworkItem()` creates it with fixed width `300`.
- `configureStatusButton(_:)` sets clipping, single-line mode, and no wrapping.
- `combinedAttributedString()` already appends CPU, GPU, memory, and network segments.
- `baseAttributes()` already uses monospaced digits and `NSColor.labelColor`.

The current gap is that CPU and memory use all-default attributes, while GPU uses `gpuPressureColor()` on the entire GPU segment and maps normal pressure to green. Phase 4 must replace that segment-level coloring with value-level coloring.

### State Needed For Coloring

Current latest text strings are enough for the plain title, but safer attributed coloring needs raw state:

- CPU: keep `latestCPUUsage: Double?`
- GPU: keep `latestGPUUsage: Double?`
- Memory: keep `latestMemoryPressure: MemoryPressureLevel?`

Fallback updates should reset the matching raw state to `nil`, while preserving fallback text:

- `C --%`
- `G --`
- `M --`
- `↓-- ↑--`

## Recommended Technical Approach

Use small local helpers in `StatusBarManager`:

- `usageColor(for value: Double?) -> NSColor?`
  - `nil` or `<60` returns `nil` so base default color is used.
  - `60..<85` returns `.systemYellow`.
  - `>=85` returns `.systemRed`.
- `memoryColor(for level: MemoryPressureLevel?) -> NSColor?`
  - `.warning` returns `.systemYellow`.
  - `.critical` returns `.systemRed`.
  - `.normal`, `.unknown`, and `nil` return `nil`.
- `metricAttributes(valueColor:)` overlays foreground color only when a warning/critical color is present.
- `appendMetric(label:value:valueColor:to:)` appends label and space with base attributes, then appends value/status with value attributes.

This keeps the implementation inside `StatusBarManager`, avoids parsing formatted strings, and maintains the existing reader and formatter boundaries.

## Risks And Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Coloring the entire `G 34%` segment violates D-02/D-04 | Medium | Build attributed segments as label + value, not one string |
| GPU normal stays green from Phase 3 | Medium | Remove or replace green `.normal` mapping; use utilization thresholds instead |
| Fallback values accidentally inherit stale color | High | Reset raw CPU/GPU/MEM state to `nil` when the metric update is unavailable |
| Fixed width changes create layout jitter | Medium | Keep `NSStatusBar.system.statusItem(withLength: 300)` |
| Light/dark mode readability regresses | Medium | Use system colors only: `labelColor`, `systemYellow`, `systemRed` |

## Recommended Plan Split

One plan is sufficient because Phase 4 touches a single production file and is presentation-only:

- `04-01-PLAN.md`: Implement value-level colors, raw metric state, fallback reset, source checks, build, and smoke launch.

## Validation Strategy

Run:

`xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build`

Source assertions:

- `StatusBarManager.swift` contains `latestCPUUsage`, `latestGPUUsage`, and `latestMemoryPressure`.
- `usageColor(for:)` maps `..<60` to default, `..<85` to yellow, and default to red.
- `memoryColor(for:)` maps warning to yellow and critical to red.
- `combinedAttributedString()` uses label/value appending helpers rather than coloring whole CPU/GPU/MEM segments.
- `setupNetworkItem()` still uses fixed width `300`.

Manual smoke:

- Launch the Debug app and confirm one visible menu bar item appears.
- Confirm all segments remain present even while GPU or network data is unavailable.
