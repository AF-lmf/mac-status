---
quick_id: 260514-vhu
slug: github-readme-release
status: complete
completed: 2026-05-14
commit: 149763f
---

# Quick Task Summary: GitHub README and Release Prep

## Result

Prepared and published the project as a public GitHub repository.

## Files Changed

- `README.md`
- `.gitignore`
- `docs/images/menubar-preview.png`
- `.planning/quick/260514-vhu-github-readme-release/PLAN.md`

## Artifacts

- Local Release zip: `dist/MacStatus-1.0.zip`
- Zip size: about 529 KB
- Release app path: `build/Build/Products/Release/MacStatus.app`

## Verification

- Ran `xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Release -derivedDataPath build build`.
- Release build succeeded.
- Packaged `dist/MacStatus-1.0.zip` with `COPYFILE_DISABLE=1 ditto --norsrc`.
- Verified the zip contents do not contain AppleDouble `._*` files.

## GitHub Publishing Status

- Public repository: <https://github.com/AF-lmf/mac-status>
- Default branch: `main`
- Release tag: `v1.0`
- Release URL: <https://github.com/AF-lmf/mac-status/releases/tag/v1.0>
- Release asset: `MacStatus-1.0.zip`
