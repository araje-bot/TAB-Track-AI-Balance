# How TUM will sync the next apps

Researched 2026-11-06. An app goes on Coming soon only when there is a real way to read the same credits the person's plan uses. Each path below was checked against vendor docs and against OpenUsage and CodexBar, two open-source monitors with working code.

## Rules every new reader follows

- An app gets a Connect button only once TUM can show its real numbers (AK, 2026-11-06). Until then it waits under Coming soon.
- Read the usage number only. Never prompts, files or chats.
- Prefer a sign-in the app already keeps on this Mac. If there is none, use the vendor's own browser sign-in and keep the result in TUM's own Keychain item, deleted on Remove (like Cursor and GitHub today).
- Never renew, rewrite or delete another app's sign-in.
- Log names and status codes only, never tokens or service messages.
- If the number can't be read, the card says so in one line. It never shows a guess.

## Build order

| Order | App | How TUM reads it | Limit TUM shows | State | Open question |
|---|---|---|---|---|---|
| 1 | Zed | Zed's own sign-in in the Keychain, then `cloud.zed.dev/client/users/me` | Monthly edit predictions (Pro and up have no cap, so they show full) | **Built 2026-11-06** | No |
| 2 | Kiro | Run `kiro-cli chat --no-interactive "/usage"` and read its monthly and bonus credits (how CodexBar does it) | Monthly | Ready (CodexBar has it) | Needs kiro-cli installed and signed in |
| 3 | Antigravity | The local language server's `GetUserStatus`, with the one-time key from its process arguments | Session and weekly | Ready (CodexBar has it) | Reading a key from another process |
| 4 | ElevenLabs | Person pastes an API key with only the User read permission. `GET api.elevenlabs.io/v1/user/subscription` returns used, limit and reset date | Monthly credits | Ready (CodexBar has it) | A new "paste a key" step |
| 5 | Higgsfield | Higgsfield's official MCP server with its own browser sign-in, then its balance tool | Monthly credits | Possible. Confirm the sign-in and tool name first | TUM acting as a small MCP client |
| 6 | Windsurf | Windsurf's local `state.vscdb` plan info | Monthly | Possible. The cached value can be stale | Reading Windsurf's own sign-in file |
| 7 | Suno, Manus, Perplexity | The person's browser session cookie, then each site's own billing call | Credits | Possible but fragile. Can break any time, terms risk | Browser cookies, a sensitive pattern. Likely skipped |
| 8 | Ollama (cloud) | Person pastes an Ollama key, `ollama.com/api/balance` | Credits | Possible | Same as ElevenLabs |

Every step ends with the self-test covering the new reader with sample replies, and a check of real numbers before it ships.

## Not on Coming soon, and why

| App | Why not now |
|---|---|
| Midjourney | No API. Its terms forbid automated access and accounts get blocked. |
| Kling AI | Its API uses separate prepaid packs. No way to read plan credits. |
| Runway | API credits are separate from plan credits. Recheck in a few months. |
| Canva | No call returns the remaining AI credits. Not listed. |
| CapCut | No public API. Not listed. |
| Lovable | Credits show only on its settings page. No API. Not listed. |
| Gamma, Granola, Wispr Flow, Otter, Grammarly, NotebookLM, QuillBot, Microsoft Copilot, Le Chat, DeepSeek, Meta AI, Character.AI | Small impact for this persona, or no limit to read. |
| Sora | Shut down in 2026. |

## Open decisions

1. A "paste a key" step (ElevenLabs, Ollama). Simple and documented, but new for TUM.
2. Reading another app's own sign-in file or a key from its process (Windsurf, Antigravity). Each needs a careful privacy review first.
3. Browser cookies (Suno, Manus, Perplexity). The most fragile and the most sensitive, so these wait until the others ship.
