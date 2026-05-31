---
quick_id: 260531-wb7
status: complete
completed: 2026-05-31
---

# Summary

Adjusted the network process dropdown to show the current top five processes, one process per row.

## Changes

- Changed `ProcessNetworkReader` to return a sorted top-five process list.
- Removed total-rate and update-time rows from the dropdown.
- Reformatted each process row as `process name  ↑ upload  ↓ download`.

## Verification

- `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build.noindex CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- build`
- Installed and opened `/Applications/MacStatus.app`.
- Clicked the status item through Accessibility and verified five rows, e.g. `verge-mihomo (PID 1132)  ↑ 132K/s  ↓ 137K/s`.
