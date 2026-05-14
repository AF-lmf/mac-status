---
quick_id: 260514-vww
slug: release-mac-macstatus-app
status: planned
created: 2026-05-14
files_modified:
  - README.md
  - scripts/package-release.sh
  - .planning/quick/260514-vww-release-mac-macstatus-app/PLAN.md
---

# Quick Task: Release Signing and Notarization

## Goal

Fix the release instructions that caused MacStatus.app to be blocked by Gatekeeper on other Macs by documenting the required Developer ID signing and notarization flow.

## Tasks

1. Add a release packaging script that builds with a Developer ID identity, submits the app for notarization, staples the ticket, and creates the final zip.
2. Update README release instructions to distinguish local test packages from notarized public release packages.
3. Document a limited quarantine-removal workaround for trusted personal testing only.

## Verification

```bash
bash -n scripts/package-release.sh
codesign -dv --verbose=4 build/Build/Products/Release/MacStatus.app
security find-identity -v -p codesigning
```
