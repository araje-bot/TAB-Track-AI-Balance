# TUM private test release: plan

Goal: put TUM on GitHub as a **private** repository, and let invited testers install it with **one Terminal command**, with no "may contain malware" warning. Every step is written so Claude Code can run it, with AK approving the steps marked **AK**.

Status on 2026-11-04: the app builds (`./make_dmg.sh`), passes 75 release checks, and the first security review is done (`SECURITY-REVIEW.md`). Nothing is in git yet. The `gh` command isn't installed.

---

## The one problem to solve first: private repos and `curl`

A one-line `curl` install only works if `curl` can download the files without signing in. Files in a **private** repo (the install script and the DMG in its Releases) need a GitHub sign-in, so a plain `curl` gets "404 Not Found".

| Option | How testers install | Source code | Good for |
|---|---|---|---|
| **A. Two repos (recommended)** | `curl -fsSL https://raw.githubusercontent.com/<you>/tum-install/v0.1.0/install.sh \| bash` | Private repo `tum` | Anyone you send the link to, no GitHub account needed |
| B. Private repo only, testers invited | Testers install the `gh` tool, sign in, then run `gh api ... \| bash` | Private repo `tum` | Technical testers who have GitHub accounts |

**Option A explained:** the code stays in a private repo `tum`. A second, **public** repo `tum-install` holds only three things: `install.sh`, the built DMG attached to a Release, and a short README. No source code is public. Anyone with the command can install TUM, but the link isn't listed anywhere, so in practice only the people you send it to will find it.

**Option B explained:** nothing is public, but each tester needs a GitHub account, an invite to the repo, and the `gh` tool, which is too much for non-technical testers.

**AK decides:** A or B. The rest of this plan assumes **A**. Steps that change for B are marked.

---

## Phase 0: decisions and accounts (AK)

1. **AK:** choose Option A or B.
2. **AK:** GitHub username, and repo names (suggested `tum` private, `tum-install` public).
3. **AK:** license for later open source (MIT or Apache-2.0). Not needed for private testing; put "All rights reserved" in the README for now.
4. **AK:** decide whether `CLAUDE.md`, `HANDOFF.md` and `SECURITY-REVIEW.md` go into the private repo. They are internal notes; private is fine, but they must never go into the public `tum-install` repo.
5. Install the GitHub command line tool and sign in. These are one-time steps on AK's Mac:
   ```
   brew install gh          # or download from https://cli.github.com
   gh auth login            # choose GitHub.com, HTTPS, log in with a browser
   ```
   Never paste a GitHub token into a chat, a file or a commit.

---

## Phase 1: critical security review (before anything leaves this Mac)

The first review found no critical or high issues and fixed the release blockers. This pass is stricter and also covers what changed since and the new installer.

**Prompt for Claude Code:**
> Read `TUMApp/SECURITY-REVIEW.md` and `TUMApp/SECURITY.md`. Do a fresh, adversarial security review of everything in `TUMApp/` as if TUM were about to be installed on strangers' Macs with one Terminal command. Use three parallel reviewers: (1) sign-ins, Keychain and tokens, (2) network, logs and privacy wording, (3) app, build, git hygiene and the installer. Verify every finding against the code. Fix every Critical, High and Medium finding, plus the open Low items L3, L5, L6, L7, L8, L13, L14 from SECURITY-REVIEW.md. Remove dead code (`SwitcherWatcher`, unused `SafeStorage` helpers). Then run `./dev.sh --test` and `./make_dmg.sh`, both must pass. Update SECURITY-REVIEW.md with what was fixed and what is still open. Never print or log tokens and never open real credential files.

**Must be true before Phase 2 (checklist):**
- [ ] No Critical, High or Medium findings left open.
- [ ] `grep -rn "eyJ\|ghp_\|gho_\|sk-ant\|BEGIN PRIVATE" TUMApp` finds nothing (no secrets in files).
- [ ] No personal paths or emails in files that will be committed (`grep -rn "araje\|@gmail" TUMApp --include=*.swift --include=*.md --include=*.sh`; CLAUDE.md is the only allowed exception, and only in the private repo).
- [ ] `--export-icon` and `--snapshots` only work with `TUM_BUILD_TOOLS=1` (already done).
- [ ] TUM never changes other apps' sign-ins (already done).
- [ ] SECURITY.md matches the code.
- [ ] Release build passes all self-test checks.

---

## Phase 2: clean the folder for git

**Prompt for Claude Code:**
> In `TUMApp`, prepare for a first git commit. Update `.gitignore` to also cover `releases/`, `*.sha256`, `*.log`, `.claude/`, `xcuserdata/`, `*.xcuserstate`, `.env`, `*.p12`, `*.cer`, `*.mobileprovision`, `notarytool*`, `build-snapshots/`. Delete or rewrite `build.sh` so the README only points to `make_dmg.sh`. Change `dev.sh` and `build.sh` to quit TUM by bundle id, not `pkill -x TUM`. Make `make_dmg.sh` take the version from one place, use a real build number, and refuse to build if `git status` shows uncommitted changes (with an override flag for local testing). Show me `git status --ignored` before committing.

Then (Claude Code runs, AK approves):
```
cd TUMApp
git init -b main
git add .
git status            # AK checks the list: no DMGs, no logs, no snapshots
git commit -m "TUM 0.1.0, first private commit"
```

---

## Phase 3: private source repo

```
gh repo create tum --private --source . --remote origin --push
```
Then on github.com, in the repo's Settings:
- **Security › Secret scanning and Push protection:** turn both on (free for private repos owned by personal accounts where available; if not shown, skip).
- **Branches:** protect `main` (no force pushes).
- **Collaborators:** add teammates only if they need the code.

---

## Phase 4: the installer (`install.sh`)

**Prompt for Claude Code:**
> Write `TUMApp/install/install.sh` following every rule below, plus `TUMApp/install/uninstall.sh`. Test both on this Mac with a local file server, then show me the scripts.

Rules (from security review item M9, all required):
1. Starts with `#!/bin/bash` and `set -euo pipefail`. All logic lives in a `main()` function, and the last line is `main "$@"`, so a half-downloaded script does nothing.
2. Prints in plain words what it will do, and asks "Install TUM? (y/n)" when run in a terminal.
3. Checks macOS 13 or later, and stops with a clear message otherwise.
4. Downloads the DMG with `curl --proto '=https' --tlsv1.2 -fsSL` from **one pinned release URL** (`.../releases/download/v0.1.0/TUM-0.1.0.dmg`), never "latest".
5. Checks the DMG's SHA-256 against a value **written into the script** for that release, with `shasum -a 256`. On a mismatch it stops and deletes the file.
6. Works only inside `mktemp -d`, and a `trap` always cleans up and detaches the disk image.
7. Mounts with `hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$tmp/mnt"`.
8. Checks the app with `codesign --verify --strict --deep` and checks its bundle id is `edu.umd.inst474.tum`.
9. Quits a running TUM by bundle id (`osascript -e 'quit app id "edu.umd.inst474.tum"'`), never `pkill`.
10. Installs only to `/Applications/TUM.app`, or `~/Applications/TUM.app` if `/Applications` isn't writable. Never uses `sudo`. Refuses if the target is a symlink or another app. Copies with `ditto` to a temporary name, then moves it into place.
11. No `eval`, no second downloads, no changes to system settings, and no blanket `xattr -d` on anything except the app it just verified.
12. Opens TUM at the end and prints how to uninstall.

`uninstall.sh` quits TUM by bundle id, moves `/Applications/TUM.app` to the Trash, and explains (without doing it automatically) how to remove TUM's Keychain items and settings.

**Option B change:** the script's download step uses `gh release download v0.1.0 --repo <you>/tum --pattern 'TUM-*.dmg'` instead of `curl`.

---

## Phase 5: build and publish a release

```
cd TUMApp
git tag v0.1.0 && git push origin v0.1.0
./make_dmg.sh                          # prints the SHA-256
```
1. Claude Code writes that SHA-256 into `install/install.sh`, commits, and tags the installer version.
2. **Option A:** create the public repo and its release (AK approves before it runs, because this makes files public):
   ```
   gh repo create tum-install --public --description "Installer for TUM test builds"
   # copy ONLY install.sh, uninstall.sh and a short README into it, commit, push, tag v0.1.0
   gh release create v0.1.0 build/TUM-0.1.0.dmg --repo <you>/tum-install --title "TUM 0.1.0 (test)" --notes "SHA-256: <hash>"
   ```
3. **Option B:** `gh release create v0.1.0 build/TUM-0.1.0.dmg --repo <you>/tum` and keep everything private.
4. Double-check the public repo contains no source code, no CLAUDE.md, and no notes.

---

## Phase 6: instructions for testers

**Prompt for Claude Code:**
> Write `README.md` for the `tum-install` repo for non-technical testers. One page, short plain sentences, no jargon. Sections: what TUM is (one line), what you need (a Mac with macOS 13 or later), Install (open Terminal from Spotlight, paste one line, press Return, type y), what happens next (TUM opens with the welcome screens; Claude may ask once to allow access, choose Always Allow), Uninstall (one line), and "Is this safe?" (what TUM reads, that it has no server, a link to the checksum, and that the script can be read before running).

The command testers paste:
```
curl -fsSL https://raw.githubusercontent.com/<you>/tum-install/v0.1.0/install.sh | bash
```
Also give testers the safer two-step form, which lets them read the script first:
```
curl -fsSL -o install-tum.sh https://raw.githubusercontent.com/<you>/tum-install/v0.1.0/install.sh
less install-tum.sh && bash install-tum.sh
```

---

## Phase 7: test like a real user (before sending to anyone)

1. On AK's Mac, create a fresh macOS user account (System Settings › Users & Groups), log in, and run the one-line command. This is the closest thing to a stranger's Mac.
2. Check: no malware warning, TUM opens, onboarding shows, Claude and Codex connect, the menu bar icon works, uninstall works.
3. Test a broken download: change one character of the checksum in a local copy of the script and confirm it refuses to install.
4. If possible, test on one Intel Mac and one Apple silicon Mac.
5. Delete the test user afterwards.

---

## Phase 8: each new test version

1. Make changes, `./dev.sh --test`.
2. Bump the version in one place, commit, tag `v0.1.1`.
3. `./make_dmg.sh`, put the new SHA-256 and URL into `install.sh`, commit, tag.
4. Publish the new release and the new install command (it contains the version).
5. Old command links keep installing the old version, so testers always get exactly what you tested.

---

## Things that stay true

- Apple will still treat TUM as unsigned. The one-line installer avoids the warning, but the DMG download path still shows "Open Anyway". Only an Apple Developer account removes that for everyone.
- Each update changes TUM's ad-hoc signature, so macOS may ask Keychain permission again after an update.
- The public `tum-install` link works for anyone who has it. Treat it like an unlisted link, not a secret.
