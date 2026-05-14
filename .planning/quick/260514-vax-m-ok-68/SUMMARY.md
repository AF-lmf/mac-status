---
quick_id: 260514-vax
slug: m-ok-68
status: complete
completed: 2026-05-14
commit: 0b4b1fa
---

# Quick Task Summary: Memory Display as `M OK 68%`

## Result

Changed the memory segment to show both pressure and estimated physical memory usage percentage.

## Files Changed

- `MacStatus/MacStatus/Readers/MemoryReader.swift`
- `MacStatus/MacStatus/Utils/ByteFormatting.swift`
- `MacStatus/MacStatus/UI/StatusBarManager.swift`

## Behavior

- Normal pressure now renders like `M OK 68%`.
- Warning pressure renders like `M WARN 82%`.
- Critical pressure renders like `M CRIT 91%`.
- If usage percentage cannot be read, the segment falls back to `--%` while preserving pressure, e.g. `M OK --%`.
- If pressure is unavailable, the existing `M --` fallback remains.

## Verification

- Ran `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build`.
- Build succeeded.
- Restarted the Debug app; running PID after restart: `37081`.
