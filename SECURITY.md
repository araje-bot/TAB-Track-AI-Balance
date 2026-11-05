# Security and privacy

TUM runs entirely on your Mac. There is no TUM server, no account, no analytics and no tracking.

## What TUM reads
To show usage, TUM uses the sign-in each AI app already keeps on your Mac, the same way the open-source OpenUsage does. It only reads these; it never changes them.

| App | Read from |
|---|---|
| Claude | The Claude app's saved session (`~/Library/Application Support/Claude`, unlocked with the Keychain item "Claude Safe Storage"), or Claude Code's sign-in (Keychain item "Claude Code-credentials" or `~/.claude/.credentials.json`) |
| Codex | `~/.codex/auth.json` or Codex's Keychain item, plus the usage lines in Codex's newest session file |
| GitHub Copilot | VS Code's Copilot sign-in (`~/.config/github-copilot/`) or the GitHub CLI (`~/.config/gh/hosts.yml`, Keychain item "gh:github.com"). If neither exists, TUM's own GitHub sign-in (below). |
| Cursor, Grok Bot | TUM's own Cursor sign-in (below). TUM doesn't read Cursor's files. |
| Grok | `~/.grok/auth.json` |
| Gemini | `~/.gemini/oauth_creds.json` |

Notes:
- The "Claude Safe Storage" key can unlock everything the Claude app stores on your Mac. TUM uses it only to read Claude's sign-in, and only after you click Connect.
- For Codex, TUM loads the end of Codex's newest session file to find the usage numbers. Those files also hold your prompts. TUM only reads the usage lines and never saves or sends anything else from them.
- To refresh soon after you use an app, TUM watches those apps' folders for changes (file names only).

## Where each sign-in goes
- Each sign-in is sent **only to its own company**, over HTTPS, to that company's usage service. Claude's goes to api.anthropic.com, Codex's to chatgpt.com, Copilot's to api.github.com, Cursor's and Grok Bot's to api2.cursor.sh and cursor.com, Grok's to cli-chat-proxy.grok.com, Gemini's to cloudcode-pa.googleapis.com. TUM's own sign-ins are made at cursor.com and github.com.
- Values TUM reads from a sign-in file only ever go back to that same company, and only if they are plain printable text.
- TUM never sends your prompts, chats, files or code anywhere.

## What TUM stores
- **Its own sign-ins, only for apps that need one:**
  - Cursor and Grok Bot: Connect opens cursor.com in your browser and you approve once. The token is kept in TUM's Keychain item "TUM Cursor sign-in" and renewed by TUM before it expires.
  - GitHub Copilot, only when VS Code and the GitHub CLI aren't signed in: Connect shows a code for github.com/login/device. The token is kept in TUM's Keychain item "TUM GitHub sign-in".
  - Both items are deleted when you remove the app in TUM, and a sign-in that doesn't lead to a working connection is deleted again right away. If Cursor ends TUM's sign-in, TUM deletes its copy and shows Connect again. The items stay if you delete TUM.app without removing the apps first; the uninstaller says so, and you can delete them in Keychain Access and revoke access at cursor.com or github.com/settings/applications.
- **Settings** (which apps are connected, your choices) in TUM's preferences. No tokens.
- **Diagnostics log** at `~/Library/Logs/TUM/diagnostics.log`, readable only by you, never written through a link, capped at 512 KB. It records status codes, the names of fields in replies (anything that looks like an id or an email is replaced by `<key>`), short error codes like `invalid_grant`, error kinds with macOS error numbers, and crash names. It never records tokens, messages from services, prompts, file paths, emails or ids. Control characters are removed, so nothing a service sends can forge a log line. "Copy diagnostics" in Settings copies it for support.
- No network cache or cookies: requests use an ephemeral session.
- To read one value from the Claude app's database without locking it, TUM copies it into a private temporary folder (readable only by you) and deletes the copy right after. Leftover copies from a crash are deleted at the next launch.
- Files TUM reads (sign-in files, the Claude database, Codex session files) must be plain files of a sane size, never links or pipes.

## What TUM never changes
- TUM never renews, rewrites or deletes other apps' sign-ins, files or Keychain items. When an app's sign-in has expired, TUM asks you to open that app once; the app renews it and TUM picks up the fresh one.

## Identity used with each service
Some services only accept requests that look like their own apps. To read usage, TUM uses:
- Claude: a Claude Code User-Agent and the `anthropic-beta: oauth-2025-04-20` header.
- GitHub Copilot: VS Code and Copilot Chat version headers; TUM's own GitHub sign-in uses Copilot's public app id, so GitHub's approval page says "GitHub Copilot".
- Cursor and Grok Bot: the Cursor CLI's public app id for TUM's own sign-in, and, as a backup for the usage numbers, the same sign-in sent to cursor.com the way a browser session would.
- Grok: the Grok CLI's `X-XAI-Token-Auth: xai-grok-cli` header.
- Gemini: the Gemini CLI's plugin type in the request body.
Everywhere else TUM identifies itself as `TUM/0.1 (macOS)`. These ids are public and contain no secrets. They are listed here so you know exactly what TUM does.

## Permissions
- **No keyboard monitoring, screen recording or accessibility access.** The quick view shortcut is a registered hotkey, so TUM never sees other keys you press.
- **Keychain:** macOS may ask once when you connect Claude, Codex or Copilot. TUM only asks right after you click Connect; background checks never show a prompt. Because TUM isn't signed by Apple, macOS may ask again after an update.

## Network safety
- HTTPS only, TLS 1.2 or newer, standard certificate checks.
- Redirects are only followed within the same site and port, so a sign-in can never be carried to another host.
- Requests time out after 30 seconds; replies over 1 MB are refused.
- Failed checks back off (1, 2, 4 ... 60 minutes), "too many requests" replies are honored, and automatic checks keep each service's minimum gap, so TUM never hammers a service.

## Installing and verifying a download
- `install.sh` downloads one exact release from GitHub over HTTPS, checks it against the SHA-256 written into the script, opens the disk image read-only, checks the app's signature, bundle id and version, and copies it into /Applications (or ~/Applications). A download that doesn't match is deleted. It never uses sudo, never changes system settings, and never strips a quarantine mark.
- Each release lists the DMG's SHA-256. Check it with `shasum -a 256 TUM-0.1.0.dmg` before opening.
- "Open at login" only works for a TUM in /Applications or ~/Applications, so a copy opened from the disk image can't leave a broken login item behind.

## Reporting a problem
Please open a private security advisory on the GitHub repository rather than a public issue.
