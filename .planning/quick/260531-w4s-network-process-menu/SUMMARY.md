---
quick_id: 260531-w4s
status: complete
completed: 2026-05-31
---

# Summary

Implemented an on-click menu section for the MacStatus status item that samples per-process network activity and displays the current top process.

## Changes

- Added `ProcessNetworkReader`, an on-demand `nettop` CSV delta sampler for per-process network usage.
- Extended the existing status bar menu with a network process section showing process name, PID, download, upload, total rate, and update time.
- Kept per-process sampling tied to menu open so normal menu bar polling remains low overhead.
- Added compact `/s` rate formatting for menu rows.

## Verification

- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build.noindex CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- build`
- Installed and opened `/Applications/MacStatus.app`.
- Clicked the status item through Accessibility and verified the menu rendered a live top process entry, e.g. `verge-mihomo (PID 1132), ↓ 247K/s, ↑ 239K/s, 总计 486K/s`.
