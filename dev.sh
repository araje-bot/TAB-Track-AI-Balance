#!/bin/bash
# Fast dev loop: debug build for this Mac only, assemble TAB.app, relaunch it, save snapshots.
# Takes seconds instead of a full DMG build. The debug build has the Developer menu
# (right-click the menu bar icon).
#
#   ./dev.sh              build, save snapshots, relaunch
#   ./dev.sh --test       also run the self-test
#   ./dev.sh --no-run     build and snapshots only, don't relaunch
#   ./dev.sh --no-shots   skip the snapshots
#
# The DMG (./make_dmg.sh) is only for final checks and sharing.
set -euo pipefail
cd "$(dirname "$0")"
exec > >(sed -l "s#$HOME#~#g" | tee dev-log.txt) 2>&1

RUN=1; TEST=0; SHOTS=1
for a in "$@"; do
  case "$a" in
    --test) TEST=1 ;;
    --no-run) RUN=0 ;;
    --no-shots) SHOTS=0 ;;
    *) echo "Unknown option $a"; exit 2 ;;
  esac
done

echo "Building (debug)..."
swift build -c debug
BIN="$(swift build -c debug --show-bin-path)/TAB"

# Assemble outside Desktop, which adds Finder data that breaks signing.
# "TAB Dev" is its own app (bundle id edu.umd.inst474.tab.dev, its own settings), so it never
# replaces or quits the real TAB installed from the DMG (AK: one version to debug, one to use).
APP="${TMPDIR:-/tmp}/tab-dev/TAB Dev.app"
rm -rf "${TMPDIR:-/tmp}/tum-dev"   # TUM Dev, from before the rename to TAB
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TAB"
# Record this Mac's SDK so macOS uses Liquid Glass, not the old look.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
xcrun vtool -set-build-version macos 13.0 "$SDK_VERSION" -replace -output "$APP/Contents/MacOS/TAB.tmp" "$APP/Contents/MacOS/TAB"
mv "$APP/Contents/MacOS/TAB.tmp" "$APP/Contents/MacOS/TAB"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>TAB Dev</string>
  <key>CFBundleDisplayName</key><string>TAB Dev</string>
  <key>CFBundleIdentifier</key><string>edu.umd.inst474.tab.dev</string>
  <key>CFBundleExecutable</key><string>TAB</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0-dev</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

xattr -cr "$APP"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

if [[ $TEST == 1 ]]; then
  echo "Running self-test..."
  "$APP/Contents/MacOS/TAB" --self-test
fi

if [[ $SHOTS == 1 ]]; then
  echo "Saving snapshots to build-snapshots/ ..."
  TAB_BUILD_TOOLS=1 "$APP/Contents/MacOS/TAB" --snapshots "$(pwd)/build-snapshots" || echo "(snapshots skipped)"
fi

if [[ $RUN == 1 ]]; then
  # Quit only the previous TAB Dev (by bundle id), never the real TAB. The new copy also closes
  # other debug copies itself (for example one run from Xcode).
  osascript -e 'quit app id "edu.umd.inst474.tab.dev"' >/dev/null 2>&1 || true
  sleep 0.5
  open "$APP"
  echo "TAB Dev is running (orange dot on its icon). Right-click it for the pill previews and Developer menu."
fi
