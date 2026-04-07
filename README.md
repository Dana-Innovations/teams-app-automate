# teams-publish

A Claude Code skill that packages any deployed web app for Microsoft Teams. Instead of manually figuring out manifests, app registration, iframe quirks, and icon requirements, run one slash command and Claude handles the prep work.

## Install

```bash
bash install.sh
```

Or manually:

```bash
mkdir -p ~/.claude/skills/teams-publish && cp SKILL.md ~/.claude/skills/teams-publish/SKILL.md
```

## Usage

Open Claude Code in any project with a deployed web app and run:

```
/teams-publish https://your-app.vercel.app
```

## What it does

Claude walks through six phases:

| Phase | What happens |
|---|---|
| **0 — Collect inputs** | Asks for URL, app name, description, and tab type (personal or configurable) |
| **1 — Codebase scan** | Detects Teams iframe blockers (`alert()`, `confirm()`, `window.open()`, `localStorage`, theme toggles, missing SDK init) and offers auto-fix diffs |
| **2 — Generate manifest** | Creates `./teams-app/manifest.json` using schema 1.16 with auto-generated UUID, correct scopes, and valid domains |
| **3 — Icon guidance** | Tells you exactly what icon files are needed (192x192 color, 32x32 outline) and warns that name/logo lock after submission |
| **4 — Package & validate** | Runs validation checks, then zips `manifest.json` + icons into `teams-app-package.zip` |
| **5 — Submission checklist** | Prints a copy-paste checklist and direct link to Teams Admin Center — this is the only step that needs IT |

An optional **Phase 6** covers shared channel caveats if you ask about cross-tenant scenarios.

## Who does what

- **You (the developer):** Build your app, deploy it, run `/teams-publish`, review and approve the fixes and manifest Claude generates, create your icons.
- **IT admin:** Review and approve the finished package in Teams Admin Center. That's it.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- A deployed web app (Vercel, Netlify, any public URL)
- Two PNG icons ready (or the ability to create them — Claude tells you the specs)

## Known gotchas

- **staticTabs + sharedChannels can't coexist** in one manifest — the skill enforces this and explains why
- **App name and logo are locked after first submission** — the skill warns you before packaging
- **Upload succeeds but app doesn't appear** — normal, it's waiting for IT approval in Admin Center
