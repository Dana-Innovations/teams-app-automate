---
name: teams-publish
description: Package any deployed web app for Microsoft Teams — scans for iframe blockers, generates manifest, builds submission-ready zip
---

# Teams Publish

Turn a deployed web app into a Teams-ready package. Walk the developer through fixing iframe blockers, generating a valid manifest, and packaging everything for IT submission — all inside Claude Code, in the project itself.

## Invocation

```
/teams-publish [url]
```

If the URL is provided as an argument, skip asking for it. If not, ask.

## Phase 0: Collect Inputs

Gather four things. Infer from project context when possible — only ask for what you can't determine.

| Input | Required | How to infer |
|---|---|---|
| **App URL** | Yes | Argument to `/teams-publish`, or ask |
| **App name** | Yes | `<title>` in index/layout, `package.json` name, or URL hostname |
| **Short description** | Yes | `package.json` description, meta description, or ask |
| **Tab type** | Yes, default `personal` | Ask: personal (left rail), configurable (channels/chats), or both |

### Hard Rule: staticTabs + sharedChannels

**NEVER** generate a manifest that combines `staticTabs` with shared channel scopes. This causes silent deployment failures. If the user needs both personal tabs and shared channel support, tell them they need two separate app packages — and explain why. Flag this the moment the user mentions shared channels.

## Phase 1: Codebase Scan & Auto-Fix

Read the user's project files. Detect and offer to fix these Teams iframe blockers:

### Blockers to detect

| Pattern | Why it breaks | Replacement |
|---|---|---|
| `alert(` / `confirm(` / `prompt(` | Native dialogs blocked in Teams iframe | Custom modal component, or `microsoftTeams.dialog.open()` |
| `window.open(` | Popups blocked in iframe | `microsoftTeams.app.openLink(url)` or `<a target="_blank">` with `rel="noopener"` |
| `localStorage` / `sessionStorage` | Blocked in third-party iframe context (Safari, some Edge configs) | Add try/catch fallback; warn user about cross-browser restrictions |
| Dark mode toggle / theme switcher UI | Teams controls the theme — user toggles conflict | Hook into `app.registerOnThemeChangeHandler()` and apply Teams theme classes |
| No Teams SDK initialization | App loads forever (spinner never clears) | Add `@microsoft/teams-js`, call `await app.initialize()` then `app.notifySuccess()` |

### Header checks

Search for `next.config.js`, `vercel.json`, middleware files, or server config:
- `X-Frame-Options` — must be removed or set to `ALLOWALL`; if set to `DENY` or `SAMEORIGIN`, Teams cannot frame the app
- `Content-Security-Policy` with `frame-ancestors` — must include `teams.microsoft.com *.teams.microsoft.com *.skype.com`
- If using Vercel, check `vercel.json` headers config

### Presenting fixes

For each issue:
1. Show file path, line number, and current code
2. Show the proposed fix as a diff
3. After showing all issues, ask: "Apply all N fixes?" or let user pick individually
4. Apply fixes but do NOT commit — let the user review the changes and commit when ready

If no blockers found, say: "No Teams iframe blockers detected — your codebase looks ready." Move to Phase 2.

## Phase 2: Generate Manifest

Create directory `./teams-app/` and generate `./teams-app/manifest.json` using schema 1.16.

### Template

```json
{
  "$schema": "https://developer.microsoft.com/en-us/json-schemas/teams/v1.16/MicrosoftTeams.schema.json",
  "manifestVersion": "1.16",
  "version": "1.0.0",
  "id": "{{UUID_V4}}",
  "developer": {
    "name": "{{developer_name}}",
    "websiteUrl": "{{app_url}}",
    "privacyUrl": "{{app_url}}/privacy",
    "termsOfUseUrl": "{{app_url}}/terms"
  },
  "name": {
    "short": "{{app_name}}",
    "full": "{{app_name}}"
  },
  "description": {
    "short": "{{short_description}}",
    "full": "{{short_description}}"
  },
  "icons": {
    "color": "color.png",
    "outline": "outline.png"
  },
  "accentColor": "#4F46E5",
  "permissions": ["identity"],
  "validDomains": ["{{app_domain}}"]
}
```

### Field rules

- **id**: Generate a fresh UUID v4 every time. Use `uuidgen` or Python's `uuid.uuid4()`.
- **developer.name**: Infer from `package.json` author, `git config user.name`, or ask.
- **developer.privacyUrl / termsOfUseUrl**: Default to `{{app_url}}/privacy` and `{{app_url}}/terms`. Warn the user: "These pages should exist at these URLs — Teams reviewers may check."
- **validDomains**: Extract the hostname from the app URL (e.g., `my-app.vercel.app`). If the app is on Vercel with a custom domain, include both the custom domain and `*.vercel.app`.
- **accentColor**: Default `#4F46E5`. Offer to change.

### Tab type → manifest fields

**Personal tab** — add `staticTabs`:
```json
"staticTabs": [
  {
    "entityId": "home",
    "name": "{{app_name}}",
    "contentUrl": "{{app_url}}",
    "websiteUrl": "{{app_url}}",
    "scopes": ["personal"]
  }
]
```

**Configurable tab** — add `configurableTabs`:
```json
"configurableTabs": [
  {
    "configurationUrl": "{{app_url}}/config",
    "canUpdateConfiguration": true,
    "scopes": ["team", "groupChat"]
  }
]
```
Warn: configurable tabs require a `/config` page that uses the Teams SDK to save settings via `pages.config.setConfig()`. If the user doesn't have one, explain what it needs to do.

**Both** — add both arrays, but enforce the Hard Rule: no shared channel scopes alongside `staticTabs`.

### Present and confirm

Show the complete generated manifest. Ask: "Does this look right?" Write to `./teams-app/manifest.json` only after confirmation.

## Phase 3: Icon Guidance

Teams requires two icons **in the zip alongside manifest.json**:

| File | Size | Rules |
|---|---|---|
| `color.png` | 192 x 192 px | Full-color PNG. Transparent background OK. Used in app store and install dialogs. |
| `outline.png` | 32 x 32 px | **White only** with transparent background. No gradients, no colors. Used in left rail and small surfaces. |

### Tell the user

1. Both files must be placed in `./teams-app/` next to `manifest.json`
2. `outline.png` must be a single white color on transparency — Teams will reject anything else
3. **App name and logo are locked after your first submission.** Changing them later requires creating a new app registration. Get these right before packaging.

### Help find existing assets

Check common locations for icons:
- `public/favicon.ico`, `public/favicon.png`, `public/logo.png`
- `src/assets/`, `src/images/`
- Project root `icon.png`, `logo.png`

If found, suggest resizing. If not found, tell the user what to create and where to put it.

Do NOT proceed to Phase 4 until both icon files exist in `./teams-app/`.

## Phase 4: Package & Validate

### Validate before packaging

Check all of these. Report pass/fail for each:

1. `./teams-app/manifest.json` exists and is valid JSON
2. Required manifest fields present: `$schema`, `manifestVersion`, `id`, `version`, `name`, `description`, `icons`, `developer`, `accentColor`, `validDomains`
3. `id` is a valid UUID format
4. `./teams-app/color.png` exists
5. `./teams-app/outline.png` exists
6. No extra files in `./teams-app/` beyond `manifest.json`, `color.png`, `outline.png`
7. `validDomains` entries don't use wildcards for the specific app domain (wildcards only allowed for platform-level domains like `*.vercel.app`)
8. If `staticTabs` is present, no shared channel scopes exist anywhere in the manifest

If any check fails, explain the fix and offer to apply it. Do not package until all checks pass.

### Build the zip

```bash
cd ./teams-app && zip -j ../teams-app-package.zip manifest.json color.png outline.png
```

Confirm: "Package created at `./teams-app-package.zip` — ready for submission."

## Phase 5: Submission Checklist

Print this for the user, filling in their specific details:

---

**Your package:** `teams-app-package.zip`

### Pre-submission checklist
- [ ] App is live and accessible at {{app_url}}
- [ ] App loads in an incognito/private browser window
- [ ] No `alert()` / `confirm()` / `prompt()` calls in codebase
- [ ] No `X-Frame-Options: DENY` or `SAMEORIGIN` header
- [ ] Privacy page exists at {{app_url}}/privacy
- [ ] Terms page exists at {{app_url}}/terms
- [ ] Icons: `color.png` is 192x192, `outline.png` is 32x32 white-on-transparent

### Submit to Teams
1. Open [Teams Admin Center — Manage apps](https://admin.teams.microsoft.com/policies/manage-apps)
2. Click **Upload new app** then **Upload an app to your org's app catalog**
3. Select `teams-app-package.zip`
4. **Hand off to your IT admin** — they need to review and approve the app in Admin Center

### After submission
- The app will **not appear immediately**. This is normal — it's waiting for admin approval.
- Once approved, users find it in the Teams app store under **Built for your org**.
- If the upload succeeds but nothing shows up, don't re-upload. Ask IT to check the Admin Center pending queue.

---

This is the end of the guided flow. The developer's work is done — IT takes it from here.

## Phase 6: Shared Channel Caveats (On Request Only)

Only discuss these if the user specifically asks about shared channels or cross-tenant use:

- Shared channels have stricter security than standard channels — some APIs behave differently or are unavailable
- `staticTabs` and shared channel support **cannot coexist** in one manifest (the Hard Rule)
- Cross-tenant shared channels require the app to be published in **both** tenants
- Resource-specific consent (RSC) permissions may be required
- Always test explicitly in a shared channel — do not assume behavior carries over from personal or standard channel tabs

## Troubleshooting Quick Reference

Use this if the user hits problems at any phase:

| Symptom | Likely cause | Fix |
|---|---|---|
| White screen / blank iframe | `X-Frame-Options` or CSP `frame-ancestors` blocking Teams | Remove restrictive header or add `teams.microsoft.com *.teams.microsoft.com *.skype.com` to `frame-ancestors` |
| Infinite loading spinner | Missing `app.notifySuccess()` after Teams SDK init | Add `await app.initialize(); app.notifySuccess();` to app startup |
| "App not found" after upload | Pending IT approval | Normal. Tell IT admin to approve in Admin Center. |
| Upload rejects the zip | Schema validation failure | Check manifest against schema 1.16; ensure no extra fields or files in zip |
| Works in browser, broken in Teams | Native dialog / popup / storage blocker | Re-run Phase 1 scan |
| Icons rejected | Wrong dimensions or outline uses color | `color.png` must be exactly 192x192, `outline.png` exactly 32x32 white-on-transparent |
| App approved but users can't find it | App policy not assigned | IT needs to assign the app via Teams app setup policies, or set it to "Allowed" for the org |
