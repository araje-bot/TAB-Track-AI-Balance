# TAB · Track AI Balance

TAB sits in your Mac's menu bar and keeps tabs on how much of your AI plan you have left. When an app runs low, its icon turns yellow, then red. When a limit is about to reset and you've barely used it, the icon turns green, so you can use it before it goes to waste.

TAB shows real numbers for Claude, Codex, Cursor, Gemini, GitHub Copilot, Zed and Grok Bot, and for the Grok command-line tool. Other AI apps it finds on your Mac wait under Coming soon until TAB can show their numbers.

![The menu bar icon in its four states. All good, getting low (yellow), almost out (red), and not utilized enough (green).](docs/images/pills.png)

When everything is fine, you see a small round icon. Yellow means an app is getting low. Red means it is almost out. Green means not utilized enough. An app you've barely used has plenty left and resets soon, so use it before that goes to waste.

When several apps need you at once, red comes first, then yellow, then green. Apps of the same color take turns, about a minute each, so you see every one. Hover over the icon to see them all at once.

## What TAB supports today

- **Native Mac apps only, for now.** TAB works with AI apps installed on your Mac, like the Claude, Codex and Cursor desktop apps and their command-line tools.
- **Web apps are coming.** AI tools you mostly use in a browser, like ElevenLabs, Higgsfield and Suno, are planned. TAB lists them under Coming soon.
- **Windows is planned.** TAB runs on macOS today. A Windows version is on the way.

## Install

Open Terminal (press ⌘ Space, type Terminal, press Return), paste this line, press Return, then type `y`:

```bash
curl -fsSL https://raw.githubusercontent.com/araje-bot/TAB-Track-AI-Balance/v0.1.0/install.sh | bash
```

TAB opens with a short welcome and shows the AI apps it found. It needs macOS 13 or later, on Apple silicon or Intel.

TAB used to be called TUM. If you had TUM, the installer replaces it, and TAB brings over your settings and connected apps.

## A quick look

**Welcome.** TAB opens with a short tour the first time.

![The welcome screen](docs/images/welcome.png)

**Pick your AI apps.** TAB finds the ones on your Mac. Tap the plug to connect one. Connected apps say so in green. Only apps TAB can show real numbers for can be connected. Apps it can't read yet wait under Coming soon.

![The list of AI apps, with Claude, Codex, Cursor and Grok Bot connected](docs/images/apps.png)

**Choose when to be nudged.** Pick when the icon turns yellow. You see the change right away.

![The nudge settings](docs/images/nudge.png)

**Click the icon any time.** Each circle fills up to match what is left. It opens on the view you picked during setup, and you can switch between Session, Weekly and Monthly. Click an app for more, and Sync to get its latest numbers.

<p>
  <img src="docs/images/popover.png" alt="The menu bar popover showing Claude at 24% and Codex at 88%" width="320">
  &nbsp;&nbsp;
  <img src="docs/images/detail.png" alt="One app opened, showing 24% left and when it resets" width="320">
</p>

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/araje-bot/TAB-Track-AI-Balance/v0.1.0/uninstall.sh | bash
```

Or drag TAB from Applications to the Trash.

## How TAB works

1. **It finds your AI apps.** TAB checks which supported apps are on your Mac.
2. **It uses the sign-in you already have.** Most AI apps keep you signed in on your Mac, and TAB uses that, so there is nothing new to log in to. For Cursor, and for GitHub Copilot when it isn't signed in yet, you sign in once in your browser. For Gemini, you sign in once on Google's own page in a small TAB window. TAB keeps that sign-in in your Mac's Keychain and deletes it when you remove the app.
3. **It asks each app's own company how much is left.** Claude's numbers come from Anthropic, Codex's from OpenAI, and so on. TAB has no server, no account and no analytics, so nothing goes anywhere else, except feedback you choose to send.
4. **It shows the answer in your menu bar.** TAB checks again whenever you use an app, and every so often in between.

TAB only asks for usage numbers. It does not save your prompts, chats, files or code, and it does not change the sign-ins other apps keep.

## Good to know

- TAB never asks for your password. When you connect Gemini, you type it on Google's own sign-in page. TAB doesn't read or keep it. TAB does not need keyboard, screen or accessibility permissions.
- macOS may ask once about your Keychain when you connect Claude or Zed. Choose Always Allow.
- The installer downloads one exact release and checks it against a fingerprint written into the script. A different file is deleted, not installed.
- All of TAB's code is in this repository, so anyone can read exactly what it does.

## Feedback

Click **Any issues? Let us know** at the bottom of TAB and type your note. If you have a GitHub account, you can also open an issue here.

## License

Not chosen yet, so all rights reserved for now. TAB is a University of Maryland INST474 team project; an open-source license is planned.
