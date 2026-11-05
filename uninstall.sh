#!/bin/bash
# Removes TUM (Token Utilization Monitor) from this Mac.
#
#   curl -fsSL https://raw.githubusercontent.com/araje-bot/TUM-Token-Utilization-Monitor/v0.1.0/uninstall.sh | bash
#
# Quits TUM and moves TUM.app to the Trash. Settings, the diagnostics log and TUM's own sign-ins
# are left alone and explained at the end, so nothing you may want is deleted by surprise.
#
# Options:  --yes   don't ask
#           --all   also delete TUM's settings and diagnostics log (never Keychain items)
set -euo pipefail

readonly APP_NAME="TUM"
readonly BUNDLE_ID="edu.umd.inst474.tum"

say() { printf '%s\n' "$*"; }
fail() { say ""; say "Stopped: $*" >&2; exit 1; }

ask_yes() {
  local answer=""
  if ( : < /dev/tty ) 2>/dev/null; then
    printf '%s' "$1" > /dev/tty
    read -r answer < /dev/tty || true
  else
    fail "No terminal to ask on. Run again with --yes."
  fi
  case "$answer" in y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac
}

bundle_id() { /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null; }

quit_running() {
  if pgrep -qf "/${APP_NAME}\.app/Contents/MacOS/${APP_NAME}\$"; then
    say "Quitting TUM…"
    osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -qf "/${APP_NAME}\.app/Contents/MacOS/${APP_NAME}\$" || break
      sleep 0.5
    done
  fi
}

main() {
  local yes=0 all=0 a
  for a in "$@"; do
    case "$a" in
      --yes|-y) yes=1 ;;
      --all) all=1 ;;
      -h|--help) say "Usage: uninstall.sh [--yes] [--all]"; exit 0 ;;
      *) fail "Unknown option: $a" ;;
    esac
  done
  [[ "$(uname -s)" == "Darwin" ]] || fail "TUM runs on macOS only."

  # Only a real TUM.app (right bundle id, not a link) is ever moved.
  local found=() dir app
  for dir in /Applications "$HOME/Applications"; do
    app="$dir/$APP_NAME.app"
    [[ -d "$app" && ! -L "$app" ]] || continue
    [[ "$(bundle_id "$app" || true)" == "$BUNDLE_ID" ]] || continue
    found+=("$app")
  done
  if (( ${#found[@]} == 0 )); then
    say "TUM isn't in /Applications or ~/Applications, so there is nothing to remove."
    exit 0
  fi

  say "This moves ${found[*]} to the Trash."
  if (( all )); then say "It also deletes TUM's settings and diagnostics log."; fi
  if (( ! yes )); then
    ask_yes "Remove TUM? (y/n) " || { say "OK, nothing was changed."; exit 0; }
  fi

  quit_running
  local trash="$HOME/.Trash" dest
  mkdir -p "$trash"
  for app in "${found[@]}"; do
    dest="$trash/$APP_NAME.app"
    if [[ -e "$dest" ]]; then dest="$trash/$APP_NAME $(date +%Y-%m-%d-%H%M%S).app"; fi
    mv "$app" "$dest" || fail "Couldn't move $app to the Trash."
    say "Moved $app to the Trash."
  done

  if (( all )); then
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    if [[ -d "$HOME/Library/Logs/$APP_NAME" ]]; then rm -rf "$HOME/Library/Logs/$APP_NAME"; fi
    say "Deleted TUM's settings and diagnostics log."
  else
    say ""
    say "Left in place, in case you install TUM again:"
    say "  Settings:     defaults delete $BUNDLE_ID"
    say "  Diagnostics:  rm -r ~/Library/Logs/$APP_NAME"
  fi
  say ""
  say "If \"Open at login\" was on, remove TUM under System Settings › General › Login Items."
  say "If you connected Cursor, Grok Bot or GitHub Copilot through TUM's own sign-in, two items may"
  say "remain in your Keychain: \"TUM Cursor sign-in\" and \"TUM GitHub sign-in\". Delete them in"
  say "Keychain Access if you like, and revoke the access at cursor.com or github.com/settings/applications."
  say "TUM never changed any other app's sign-in, so there is nothing else to undo."
}

main "$@"
