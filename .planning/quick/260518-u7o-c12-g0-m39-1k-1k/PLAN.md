---
quick_id: 260518-u7o
slug: c12-g0-m39-1k-1k
status: planned
created: 2026-05-18
files_modified:
  - MacStatus/MacStatus/UI/StatusBarManager.swift
  - MacStatus/MacStatus/Utils/ByteFormatting.swift
---

# Quick Task: Compact Menu Bar Format

## Goal

Change the visible menu bar text to the compact form `C12 G0 M39 ↓1K ↑1K` without reducing metric coverage.

## Tasks

1. Compact CPU, GPU, and memory segments by removing internal spaces and percent signs.
2. Replace pipe separators with single spaces and reduce the fixed `NSStatusItem` width to match the shorter format.
3. Trim `.0` from compact network units so `1.0K` renders as `1K`.

## Verification

```bash
xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build
```
