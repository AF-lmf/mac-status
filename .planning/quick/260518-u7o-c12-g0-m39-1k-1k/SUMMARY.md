---
quick_id: 260518-u7o
slug: c12-g0-m39-1k-1k
status: complete
completed: 2026-05-18
commit: da37905
---

# Quick Task Summary: Compact Menu Bar Format

## Result

Changed the visible menu bar format to the compact style `C12 G0 M39 ↓1K ↑1K`.

## Files Changed

- `MacStatus/MacStatus/UI/StatusBarManager.swift`
- `MacStatus/MacStatus/Utils/ByteFormatting.swift`

## Behavior

- CPU, GPU, and memory now render without internal spaces or percent signs.
- Metric separators are single spaces instead of pipes.
- The combined status item fixed width was reduced from 300pt to 210pt.
- Memory pressure still appears through the existing value color rules.
- Network values trim `.0`, so `1.0K` renders as `1K`.

## Verification

- Ran `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build`.
- Build succeeded.
