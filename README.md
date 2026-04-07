# teams-publish

A Claude Code skill that packages any deployed web app for Microsoft Teams. Instead of manually figuring out manifests, app registration, iframe quirks, and icon requirements, run one slash command and Claude handles the prep work.

## Install

```bash
bash install.sh
```

Or manually:

```bash
mkdir -p ~/.claude/skills/teams-publish && cp SKILL.md ~/.claude/skills/teams-publish/SKILL.md && cp -r scripts ~/.claude/skills/teams-publish/scripts
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
| **1 — Codebase scan** | Sets up dual-auth (Teams bypasses login, browser keeps existing auth), fixes iframe blockers (`alert()`, `confirm()`, `window.open()`, `localStorage`, theme toggles), adds Teams SDK |
| **2 — Generate manifest** | Creates `./teams-app/manifest.json` with `?inTeams=true` in contentUrl, auto-generated UUID, correct scopes. Generates privacy/terms stub pages if missing. |
| **3 — Icon guidance** | Tells you what icon files are needed, offers to convert existing SVG/PNG assets, warns that name/logo lock after submission |
| **4 — Package & validate** | Runs validation script, then zips `manifest.json` + icons into `teams-app-package.zip` |
| **5 — Submission checklist** | Prints a copy-paste checklist and direct link to Teams Admin Center — this is the only step that needs IT |

An optional **Phase 6** covers shared channel caveats if you ask about cross-tenant scenarios.

## How dual-auth works

The app serves both Teams and browser users from a single deployment:

- **In Teams:** The manifest loads the app with `?inTeams=true`. Middleware detects this and skips login. A `TeamsContext` provider initializes the Teams SDK and gets the user's identity via `app.getContext()`. No login screen ever appears.
- **In browser:** Normal auth flow (login page, SSO, session cookies) works exactly as before. Nothing changes for browser users.

## Files

| File | Purpose |
|---|---|
| `SKILL.md` | The skill instruction payload — Claude reads this when `/teams-publish` is invoked |
| `install.sh` | Copies the skill + scripts into `~/.claude/skills/teams-publish/` |
| `README.md` | This file |
| `scripts/validate-package.sh` | Standalone validator — checks manifest, icons, UUID, no conflicts |

## Who does what

- **You (the developer):** Build your app, deploy it, run `/teams-publish`, review and approve the fixes and manifest Claude generates, create your icons.
- **IT admin:** Review and approve the finished package in Teams Admin Center. That's it.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- A deployed web app (Vercel, Netlify, any public URL)
- Two PNG icons ready (or the ability to create them — Claude tells you the specs)

## Known gotchas

- **Auth still works in browser** — the skill sets up dual-auth, not auth removal. Teams users skip login, browser users get normal auth.
- **`?inTeams=true` in manifest** — this is how middleware knows to bypass auth. The manifest contentUrl includes this param; the websiteUrl does not.
- **staticTabs + sharedChannels can't coexist** in one manifest — the skill and validation script both enforce this
- **Cookie SameSite** — Teams iframe requires `sameSite: 'none'` + `secure: true`. Browser uses `sameSite: 'lax'`. The skill patches this based on context.
- **App name and logo are locked after first submission** — the skill warns you before packaging
- **Upload succeeds but app doesn't appear** — normal, it's waiting for IT approval in Admin Center
