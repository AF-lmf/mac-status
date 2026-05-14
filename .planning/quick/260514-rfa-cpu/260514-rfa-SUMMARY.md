---
status: complete
quick_id: 260514-rfa
completed: 2026-05-14
commit: c9f03bd
---

# Quick Task 260514-rfa: 继续修复 CPU 状态不显示

## Result

Made status item text assignment more robust:

- Every status item is explicitly marked visible after creation.
- Text updates now set both `NSStatusBarButton.title` and `attributedTitle`.
- This gives the variable-width CPU item a normal title for AppKit sizing while preserving the styled attributed text.

## Files Changed

- `MacStatus/MacStatus/UI/StatusBarManager.swift`

## Verification

- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` passed.
- Restarted `build/Build/Products/Debug/MacStatus.app`; new process PID was `9734`.

