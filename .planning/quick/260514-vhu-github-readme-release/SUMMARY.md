---
quick_id: 260514-vhu
slug: github-readme-release
status: remote_publish_blocked
completed: 2026-05-14
commit: 9ba8720
---

# Quick Task Summary: GitHub README and Release Prep

## Result

Prepared the project for public GitHub publishing.

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

- GitHub connector authenticated as `AF-lmf`.
- `AF-lmf/mac-status` does not currently exist.
- The available GitHub connector tools can read/write existing repositories, but do not expose repository creation or Release creation/upload.
- Local machine has no `gh` CLI, no `GITHUB_TOKEN`/`GH_TOKEN`, no HTTPS git credential, and no working SSH credential for GitHub.
- Remote repository creation, push, and Release upload are therefore blocked until GitHub CLI/token/SSH/browser creation is available.
