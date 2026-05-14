---
quick_id: 260514-vhu
slug: github-readme-release
status: planned
created: 2026-05-14
files_modified:
  - README.md
  - .gitignore
  - docs/images/menubar-preview.png
---

# Quick Task: GitHub README and Release Prep

## Goal

Prepare MacStatus for publishing as a public GitHub repository with a reader-friendly README, an effect preview image, and a local Release zip artifact.

## Tasks

1. Add a public-facing `README.md` that explains what MacStatus does, shows the menu bar effect, and documents build/use/package steps.
2. Add a safe menu bar preview image under `docs/images/`.
3. Keep build and release artifacts out of git with `.gitignore`.
4. Build a Release app and package it as `dist/MacStatus-1.0.zip` for GitHub Releases.
5. Attempt GitHub repository/release publication if local authentication/tooling allows it.

## Verification

```bash
xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Release -derivedDataPath build build
COPYFILE_DISABLE=1 ditto --norsrc -c -k --keepParent build/Build/Products/Release/MacStatus.app dist/MacStatus-1.0.zip
```
