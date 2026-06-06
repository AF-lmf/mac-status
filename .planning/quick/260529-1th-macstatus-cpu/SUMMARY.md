---
status: complete
---

# Summary

Investigated MacStatus appearing to run without visible CPU, GPU, memory, and network data on macOS 26.

## Findings

- The app process and `NSStatusItem` scene are created successfully.
- Accessibility can read the live status text (for example `C14 G40 M35 ↓3.1K ↑1K`), so readers and UI updates are working.
- Even a temporary square SF Symbol status item did not render on screen, which rules out text/attributed-title rendering as the root cause.
- The machine is running macOS 26.5 on a notched MacBook display with a crowded right-side menu bar. Apple documents that `NSStatusItem.isVisible` can still return true when an item is temporarily hidden because there is insufficient menu bar space.
- Multiple MacStatus instances were also running at the same time during initial investigation, which can create multiple status items and make visibility/debugging ambiguous.

## Changes

- Added a single-instance guard in `AppDelegate` so a second MacStatus launch exits instead of creating another menu bar item.
- Removed the `autosaveName` position cache and switched the combined status item from a 210pt fixed width to `NSStatusItem.variableLength`, minimizing the chance that MacStatus is pushed into an unavailable menu bar area.
- Replaced the unreliable `isVisible == false`-only check with a macOS 26+ notice that mentions both System Settings -> Menu Bar and crowded/notched menu bar hiding.

## Verification

- Built Debug successfully with `xcodebuild`.
- Relaunched from a clean state and confirmed only one MacStatus process remains.
- Confirmed via Accessibility that the status item exists and is receiving live metric updates.
- Confirmed that lack of screen visibility is caused by macOS menu bar space/crowding rather than reader or rendering failure.
