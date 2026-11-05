# TUM · Token Utilization Monitor

A macOS menu bar app that shows how much AI usage you have left in Claude, Codex, Cursor, Grok Bot, GitHub Copilot, Grok and Gemini. The icon turns into a yellow or red pill when an app runs low, and tells you when a limit resets soon with plenty left.

## Install

Open Terminal (press ⌘ Space, type Terminal, press Return), paste this line, press Return, then type `y`:

```bash
curl -fsSL https://raw.githubusercontent.com/araje-bot/TUM-Token-Utilization-Monitor/v0.1.0/install.sh | bash
```

TUM opens with a short welcome and shows the AI apps it found. It needs macOS 13 or later, on Apple silicon or Intel.

Want to read the script before running it?

```bash
curl -fsSL -o install-tum.sh https://raw.githubusercontent.com/araje-bot/TUM-Token-Utilization-Monitor/v0.1.0/install.sh
```

```bash
less install-tum.sh && bash install-tum.sh
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/araje-bot/TUM-Token-Utilization-Monitor/v0.1.0/uninstall.sh | bash
```

Or drag TUM from Applications to the Trash.

## Why is TUM so safe?

- TUM has no server, no account and no analytics. It runs only on your Mac.
- It reads the sign-in each AI app already keeps on your Mac and sends it only to that app's own company, to ask how much is left. It never changes those sign-ins.
- It never saves or sends your prompts, chats, files or code.
- The installer downloads one exact release and checks it against a fingerprint written into the script. A different file is deleted, not installed. It never asks for your password.
- No keyboard, screen or accessibility permissions. macOS may ask once about the Keychain when you connect Claude; choose Always Allow.

App-by-app details are in [SECURITY.md](SECURITY.md).

## Build it yourself

```bash
./make_dmg.sh --allow-dirty
```

Needs Xcode or the Command Line Tools (`xcode-select --install`). The build runs TUM's self-test and writes `build/TUM-0.1.0.dmg`. For day-to-day work, `./dev.sh --test` builds a debug copy ("TUM Dev") in seconds.

## License

Not chosen yet, so all rights reserved for now. TUM is a University of Maryland INST474 team project; an open-source license is planned.
