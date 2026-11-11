#!/bin/bash
# Builds a universal TAB.app (Apple silicon + Intel) and packages it as a drag-to-install DMG.
#
#   ./make_dmg.sh                      -> build/TAB-0.2.5.dmg (signed only on this Mac)
#
# For a DMG that opens on any Mac without warnings (needs a paid Apple Developer account):
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="tab-notary" ./make_dmg.sh
#   (create the profile once with: xcrun notarytool store-credentials tab-notary)
#   ./make_dmg.sh --allow-dirty        build with uncommitted changes (local testing only)
#   ./make_dmg.sh --update-installer   put the zip in dist/ and write its SHA-256 into install.sh
set -euo pipefail
cd "$(dirname "$0")"
# Everything this script prints also goes to build-log.txt, with home folder paths shortened to ~.
exec > >(sed -l "s#$HOME#~#g" | tee build-log.txt) 2>&1
echo "TAB build $(date)  macOS $(sw_vers -productVersion)  $(uname -m)"
echo "Developer tools: $(xcode-select -p 2>/dev/null || echo 'not installed')"

VERSION="0.2.5"
APP_NAME="TAB"
BUNDLE_ID="edu.umd.inst474.tab"

ALLOW_DIRTY=0; UPDATE_INSTALLER=0
for a in "$@"; do
  case "$a" in
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --update-installer) UPDATE_INSTALLER=1 ;;
    *) echo "Unknown option $a"; exit 2 ;;
  esac
done

# A release comes from a commit, so the file whose fingerprint testers check is exactly what was
# tagged (security review). The build number counts commits.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo none)"
  BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
  if [[ -n "$(git status --porcelain)" && $ALLOW_DIRTY == 0 ]]; then
    echo "There are uncommitted changes. Commit first, so the release matches its tag, or run"
    echo "  ./make_dmg.sh --allow-dirty   for a local build."
    exit 1
  fi
else
  COMMIT="none"
  BUILD_NUMBER="$(date +%Y%m%d%H%M)"
  echo "   (not a git repository: build number from the date)"
fi
if ! grep -q "^readonly VERSION=\"$VERSION\"" install.sh; then
  echo "install.sh is for a different version than $VERSION. Update both before a release."
  exit 1
fi
echo "Version $VERSION, build $BUILD_NUMBER, commit $COMMIT"

if ! CHECK=$(xcrun --find swift 2>&1); then
  echo "Swift check failed: $CHECK"
  if echo "$CHECK" | grep -qi "license"; then
    echo "Fix: run   sudo xcodebuild -license accept   then run this script again."
  elif [[ "$(xcode-select -p 2>/dev/null)" == *Xcode.app* ]]; then
    echo "Fix: run   sudo xcodebuild -runFirstLaunch   then run this script again."
  else
    echo "Fix: run   xcode-select --install   then run this script again."
  fi
  exit 1
fi

echo "1/5 Building for Apple silicon and Intel..."
# Each chip is built separately and then joined. The Intel step may print a
# "deprecated" warning, which is harmless; the app still runs on macOS 13 and later.
# Start clean, so an old Intel build can never be reused (security review M8).
rm -rf .build/universal
mkdir -p .build/universal
BIN=".build/universal/$APP_NAME"
# Newer Xcode puts every build in the same folder, so copy each one out right away.
swift build -c release --arch arm64
cp "$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME" ".build/universal/$APP_NAME-arm64"
if ! swift build -c release --arch x86_64; then
  echo "Intel build failed. A release must run on Intel Macs too, so no DMG was made."
  exit 1
fi
cp "$(swift build -c release --arch x86_64 --show-bin-path)/$APP_NAME" ".build/universal/$APP_NAME-x86_64"
# Mark the app as built with this Mac's SDK. Without this, the build tools record
# macOS 13 as the SDK and macOS shows the app in the old, pre-Liquid Glass style.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
echo "   Marking build with macOS SDK $SDK_VERSION"
for slice in ".build/universal/$APP_NAME-arm64" ".build/universal/$APP_NAME-x86_64"; do
  [[ -f "$slice" ]] || continue
  xcrun vtool -set-build-version macos 13.0 "$SDK_VERSION" -replace -output "$slice.tmp" "$slice"
  mv "$slice.tmp" "$slice"
done
if [[ -f ".build/universal/$APP_NAME-x86_64" ]] && lipo -create ".build/universal/$APP_NAME-arm64" ".build/universal/$APP_NAME-x86_64" -output "$BIN" 2>/dev/null; then
  :
else
  echo "Couldn't join the Apple silicon and Intel builds. A release must run on both, so no DMG was made."
  exit 1
fi
[[ -f "$BIN" ]] || { echo "Build output not found at $BIN"; exit 1; }
lipo -info "$BIN"

echo "2/5 Assembling $APP_NAME.app..."
# Assemble and sign outside Desktop: Desktop and iCloud folders add hidden
# Finder data to files, and macOS refuses to sign an app that has it.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tab-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/$APP_NAME.app"
rm -rf build && mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>TabGitCommit</key><string>$COMMIT</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>TAB · Track AI Balance</string>
</dict>
</plist>
PLIST

echo "3/5 Making the app icon..."
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
if TAB_BUILD_TOOLS=1 "$BIN" --export-icon "$WORK/icon_1024.png"; then
  for s in 16 32 128 256 512; do
    sips -z $s $s "$WORK/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$WORK/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
  echo "   (icon export failed, continuing with the default icon)"
fi

echo "4/5 Signing..."
xattr -cr "$APP"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
else
  codesign --force --options runtime --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

echo "   Running self-test..."
if ! "$APP/Contents/MacOS/$APP_NAME" --self-test; then
  echo ""
  echo "Self-test failed, so no DMG was made. The failing checks are listed above."
  exit 1
fi
echo "   Saving screen pictures for design review..."
TAB_BUILD_TOOLS=1 "$APP/Contents/MacOS/$APP_NAME" --snapshots "$(pwd)/build-snapshots" || echo "   (pictures skipped)"

echo "5/5 Creating DMG..."
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
ditto --norsrc --noextattr "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
DMG="$WORK/$APP_NAME-$VERSION.dmg"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --sign "$DEVELOPER_ID" --timestamp "$DMG"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "Notarizing with Apple (takes a few minutes)..."
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi

cp "$DMG" "build/"
ditto --norsrc --noextattr "$APP" "build/$APP_NAME.app"
DMG="build/$APP_NAME-$VERSION.dmg"
# build/ is wiped on every run, so keep a dated copy of each DMG in releases/ as the version history.
mkdir -p releases
KEEP="releases/$APP_NAME-$VERSION-$(date +%Y-%m-%d-%H%M).dmg"
cp "$DMG" "$KEEP"
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
echo "$SHA  $APP_NAME-$VERSION.dmg" > "$KEEP.sha256"
echo "$SHA  $APP_NAME-$VERSION.dmg" > "$DMG.sha256"
echo ""
echo "Done: $(pwd)/$DMG"
echo "SHA-256: $SHA"
echo "Kept a copy: $(pwd)/$KEEP"
# The terminal installer downloads this zip from the repository at the version's tag (dist/).
# Only the current version's zip is kept there; older ones stay in git history and their tags.
ZIP="build/$APP_NAME-$VERSION.zip"
ditto -c -k --norsrc --noextattr --keepParent "build/$APP_NAME.app" "$ZIP"
ZIP_SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
cp "$ZIP" "releases/$APP_NAME-$VERSION-$(date +%Y-%m-%d-%H%M).zip"
echo "Zip for the installer: $(pwd)/$ZIP"
echo "Zip SHA-256: $ZIP_SHA"
if [[ $UPDATE_INSTALLER == 1 ]]; then
  mkdir -p dist
  find dist -name "$APP_NAME-*.zip" -delete
  cp "$ZIP" "dist/"
  sed -i '' "s/^readonly ZIP_SHA256=.*/readonly ZIP_SHA256=\"$ZIP_SHA\"/" install.sh
  echo "Put dist/$APP_NAME-$VERSION.zip in place and wrote its SHA-256 into install.sh."
  echo "Commit both, tag v$VERSION and push the tag. The install command then works as is."
else
  echo "For a release, run   ./make_dmg.sh --update-installer   so install.sh checks for this exact file."
fi
if [[ -z "${DEVELOPER_ID:-}" ]]; then
  echo "Note: this build is signed only on this Mac. Share it through the terminal installer, not the DMG."
fi
