---
status: diagnosed
phase: 02-network-memory-monitoring
source:
  - 02-01-SUMMARY.md
  - 02-02-SUMMARY.md
started: 2026-05-14T11:53:55Z
updated: 2026-05-14T12:01:28Z
---

## Current Test

[testing complete]

## Tests

### 1. Menu Bar Metrics Visible
expected: The menu bar shows live CPU and network text together in the visible network item, such as "CPU 12% ↓1K ↑1K", and also shows memory as "MEM used/total" nearby. Text stays on one line without vertical overflow.
result: issue
reported: "mem没有显示"
severity: major

### 2. Network Rate Updates
expected: When network activity changes, the download and upload values in the menu bar update within about one second and remain compact.
result: pass

### 3. Memory Usage Display
expected: The menu bar memory item shows used/total memory, such as "MEM 8.2G/16G", and remains visible alongside the CPU/network item.
result: issue
reported: "没显示"
severity: major

### 4. Active Network Interface
expected: The app monitors the currently active network interface without manual configuration; after changing Wi-Fi/Ethernet/VPN state, rates recover instead of staying blank.
result: pass

## Summary

total: 4
passed: 2
issues: 2
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "The menu bar shows live CPU and network text together in the visible network item, such as \"CPU 12% ↓1K ↑1K\", and also shows memory as \"MEM used/total\" nearby. Text stays on one line without vertical overflow."
  status: failed
  reason: "User reported: mem没有显示"
  severity: major
  test: 1
  root_cause: "StatusBarManager writes memory text to a separate memoryStatusItem, but this user's menu bar is only showing the networkStatusItem. The same independent-status-item visibility issue affected CPU, which was fixed by merging CPU text into the visible network item."
  artifacts:
    - path: "MacStatus/MacStatus/UI/StatusBarManager.swift"
      issue: "latest combined status includes CPU + network only; memory remains rendered to separate memoryStatusItem"
  missing:
    - "Track latest memory text in StatusBarManager"
    - "Append memory text to the visible combined networkStatusItem title"
    - "Avoid relying on the independent memoryStatusItem for the user-visible Phase 2 display"
  debug_session: "inline-UAT-diagnosis-2026-05-14"
- truth: "The menu bar memory item shows used/total memory, such as \"MEM 8.2G/16G\", and remains visible alongside the CPU/network item."
  status: failed
  reason: "User reported: 没显示"
  severity: major
  test: 3
  root_cause: "MemoryReader is wired, but StatusBarManager displays memory through a separate NSStatusItem that is not visible in the user's menu bar. The visible combined item currently omits memory."
  artifacts:
    - path: "MacStatus/MacStatus/UI/StatusBarManager.swift"
      issue: "updateMemory(_:) calls setTitle(..., on: memoryStatusItem) instead of updating the combined visible status"
  missing:
    - "Include memory text in updateCombinedStatus()"
    - "Update combined status when memory readings arrive or fail"
  debug_session: "inline-UAT-diagnosis-2026-05-14"
