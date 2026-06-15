#!/usr/bin/env bash
set -euo pipefail

# Build the current source locally and install it as the live menu-bar app.
#
#   build (Debug) -> build.noindex (Spotlight-excluded) -> /Applications -> relaunch
#
# Unlike package-release.sh this skips signing/notarization: it produces an
# ad-hoc "Sign to Run Locally" build for personal use on this machine. Because
# the build lands in build.noindex (the `.noindex` suffix is excluded from
# Spotlight) the only copy Spotlight/LaunchServices can see is the installed
# one in /Applications -- no duplicate entries in the app launcher.

APP_NAME="MacStatus"
PROJECT="MacStatus/MacStatus.xcodeproj"
SCHEME="MacStatus"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build.noindex}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
Usage:
  scripts/install-local.sh

Builds the current source and installs it as the running menu-bar app,
replacing the copy in /Applications and restarting it. The login item
(SMAppService) re-registers itself to /Applications on launch, so auto-start
picks up this build on the next login.

Overridable via environment variables:
  CONFIGURATION       Build configuration (default: Debug)
  DERIVED_DATA_PATH   Build output dir (default: build.noindex)
  INSTALL_DIR         Install destination (default: /Applications)
EOF
  exit 0
fi

# Run from the repo root so the relative paths above resolve deterministically.
cd "$(dirname "$0")/.."

# 1. Build first -- if this fails the currently running app keeps running.
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
DEST="$INSTALL_DIR/$APP_NAME.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: build product not found at $APP_PATH" >&2
  exit 1
fi

if [[ ! -w "$INSTALL_DIR" ]]; then
  echo "error: $INSTALL_DIR is not writable; re-run with a writable INSTALL_DIR" >&2
  echo "       or move the existing app so you own it." >&2
  exit 1
fi

# 2. Quit the running instance before swapping the bundle.
pkill -f "/$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
sleep 1

# 3. Replace the installed copy (rm first so no stale files survive the swap).
rm -rf "$DEST"
ditto "$APP_PATH" "$DEST"

# 4. Relaunch -- the app re-registers its login item on launch.
open "$DEST"

echo "Installed and launched: $DEST"
echo -n "  built: "; stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$DEST/Contents/MacOS/$APP_NAME"
