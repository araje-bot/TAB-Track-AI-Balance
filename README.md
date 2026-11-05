# TUM · Token Utilization Monitor

A macOS menu bar app that shows how much AI usage you have left in Claude, Codex, Cursor, Grok Bot, GitHub Copilot, Grok and Gemini. The icon turns into a yellow or red pill when an app runs low, and tells you when a limit resets soon with plenty left.

![The menu bar icon in its four states. All good, getting low (yellow), almost out (red), and use it before it resets (green).](docs/images/pills.png)

When everything is fine, you see a small round icon. Yellow means an app is getting low. Red means it is almost out. Green means a limit resets soon and you still have plenty left, so now is a good time to use it.

## Install

Open Terminal (press ⌘ Space, type Terminal, press Return), paste this line, press Return, then type `y`:

```bash
curl -fsSL https://raw.githubusercontent.com/araje-bot/TUM-Token-Utilization-Monitor/v0.1.0/install.sh | bash
```

TUM opens with a short welcome and shows the AI apps it found. It needs macOS 13 or later, on Apple silicon or Intel.

## A quick look

**Welcome.** TUM opens with a short tour the first time.

![The welcome screen](docs/images/welcome.png)

**Pick your AI apps.** TUM finds the ones on your Mac. Tap the plug to connect one. Connected apps say so in green.

![The list of AI apps, with Claude, Codex, Cursor and Grok Bot connected](docs/images/apps.png)

**Choose when to be nudged.** Pick when the icon turns yellow. You see the change right away.

![The nudge settings](docs/images/nudge.png)

**Click the icon any time.** Each circle fills up to match what is left. Session, Weekly and Monthly tabs show each limit. Click an app for more.

<p>
  <img src="docs/images/popover.png" alt="The menu bar popover showing Claude at 24% and Codex at 88%" width="320">
  &nbsp;&nbsp;
  <img src="docs/images/detail.png" alt="One app opened, showing 24% left and when it resets" width="320">
</p>

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

## Build it yourself

```bash
./make_dmg.sh --allow-dirty
```

Needs Xcode or the Command Line Tools (`xcode-select --install`). The build runs TUM's self-test and writes `build/TUM-0.1.0.dmg`. For day-to-day work, `./dev.sh --test` builds a debug copy ("TUM Dev") in seconds.

## License

Not chosen yet, so all rights reserved for now. TUM is a University of Maryland INST474 team project; an open-source license is planned.
