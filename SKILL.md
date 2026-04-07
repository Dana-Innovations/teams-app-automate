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

### Dual-auth bypass (highest priority)

The app must serve two audiences from a single deployment: **Teams users** (already authenticated by Microsoft) and **browser users** (who need the existing login flow). Never remove existing auth — add a Teams bypass lane that runs alongside it.

This pattern is proven in production (talent-management-next). It has three layers: manifest query param, server middleware, and client-side Teams context detection.

#### 1. Manifest injects `?inTeams=true`

In the generated manifest, the `contentUrl` (and `websiteUrl` for static tabs) must append `?inTeams=true` to the app URL. This tells the server the request is from Teams **before any client JS loads**.

```json
"staticTabs": [
  {
    "entityId": "home",
    "name": "{{app_name}}",
    "contentUrl": "{{app_url}}?inTeams=true",
    "websiteUrl": "{{app_url}}",
    "scopes": ["personal"]
  }
]
```

For configurable tabs, append it to `configurationUrl`:
```json
"configurableTabs": [
  {
    "configurationUrl": "{{app_url}}/config?inTeams=true",
    "canUpdateConfiguration": true,
    "scopes": ["team", "groupChat"]
  }
]
```

#### 2. Middleware detects Teams context and skips auth

Find the project's auth middleware (e.g., `middleware.ts`, `middleware.js`, auth guards). Add a check at the very top: if the `inTeams=true` query param is present, skip the auth redirect and let the request through to the client.

**Next.js `middleware.ts` pattern:**

```typescript
import { NextResponse } from 'next/server';
import type { NextRequest } from 'next/server';

export function middleware(request: NextRequest) {
  const { searchParams } = request.nextUrl;

  // Teams iframe bypass — let the client-side TeamsContext provider handle identity
  if (searchParams.get('inTeams') === 'true') {
    return NextResponse.next();
  }

  // --- existing auth logic below (untouched) ---
  // e.g., check session cookie, redirect to /login, etc.
}
```

For other frameworks (Express, Fastify, etc.), apply the same pattern: check for `inTeams=true` in the query string before any auth redirect logic.

**Important:** This is safe because `inTeams=true` only skips the *redirect to a login page*. The client still needs to prove it's in Teams via the SDK (next step). A browser user who manually adds `?inTeams=true` would land on the app but get no session/identity unless they're actually inside the Teams iframe where `app.initialize()` succeeds.

#### 3. Client-side TeamsContext provider

Generate a React context provider that wraps the app. It tries `app.initialize()` from `@microsoft/teams-js` — if it succeeds, the app is in Teams and the user's identity comes from `app.getContext()`. If it fails, the app is in a browser and normal auth takes over.

```typescript
// components/TeamsContext.tsx
'use client';

import { createContext, useContext, useEffect, useState, ReactNode } from 'react';
import { app } from '@microsoft/teams-js';

interface TeamsContextValue {
  isTeams: boolean;
  loading: boolean;
  userPrincipalName: string | null;
  displayName: string | null;
  tenantId: string | null;
}

const TeamsCtx = createContext<TeamsContextValue>({
  isTeams: false,
  loading: true,
  userPrincipalName: null,
  displayName: null,
  tenantId: null,
});

export function TeamsContextProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<TeamsContextValue>({
    isTeams: false,
    loading: true,
    userPrincipalName: null,
    displayName: null,
    tenantId: null,
  });

  useEffect(() => {
    let cancelled = false;

    async function initTeams() {
      try {
        await app.initialize();
        const context = await app.getContext();

        if (!cancelled) {
          setState({
            isTeams: true,
            loading: false,
            userPrincipalName: context.user?.userPrincipalName ?? null,
            displayName: context.user?.displayName ?? null,
            tenantId: context.user?.tenant?.id ?? null,
          });
        }

        app.notifySuccess();
      } catch {
        // Not in Teams — fall through to normal auth
        if (!cancelled) {
          setState((prev) => ({ ...prev, isTeams: false, loading: false }));
        }
      }
    }

    initTeams();
    return () => { cancelled = true; };
  }, []);

  return <TeamsCtx.Provider value={state}>{children}</TeamsCtx.Provider>;
}

export const useTeamsContext = () => useContext(TeamsCtx);
```

Wrap the app's root layout with this provider. Components can then call `useTeamsContext()` to check `isTeams` and access the user's identity without any login flow.

#### 4. Cookie considerations

When the app is loaded inside the Teams iframe, session cookies **must** use `sameSite: 'none'` and `secure: true` — otherwise the browser blocks them in the cross-origin iframe context (especially Safari and Edge).

When the app is loaded in a normal browser, keep `sameSite: 'lax'` (the secure default).

Detect based on the `inTeams` query param at the point where session cookies are set:

```typescript
const isTeams = request.url.includes('inTeams=true');

const cookieOptions = {
  httpOnly: true,
  secure: true,
  sameSite: isTeams ? 'none' as const : 'lax' as const,
  path: '/',
};
```

If using NextAuth / Auth.js, this means customizing the cookie options in the auth config. If using a custom session system, apply it wherever `Set-Cookie` is issued.

#### 5. What NOT to do

- **Don't remove existing auth.** Browser users still need it. The dual-auth pattern adds a bypass lane — it never deletes the original lane.
- **Don't require separate builds or deployments.** One codebase, one deployment, two auth paths selected at runtime by the `inTeams` query param.
- **Don't add Azure AD app registration.** This pattern uses Teams' built-in identity via `app.getContext()` — no OAuth app registration, no client secrets, no token exchange. If the user later wants SSO token exchange for calling Microsoft Graph, that's a separate enhancement, not a prerequisite.
- **Don't rely solely on `Sec-Fetch-Dest: iframe`.** This header is inconsistent across browsers and can be stripped by proxies. The `?inTeams=true` manifest param is reliable because Teams always loads the exact `contentUrl` from the manifest.

### Other blockers to detect and fix

| Pattern | Why it breaks | Fix |
|---|---|---|
| `alert(` / `confirm(` / `prompt(` | Native dialogs blocked in Teams iframe | Replace with a modal component |
| `window.open(` | Popups blocked in iframe | Conditional: Teams `app.openLink()` vs browser `window.open()` |
| `localStorage` / `sessionStorage` | May be blocked in third-party iframe context | Wrap in try/catch with in-memory fallback |
| Dark mode toggle / theme switcher | Teams controls the theme | In Teams context, hide toggle and sync to Teams theme |

Note: Teams SDK initialization is handled by the dual-auth bypass step above — `app.initialize()` + `app.notifySuccess()` are part of the TeamsContext provider. Don't add them separately.

#### Fix: Native dialogs → modal component

If the project uses Radix UI, Shadcn, or has an existing modal/dialog component, use it. If not, create a minimal confirm dialog:

```tsx
// Use the project's existing dialog system when available.
// Example using the existing component library:
const confirmed = await showConfirmDialog({
  title: 'Disconnect account',
  description: `Disconnect your ${provider} account?`,
});
if (!confirmed) return;
```

Search for existing dialog/modal components before creating new ones. Check: `components/ui/dialog`, `components/ui/modal`, `components/ui/alert-dialog`, or any Radix/Shadcn dialog imports.

#### Fix: window.open → conditional Teams/browser

```typescript
import { useTeams } from '@/components/TeamsContext'; // generated in auth step
import { app } from '@microsoft/teams-js';

// In the component:
const { isTeams } = useTeams();

function openUrl(url: string) {
  if (isTeams) {
    app.openLink(url);
  } else {
    window.open(url, '_blank');
  }
}
```

#### Fix: localStorage → safe wrapper

```typescript
function safeGetItem(key: string): string | null {
  try { return localStorage.getItem(key); } catch { return null; }
}
function safeSetItem(key: string, value: string): void {
  try { localStorage.setItem(key, value); } catch { /* iframe restriction — ignore */ }
}
```

Replace all `localStorage.getItem()` with `safeGetItem()` and `localStorage.setItem()` with `safeSetItem()`. Place the helper in a utils file the project already uses, or create `lib/safe-storage.ts`.

#### Fix: Theme toggle → Teams theme sync

In Teams context, hide the manual theme toggle and sync to the Teams theme instead:

```typescript
import { useTeams } from '@/components/TeamsContext';
import { app } from '@microsoft/teams-js';

// In the theme provider or layout:
const { isTeams } = useTeams();

useEffect(() => {
  if (!isTeams) return;
  // Set initial theme from Teams context
  app.getContext().then(ctx => {
    const teamsTheme = ctx.app?.theme ?? 'default';
    const appTheme = teamsTheme === 'dark' ? 'dark' : 'light';
    document.documentElement.setAttribute('data-theme', appTheme);
  });
  // Listen for theme changes
  app.registerOnThemeChangeHandler((theme) => {
    const appTheme = theme === 'dark' ? 'dark' : 'light';
    document.documentElement.setAttribute('data-theme', appTheme);
  });
}, [isTeams]);
```

In Teams context, hide the toggle button:
```tsx
{!isTeams && <ThemeToggle />}
```

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
    "contentUrl": "{{app_url}}?inTeams=true",
    "websiteUrl": "{{app_url}}",
    "scopes": ["personal"]
  }
]
```

**Configurable tab** — add `configurableTabs`:
```json
"configurableTabs": [
  {
    "configurationUrl": "{{app_url}}/config?inTeams=true",
    "canUpdateConfiguration": true,
    "scopes": ["team", "groupChat"]
  }
]
```
Note: `contentUrl` / `configurationUrl` include `?inTeams=true` so middleware can detect Teams context. `websiteUrl` stays clean — it's the fallback URL when opened in a browser.

Warn: configurable tabs require a `/config` page that uses the Teams SDK to save settings via `pages.config.setConfig()`. If the user doesn't have one, explain what it needs to do.

**Both** — add both arrays, but enforce the Hard Rule: no shared channel scopes alongside `staticTabs`.

### Present and confirm

Show the complete generated manifest. Ask: "Does this look right?" Write to `./teams-app/manifest.json` only after confirmation.

### Generate privacy and terms pages (if missing)

Check if the app has routes at `/privacy` and `/terms`. If not, offer to create stub pages.

**For Next.js App Router projects**, generate:

`app/privacy/page.tsx`:
```tsx
export default function PrivacyPage() {
  return (
    <main style={{ maxWidth: 640, margin: '0 auto', padding: '2rem' }}>
      <h1>Privacy Policy</h1>
      <p>{{app_name}} is an internal tool. No personal data is shared with third parties.</p>
      <p>User identity is provided by Microsoft Teams or your organization&apos;s SSO provider.
         No additional data collection occurs beyond what is necessary to operate the application.</p>
      <p>For questions, contact your IT administrator.</p>
    </main>
  );
}
```

`app/terms/page.tsx`:
```tsx
export default function TermsPage() {
  return (
    <main style={{ maxWidth: 640, margin: '0 auto', padding: '2rem' }}>
      <h1>Terms of Use</h1>
      <p>{{app_name}} is provided for internal use within your organization.</p>
      <p>Use of this application is subject to your organization&apos;s acceptable use policies.
         This tool is provided as-is for internal productivity purposes.</p>
      <p>For questions, contact your IT administrator.</p>
    </main>
  );
}
```

**For other frameworks**, generate equivalent simple HTML pages at the right paths.

These are intentionally minimal — they satisfy the Teams manifest requirement. Tell the user: "These are stub pages. You can customize them later, but they must exist at these URLs before submission."

Make sure these routes are **excluded from auth middleware** — they need to be publicly accessible. Add them to the public routes list in the middleware bypass.

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
- [ ] Auth is bypassed in Teams context — no login screen appears when loaded in an iframe
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
| Login screen inside Teams | Auth middleware redirecting to `/login` | Detect Teams context and bypass auth — Teams already authenticated the user |
| Redirect loop in iframe | SSO/OAuth flow trying to navigate away | Strip SSO redirects in Teams context; use `app.getContext()` for identity |
| White screen / blank iframe | `X-Frame-Options` or CSP `frame-ancestors` blocking Teams | Remove restrictive header or add `teams.microsoft.com *.teams.microsoft.com *.skype.com` to `frame-ancestors` |
| Infinite loading spinner | Missing `app.notifySuccess()` after Teams SDK init | Add `await app.initialize(); app.notifySuccess();` to app startup |
| "App not found" after upload | Pending IT approval | Normal. Tell IT admin to approve in Admin Center. |
| Upload rejects the zip | Schema validation failure | Check manifest against schema 1.16; ensure no extra fields or files in zip |
| Works in browser, broken in Teams | Native dialog / popup / storage blocker | Re-run Phase 1 scan |
| Icons rejected | Wrong dimensions or outline uses color | `color.png` must be exactly 192x192, `outline.png` exactly 32x32 white-on-transparent |
| App approved but users can't find it | App policy not assigned | IT needs to assign the app via Teams app setup policies, or set it to "Allowed" for the org |
