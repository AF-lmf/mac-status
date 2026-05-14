#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MacStatus"
PROJECT="MacStatus/MacStatus.xcodeproj"
SCHEME="MacStatus"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build}"
DIST_DIR="${DIST_DIR:-dist}"
VERSION="${VERSION:-1.0}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-MacStatusNotaryProfile}"
TEAM_ID="${TEAM_ID:-}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
Usage:
  TEAM_ID=YOURTEAMID \
  SIGNING_IDENTITY="Developer ID Application: Your Name (YOURTEAMID)" \
  NOTARY_PROFILE=MacStatusNotaryProfile \
  VERSION=1.0 \
  scripts/package-release.sh

Before first use, store notarization credentials:
  xcrun notarytool store-credentials MacStatusNotaryProfile \
    --apple-id "you@example.com" \
    --team-id "YOURTEAMID" \
    --password "app-specific-password"
EOF
  exit 0
fi

if ! security find-identity -v -p codesigning | grep -Fq "$SIGNING_IDENTITY"; then
  cat >&2 <<EOF
error: signing identity not found: $SIGNING_IDENTITY

Install a "Developer ID Application" certificate in Keychain Access, or pass
SIGNING_IDENTITY with the exact certificate name shown by:
  security find-identity -v -p codesigning
EOF
  exit 1
fi

mkdir -p "$DIST_DIR"

build_args=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
  CODE_SIGN_STYLE=Manual
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
  OTHER_CODE_SIGN_FLAGS="--timestamp"
)

if [[ -n "$TEAM_ID" ]]; then
  build_args+=(DEVELOPMENT_TEAM="$TEAM_ID")
fi

build_args+=(build)

xcodebuild "${build_args[@]}"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
NOTARY_ZIP="$DIST_DIR/$APP_NAME-$VERSION-notary.zip"
FINAL_ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
rm -f "$NOTARY_ZIP" "$FINAL_ZIP"

COPYFILE_DISABLE=1 ditto --norsrc -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

COPYFILE_DISABLE=1 ditto --norsrc -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

echo "Created notarized release package: $FINAL_ZIP"
