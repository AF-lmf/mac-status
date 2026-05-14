---
quick_id: 260514-vww
slug: release-mac-macstatus-app
status: complete
completed: 2026-05-14
commit: f15b0c8
---

# Quick Task Summary: Release Signing and Notarization

## Result

Documented that the reported "Apple cannot verify MacStatus.app" prompt is caused by distributing an ad-hoc signed, unnotarized app bundle, and added a release script for Developer ID signing, notarization, stapling, and final zip packaging.

## Files Changed

- `README.md`
- `scripts/package-release.sh`
- `.planning/quick/260514-vww-release-mac-macstatus-app/PLAN.md`

## Verification

- Ran `codesign -dv --verbose=4 build/Build/Products/Release/MacStatus.app`; the existing app is ad-hoc signed with no TeamIdentifier.
- Ran `security find-identity -v -p codesigning`; this machine has 0 valid signing identities, so a notarized package cannot be produced here yet.
- Ran `bash -n scripts/package-release.sh`.
- Ran `scripts/package-release.sh --help`.
- Ran `git diff --check README.md scripts/package-release.sh .planning/quick/260514-vww-release-mac-macstatus-app/PLAN.md`.

## Distribution Note

The next public release should be rebuilt from `scripts/package-release.sh` after installing a valid Developer ID Application certificate and storing notary credentials with `xcrun notarytool store-credentials`.
