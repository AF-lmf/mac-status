---
status: complete
quick_id: 260514-rj1
completed: 2026-05-14
commit: c9bbf1d
---

# Quick Task 260514-rj1: 把 CPU 并入可见网络菜单栏项显示

## Result

The visible network status item now also shows CPU usage:

- Removed reliance on the separate CPU-only status item, which was not appearing in the menu bar.
- Added cached CPU/network display text in `StatusBarManager`.
- Rendered a combined title on the visible network item, e.g. `CPU 12% ↓1K ↑1K`.
- Increased the visible network item width from 90pt to 160pt and kept single-line clipping.

## Files Changed

- `MacStatus/MacStatus/UI/StatusBarManager.swift`

## Verification

- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build` passed.
- Restarted `build/Build/Products/Debug/MacStatus.app`; new process PID was `10153`.

