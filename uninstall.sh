#!/bin/bash
# Removes TAB (Track AI Balance) from this Mac.
#
#   curl -fsSL https://raw.githubusercontent.com/araje-bot/TAB-Track-AI-Balance/v0.2.2/uninstall.sh | bash
#
# Quits TAB and moves TAB.app to the Trash. Settings, the diagnostics log and TAB's own sign-ins
# are left alone and explained at the end, so nothing you may want is deleted by surprise.
#
# Options:  --yes   don't ask
#           --all   also delete TAB's settings and diagnostics log (never Keychain items)
set -euo pipefail

readonly APP_NAME="TAB"
readonly BUNDLE_ID="edu.umd.inst474.tab"
readonly OLD_BUNDLE_ID="edu.umd.inst474.tum"   # TAB's name before the rename

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
    say "Quitting TAB…"
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
  [[ "$(uname -s)" == "Darwin" ]] || fail "TAB runs on macOS only."

  # Only a real TAB.app (right bundle id, not a link) is ever moved.
  local found=() dir app
  for dir in /Applications "$HOME/Applications"; do
    app="$dir/$APP_NAME.app"
    [[ -d "$app" && ! -L "$app" ]] || continue
    [[ "$(bundle_id "$app" || true)" == "$BUNDLE_ID" ]] || continue
    found+=("$app")
  done
  if (( ${#found[@]} == 0 )); then
    say "TAB isn't in /Applications or ~/Applications, so there is nothing to remove."
    exit 0
  fi

  say "This moves ${found[*]} to the Trash."
  if (( all )); then say "It also deletes TAB's settings and diagnostics log."; fi
  if (( ! yes )); then
    ask_yes "Remove TAB? (y/n) " || { say "OK, nothing was changed."; exit 0; }
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
    # TAB's settings from before the rename (TUM), so a later install starts fresh.
    defaults delete "$OLD_BUNDLE_ID" >/dev/null 2>&1 || true
    if [[ -d "$HOME/Library/Logs/$APP_NAME" ]]; then rm -rf "$HOME/Library/Logs/$APP_NAME"; fi
    say "Deleted TAB's settings and diagnostics log."
  else
    say ""
    say "Left in place, in case you install TAB again:"
    say "  Settings:     defaults delete $BUNDLE_ID"
    say "  Diagnostics:  rm -r ~/Library/Logs/$APP_NAME"
  fi
  say ""
  say "If \"Open at login\" was on, remove TAB under System Settings › General › Login Items."
  say "If you connected Cursor, Grok Bot, GitHub Copilot, Gemini or ChatGPT through TAB's own sign-in,"
  say "these items may remain in your Keychain: \"TAB Cursor sign-in\", \"TAB GitHub sign-in\","
  say "\"TAB Gemini sign-in\" and \"TAB ChatGPT sign-in\" (before the rename they started with \"TUM\"). Delete them in Keychain"
  say "Access if you like. You can also revoke the access at cursor.com or"
  say "github.com/settings/applications, and sign out of Google at myaccount.google.com."
  say "TAB never changed any other app's sign-in, so there is nothing else to undo."
}

main "$@"
