# Roadmap: MacStatus

## Milestones

- ✅ **v1.0 MVP** — Phases 1-5 (shipped 2026-06-10)
- 🟡 **v2.0 洞察与可定制 (Insight & Customization)** — Phases 6-9 (planning)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-5) — SHIPPED 2026-06-10</summary>

- [x] Phase 1: Foundation + CPU Monitoring (2/2 plans) — completed 2026-05-14
- [x] Phase 2: Network + Memory Monitoring (3/3 plans) — completed 2026-05-14
- [x] Phase 3: GPU Monitoring (2/2 plans) — completed 2026-05-14
- [x] Phase 4: Combined Display + Formatting (1/1 plan) — completed 2026-05-14
- [x] Phase 5: Launch at Login + Quality of Life (1/1 plan) — completed 2026-05-14

</details>

### v2.0 洞察与可定制 (Insight & Customization)

**Milestone goal:** 把 MacStatus 从"看一眼系统状态"升级为"看明白哪个进程在吃资源、看到电池全貌，并按我自己的方式配置"。

- [x] **Phase 6: Settings Foundation + Live Re-apply Seam** - 单一 SettingsManager 真源、持久化与"改即生效"的实时重应用通道 — ✅ completed 2026-06-17 (3/3 plans, 验证通过)
- [x] **Phase 7: Battery & Power** - 弹窗内电量/充电状态/功率/剩余时间/健康度，台式机优雅降级 — ✅ completed 2026-06-17 (2/2 plans, 静态验证通过, 人工 UAT 延后)
- [x] **Phase 8: Per-Process Top-N CPU & Memory** - 弹窗打开时按需采样 CPU/内存占用最高的进程 — ✅ completed 2026-06-17 (2/2 plans, 静态验证通过, 人工 UAT 延后)
- [ ] **Phase 9: Settings Window UI + Customization** - 独立设置窗口：开关、拖动排序、阈值、配色、紧凑/详细模式

## Phase Details

<details>
<summary>✅ v1.0 MVP Phase Details (Phases 1-5) — see milestones/ archive for full criteria</summary>

Phases 1-5 delivered the shipped v1.0 MVP: single combined fixed-width status-bar item rendering CPU / GPU / memory-pressure / network with value-level coloring, dark/light adaptation, graceful degradation, launch-at-login, right-click Quit, and sleep/wake reader recovery. Full per-phase detail is archived under `.planning/milestones/`.

</details>

### Phase 6: Settings Foundation + Live Re-apply Seam
**Goal**: A single typed `SettingsManager` becomes the one source of truth, preferences survive restart, and changing a preference takes effect immediately without relaunch — establishing the plumbing every customizable feature depends on.
**Depends on**: v1.0 (Phases 1-5)
**Requirements**: SET-07, SET-08
**Success Criteria** (what must be TRUE):
  1. All settings read and write through one `SettingsManager` — the `SettingsView` `@AppStorage` duplication is gone, so there is no longer a second source of truth that can drift (testable: changing a preference is observed identically by `MetricCollector` and `StatusBarManager`).
  2. Every preference (existing + new keys: `metricOrder`, per-metric enabled-set, custom thresholds, custom colors, compact/verbose mode) persists across an app quit-and-relaunch via versioned `UserDefaults` storage (a `schemaVersion` exists so future key additions migrate cleanly).
  3. Changing a setting re-applies live without relaunch: a `SettingsManager` change broadcast triggers `MetricCollector.applyNow()` (re-push the last sample) and `reconfigure()` when timing changes, so the status bar and popover reflect the change on the next forced refresh, not after a restart.
  4. `StatusBarManager.updateTitle` honors an enabled-set and `metricOrder` by conditionally composing segments on the single combined `NSStatusItem` (never adding/removing status items), and `colorForUsage` reads custom thresholds/colors live — the seam that Phase 9's controls will drive.
**Plans**: 3 plans
Plans:
- [x] 06-01-PLAN.md — Metric 枚举 + SettingsManager 重构（@Observable + 版本化存储 + 新键）
- [x] 06-02-PLAN.md — MetricCollector reconfigure/applyNow/observer + SettingsView @AppStorage 消除
- [x] 06-03-PLAN.md — NSColor+Hex 扩展 + StatusBarManager 启用集/顺序接缝 + colorForUsage 实时阈值/配色

### Phase 7: Battery & Power
**Goal**: On laptops the user can open the popover and see a complete battery picture — charge %, charging state, time remaining, real-time power draw, and health — while desktop Macs hide the whole battery section cleanly.
**Depends on**: Phase 6
**Requirements**: BATT-01, BATT-02, BATT-03, BATT-04, BATT-05
**Success Criteria** (what must be TRUE):
  1. The popover shows battery charge percentage and charging state (充电中 / 已充满 / 使用电池) sourced from IOKit Power Sources.
  2. The popover shows estimated time remaining (or time-to-full while charging), rendering a "计算中" state for the `-1`/`-2` sentinels rather than a wrong number.
  3. The popover shows real-time charge/discharge power in Watts (signed: + charging, − discharging) and battery health (max-capacity %) with cycle count, each degrading to "—" when the model's `AppleSmartBattery` keys are unreadable rather than showing a fake value.
  4. On a desktop Mac (no battery present) the entire battery section is hidden — no empty fields, no zero/placeholder values — using the proven v1.0 GPU nil-degradation pattern.
  5. The new `BatteryReader` emits only `Sendable` snapshots across actor boundaries and rejoins the v1.0 sleep/wake recovery chain (delaying trust in post-wake estimates), so readings recover correctly after sleep.
**Plans**: 2 plans
Plans:
- [x] 07-01-PLAN.md — BatterySnapshot struct + BatteryReader class（IOKit 双层读取、probe-and-nil、sleep/wake 观察器）
- [x] 07-02-PLAN.md — MetricCollector 接入 + DashboardState 电池字段 + DashboardView 电池区块

### Phase 8: Per-Process Top-N CPU & Memory
**Goal**: When the user opens the popover they can see which 3-5 processes are consuming the most CPU and the most memory right now, and that sampling stops the moment the popover closes so there is no 24/7 background cost.
**Depends on**: Phase 6
**Requirements**: PROC-01, PROC-02, PROC-03
**Success Criteria** (what must be TRUE):
  1. With the popover open, the user sees the top 3-5 processes by CPU usage (process name + CPU%), where CPU% is a wall-clock delta between two `libproc` snapshots (first frame may show "—"), never cumulative rusage.
  2. With the popover open, the user sees the top 3-5 processes by resident memory (process name + memory), reusing the generalized process-list row alongside the existing network Top-N.
  3. Per-process sampling runs only while the popover is visible (off-main `Task.detached`, gated like `ProcessNetworkReader`) and is cancelled on popover close — verifiable as no measurable CPU cost while the popover is shut.
  4. The sampler is `task_for_pid`-free (`libproc` only, no new entitlement), handles PID disappearance/reuse via a `(pid, start-time)` key with `max(delta,0)`, and returns only `Sendable` snapshots across the actor boundary.
**Plans**: 2 plans
Plans:
- [x] 08-01-PLAN.md — ProcessResourceReader.swift（libproc 采样引擎 + proc_pid_rusage + snapshot diff + pbxproj 注册）
- [x] 08-02-PLAN.md — PopoverManager 采样循环启停 + DashboardState 新字段 + DashboardView CPU/内存 Top 5 区块 + ProcessMetricRow 泛化

### Phase 9: Settings Window UI + Customization
**Goal**: From the right-click menu the user opens a real settings window and can directly toggle which metrics show, drag to reorder them, set custom thresholds and colors, and switch between compact and verbose status-bar modes — each change visible immediately.
**Depends on**: Phase 6, Phase 7, Phase 8
**Requirements**: SET-01, SET-02, SET-03, SET-04, SET-05, SET-06
**Success Criteria** (what must be TRUE):
  1. The user opens a dedicated settings window from the right-click menu (NSWindow + NSHostingView; the `LSUIElement` app cannot use the SwiftUI `Settings` scene).
  2. The user toggles any metric on/off and drag-reorders metrics in a SwiftUI `List{}.onMove`; the combined status-bar segment appears/disappears and reorders immediately via the Phase 6 enabled-set/`metricOrder` seam (battery and process toggles included).
  3. The user sets custom warning/danger thresholds and custom colors per metric via `ColorPicker`/editors, and the status-bar value-level coloring updates immediately.
  4. The user switches between 紧凑 and 详细 status-bar text modes and sees the change apply at once, with all of the above persisting across restart (no raw `@AppStorage` re-introduced — every control is bound to the Phase 6 `SettingsManager`).
**Plans**: 3 plans
Plans:
- [x] 09-01-PLAN.md — SettingsManager 新增 showBatterySection/showProcessSection bool 键
- [x] 09-02-PLAN.md — SettingsView 重构：状态栏指标 List.onMove + 弹窗区块 Toggles + 文字模式 Picker
- [x] 09-03-PLAN.md — SettingsView 告警阈值/配色 Section + DashboardView 可见性门控

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation + CPU Monitoring | v1.0 | 2/2 | Complete | 2026-05-14 |
| 2. Network + Memory Monitoring | v1.0 | 3/3 | Complete | 2026-05-14 |
| 3. GPU Monitoring | v1.0 | 2/2 | Complete | 2026-05-14 |
| 4. Combined Display + Formatting | v1.0 | 1/1 | Complete | 2026-05-14 |
| 5. Launch at Login + QoL | v1.0 | 1/1 | Complete | 2026-05-14 |
| 6. Settings Foundation + Live Re-apply Seam | v2.0 | 3/3 | Complete   | 2026-06-16 |
| 7. Battery & Power | v2.0 | 0/2 | Not started | - |
| 8. Per-Process Top-N CPU & Memory | v2.0 | 2/2 | Complete   | 2026-06-17 |
| 9. Settings Window UI + Customization | v2.0 | 3/3 | Complete   | 2026-06-17 |
