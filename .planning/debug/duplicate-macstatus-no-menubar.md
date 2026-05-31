---
status: partially-resolved
trigger: "应用中有三个 MacStatus，并且现在打开应用状态栏没有显示出相关状态"
created: 2026-05-31
updated: 2026-05-31
---

# Debug Session: Duplicate MacStatus Entries And Missing Menu Bar Status

## Symptoms

- expected_behavior: "Only one usable MacStatus app entry should appear, and launching it should show live CPU/GPU/memory/network metrics in the macOS menu bar."
- actual_behavior: "macOS app search shows three MacStatus entries; opening MacStatus does not show the resource status in the menu bar."
- error_messages: "No explicit error message reported."
- timeline: "Reported on 2026-05-31; prior behavior unknown."
- reproduction: "Search/open MacStatus from the macOS app UI, then inspect the menu bar."

## Current Focus

- hypothesis: "Spotlight/LaunchServices indexed multiple build products, and an old running DerivedData bundle can keep the latest app from becoming the visible menu bar instance."
- test: "Locate indexed MacStatus.app bundles, inspect running process path, build current project, then clean/re-register only the intended local bundle."
- expecting: "Three app entries correspond to build/DerivedData products; current running process path will not match the latest local build."
- next_action: "Gather local bundle/process evidence and implement a repeatable cleanup path."
- reasoning_checkpoint:
- tdd_checkpoint:

## Evidence

- timestamp: 2026-05-31T21:45:00+08:00
  observation: "mdfind returned three MacStatus.app bundles: project build Debug, project build Release, and Xcode DerivedData Debug."
- timestamp: 2026-05-31T21:46:00+08:00
  observation: "pgrep showed the running MacStatus process came from /Users/halo/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/MacStatus.app."
- timestamp: 2026-05-31T21:45:22+08:00
  observation: "xcodebuild Debug with derivedDataPath=build succeeded."
- timestamp: 2026-05-31T22:18:00+08:00
  observation: "After unregistering/removing stale build and DerivedData app bundles, mdfind returned only /Applications/MacStatus.app plus source directories, eliminating the three-app search result."
- timestamp: 2026-05-31T22:24:00+08:00
  observation: "System Events can read the MacStatus status item with live text such as C22/G63/M53/network, and AXPress opens the Quit MacStatus menu."
- timestamp: 2026-05-31T22:24:00+08:00
  observation: "The AX position remains under the macOS 26 ControlCenter/clock area, so the item is functional but visually obscured on this machine."
- timestamp: 2026-05-31T22:52:00+08:00
  observation: "Apple Developer Forums report macOS 26 ControlCenter menu bar tracking corruption where changing the bundle identifier makes the status item appear normally. Rebuilding MacStatus as com.aflmf.macstatus moved the status item to x=1173 and made it visibly render in the menu bar."

## Eliminated

## Resolution

- root_cause: "The old com.macstatus.app bundle identifier had stale/corrupt macOS 26 ControlCenter menu bar tracking state after multiple build products with the same identity were registered. ControlCenter created the status item but placed/handled it under the system status region, so it was accessible and clickable but not visibly rendered."
- fix: "Removed stale local app bundles, installed the current signed app at /Applications/MacStatus.app, made launch take over old same-bundle processes, changed source builds to build.noindex, updated the status item to use a standard NSStatusItem.menu path with an image-rendered status fallback, and changed the app bundle identifier to com.aflmf.macstatus to escape the corrupt ControlCenter state."
- verification: "Debug builds succeed. /Applications/MacStatus.app runs as com.aflmf.macstatus. mdfind no longer reports three MacStatus.app bundles. The status item visibly renders in the menu bar and AX verification confirms live text updates."
- files_changed: ".gitignore; README.md; scripts/package-release.sh; MacStatus/MacStatus.xcodeproj/project.pbxproj; MacStatus/MacStatus/App/AppDelegate.swift; MacStatus/MacStatus/UI/StatusBarManager.swift"
