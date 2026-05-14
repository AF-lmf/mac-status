---
status: complete
quick_id: 260514-r6z
completed: 2026-05-14
commit: ddf9307
---

# Quick Task 260514-r6z: 修复 CPU 状态不显示和网络速度换行溢出

## Result

Fixed the status bar display issues reported by the user:

- Restored the CPU status item to `NSStatusItem.variableLength` so the CPU label is not constrained by the accidental 70pt fixed width.
- Forced status item buttons to render as single-line clipped text instead of wrapping.
- Shortened byte formatting so network components stay compact, e.g. `↓9.8M ↑512K`, `↓10M ↑999M`.

## Files Changed

- `MacStatus/MacStatus/UI/StatusBarManager.swift`
- `MacStatus/MacStatus/Utils/ByteFormatting.swift`

## Verification

- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` passed.
- Direct `host_statistics(HOST_CPU_LOAD_INFO)` smoke check returned `KERN_SUCCESS`, confirming the CPU data source is available on this machine.

