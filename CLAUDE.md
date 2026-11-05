# TUM (Token Utilization Monitor): brief for Claude Code

INST474 team project (UMD HCIM). A macOS menu bar app that shows how much AI usage is left across the AI apps a person uses. Target users are non-technical creative freelancers. Owner: AK (Akash Raje). Last updated 2026-11-04.

## How AK wants you to work
- Short, plain sentences. **Never use em dashes, anywhere** (code comments and UI copy included). Avoid colons in prose. No formal or AI-sounding phrasing.
- Work autonomously: build, read errors, fix, rebuild. Only stop for decisions that are truly his.
- **Never use browser automation or control his screen** unless he explicitly asks. Running build commands in this terminal is fine.
- Follow the team's Figma prototype exactly, plus the macOS 26 Liquid Glass HIG. Ask AK for the Figma link if you need it.
- He gives feedback as screenshots with short notes. Fix everything in one pass, then tell him in a few lines what changed.
- Keep everything in this folder. **Predicare is a separate project; never touch it.**
- **Privacy is a product requirement.** Never print or log tokens. Ask AK before reading another app's private sign-in files directly (for example `~/.grokbot` or Cursor's `state.vscdb`); use TUM's own diagnostics log instead, which records only names and shapes.

## Start here (each session)
1. Fast loop: `cd TUMApp && ./dev.sh --test`. Debug build, self-test, snapshots, relaunch. About 15 seconds.
2. Look at `TUMApp/build-snapshots/*.png` yourself (Read tool). `dev-*.png` are sample-data states from debug builds.
   - Offscreen captures can't draw two things. Glass and prominent buttons come out gray or black (the accent color shows in the real app), and scroll areas (app grid, Settings list) come out blank white. Both look fine in the real app and the Xcode canvas.
3. `./make_dmg.sh` only for final checks and sharing. All self-test checks must pass (74 now). It refuses to build with uncommitted changes (`--allow-dirty` for a local build).

## Two versions (AK, 2026-11-04)
- **TUM** (real use): installed from the DMG into /Applications, bundle id `edu.umd.inst474.tum`, its own settings. Release build, no Developer menu.
- **TUM Dev** (debugging): `./dev.sh` builds `$TMPDIR/tum-dev/TUM Dev.app`, and Xcode ⌘R runs the same identity (`Support/DebugInfo.plist`). Bundle id `edu.umd.inst474.tum.dev`, its own settings, an orange dot on its menu bar icon, pill previews and the Developer menu on right-click.
- They can run side by side. Debug builds only ever quit other debug copies, never the real TUM; dev.sh quits the old TUM Dev by bundle id. Both share TUM's own Keychain sign-ins (Cursor, GitHub).

## Fast dev loop (set up 2026-11-04)
- **Xcode canvas:** AK opens `TUMApp/Package.swift` in Xcode, opens `Sources/TUM/Previews.swift`, presses ⌥⌘↩ (refresh ⌥⌘P). One preview per screen and state, picked from the canvas tabs. Sample data comes from `Store.preview(apps:)`, which saves to a scratch defaults suite and never fetches (`Store.isPreview` blocks refresh).
- **Xcode ⌘R:** runs the debug build as a bare executable (no .app). Debug builds embed `Support/DebugInfo.plist` (Package.swift `-sectcreate`), so it is "TUM Dev" (`edu.umd.inst474.tum.dev`), sharing settings with dev.sh and separate from the installed app. Console noise about `com.apple.linkd.autoShortcut` comes from macOS for every TUM build, even the .app, and is harmless. It quits the installed TUM on launch so only one icon shows.
- **Developer menu** (right-click the menu bar icon, debug builds only, `Developer.swift`): onboarding steps 1 to 4, connect sheet, intro callout, quick view, fake states (white, yellow 24%, red 8%, then "Use real data"), and "Start fresh" (clears TUM settings, reopens).
- **Debug builds skip the per-build onboarding reset**, since every rebuild changes the executable date. Use Start fresh or the Developer menu instead.
- **`dev.sh`** flags: `--test` (self-test), `--no-run` (don't relaunch), `--no-shots`. The app is assembled in `$TMPDIR/tum-dev/TUM.app`. Log in `dev-log.txt`.

## Next tasks, in order
0. **Test release (AK, 2026-11-04):** the security pass, git, installer (`install.sh`, `uninstall.sh`) and tester README are done, and the code is in `github.com/araje-bot/TUM-Token-Utilization-Monitor` (pushed over SSH as araje-bot; `gh` is not installed). AK chose to make that one repo public (2026-11-04) instead of a separate installer repo, since a `curl` one-liner can't fetch from a private repo. Left for AK on the website: flip the repo to public, attach the DMG from the `./make_dmg.sh --update-installer` run to a `v0.1.0` release, then the real-user test (`RELEASE-PLAN.md` phase 7). The README says "all rights reserved" until AK picks a license.
1. **Open-source readiness (AK's goal):** anyone can download, install and connect their local apps without trouble, and the Coming soon apps get real support. See the plan in the 2026-11-04 session summary; decisions on signing and which apps first are AK's.
2. Cursor works (browser sign-in, 2026-11-04). Confirm Grok Bot too.
2. Release decisions (bottom of this file).

## Recent changes (compiled and self-tested 2026-11-04, not yet checked by AK in the app)
- **Cursor:** TUM's own browser sign-in only; no Cursor files are read. A renewal that answers `shouldLogout` signs TUM out and the card shows Connect again (`needsApproval`); an unreadable stored item is deleted; a sign-in made during Connect that doesn't end in a working connection is deleted again; a renewal still running when Cursor is removed is thrown away (`CursorAuth.generation`). Renewal logs `shouldLogout` and the new token's shape only. A 401 logs the service's short reason (`<provider> reason: ...`).
- **Hover tip:** hovering the menu bar icon (white icon or pill) shows a Liquid Glass panel after 0.12s, with one row per connected app (logo, name, Session/Weekly/Monthly, %). It hides on mouse exit or click. This replaced the system tooltip. Code: `HoverTracker`, `HoverTip`, `HoverTipController` in `MenuBar.swift`, `Store.tipRows`, `Store.kindName`.
- **Pill clipped in the menu bar:** the slot width now comes from `StatusItemController.slotWidth(urgentPct:)` (measured text width), not a SwiftUI sizer that lagged a frame behind.
- **Shortcut:** ⌘T by default (AK, knowing it takes ⌘T from other apps while TUM runs). Choices are two keys only: ⌘T, ⌥T, ⌥Space (`ShortcutChoice`). Existing installs moved to ⌘T once (`shortcutDefaultCommandT`). When another app owns the chosen shortcut, the row's subtitle says so; never insert a separate row (it made the form jump). Keys always have a "+" between them ("⌘ + T", AK), in the choices and in the hint "Press ⌘ + T to see all apps" (`ShortcutHint`). Registered exclusively, with automatic fallback if another app owns it.
- **⌘Tab overlay is off.** It is impossible without keystroke permission, which AK rejected, and the old `SwitcherWatcher` code is deleted. Switching into a low app shows a heads-up instead (at most once a minute per app, never while onboarding or Settings is open).
- **No access prompts before onboarding:** `Keychain.silentReadsAllowed` stays false until onboarding is done. Silent reads also set `kSecUseAuthenticationUIFail` and `SecKeychainSetUserInteractionAllowed(false)`, because the older "allow access" dialog ignores `LAContext`. `CursorAuth.available()` only checks that a sign-in exists and never decrypts.
- **Onboarding shows on every new install:** completion is tied to the installed build's executable modification date (`Store.buildStamp`, key `onboardingBuild`). Before a public release, decide whether updates should re-show it.
- **Copy:** app subtitles are one short line ("Tracked through Codex", "No usage data yet", "Coming soon", "Sign in to Cursor, then scan"). Sources are short ("Claude sign-in").
- **Onboarding spacing:** 40pt between the subtitle and the content.

## Project layout
- `TUMApp/`: SwiftPM app (`Package.swift`, swift-tools 5.9, macOS 13+, links sqlite3).
  - Two targets. `TUMKit` is a library with all the code (path `Sources/TUM`), so previews work. `TUM` is a thin launcher (`Sources/TUMLauncher/Launcher.swift`) that calls `TUMMain.main()`.
- `TUMApp/Sources/TUM/`:
  - `App.swift`: entry point, `AppDelegate`, `WindowHost`, `LaunchGuard`, Dock and menus, shortcut, heads-up.
  - `Store.swift`: state, settings, refresh, `connectAndCheck`, scanning, pill priority, tip rows.
  - `Providers.swift`: per-app usage readers plus `Keychain`, `SQLiteRead`, `SafeStorage`, `JWT` helpers.
  - `Activity.swift`: FSEvents refresh when an app is used; `CodexLocal` session-file reader.
  - `Detection.swift`: app catalog and auto-detection (helper apps like "URL Handler" are excluded).
  - `Onboarding.swift`: 4 steps, `ConnectSheet`, app cards, carousel demo, `TextStyle`.
  - `PopoverView.swift`, `MenuBar.swift` (status item, quick view, hover tip, hotkey, intro), `Settings.swift` ("Advanced settings").
  - `Components.swift`: `MorphMark`, `PillView`, `LiquidDot`, `TankMark`, `LiquidTile`, `GlyphMaker`, `ConnectButton`, `ShortcutHint`, `LimitIcon`.
  - `Glass.swift`: the HIG design layer (button styles, `contentCard`, `glassPanel`, `innerCard`, `Radius`), `SegmentedChoice`, `ScanButton`, `ShortcutChoice`.
  - `SelfTest.swift`: `--self-test` (74 checks) and `--snapshots <dir>` (debug builds add `dev-*` sample-data shots, including `dev-app-cards` outside a scroll view).
  - `Developer.swift` (debug only): Developer menu and fake states. `SampleData.swift` (all builds, since `--self-test` runs on release): `Store.preview`, `sampleLimits`, `useItLimits`.
  - `Previews.swift` (debug only): every `#Preview`.
  - `Util.swift` (Diagnostics, HTTP, `Files`, `headerSafe`, Palette, errors), `Models.swift`.
- `dev.sh` (fast debug loop), `make_dmg.sh` (full build and DMG; `--allow-dirty`, `--update-installer`), `install.sh` and `uninstall.sh` (the one-line installer, tested against a local file server), `README.md` (for testers: one command), `SECURITY.md`, `SECURITY-REVIEW.md`, `RELEASE-PLAN.md`, `HANDOFF.md` (a copy of this file, gitignored).

## Build, test, install
```
cd TUMApp && ./make_dmg.sh                           # universal build, SDK fix, sign, self-test, snapshots, DMG (clean git tree, or --allow-dirty)
/Applications/TUM.app/Contents/MacOS/TUM --self-test   # checks on the installed copy
killall TUM; defaults delete edu.umd.inst474.tum       # reset to a fresh user
```
- **Version history lives in `TUMApp/releases/`** (dated DMGs, never delete). `make_dmg.sh` wipes `build/` on every run, so it also copies each new DMG there. Nothing is installed in /Applications until AK installs a DMG himself.
- Bundle id `edu.umd.inst474.tum`. Ad-hoc signed. The `DEVELOPER_ID` and `NOTARY_PROFILE` env vars enable Developer ID signing and notarization.
- Logs: `~/Library/Logs/TUM/diagnostics.log` (key names and status codes only, never tokens).
- Xcode 27.2 SDK on macOS 26.6 (Apple silicon).

## Hard-won facts (don't regress these)
- **Security review (2026-11-04, `TUMApp/SECURITY-REVIEW.md`).** TUM never renews, rewrites or deletes other apps' sign-ins (AK's decision; renewing could sign people out). Only TUM's own Cursor sign-in is renewed. Logs hold only short error codes, never service messages. `--export-icon`/`--snapshots` need `TUM_BUILD_TOOLS=1`. Failed checks back off up to 60 minutes. Keep SECURITY.md in step with the code. Second review (same day, three parallel reviewers, everything fixed): log lines are cleaned (`Diagnostics.clean`, reply keys filtered in `J.keyPaths`, errors logged by kind through `Diagnostics.describe`, never by text), every file TUM reads goes through `Files.isSmallRegularFile`, every header value through `headerSafe`, `Keychain.update`/`delete` return a status and background updates never prompt, "Open at login" works only from Applications, `Store.isPreview` is false in release, and `make_dmg.sh` refuses a dirty tree.
- **Liquid Glass needs the real SDK in the binary.** SwiftPM and Xcode both record SDK 13.0 by default, so the app runs in compatibility mode with the old look. The `TUM` target's linker flag (`-platform_version macos 13.0 26.0`) fixes every build, Xcode ⌘R included. `make_dmg.sh` and `dev.sh` also run `xcrun vtool -set-build-version macos 13.0 <sdk>`, and the self-test checks it.
- **Build per arch and copy out via `--show-bin-path` before `lipo`.** The builds overwrite each other otherwise.
- **Assemble and sign in a temp dir, then `xattr -cr`.** Desktop's Finder xattrs break codesign.
- **`withExtendedLifetime(delegate)` in `main`.** NSApplication holds its delegate weakly, so a release build otherwise shows nothing.
- **No keystroke monitoring, ever.** No CGEventTap and no `CGEventSource.keyState`. Carbon `RegisterEventHotKey` is fine.
- **No surprise permission prompts.** Nothing touches the Keychain before onboarding finishes. After that, background reads are silent; a refused read shows an "Allow" button instead of a dialog.
- **Copy SQLite databases with `-wal`/`-shm` to a private temp dir before reading.** Immutable mode returned stale sign-ins.
- **Proto-JSON leaves fields out when they're 0.** A missing percent means 0% used (Cursor, Codex, Grok, Grok Bot).
- **Menu bar icon pinned far right** (`NSStatusItem Preferred Position TUM = 0`, `autosaveName "TUM"`), so the notch can't hide it. If it's hidden anyway, TUM opens a `FloatingPanel` at the top right instead of an off-screen popover.
- **Refresh is guarded** by `onboardingDone || interactive`.

## How each app connects (modeled on OpenUsage v0.7.16: read existing sign-ins, never ask the user to log in)
Reference: `git clone https://github.com/robinebers/openusage && git checkout v0.7.16`. Its newer main branch uses its own sign-in, so use v0.7.16.
- **Claude** (works; AK sees real numbers):
  - The Claude desktop app's `config.json` `oauth:tokenCacheV2`, Electron Safe Storage. The key is from Keychain `Claude Safe Storage`, PBKDF2-SHA1 with salt `saltysalt`, 1003 iterations, AES-128-CBC, IV of 16 spaces, `v10` prefix. The org comes from the `lastActiveOrg` cookie.
  - Then Claude Code (Keychain `Claude Code-credentials` or `~/.claude/.credentials.json`), read only. Expired means "Open Claude Code once".
  - Usage: `api.anthropic.com/api/oauth/usage` with `anthropic-beta: oauth-2025-04-20`. Session (`five_hour`) and weekly (`seven_day`) limits.
- **Codex** (works):
  - Reads `~/.codex/auth.json` or Keychain `Codex Auth`, read only (no renewal).
  - Usage: `chatgpt.com/backend-api/wham/usage`. Local session files are the fast path. ChatGPT limits come through Codex.
- **Cursor** (TUM's own browser sign-in, built 2026-11-04 with AK's OK, waiting for AK to test):
  - Current Cursor keeps a sign-in on disk that other apps can't use (the stored token was 583 characters, not a JWT, and was refused with `ERROR_NOT_LOGGED_IN`). OpenUsage's current main branch also signs in on its own. TUM no longer reads any Cursor files.
  - Connect opens `cursor.com/loginDeepControl?challenge=<PKCE>&uuid=<uuid>&mode=login&redirectTarget=cli`, then polls `api2.cursor.sh/auth/poll?uuid=&verifier=` every 2s for 5 minutes (404/202 means not yet). The result (`accessToken`, `refreshToken`) is saved in TUM's own Keychain item `TUM Cursor sign-in`.
  - The access token is a 60-day JWT. TUM renews it a week early with `api2.cursor.sh/oauth/token` (client `KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB`). The new access token is also the next refresh token. `shouldLogout` means connect again.
  - Removing Cursor or Grok Bot (when neither remains) deletes the Keychain item (`CursorAuth.signOut`, real store only, never as a side effect of removing another app). AK's browser sign-in worked on 2026-11-04 (JWT, 200s). Cards say "Needs a quick sign-in in your browser". Settings says "Its Cursor sign-in stays in your Keychain."
  - Usage: `api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage`, with `cursor.com/api/usage-summary` as the backup.
- **Grok Bot:** Cursor's "Sand" agent app. Same TUM Cursor sign-in, `DashboardService/GetSandUsageStatus`.
- **GitHub Copilot:** VS Code or GitHub CLI sign-ins are used when present. Otherwise Connect runs GitHub's device flow (`GitHubAuth`, Copilot's public app id `Iv1.b507a08c87ecfe98`, scope `read:user`): the sheet shows the code (copied to the clipboard) and opens github.com/login/device. The token lives only in TUM's Keychain item `TUM GitHub sign-in` and is deleted on Remove. Usage: `api.github.com/copilot_internal/user`.
- **Grok CLI:** `~/.grok/auth.json`, `cli-chat-proxy.grok.com/v1/billing?format=credits`.
- **Gemini CLI:** `~/.gemini/oauth_creds.json`. No embedded client secret; on expiry it asks the user to open Gemini CLI once.
- **GitHub Copilot:** token from `~/.config/github-copilot/*.json`, `~/.config/gh/hosts.yml`, or Keychain `gh:github.com`. Usage: `api.github.com/copilot_internal/user`.
- **ChatGPT is not listed** (AK, 2026-11-04). Its limits are Codex's and show there. `Detector.coveredElsewhere` also keeps the generic "GPT" keyword scan from adding it back; the self-test checks this.
- **Detect-only apps:** Perplexity, Microsoft Copilot, Antigravity, Kiro, Lovable, Zed, Windsurf, Ollama, LM Studio, Midjourney, ElevenLabs, Suno, Runway, Higgsfield.

## Design system (Apple HIG for macOS 26 first, rebuilt 2026-11-04 at AK's request)
- **Everything comes from the SDK.** No hard-coded font sizes, hex colors or corner radii in the UI. The only exceptions are the Figma menu bar pill (`Pill` colors in `Util.swift`) and the TUM logo (`AppLogo`).
- **Appearance:** follows the person's Light or Dark Mode. Never force `.darkAqua` or `.colorScheme(.dark)`. Snapshots save both (`light-*` files).
- **Type:** system text styles only (`.largeTitle`, `.title`, `.title2`, `.title3`, `.headline`, `.body`, `.callout`, `.subheadline`, `.caption`), in label colors (`.primary`, `.secondary`, `.tertiary`). `TextStyle` maps to these.
- **Color:** semantic and system colors (`Palette` in `Util.swift`): `.tint`/accent for the one main action and info icons, `.green` connected, `.orange` low text, `.red` almost out, `.yellow`/`.red`/`.blue` tile water.
- **Buttons:** one Liquid Glass family at one size (`ControlMetrics.size` = `.large`, all 28pt tall; the self-test checks Connect, back, text and main buttons match). `primaryButton()` `.glassProminent` capsule (one per view), `secondaryButton()` `.glass` capsule, `iconButton()` glass circle with a 16pt icon box (`SquareIcon`), `iconButton(prominent: true)` blue. Every text label goes through `ButtonText` (one min width, `ControlMetrics.minTextWidth`). The back button is an icon-only chevron.
- **Connect (Figma):** blue Liquid Glass circle with the plug tilted 45° (`ConnectButton`, `PlugGlyph`, 1.3pt stroke to match SF Symbols). Connected cards show a More button instead (see App groups).
- **Tabs (AK's final call, 2026-11-04):** every choice uses `SegmentedChoice`: a rounded track inside its section with one raised pill that slides between equal-width options (`matchedGeometryEffect`, spring 0.32), the pattern from Nil Coalescing's custom segmented control. Solid pill, not glass. One font weight for every option, so labels never shift. Plain buttons (clicks work inside forms), arrow keys, VoiceOver sees a segmented picker. Same look in the popover, onboarding and Settings. The system picker and AppKit `role = .tabs` (macOS 27 only) were tried and rejected.
- **Stable layout:** popover and quick view tiles use `displayOrder` (connection order), never re-sorted by mode. Values animate on `Motion.standard`. The menu bar slot width glides over 0.45s (`animateLength`), so neighboring menu bar icons slide instead of snapping.
- **Containers:** `Card` (`Glass.swift`): system fill, 18pt continuous corners (`Radius.card`), no border, 12pt padding. Never `GroupBox` (its corners are too square for macOS 26, AK). A card holding its own rounded block uses concentric corners: `Card(padding: p, cornerRadius: Radius.card + p)` (How TUM works). Grouped `Form` for Settings, where every row is a `SettingRow` (title plus a one-line plain-words subtitle on the left, control right, both centered, 48pt for every row; never `LabeledContent`, which baseline-aligns; switches go through it too, at `.regular`: a grouped form shrinks them to mini by default, which AK found too small, and large was too big). Onboarding's nudges box uses the same row. `Divider` between rows, `InfoRow` for icon rows.
- **Glass:** `.glassEffect` only on TUM's own floating layers (quick view, hover tip, fallback panel) via `glassPanel()`, which also sets the container shape. Blocks inside use `innerCard()` (concentric corners on macOS 26).
- **Radius:** `Radius.panel` 18 and `.tip` 12 for TUM's own glass panels, `.tile` 0.225 (the macOS app icon shape) for usage tiles. Real app icons are shown as they are, without a tile behind them.
- **Icons:** SF Symbols (`clock` session, `calendar` weekly, `N.circle.fill` step numbers). Shortcuts are written like menus ("⌘T") inside a plain sentence, not as keycaps.
- **Windows:** Settings has a real title bar title ("Advanced settings") and native subtitle ("Manage your apps, alerts and shortcut"). Onboarding keeps its large in-content title, like Apple's setup screens.
- **Usage tiles are circles** (`LiquidTile` = the pill's `LiquidDot`): dark circle tinted with its water color, the app's white logo centered, two waves flowing at different speeds (a calm muted blue when fine, since full blue was harsh; Figma `#FFB800` low, `#FF6165` almost out). Old numbers dim to 60% but keep flowing; only Reduce Motion stops it. Grid tiles are top-aligned so a row of icons always lines up; more apps start a new row.
- **Hover tip** is a `Grid`: the app's real logo (`AppTile`, 28pt, never a tiny water circle), name (max 104pt, tip at least 210pt wide; leading padding is trimmed by the app icon's built-in 10% margin with 4pt extra on the right because text reads lighter than a logo (AK), long names end in "…") on the left; on the right a `LimitTag` (limit icon and Session/Weekly/Monthly as plain secondary text, no background, following Usage monitoring), tags left-aligned in their column, then the % right-aligned. No text in the tip ever wraps; it widens instead.
- **Settings top:** the privacy promise is the first section ("Your info stays secure", large `lock.shield.fill`, one plain line). The bottom section only has Copy diagnostics and Quit TUM; there is no "Remove all" (AK).
- **Onboarding step 4:** three tall state cards (icon, name, a live line such as "At 25% or less"). "Getting low" has a 2pt system yellow border and previews the chosen "Turn yellow at" value live (HIG: show the effect of a setting right away), with a short pulse on change; a yellow `arrow.up` SF Symbol at `.title` semibold (one connected shape) leads from the settings card up to it. Setting rows add `SettingRow.formInset` (10pt) above and below, so they are 68pt like rows in the grouped Settings form.
- **Onboarding page motion (AK):** pages crossfade in place (`.opacity` on `Motion.page`, `.smooth(duration: 0.35)`), the system standard for swapping a window's content. Each page (title and content) is one view in a ZStack keyed by `.id(step)`, so old and new overlap exactly. Slide and push versions were tried and rejected.
- **Pills at larger sizes:** use `PillView(scale:)`, never `scaleEffect` (the logo is flattened first and blurs). The welcome screen `AppLogo(flowing: true)` animates its water like the usage circles.
- **Connected status:** rows just say "Connected". After "Update now" they show "Connected · Updating…", then "Connected · Just now" for 4s (`Store.justUpdated`), then "Connected" again (AK: less clutter). Errors still show.
- **Loading (AK, from a macOS 26 / Xcode screenshot):** every spinner is `ActivityRing` (Components.swift): a thin gray track with a lighter arc turning, drawn from SDK shapes in label colors. Never the spokes `ProgressView()` or a rotating symbol. Reduce Motion fades instead of turning.
- **Popover anchor (AK):** the popover and intro callout point at a tiny invisible panel (`anchorPanel`) placed over the icon's spot at the slot's right end when they open. Anchoring to the status button itself made the popover slide while the slot resized (pill to icon when switching tabs); `positioningRect` updates and a pinned subview did not fix it. The self-test opens the real popover, flips pill to icon, and checks the popover frame doesn't move.
- **Debug builds:** the newest copy kills other debug copies (executable named TUM whose bundle id isn't the real one), so only one TUM Dev icon shows. A copy paused in Xcode's debugger can't be killed; stop it in Xcode.
- **Tabs are Session, Weekly, Monthly (AK, "Both" removed).** `WatchMode.period(of:)` maps limits (daily counts as session). The popover grid lists only apps with a limit of that period (`Store.tabApps`; apps with no numbers yet stay); an empty tab says "No monthly limits". Warnings still use every app (an app without that period falls back to its own limits), and opening TUM on a warning for an app not on the tab switches to its tab (`showTipTab`). Old "Both" settings start on Session.
- **"Got it" (AK):** the yellow, red and green status lines have a "Got it" button. On a warning it hides the line and turns the pill back to the icon until that app reaches a new level (`Store.acknowledged`, cleared when the level changes or the app recovers). On a tip it marks it seen until the next reset (`markUseItSeen`). Opening TUM no longer clears the green pill. Clicking the green pill opens the tab the tip is about (`showTipTab`). The tip icon is `lightbulb.fill` (no sparkles); copy is "Codex has 85% left and resets tomorrow at 7 AM."
- **Popover title:** "Token Utilization Monitor".
- **Copy voice (AK):** say what happens and what to click, in one short line, with no jargon (never "sign-in token", "read-only", "Keychain", "Needs your OK"). An app that needs the macOS permission step shows the blue Connect button, never "Allow" next to "Remove". Remove only appears on fully connected apps.
- **Scanning (HIG):** `FindAppsButton` is one glass icon button with `arrow.clockwise` that never moves. While scanning, the arrow inside the circle is replaced by `ActivityRing` and the button is disabled. The SF Symbols Rotate effect on the arrow was tried and rejected by AK. On onboarding step 3 it sits on the title line, centered on it. Tooltip and VoiceOver: "Scan for more apps". TUM also scans on its own when onboarding or Settings opens.
- **App icons:** the installed app's real icon first, then its official logo (`BrandLogos.swift`: Simple Icons CC0 marks on brand colors, or icons from each company's site, drawn on the macOS app icon grid; black brands use the light version, a black mark on white, and site icons fill the tile), then a neutral symbol on the same grid. Midjourney and Microsoft Copilot publish no usable icon yet. Coming soon icons show in normal colors (AK): there's no button, so nothing needs to look disabled. White pill and circle logos use the official mark when there is one.
- **Popover detail (one app):** back button and app name in one header row, the app's circle, then one card ("Finish connecting" with a single Connect button, or the tabs plus the limits card), then "Update now" and Remove at equal width. It sizes to its content (no fixed height). Never an "Open Claude"-style button (AK). Opening it pushes in from the right and Back slides out (`Motion.morph`), and the popover glides between measured heights.
- **The core rule (AK, the product's selling point):** healthy apps keep the white icon. At or under "Turn yellow at" (20, 25 or 40%, default 25%) the icon becomes the yellow pill; at 10% or less it is always red (`Store.redAt`, not a setting). The same levels color the water circles. The status line appears only for yellow and red, never for "needs a click" or old numbers.
- **Use it before it resets (AK, the differentiator):** `Store.useItTips` lists apps whose weekly, monthly or daily limit resets within a day with at least 50% left, or within three days with 80% or more left (`Store.worthUsing`; the 5-hour session limit never counts, and apps that are low never appear). It is checked on every refresh (launch, wake, app use). The newest unseen tip shows as a green pill (`Level.use`, `Pill.green*`, app logo and % left) until TUM is opened (`markUseItSeen`, saved in `useItSeen` per reset). Yellow and red always win (`Store.pillState`). The status line is green with a lightbulb and a "Got it" button. Developer menu has "Green pill". Self-test checks the rule, the click and that warnings win.
- **Preview the pill (debug builds):** the right-click menu starts with Yellow, Red and Green previews and "Back to real data" (`addPillPreviews` in Developer.swift). They swap in sample numbers only; connections are never touched.
- **One-limit apps (Cursor is monthly):** the detail screen hides the Session/Weekly/Both tabs and shows "Monthly limit" instead, and limits read "70% left this month" (`Store.hasOnlyOneLimit`, `periodPhrase`).
- **Grok Bot mark:** it publishes no one-color logo, so `BrandLogos.grokBotMark()` draws its face (round head, two slanted eyes cut out) from its app icon. `dev-marks.png` shows every supported app's white mark.
- **Popover grid:** 24pt between rows.
- **Healthy water** is `Pill.blueLiquid` (#4FA3FF), matched in strength to the Figma yellow and red (AK found the faded blue dull).
- **Pill must never silently vanish:** `urgent` uses `canAlert`, so a low reading keeps the pill for up to 3 hours if refreshes fail, and clears on reset. The self-test drives the real `StatusItemController` and checks the slot grows to the pill and shrinks back.
- **Morph motion:** icon to pill and back use `Motion.morph` (0.35s smooth), and the slot width glides on the same 0.35s ease-in-out curve so neighboring menu bar icons slide, never snap.
- **Card notes are one line** (AK): every catalog `hint` is 24 characters at most, 18 for Cursor and Grok Bot (they share the row with the Connect button). Coming soon apps say how support is planned ("AWS sign-in planned", "Credits view planned"), never just "Coming soon". The self-test checks the lengths.
- **App groups:** onboarding step 3 and Settings show "Ready to connect" (supported apps, full cards) and "Coming soon" (dimmed, grayscale icons, not clickable, no buttons). Connected apps say it in the subtitle: "Connected · 2 min ago" (`Store.connectedText`), with "Connected" in system green via `statusText`, never the sign-in source. The trailing control is `AppMenu`, a More button like the Wi-Fi list in System Settings (HIG Pull-down buttons), all stock SDK: the same `iconButton()` glass circle as Connect, opening a plain AppKit `NSMenu` as a pull-down just below it (`MenuAnchor`, `ActionItem`). Items are "Update now" (`Store.updateNow`: "Connected · Updating…" for at least 0.8s, then "Just now" for 4s; skips the Codex file shortcut and any backoff), a separator, then "Remove <app>" last, not red (macOS menus never color destructive items; that is the iOS rule). SwiftUI `Menu` was rejected: it ignores the glass button style and looked non-native. No confirmation, since connecting again undoes it. Right-click shows the same items (`AppMenuItems`). The popover detail uses a plain destructive "Remove" capsule next to Refresh, like "Remove all" in Settings.
- **Welcome benefits:** three separate `Card(padding: 20, bordered: true)` rows (hairline in the system separator color, 18pt corners), stacked with 18pt gaps, each one line of detail so all three match, like the How TUM works cards (AK). Each has a large filled SF Symbol (`.largeTitle`: menubar.rectangle, bell.badge.fill, lock.shield.fill), a headline title and one secondary line. Security copy says sign-ins stay on the Mac; never claim TUM stores nothing.
- **How TUM works cards:** step numbers are `StepNumber` (white circle, dark semibold number; flips in Light Mode), never tinted blue. Below each illustration, the number and step name sit side by side, the number vertically centered on the text and the pair centered in the card (AK), in regular `.body`. Each illustration sits on a lighter rounded square (`StepWell`, radius nested inside the card).
- **Onboarding window:** 800 × 600 (`OnboardingView.height`; title 60pt from the top, AK, content padding 12pt; step 4 is the tallest and sets this). Each step's content is centered between the title and the bottom buttons; the app grid scrolls only when it doesn't fit.
- **Pill (Figma, unchanged):** glossy amber `#E0A400` or red `#C62F35` capsule, 20px tall, dark `#1C1C1E` circle with the white app logo and liquid `#FFB800`/`#FF6165` up to the % left. % text `#1C1C1E` on amber, white on red. The white "all good" icon is `TankMark`.
- **Motion:** `MorphMark` morphs the icon into the pill on `Motion.standard`. The water flows (TimelineView). The onboarding carousel loops.
- **Pill priority (AK, 2026-11-04):** the pill shows the latest app to cross into yellow (`Store.alertSince`, `updateAlerts`), not the lowest, so each new app running low takes the pill. An app that already alerted returns only when it turns red. Red always wins over yellow; among reds, the latest. The limit that counts follows Usage monitoring (session first in Both). The self-test plays this scenario. Crossing times live in memory, so after a relaunch the order follows the first refresh.
- The status line ("Codex may run out...") appears only for alerts, never "All good".
- Onboarding: the title stays in one spot; each step's content is centered below it. Page dots and Back/Next are pinned to the bottom. Next is off on the apps step until one app is connected. After finishing, an intro callout points at the menu bar icon.
- Minimal copy everywhere: one-line subtitles, "Turn yellow at", "Usage monitoring", "Advanced settings".
- TUM shows in the Dock while a window is open (TUM menu with ⌘Q) and leaves it when windows close.

## Security (reviewed) and decisions left for AK before public release
- Done:
  - Ephemeral URLSession, HTTPS only, TLS 1.2+, same-host redirects only.
  - Diagnostics log is 0600, capped at 512 KB, with ids redacted.
  - Never renews, rewrites or deletes other apps' sign-ins. TUM stores only its own Cursor and GitHub sign-ins, deleted on Remove.
  - No embedded client secrets. Hardened runtime, `.gitignore`, `SECURITY.md`.
  - The one-line installer (`install.sh`) follows the M9 rules; the DMG it checks must be the one from the `./make_dmg.sh --update-installer` run (every build has a new fingerprint).
- Needs AK's decision:
  1. Developer ID and notarization ($99/yr). Without it, users see a Gatekeeper warning.
  2. Terms risk: renewing tokens with other apps' OAuth client IDs, and the Claude Code User-Agent. Consider an honest `TUM/x.y` User-Agent and a README note.
  3. License (MIT or Apache-2.0).
  4. Whether onboarding should re-show after updates, or only on first install.
