# Milestones

## v2.0 洞察与可定制 (Shipped: 2026-06-23)

**Phases completed:** 4 phases, 10 plans, 9 tasks

**Key accomplishments:**

- 一句话总结：
- 一句话总结：
- 一句话总结：
- Task 1 — MetricCollector 接入
- 一句话概述：
- 一句话概述：
- 一句话摘要：
- 一句话摘要：
- 一句话摘要：

---

## v1.0 MVP (Shipped: 2026-06-10)

**Phases completed:** 5 phases, 9 plans, 18 tasks

**Key accomplishments:**

- Buildable menu bar app showing live "CPU XX%" via host_statistics Mach kernel API on background queue with monospaced digits and dark/light mode adaptation
- Inline walking-skeleton code extracted into 5 properly separated classes following D-02 folder structure, with Swift 6 Sendable compliance, macOS 26 privacy gate detection, and production-grade status bar lifecycle
- Network throughput monitoring via `getifaddrs()` byte counters with `SystemConfiguration` primary interface detection, displayed as "↓2.1M ↑512K" in a fixed-width NSStatusItem
- One-liner:
- Visible menu bar display now renders CPU, network, and memory together through the same combined status item.
- IOKit-backed GPU reader with utilization extraction, Apple Silicon pressure model, and Xcode project linkage
- GPUReader wired into the single visible menu bar item with compact labels, GPU fallback, and GPU-only pressure color
- Value-level menu bar coloring for CPU, GPU, and memory while preserving one fixed-width combined status item
- Lifecycle polish for v1: login item registration, right-click Quit, and sleep/wake reader recovery

---
