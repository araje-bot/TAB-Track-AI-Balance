# TUM security review

Date: 2026-11-04. Scope: every Swift file in `Sources/`, `Package.swift`, `make_dmg.sh`, `dev.sh`, `build.sh`, `README.md`, `SECURITY.md`, `.gitignore`, and the planned `curl | bash` installer. Code was read line by line; nothing was run against real accounts, and no real credential or log files were opened.

## Summary

| Severity | Count | Short version |
|---|---|---|
| Critical | 0 | |
| High | 0 | |
| Medium | 9 | Write-back can sign people out of Claude Code or Codex; borrowed app identities; no backoff on errors; log can hold emails; docs promise more than the code does; Keychain trust resets every release; stale Intel build risk; installer requirements |
| Low | 14 | Crashes on "nan" numbers; device-flow URL host not checked; redirect port; timeouts; log file mode; SQLite symlink; debug flags in release; and more |
| Info | 10 | Dead code, leftover tokens on uninstall, small doc drift |

No token, refresh token, cookie or auth header is ever written to the log, put in settings, or sent to a different company's server. The real risks are about reliability of other apps' sign-ins, honesty of the privacy wording, and robustness.

## What is already done well

- Network: ephemeral `URLSession` with no cache, cookies or credential store; HTTPS only; TLS 1.2 or newer; no custom certificate trust; redirects only to the same host.
- Every request URL is a fixed `https://` constant. Each token goes only to its own company.
- Cursor sign-in uses PKCE with 32 bytes from `SecRandomCopyBytes` and an S256 challenge; polling stops after 5 minutes.
- TUM's own Keychain items are not synced to iCloud and are deleted on Remove.
- Nothing touches the Keychain before onboarding finishes; background reads are silent.
- Log: key names and status codes only, 0600 file in a 0700 folder, capped at 512 KB.
- Write-backs are atomic, 0600, and skipped if the file changed.
- No keystroke monitoring (no CGEventTap, no key state polling in active code). The shortcut uses Carbon `RegisterEventHotKey`.
- App detection never runs code from other apps and never reads their Info.plist values.
- `make_dmg.sh` uses `set -euo pipefail`, a `mktemp -d` work folder with cleanup, hardened runtime, and the self-test gates the DMG.
- All Developer menu code is inside `#if DEBUG`.

## Medium

### M1. Renewing another app's sign-in can sign the person out of that app
`Providers.swift:311-331` (Claude Code), `543-559` (Codex), `884-903` (Grok), `writeBack` at `205-221`.

TUM spends the file's refresh token first, and only then checks whether the file changed. If the app (Claude Code, Codex) touched the file in the meantime, TUM throws away the new tokens. Anthropic and OpenAI rotate refresh tokens, so the old one in the file may now be dead, and the app signs the person out on its next renewal.

Fix options:
1. Simplest and safest: never renew other apps' sign-ins. When a token has expired, show "Open Claude Code once" (TUM already does this for Keychain sign-ins).
2. Or: re-read the file just before renewing, compare only the token part afterwards, merge instead of discarding, and hold a file lock.

### M2. Borrowed app identities (terms and trust risk)
`Providers.swift:935` GitHub device flow uses Copilot's app id, so GitHub's approval page shows "GitHub Copilot", not TUM, and the token carries Copilot's permissions. `:1069-1070` sends VS Code and Copilot Chat version headers. `:337` sends a Claude Code User-Agent. `:234, :496, :614, :863, :908` use Claude Code, Codex, Cursor and Grok client ids.

Risk: a service treats this as impersonation and blocks accounts, or a user finds "GitHub Copilot" in their authorized apps without knowing TUM did it.

Fix: register TUM's own GitHub OAuth App (free, device flow needs no secret) and test it; send `TUM/0.1` as the User-Agent wherever the service accepts it; list the borrowed ids plainly in the README. This is AK's open release decision 2.

### M3. No backoff on errors; a broken sign-in calls the service every minute
`App.swift:180-187`, `Store.swift:318-340`, `MenuBar.swift:282`.

Backoff only happens on HTTP 429. After a reset time passes and the next check fails (401, revoked token, server error), the 60-second timer keeps retrying, and for file sign-ins also tries to renew each time. That can be about 2,880 requests a day, which can look like abuse.

Fix: exponential backoff for every error (1, 2, 4 ... 60 minutes), cleared on success or on a manual "Update now"; skip apps with an error in the 60-second loop; make the popover's refresh respect the minimum gap.

### M4. 429 ignores `Retry-After`
`Util.swift:235` always waits 5 minutes, and "Update now" clears the wait every click (`Store.swift:579`). Fix: honor `Retry-After`, double on repeats, and let manual updates override at most once a minute.

### M5. The diagnostics log can contain emails and short ids
`Util.swift:225-233`, copied by `Settings.swift:146-147`.

On an error, TUM logs up to 140 characters of the service's `message`, `detail`, `error_description` and similar fields. Only runs of 30 or more letters and digits are hidden, so emails, names and shorter ids pass through. Newlines also pass through, so a reply can forge fake log lines. "Copy diagnostics" puts the whole log on the clipboard, and people will paste it into public GitHub issues.

Fix: log only short error codes that match `^[A-Za-z0-9_.-]{1,64}$` (like `invalid_grant`) and drop free text. Also scrub the text in "Copy diagnostics".

### M6. Privacy wording promises more than the code does
- "TUM never sees your prompts" (`Onboarding.swift:513`, `SECURITY.md`): the Codex reader loads the last 512 KB of Codex session files into memory, and those files hold prompts. TUM only parses usage lines and never stores or sends the rest, but "never sees" is not strictly true.
- "Sign-ins stay on your Mac" (`Onboarding.swift:149`, `Settings.swift:36`): each sign-in is sent to its own company to check usage. Better wording is "TUM has no server. Each sign-in goes only to its own company."
- `SECURITY.md` says tokens are held in memory only and TUM stores only the Cursor sign-in. TUM also stores a GitHub sign-in and writes renewed tokens back to Claude Code, Codex and Grok files. Copilot is missing from its table, and it still describes the old ⌘ Tab feature.
- `README.md` still lists old shortcuts, says Cursor needs the Cursor app signed in, says TUM "never copies" sign-ins, and includes a personal path.

Fix: rewrite `SECURITY.md` and the README "What it reads" section from the actual code, and soften the UI wording.

### M7. Keychain trust resets on every release
`Providers.swift:696-702, 1004-1007`. TUM's items use the older file keychain, where access is tied to the app's ad-hoc signature, which changes with every build. Each update loses silent access, so people get used to clicking "Always Allow" again. A fake TUM DMG would get the same prompts and the same grants, including the `Claude Safe Storage` key that decrypts all of Claude desktop's stored data.

Fix: the real fix is a stable signing identity (Developer ID or a university team). Without it, publish SHA-256 checksums for every DMG and explain the prompts in the README.

### M8. `make_dmg.sh` can ship an old Intel build
`make_dmg.sh:37-56`. `.build/universal/` is never cleared. If the Intel build fails, the Intel binary from an earlier run is reused, so a universal app ships with outdated Intel code. Fix: `rm -rf .build/universal` first, and fail the release if the Intel build fails.

### M9. Requirements for the planned `curl | bash` installer
curl does not mark downloads as quarantined, so macOS never checks the app. The script is the only integrity check, so it must:
1. Be fetched from a tagged URL (`.../v0.1.0/install.sh`), never `main`; wrap everything in `main()` and call it on the last line; `set -euo pipefail`.
2. Download only over `https` with `curl --proto '=https' --tlsv1.2 -fsSL`, from a pinned release tag.
3. Check a SHA-256 hard-coded in the script for that release; stop on mismatch.
4. Work in `mktemp -d`, mount read-only with `hdiutil attach -nobrowse -readonly -noautoopen`, clean up in a `trap`.
5. Verify the app with `codesign --verify --strict` and check its bundle id.
6. Install only to `/Applications/TUM.app` (or `~/Applications`), never with sudo; refuse symlinks; quit the old copy by bundle id.
7. No `eval`, no second downloads; print what it does; document how to uninstall.
8. `make_dmg.sh` should print the DMG's SHA-256 for release notes and set a real build number.

## Low

| # | Where | Issue | Fix |
|---|---|---|---|
| L1 | `Util.swift:78` and callers `Util.swift:285`, `Providers.swift:324, 594-598, 963` | `J.num` accepts the strings "nan" and "inf"; converting those to `Int` crashes. A Codex session line with `"timestamp":"nan"` can crash TUM on every launch. | Reject non-finite numbers in `J.num`; clamp the GitHub poll interval to 1 to 60 seconds and token lifetimes to a sane range. |
| L2 | `Providers.swift:953, 960`, `Onboarding.swift:615` | GitHub's `verification_uri` is opened after checking only `https`. | Always open the constant `https://github.com/login/device`. |
| L3 | `Util.swift:247-248` | Redirects compare host and scheme but not port. | Refuse all redirects; none of these APIs need them. |
| L4 | `Util.swift:216` | 20 s is an idle timeout only; no total timeout or size limit. | `timeoutIntervalForResource = 30`; reject bodies over 1 MB. |
| L5 | `Util.swift:150-165` | Log folder mode is only set on creation; trimming writes a 0644 file before chmod; follows symlinks; can cut a line in half. | Always chmod the folder to 0700; open with `O_NOFOLLOW` and mode 0600; trim at a newline. |
| L6 | `Providers.swift:214-215` | Write-back creates the new file as 0644 for a moment before chmod. | Write a 0600 temp file in the same folder, then rename. |
| L7 | `Providers.swift:123-128` | The SQLite copy follows a symlink into the live cookie database, and a crash leaves the copy in the temp folder. | Skip non-regular files; add `SQLITE_OPEN_NOFOLLOW`; delete leftover `tum-*` temp folders at launch. |
| L8 | `Providers.swift:98-103, 669-674, 996-999, 753` | Keychain update and delete for TUM's own items are not silent-guarded and errors are ignored, so Remove can say "removed" while the token stays. | Route them through the silent wrapper and check the result. |
| L9 | `Providers.swift:69-85` | A background silent read can block an interactive Connect at the same moment. | Hold the same lock for interactive reads. |
| L10 | `Providers.swift:708-728` | Cursor and Grok Bot can renew the same Cursor token at the same time. | Share one in-flight renewal. |
| L11 | `Providers.swift:869-872, 888-889` | Grok picks the first entry with a "key" in random order. | Choose the xAI entry by its issuer key. |
| L12 | `App.swift:8-18`, `SelfTest.swift:224-234` | Release builds accept `--export-icon <path>` and `--snapshots <dir>`, which overwrite any path and render real app data. | Put them behind `#if DEBUG` or an environment flag only the build scripts set. |
| L13 | `App.swift:195-197`, `25-31` | Any process can post the "show yourself" notice; any app with TUM's bundle id makes TUM quit at launch. | Accept the notice only right after a second launch; log the conflict. |
| L14 | `Settings.swift:136-139` | "Open at login" can register the app while it runs from the mounted DMG. | Only allow it when TUM is in `/Applications` or `~/Applications`. |

## Info

- `SwitcherWatcher` (`MenuBar.swift:425-556`) is dead code that polls modifier keys and can log other apps' window names. Delete it, along with its self-test checks.
- `Store.preview` sets `onboardingDone`, which flips the global silent-Keychain flag for the whole process (`Store.swift:56`, `SampleData.swift:46`). Only touch the flag for the real store.
- If Cursor connects but the first usage check fails, the `TUM Cursor sign-in` item stays (`Store.swift:188-192`). Uninstalling also leaves both TUM Keychain items. Document how to remove them.
- `ClaudeDesktop.cachedKey` stays in memory after Claude is removed. Clear it on disconnect.
- Unused code: `SafeStorage.key`, `bytes(fromStored:)` (`Providers.swift:173-199`).
- `build.sh` signs without hardened runtime and hides signing failures; the README points to it. Remove it or point to `make_dmg.sh`.
- `dev.sh` and `build.sh` use `pkill -x TUM`, which kills any process named TUM. Quit by bundle id instead.
- `.gitignore` sits in `TUMApp/`; if the repo root is `TUM/`, add a root `.gitignore`, and add `*.log`, `.claude/`, `xcuserdata/`, `.env`, `*.p12`. Decide whether `CLAUDE.md` and `HANDOFF.md` should be public.
- `Activity.swift:69` path check lacks a trailing `/`; require regular files under 50 MB.
- Crash reasons are logged as-is (`App.swift:43`); truncate them.

## Recommended order

1. Before any public release: M1 (stop or fix write-back), M5 (log scrubbing), M6 (honest wording and docs), L1 (crash), M8 (stale build), L12 (release flags), M3 and M4 (backoff).
2. Before the installer goes live: M9, plus SHA-256 checksums in every release.
3. When possible: M2 (own GitHub app and honest User-Agent) and M7 (stable signing).
4. The remaining Low and Info items.

## Status after fixes (2026-11-04)

Fixed and verified (debug and release builds, 70 self-test checks):
- **M1:** TUM no longer renews or writes other apps' sign-ins (Claude Code, Codex, Grok). An expired sign-in shows "Open <app> once". The write-back code and those client ids are gone. TUM still renews only its own Cursor sign-in.
- **M3, M4:** every failed check backs off 1, 2, 4 ... 60 minutes; 429 honors `Retry-After` (5 minutes to 1 day); "Update now" skips the wait at most once a minute.
- **M5, L4 of the log:** only short error codes (like `invalid_grant`) are logged; free-text service messages are never logged.
- **M6:** UI wording, `SECURITY.md` and `README.md` now match the code.
- **M8:** `make_dmg.sh` starts from a clean folder, fails if the Intel build fails, and prints and saves the DMG's SHA-256.
- **L1:** non-finite numbers are rejected (new self-test check); GitHub poll interval and deadline are clamped.
- **L2:** GitHub's device page must be `https://github.com`.
- **L4 (network):** 30 second total timeout; replies over 1 MB refused.
- **L12:** `--export-icon` and `--snapshots` only work when the build scripts set `TUM_BUILD_TOOLS=1`.
- Grok now picks its entry in a fixed order (part of L11).

Still open (decisions or later work): M2 (own GitHub app, honest User-Agent), M7 (stable signing), M9 (write the installer to these rules), L3, L5 to L10, L13, L14, and the Info items.
