#!/bin/bash
# Build, sign, install, and launch SixFour on a physically-connected iPhone.
#
# Unlike the Simulator build (ad-hoc signed, CODE_SIGNING_REQUIRED=NO in
# project.yml), a real device needs a genuine signing identity + a development
# team + a provisioning profile. We override the Simulator-oriented base
# settings on the xcodebuild command line (CLI build settings win over project
# settings) and let `-allowProvisioningUpdates` mint/refresh the profile.
#
# The native Zig core is rebuilt for the device slice automatically: the Xcode
# preBuildScript runs Native/build-ios.sh, which keys off PLATFORM_NAME=iphoneos
# → `zig build-obj -target aarch64-ios` → libtool static archive (verified
# arm64 / platform 2 = iOS device).
#
# Usage:
#   scripts/run-on-device.sh                 # auto-detect device + team
#   SIXFOUR_TEAM_ID=ABCDE12345 scripts/run-on-device.sh
#   SIXFOUR_DEVICE_ID=<udid> scripts/run-on-device.sh
#   CONFIG=Release scripts/run-on-device.sh  # default Debug
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="$PWD"
CONFIG="${CONFIG:-Debug}"
SCHEME="SixFour"
BUNDLE_ID="com.sixfour.SixFour"
DERIVED="$SRC/build-device"

# ── 1. Resolve the development team (10-char ID from an Apple Development cert) ─
TEAM_ID="${SIXFOUR_TEAM_ID:-}"
if [ -z "$TEAM_ID" ]; then
  TEAM_ID="$(security find-identity -v -p codesigning \
    | grep -m1 'Apple Development' \
    | sed -E 's/.*\(([A-Z0-9]{10})\)".*/\1/')" || true
fi
if [ -z "$TEAM_ID" ]; then
  echo "error: no development team found. Add your Apple ID in Xcode ▸ Settings ▸"
  echo "       Accounts (a free personal team is fine), then set SIXFOUR_TEAM_ID." >&2
  exit 1
fi

# ── 2. Resolve the connected device UDID ──────────────────────────────────────
DEVICE_ID="${SIXFOUR_DEVICE_ID:-}"
if [ -z "$DEVICE_ID" ]; then
  DEVICE_ID="$(xcrun devicectl list devices 2>/dev/null \
    | grep -Eio '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
    | head -1)" || true
fi
if [ -z "$DEVICE_ID" ]; then
  echo "error: no connected device found. Plug in the iPhone, unlock it, tap" >&2
  echo "       'Trust This Computer', and enable Developer Mode (Settings ▸"     >&2
  echo "       Privacy & Security ▸ Developer Mode). Then re-run."              >&2
  exit 1
fi

echo "▸ team   : $TEAM_ID"
echo "▸ device : $DEVICE_ID"
echo "▸ config : $CONFIG"

# ── 3. Regenerate the project (picks up any new files) ────────────────────────
xcodegen generate >/dev/null

# ── 4. Build + sign for the device ────────────────────────────────────────────
echo "▸ building + signing for device…"
xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  build

APP="$DERIVED/Build/Products/${CONFIG}-iphoneos/SixFour.app"
if [ ! -d "$APP" ]; then
  echo "error: built app not found at $APP" >&2
  exit 1
fi

# ── 5. Install + launch via CoreDevice (Xcode 15+/iOS 17+ flow) ───────────────
echo "▸ installing on device…"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo "▸ launching…"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"

echo "✓ SixFour is running on the device."
