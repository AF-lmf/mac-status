# Roadmap: MacStatus

## Overview

MacStatus delivers a macOS menu bar system monitor in five risk-ascending phases. Starting with the simplest, best-documented metric (CPU) to validate the entire Reader→Widget pipeline, then layering on network+memory (most user-visible differentiators), isolated GPU (riskiest metric), combined display polish (core UX differentiator), and finally launch-at-login quality-of-life features. Each phase delivers an independently verifiable, end-to-end vertical slice the user can see working in their menu bar.

## Phases

- [ ] **Phase 1: Foundation + CPU Monitoring** - Project scaffold, menu bar lifecycle, CPU % display
- [ ] **Phase 2: Network + Memory Monitoring** - Network up/down rates and memory usage display
- [ ] **Phase 3: GPU Monitoring** - GPU utilization and Apple Silicon pressure indicator
- [ ] **Phase 4: Combined Display + Formatting** - Single compact status bar text with all metrics
- [ ] **Phase 5: Launch at Login + Quality of Life** - Auto-start, sleep/wake recovery, right-click menu

## Phase Details

### Phase 1: Foundation + CPU Monitoring
**Goal**: User can see real-time CPU usage in the menu bar with zero-config startup
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: CPU-01, CPU-02, LIFE-01, LIFE-03
**Success Criteria** (what must be TRUE):
  1. App launches and immediately shows CPU usage % in the menu bar — no setup or configuration required
  2. CPU reading updates every 1-3 seconds while keeping app CPU overhead under 1%
  3. App runs purely as a menu bar item with no Dock icon visible (LSUIElement behavior)
  4. Menu bar text color automatically adapts to current system appearance (light/dark mode)
**Plans:** 1/2 plans executed

Plans:
- [x] 01-01-PLAN.md — Walking skeleton: Xcode project + inline NSStatusBar + CPU reader → "CPU XX%" in menu bar
- [x] 01-02-PLAN.md — Architecture extraction: CPUReader, StatusBarManager, ReaderProtocol, TimerReader, SettingsManager → production-quality structure

**UI hint**: yes

### Phase 2: Network + Memory Monitoring
**Goal**: User can see real-time network speed and memory usage alongside CPU in the menu bar
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: NETW-01, NETW-02, NETW-03, MEM-01
**Success Criteria** (what must be TRUE):
  1. User can see network download and upload rates updating in real time with appropriate units (KB/s or MB/s)
  2. User can see memory usage displayed as used/total (e.g., "8.2G/16G")
  3. App correctly detects and monitors the active network interface (Wi-Fi, Ethernet, Thunderbolt) without manual configuration
  4. CPU, network, and memory metrics all display concurrently in the menu bar
**Plans**: TBD

### Phase 3: GPU Monitoring
**Goal**: User can see GPU usage (and pressure indicator on Apple Silicon) in the menu bar
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: GPU-01, GPU-02, GPU-03
**Success Criteria** (what must be TRUE):
  1. User can see GPU utilization % updating in the menu bar on Apple Silicon Macs
  2. On Apple Silicon, GPU pressure indicator (green/yellow/red) is visible in the status bar
  3. On Intel Macs, GPU either shows utilization % or gracefully displays "--" without crashing
  4. CPU, network, and memory metrics continue functioning regardless of GPU data availability
**Plans**: TBD

### Phase 4: Combined Display + Formatting
**Goal**: All four metrics display as one compact, stable menu bar text — the core UX differentiator
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: DISP-01, DISP-02, DISP-03, DISP-04
**Success Criteria** (what must be TRUE):
  1. All metrics appear in a single compact menu bar item (e.g., "CPU 12% · MEM 8.2G · ↓2.1M ↑512K · GPU 34%")
  2. Menu bar text width stays fixed even when values change — no layout jitter or adjacent macOS icon shifting
  3. Text remains readable and properly colored in both light and dark system appearance modes
  4. When any metric is unavailable, it shows "--" instead of crashing or leaving blank space
**Plans**: TBD
**UI hint**: yes

### Phase 5: Launch at Login + Quality of Life
**Goal**: App auto-starts on login and stays reliable across sleep/wake cycles
**Mode:** mvp
**Depends on**: Phase 4
**Requirements**: LIFE-02, LIFE-04
**Success Criteria** (what must be TRUE):
  1. App automatically launches when user logs in to their Mac (SMAppService)
  2. Right-clicking the status bar item shows a menu with at minimum a Quit option
  3. CPU, network, memory, and GPU readings resume correctly after Mac wakes from sleep
  4. App maintains under 1% CPU overhead during extended operation (30+ minutes of continuous monitoring)
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation + CPU Monitoring | 1/2 | In Progress|  |
| 2. Network + Memory Monitoring | 0/TBD | Not started | - |
| 3. GPU Monitoring | 0/TBD | Not started | - |
| 4. Combined Display + Formatting | 0/TBD | Not started | - |
| 5. Launch at Login + QoL | 0/TBD | Not started | - |
