#!/bin/bash
# Installs TUM (Token Utilization Monitor) on a Mac.
#
#   curl -fsSL https://raw.githubusercontent.com/araje-bot/TUM-Token-Utilization-Monitor/v0.1.0/install.sh | bash
#
# What it does, in order:
#   1. Downloads one exact release (TUM-0.1.0.dmg) from github.com over HTTPS.
#   2. Checks the file against the SHA-256 fingerprint written below. Anything else is deleted.
#   3. Opens the disk image read-only and checks the app's signature and bundle id.
#   4. Copies TUM.app into /Applications (or ~/Applications), replacing an older TUM, and opens it.
#
# It never asks for your password, never uses sudo, changes no system settings, and downloads
# nothing else. Everything happens in a private temporary folder that is removed at the end.
#
# Options:  --yes       install without asking
#           --no-open   don't open TUM at the end
set -euo pipefail

readonly VERSION="0.1.0"
readonly REPO="araje-bot/TUM-Token-Utilization-Monitor"
readonly APP_NAME="TUM"
readonly BUNDLE_ID="edu.umd.inst474.tum"
readonly DMG_NAME="${APP_NAME}-${VERSION}.dmg"
readonly DMG_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${DMG_NAME}"
# The SHA-256 of TUM-0.1.0.dmg. make_dmg.sh --update-installer writes it here for each release.
readonly DMG_SHA256="not-set"

TMP=""
MNT=""

say() { printf '%s\n' "$*"; }
fail() { say ""; say "Stopped: $*" >&2; exit 1; }

# Lets go of the disk image. Finder or Spotlight can hold it for a moment, so it tries a few times.
detach_dmg() {
  [[ -n "$MNT" ]] || return 0
  local i
  for i in 1 2 3 4 5; do
    if hdiutil detach "$MNT" -quiet 2>/dev/null; then MNT=""; return 0; fi
    sleep 1
  done
  hdiutil detach "$MNT" -force -quiet 2>/dev/null || true
  MNT=""
}

cleanup() {
  detach_dmg
  if [[ -n "$TMP" && -d "$TMP" && "$TMP" == *tum-install.* ]]; then rm -rf "$TMP"; fi
  return 0
}

usage() {
  say "Usage: install.sh [--yes] [--no-open]"
  say "Installs TUM $VERSION into /Applications (or ~/Applications)."
}

# Asks on the terminal even when the script itself arrives through a pipe (curl | bash).
ask_yes() {
  local answer=""
  if ( : < /dev/tty ) 2>/dev/null; then
    printf '%s' "$1" > /dev/tty
    read -r answer < /dev/tty || true
  else
    fail "No terminal to ask on. Run again with --yes to install without asking."
  fi
  case "$answer" in y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac
}

check_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "TUM runs on macOS only."
  (( $(id -u) != 0 )) || fail "Run this as your normal user, without sudo."
  local v major
  v="$(sw_vers -productVersion)"
  major="${v%%.*}"
  [[ "$major" =~ ^[0-9]+$ ]] || fail "Couldn't read the macOS version."
  (( major >= 13 )) || fail "TUM needs macOS 13 or later. This Mac has macOS $v."
}

check_tools() {
  local t
  for t in curl shasum hdiutil codesign ditto osascript xattr /usr/libexec/PlistBuddy; do
    command -v "$t" >/dev/null 2>&1 || fail "A standard macOS tool is missing ($t)."
  done
}

bundle_id() { /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null; }

# /Applications when this account may write there, otherwise the account's own Applications folder.
pick_target_dir() {
  if [[ -d /Applications && -w /Applications ]]; then
    printf '%s' "/Applications"
  else
    mkdir -p "$HOME/Applications"
    printf '%s' "$HOME/Applications"
  fi
}

# Only ever replaces a TUM. A link, a file, or another app with the same name stops the install.
check_target() {
  local t="$1"
  if [[ -L "$t" ]]; then fail "$t is a link, not an app. Remove it, then run this again."; fi
  if [[ -e "$t" ]]; then
    [[ -d "$t" ]] || fail "$t exists and isn't an app. Move it away, then run this again."
    local id
    id="$(bundle_id "$t" || true)"
    [[ "$id" == "$BUNDLE_ID" ]] || fail "$t is a different app (${id:-no bundle id}). Move it away, then run this again."
  fi
}

download() {
  local file="$TMP/$DMG_NAME" sum
  say "Downloading $DMG_NAME from github.com…"
  curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-delay 2 --max-filesize 20000000 -o "$file" "$DMG_URL" \
    || fail "Couldn't download $DMG_URL. Check your internet connection, then try again."
  sum="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [[ "$sum" != "$DMG_SHA256" ]]; then
    if [[ -f "$file" ]]; then rm -f "$file"; fi
    fail "The download doesn't match the expected file, so it was deleted and nothing was installed. (expected $DMG_SHA256, got $sum)"
  fi
  # curl never adds the "downloaded from the internet" mark. If it is there anyway, this file
  # didn't come the way it should have, and nothing is ever stripped to make it run.
  if xattr -p com.apple.quarantine "$file" >/dev/null 2>&1; then
    fail "The downloaded file carries a quarantine mark, which this installer never removes. Nothing was installed."
  fi
  say "Download checked: fingerprint matches."
}

mount_dmg() {
  MNT="$TMP/mnt"
  mkdir -p "$MNT"
  hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$MNT" "$TMP/$DMG_NAME" >/dev/null </dev/null \
    || fail "Couldn't open the disk image."
}

verify_app() {
  local app="$1" id version info signed_as flags
  [[ -d "$app" ]] || fail "The disk image doesn't contain $APP_NAME.app."
  codesign --verify --strict --deep "$app" 2>/dev/null \
    || fail "The app's signature doesn't check out, so nothing was installed."
  id="$(bundle_id "$app" || true)"
  [[ "$id" == "$BUNDLE_ID" ]] || fail "The app inside isn't TUM (${id:-no bundle id}), so nothing was installed."
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$version" == "$VERSION" ]] || fail "The app inside is TUM ${version:-?}, not $VERSION, so nothing was installed."
  info="$(codesign -d --verbose=2 "$app" 2>&1 || true)"
  signed_as="$(printf '%s\n' "$info" | awk -F= '/^Identifier=/ {print $2}')"
  [[ "$signed_as" == "$BUNDLE_ID" ]] \
    || fail "The app's signature belongs to a different app (${signed_as:-unknown}), so nothing was installed."
  flags="$(printf '%s\n' "$info" | awk '/^CodeDirectory/ { for (i = 1; i <= NF; i++) if ($i ~ /^flags=/) print $i }')"
  [[ "$flags" == *runtime* ]] || fail "The app was built without the hardened runtime, so nothing was installed."
  say "App checked: TUM $version, signature and bundle id are right."
}

# Quits a running TUM by bundle id (never by process name), and only if one is running, so a TUM
# that isn't running is never launched just to be quit. A copy that ignores the request is
# stopped by its exact path, since a still-running old TUM would keep the new one from opening.
quit_running() {
  local pattern="/${APP_NAME}\.app/Contents/MacOS/${APP_NAME}\$" i pid
  pgrep -qf "$pattern" || return 0
  say "Quitting the running TUM…"
  osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
  for i in 1 2 3 4 5 6; do
    pgrep -qf "$pattern" || return 0
    sleep 0.5
  done
  for pid in $(pgrep -f "$pattern"); do kill -TERM "$pid" 2>/dev/null || true; done
  for i in 1 2 3 4; do
    pgrep -qf "$pattern" || return 0
    sleep 0.5
  done
  return 0
}

# Copies to a temporary name next to the target, checks the copy, then swaps it in.
install_app() {
  local src="$1" dir="$2"
  local target="$dir/$APP_NAME.app" staging="$dir/.$APP_NAME.app.installing.$$"
  if [[ -e "$staging" ]]; then rm -rf "$staging"; fi
  ditto "$src" "$staging" || { rm -rf "$staging"; fail "Couldn't copy TUM into $dir."; }
  codesign --verify --strict --deep "$staging" 2>/dev/null \
    || { rm -rf "$staging"; fail "The copied app doesn't check out, so nothing was installed."; }
  if [[ -e "$target" ]]; then
    # macOS 13 and later can ask before Terminal changes an app in /Applications.
    mv "$target" "$TMP/$APP_NAME-old.app" || {
      rm -rf "$staging"
      fail "macOS didn't let this Terminal replace the old TUM. Drag TUM from $dir to the Trash and run this again, or allow Terminal under System Settings › Privacy & Security › App Management."
    }
  fi
  mv "$staging" "$target" || fail "Couldn't put TUM into $dir."
  say "Installed $target"
}

main() {
  local yes=0 open_after=1 a
  for a in "$@"; do
    case "$a" in
      --yes|-y) yes=1 ;;
      --no-open) open_after=0 ;;
      -h|--help) usage; exit 0 ;;
      *) usage; fail "Unknown option: $a" ;;
    esac
  done
  check_macos
  check_tools
  [[ "$DMG_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "This copy of the installer has no fingerprint. Get it again from github.com/$REPO."

  local dir target
  dir="$(pick_target_dir)"
  target="$dir/$APP_NAME.app"

  say "This installs TUM $VERSION, a menu bar app that shows how much AI usage you have left."
  say "It will:"
  say "  1. Download $DMG_NAME from github.com and check it against a known fingerprint."
  say "  2. Check the app's signature."
  say "  3. Put TUM in $dir, replacing any older TUM there, and open it."
  say "It never asks for your password and changes nothing else on your Mac."
  say ""
  if (( ! yes )); then
    ask_yes "Install TUM? (y/n) " || { say "OK, nothing was installed."; exit 0; }
  fi

  check_target "$target"
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/tum-install.XXXXXX")"
  chmod 700 "$TMP"
  trap cleanup EXIT
  download
  mount_dmg
  verify_app "$MNT/$APP_NAME.app"
  quit_running
  install_app "$MNT/$APP_NAME.app" "$dir"
  # Let go of the disk image before opening, so macOS only knows the installed copy.
  detach_dmg

  if (( open_after )); then
    if open "$target" 2>/dev/null; then
      say "TUM is opening. Look for its round icon at the right end of the menu bar."
    else
      say "Open TUM from $dir to start it."
    fi
  fi
  say ""
  say "To uninstall later, drag TUM from $dir to the Trash, or run:"
  say "  curl -fsSL https://raw.githubusercontent.com/$REPO/v$VERSION/uninstall.sh | bash"
}

main "$@"
