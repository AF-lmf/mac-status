---
quick_id: 260514-vax
slug: m-ok-68
status: planned
created: 2026-05-14
files_modified:
  - MacStatus/MacStatus/Readers/MemoryReader.swift
  - MacStatus/MacStatus/Utils/ByteFormatting.swift
  - MacStatus/MacStatus/UI/StatusBarManager.swift
---

# Quick Task: Memory Display as `M OK 68%`

## Goal

Change the menu bar memory segment from pressure-only text like `M OK` to pressure plus memory usage percent, e.g. `M OK 68%`.

## Tasks

1. Extend `MemoryStats` and `MemoryReader` to include an estimated memory used percentage.
2. Update memory formatting to render `M OK 68%`, `M WARN 82%`, `M CRIT 91%`, or graceful fallbacks.
3. Update `StatusBarManager` memory redraw logic so only changed rounded memory text redraws.
4. Build and restart the Debug app.

## Verification

```bash
xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build
```
