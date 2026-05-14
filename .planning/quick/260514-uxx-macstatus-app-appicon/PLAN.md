---
quick_id: 260514-uxx
slug: macstatus-app-appicon
status: planned
created: 2026-05-14
files_modified:
  - MacStatus/MacStatus/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
  - MacStatus/MacStatus/Resources/Assets.xcassets/AppIcon.appiconset/*.png
---

# Quick Task: MacStatus App Icon

Generate and install a production AppIcon set for MacStatus.

## Tasks

1. Create a deterministic macOS-style icon concept:
   - dark rounded square base
   - subtle menu bar/status motif
   - central status waveform
   - small colored metric indicators for CPU/GPU/MEM/network
2. Export all required macOS AppIcon sizes into `AppIcon.appiconset`.
3. Add `Contents.json` so Xcode can compile the icon.
4. Build the app to verify asset catalog compilation.

## Verification

```bash
xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build
```
