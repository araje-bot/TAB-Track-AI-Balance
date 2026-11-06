# TUM · Token Utilization Monitor

A macOS menu bar app that shows how much AI usage you have left in Claude, Codex, Cursor, Grok Bot, GitHub Copilot, Grok, Gemini and Zed. The icon turns into a yellow or red pill when an app runs low, and tells you when a limit resets soon with plenty left.

![The menu bar icon in its four states. All good, getting low (yellow), almost out (red), and worth using (green).](docs/images/pills.png)

When everything is fine, you see a small round icon. Yellow means an app is getting low. Red means it is almost out. Green means worth using. An app you've barely used has plenty left and resets soon, so use it before that goes to waste.

When several apps need you at once, red comes first, then yellow, then green. Apps of the same color take turns, about a minute each, so you see every one. Hover over the icon to see them all at once.

## What TUM supports today

- **Native Mac apps only, for now.** TUM works with AI apps installed on your Mac, like the Claude, Codex and Cursor desktop apps and their command-line tools.
- **Web apps are coming.** AI tools you mostly use in a browser, like ElevenLabs, Higgsfield and Suno, are planned. TUM lists them under Coming soon.
- **Windows is planned.** TUM runs on macOS today. A Windows version is on the way.

## Install

Open Terminal (press ⌘ Space, type Terminal, press Return), paste this line, press Return, then type `y`:

```bash
curl -fsSL https://raw.githubusercontent.com/araje-bot/TUM-Token-Utilization-Monitor/v0.1.0/install.sh | bash
```

TUM opens with a short welcome and shows the AI apps it found. It needs macOS 13 or later, on Apple silicon or Intel.

## A quick look

**Welcome.** TUM opens with a short tour the first time.

![The welcome screen](docs/images/welcome.png)

**Pick your AI apps.** TUM finds the ones on your Mac. Tap the plug to connect one. Connected apps say so in green. You can also connect apps TUM can't read yet, and their numbers show up once support arrives.

![The list of AI apps, with Claude, Codex, Cursor and Grok Bot connected](docs/images/apps.png)

**Choose when to be nudged.** Pick when the icon turns yellow. You see the change right away.

![The nudge settings](docs/images/nudge.png)

**Click the icon any time.** Each circle fills up to match what is left. It opens on the view you picked during setup (Session, Weekly or Monthly), and the tabs switch it. Click an app for more, and Sync to get its latest numbers.

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

## How TUM works

1. **It finds your AI apps.** TUM checks which supported apps are on your Mac.
2. **It uses the sign-in you already have.** Most AI apps keep you signed in on your Mac, and TUM uses that, so there is nothing new to log in to. For Cursor, and for GitHub Copilot when it isn't signed in yet, you sign in once in your browser. TUM keeps that sign-in on your Mac and deletes it when you remove the app.
3. **It asks each app's own company how much is left.** Claude's numbers come from Anthropic, Codex's from OpenAI, and so on. TUM has no server, no account and no analytics, so nothing goes anywhere else, except feedback you choose to send.
4. **It shows the answer in your menu bar.** TUM checks again whenever you use an app, and every so often in between.

TUM only asks for usage numbers. It does not save your prompts, chats, files or code, and it does not change the sign-ins other apps keep.

## Good to know

- TUM never asks for your password, and it does not need keyboard, screen or accessibility permissions.
- macOS may ask once about your Keychain when you connect Claude or Zed. Choose Always Allow.
- The installer downloads one exact release and checks it against a fingerprint written into the script. A different file is deleted, not installed.
- All of TUM's code is in this repository, so anyone can read exactly what it does.

## Feedback

Click **Any issues? Let us know** at the bottom of TUM and type your note. If you have a GitHub account, you can also open an issue here.

## License

Not chosen yet, so all rights reserved for now. TUM is a University of Maryland INST474 team project; an open-source license is planned.
