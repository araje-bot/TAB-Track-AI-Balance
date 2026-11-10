#!/bin/bash
# Installs TAB (Track AI Balance) on a Mac.
#
#   curl -fsSL https://raw.githubusercontent.com/araje-bot/TAB-Track-AI-Balance/v0.2.4/install.sh | bash
#
# What it does, in order:
#   1. Downloads one exact build (dist/TAB-0.2.4.zip at the v0.2.4 tag) from GitHub over HTTPS.
#   2. Checks the file against the SHA-256 fingerprint written below. Anything else is deleted.
#   3. Unpacks it in a private folder and checks the app's signature and bundle id.
#   4. Copies TAB.app into /Applications (or ~/Applications), replacing an older TAB, and opens it.
#
# Installing from Terminal is what lets TAB open without Apple's developer signature: curl never
# marks the file as downloaded from the internet, so macOS doesn't block the first launch.
#
# It never asks for your password, never uses sudo, changes no system settings, and downloads
# nothing else. Everything happens in a private temporary folder that is removed at the end.
#
# Options:  --yes       install without asking
#           --no-open   don't open TAB at the end
set -euo pipefail

readonly VERSION="0.2.4"
readonly REPO="araje-bot/TAB-Track-AI-Balance"
readonly APP_NAME="TAB"
readonly BUNDLE_ID="edu.umd.inst474.tab"
# TAB was called TUM in 0.1.0. An old TUM.app is quit and moved to the Trash.
readonly OLD_NAME="TUM"
readonly OLD_BUNDLE_ID="edu.umd.inst474.tum"
readonly ZIP_NAME="${APP_NAME}-${VERSION}.zip"
# The build is kept in the repository at the version's tag, so no separate release page is needed.
readonly ZIP_URL="https://raw.githubusercontent.com/${REPO}/v${VERSION}/dist/${ZIP_NAME}"
# The SHA-256 of TAB-0.2.4.zip. make_dmg.sh --update-installer writes it here for each release.
readonly ZIP_SHA256="8f3588ba8cd8a9294f0fc38c04955304564922a9959feab439dc2d401c92a723"

TMP=""
UNPACKED=""
STAGING=""   # the half-copied app, removed if the install stops early

say() { printf '%s\n' "$*"; }
fail() { say ""; say "Stopped: $*" >&2; exit 1; }

cleanup() {
  if [[ -n "$STAGING" && -e "$STAGING" && "$STAGING" == *".$APP_NAME.app.installing."* ]]; then rm -rf "$STAGING"; fi
  if [[ -n "$TMP" && -d "$TMP" && "$TMP" == *tab-install.* ]]; then rm -rf "$TMP"; fi
  return 0
}

usage() {
  say "Usage: install.sh [--yes] [--no-open]"
  say "Installs TAB $VERSION into /Applications (or ~/Applications)."
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
  [[ "$(uname -s)" == "Darwin" ]] || fail "TAB runs on macOS only."
  (( $(id -u) != 0 )) || fail "Run this as your normal user, without sudo."
  local v major
  v="$(sw_vers -productVersion)"
  major="${v%%.*}"
  [[ "$major" =~ ^[0-9]+$ ]] || fail "Couldn't read the macOS version."
  (( major >= 13 )) || fail "TAB needs macOS 13 or later. This Mac has macOS $v."
}

check_tools() {
  local t
  for t in curl shasum codesign ditto osascript xattr /usr/libexec/PlistBuddy; do
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

# Only ever replaces a TAB. A link, a file, or another app with the same name stops the install.
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
  local file="$TMP/$ZIP_NAME" sum
  say "Downloading $ZIP_NAME from GitHub…"
  curl --proto '=https' --tlsv1.2 -fsSL --retry 3 --retry-delay 2 --max-filesize 20000000 -o "$file" "$ZIP_URL" \
    || fail "Couldn't download $ZIP_URL. Check your internet connection, then try again."
  sum="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [[ "$sum" != "$ZIP_SHA256" ]]; then
    if [[ -f "$file" ]]; then rm -f "$file"; fi
    fail "The download doesn't match the expected file, so it was deleted and nothing was installed. (expected $ZIP_SHA256, got $sum)"
  fi
  # curl never adds the "downloaded from the internet" mark. If it is there anyway, this file
  # didn't come the way it should have, and nothing is ever stripped to make it run.
  if xattr -p com.apple.quarantine "$file" >/dev/null 2>&1; then
    fail "The downloaded file carries a quarantine mark, which this installer never removes. Nothing was installed."
  fi
  say "Download checked: fingerprint matches."
}

unpack() {
  UNPACKED="$TMP/app"
  mkdir -p "$UNPACKED"
  ditto -x -k "$TMP/$ZIP_NAME" "$UNPACKED" </dev/null || fail "Couldn't unpack the download."
  [[ -d "$UNPACKED/$APP_NAME.app" && ! -L "$UNPACKED/$APP_NAME.app" ]] || fail "The download doesn't contain $APP_NAME.app."
}

verify_app() {
  local app="$1" id version info signed_as flags
  [[ -d "$app" ]] || fail "The download doesn't contain $APP_NAME.app."
  codesign --verify --strict --deep "$app" 2>/dev/null \
    || fail "The app's signature doesn't check out, so nothing was installed."
  id="$(bundle_id "$app" || true)"
  [[ "$id" == "$BUNDLE_ID" ]] || fail "The app inside isn't TAB (${id:-no bundle id}), so nothing was installed."
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$version" == "$VERSION" ]] || fail "The app inside is TAB ${version:-?}, not $VERSION, so nothing was installed."
  info="$(codesign -d --verbose=2 "$app" 2>&1 || true)"
  signed_as="$(printf '%s\n' "$info" | awk -F= '/^Identifier=/ {print $2}')"
  [[ "$signed_as" == "$BUNDLE_ID" ]] \
    || fail "The app's signature belongs to a different app (${signed_as:-unknown}), so nothing was installed."
  flags="$(printf '%s\n' "$info" | awk '/^CodeDirectory/ { for (i = 1; i <= NF; i++) if ($i ~ /^flags=/) print $i }')"
  [[ "$flags" == *runtime* ]] || fail "The app was built without the hardened runtime, so nothing was installed."
  say "App checked: TAB $version, signature and bundle id are right."
}

# The ids of processes running exactly this executable, wherever pgrep found a match.
pids_at() {
  local exe="$1" pid
  for pid in $(pgrep -f "/${APP_NAME}\.app/Contents/MacOS/${APP_NAME}\$" || true); do
    [[ "$(ps -o comm= -p "$pid" 2>/dev/null)" == "$exe" ]] && printf '%s\n' "$pid"
  done
  return 0
}

# Quits the TAB being replaced, by bundle id, and only if it is running, so a TAB that isn't
# running is never launched just to be quit. A copy that ignores the request is stopped by its
# exact path, so no other app that happens to be called TAB is ever touched.
quit_running() {
  local exe="$1/Contents/MacOS/$APP_NAME" i pid
  [[ -n "$(pids_at "$exe")" ]] || return 0
  say "Quitting the running TAB…"
  osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
  for i in 1 2 3 4 5 6; do
    [[ -n "$(pids_at "$exe")" ]] || return 0
    sleep 0.5
  done
  for pid in $(pids_at "$exe"); do kill -TERM "$pid" 2>/dev/null || true; done
  for i in 1 2 3 4; do
    [[ -n "$(pids_at "$exe")" ]] || return 0
    sleep 0.5
  done
  return 0
}

# Copies to a temporary name next to the target, checks the copy, then swaps it in.
install_app() {
  local src="$1" dir="$2"
  local target="$dir/$APP_NAME.app" staging="$dir/.$APP_NAME.app.installing.$$" moved_old=0
  STAGING="$staging"
  if [[ -e "$staging" ]]; then rm -rf "$staging"; fi
  ditto "$src" "$staging" || { rm -rf "$staging"; fail "Couldn't copy TAB into $dir."; }
  codesign --verify --strict --deep "$staging" 2>/dev/null \
    || { rm -rf "$staging"; fail "The copied app doesn't check out, so nothing was installed."; }
  if [[ -e "$target" ]]; then
    # macOS 13 and later can ask before Terminal changes an app in /Applications.
    mv "$target" "$TMP/$APP_NAME-old.app" || {
      rm -rf "$staging"
      fail "macOS didn't let this Terminal replace the old TAB. Drag TAB from $dir to the Trash and run this again, or allow Terminal under System Settings › Privacy & Security › App Management."
    }
    moved_old=1
  fi
  if ! mv "$staging" "$target"; then
    # Put the old TAB back, so a failed install never leaves the person with no TAB at all.
    if (( moved_old )) && [[ ! -e "$target" ]]; then mv "$TMP/$APP_NAME-old.app" "$target" || true; fi
    rm -rf "$staging"
    fail "Couldn't put TAB into $dir. Your old TAB is still there."
  fi
  STAGING=""
  say "Installed $target"
}

# Moves an old TUM.app (TAB's name before the rename) to the Trash. TAB brings its settings
# and sign-ins over on first launch. Only an app with TUM's exact bundle id is ever moved.
retire_old() {
  local dir="$1" app="$1/$OLD_NAME.app" dest i
  [[ -d "$app" && ! -L "$app" ]] || return 0
  [[ "$(bundle_id "$app" || true)" == "$OLD_BUNDLE_ID" ]] || return 0
  if pgrep -qf "/${OLD_NAME}\.app/Contents/MacOS/${OLD_NAME}\$"; then
    osascript -e "quit app id \"$OLD_BUNDLE_ID\"" >/dev/null 2>&1 || true
    for i in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -qf "/${OLD_NAME}\.app/Contents/MacOS/${OLD_NAME}\$" || break
      sleep 0.5
    done
  fi
  dest="$HOME/.Trash/$OLD_NAME.app"
  if [[ -e "$dest" ]]; then dest="$HOME/.Trash/$OLD_NAME $(date +%Y-%m-%d-%H%M%S).app"; fi
  if mv "$app" "$dest" 2>/dev/null; then
    say "Moved the old TUM to the Trash. TAB keeps its settings and sign-ins."
  else
    say "The old TUM is still in $dir. Drag it to the Trash; TAB already has its settings."
  fi
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
  [[ "$ZIP_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "This copy of the installer has no fingerprint. Get it again from github.com/$REPO."

  local dir target
  dir="$(pick_target_dir)"
  target="$dir/$APP_NAME.app"

  say "This installs TAB $VERSION, a menu bar app that shows how much AI usage you have left."
  say "It will:"
  say "  1. Download $ZIP_NAME from GitHub and check it against a known fingerprint."
  say "  2. Check the app's signature."
  say "  3. Put TAB in $dir, replacing any older TAB there (or TUM, its old name), and open it."
  say "It never asks for your password and changes nothing else on your Mac."
  say ""
  if (( ! yes )); then
    ask_yes "Install TAB? (y/n) " || { say "OK, nothing was installed."; exit 0; }
  fi

  check_target "$target"
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/tab-install.XXXXXX")"
  chmod 700 "$TMP"
  trap cleanup EXIT
  download
  unpack
  verify_app "$UNPACKED/$APP_NAME.app"
  quit_running "$target"
  install_app "$UNPACKED/$APP_NAME.app" "$dir"
  retire_old "$dir"

  if (( open_after )); then
    if open "$target" 2>/dev/null; then
      say "TAB is opening. Look for its round icon at the right end of the menu bar."
    else
      say "Open TAB from $dir to start it."
    fi
  fi
  say ""
  say "To uninstall later, drag TAB from $dir to the Trash, or run:"
  say "  curl -fsSL https://raw.githubusercontent.com/$REPO/v$VERSION/uninstall.sh | bash"
}

main "$@"
