---
quick_id: 260531-w4s
status: complete
created: 2026-05-31
---

# Quick Task: Network Process Menu

Add an on-click status bar dropdown that shows the process currently using the most network bandwidth.

## Plan

1. Add an on-demand per-process network sampler using macOS `nettop` CSV delta output.
2. Extend the existing status item menu to show a loading state, then update with the top process name, PID, download, upload, total rate, and timestamp.
3. Keep sampling on menu open only so normal status bar updates remain low overhead.
4. Build the app with `xcodebuild` to verify Swift/Xcode project integration.
