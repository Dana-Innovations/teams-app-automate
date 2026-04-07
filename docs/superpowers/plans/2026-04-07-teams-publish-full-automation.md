# Teams-Publish Full Automation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the teams-publish skill complete enough that `/teams-publish <url>` drives every step of Teams packaging automatically — auth bypass, blocker fixes, manifest, icons, validation, packaging — tested against the cortex-control-center project.

**Architecture:** The skill is a single `SKILL.md` file plus a `scripts/validate-package.sh` helper, installed to `~/.claude/skills/teams-publish/`. Claude reads SKILL.md at invocation and follows the phases. The proven dual-auth pattern from talent-management-next (manifest injects `?inTeams=true`, middleware checks param, client TeamsContext provider tries SDK init) replaces the current vague auth stripping section.

**Tech Stack:** Claude Code skill (Markdown), Bash validation script, Teams manifest schema 1.16, `@microsoft/teams-js` SDK patterns

---

### Task 1: Rewrite SKILL.md Phase 1 auth section with the proven dual-auth pattern

**Files:**
- Modify: `SKILL.md:37-72` (the current "Auth stripping" section)

The current auth section is conceptual. Replace it with the concrete pattern from talent-management-next: `?inTeams=true` query param in manifest, middleware conditional bypass, `TeamsContext` provider, dual cookie SameSite settings.

- [ ] **Step 1: Replace the auth stripping section**

Replace the current "Auth stripping (highest priority)" section (lines 37-72) with this:

```markdown
### Dual-auth bypass (highest priority)

Teams handles authentication — the user is already signed into their Microsoft tenant. But the app still needs normal auth when accessed via browser. The skill sets up **dual-auth**: Teams context bypasses login, browser context uses existing auth.

This is the proven pattern. Three pieces work together:

#### 1. Manifest injects `?inTeams=true`

In Phase 2, the manifest `contentUrl` must append `?inTeams=true` to the app URL:
```json
"contentUrl": "{{app_url}}?inTeams=true"
```
This is how the server knows the request is coming from Teams before the client-side SDK loads.

#### 2. Middleware detects Teams context and skips auth

Find the project's auth middleware (e.g., `middleware.ts`, auth guards, route protection). Add a check at the top:

```typescript
// If loaded inside Teams, skip normal auth redirect — Teams handles authentication
const inTeams = request.nextUrl.searchParams.get('inTeams') === 'true';
if (inTeams) {
  // Allow through to client — TeamsContext will handle identity via SDK
  return NextResponse.next();
}
// ... existing auth logic unchanged for browser access ...
```

For frameworks other than Next.js, apply the equivalent: check the query param before any auth redirect.

#### 3. Client-side TeamsContext provider

Generate a `TeamsContext` provider component that the app wraps around its content. This provider:

1. Tries `app.initialize()` from `@microsoft/teams-js`
2. If it succeeds → the app is in Teams. Call `app.getContext()` to get user identity, then `app.notifySuccess()`.
3. If it fails → the app is in a browser. Fall through to normal auth.

```typescript
// src/components/TeamsContext.tsx (or equivalent path for the project)
'use client';

import { createContext, useContext, useEffect, useState, ReactNode } from 'react';
import { app } from '@microsoft/teams-js';

interface TeamsContextValue {
  isTeams: boolean;
  teamsUser: { id: string; displayName: string; email: string } | null;
  loading: boolean;
}

const TeamsCtx = createContext<TeamsContextValue>({ isTeams: false, teamsUser: null, loading: true });

export function useTeams() { return useContext(TeamsCtx); }

export function TeamsProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<TeamsContextValue>({ isTeams: false, teamsUser: null, loading: true });

  useEffect(() => {
    (async () => {
      try {
        await app.initialize();
        const ctx = await app.getContext();
        setState({
          isTeams: true,
          teamsUser: ctx.user ? {
            id: ctx.user.id ?? '',
            displayName: ctx.user.displayName ?? '',
            email: ctx.user.loginHint ?? '',
          } : null,
          loading: false,
        });
        app.notifySuccess();
      } catch {
        // Not in Teams — fall through to normal auth
        setState({ isTeams: false, teamsUser: null, loading: false });
      }
    })();
  }, []);

  return <TeamsCtx.Provider value={state}>{children}</TeamsCtx.Provider>;
}
```

**Tell Claude to:**
- Install `@microsoft/teams-js` as a dependency
- Create the TeamsContext provider file
- Wrap the app's root layout/providers with `<TeamsProvider>`
- In any auth-gated component, check `useTeams().isTeams` — if true, skip login redirect
- Provider ordering matters: TeamsProvider should wrap before any auth-dependent providers

#### Cookie considerations

If the app sets session cookies, they must use `sameSite: 'none'` and `secure: true` when in Teams context (iframe requires this). When in browser context, keep `sameSite: 'lax'`. Detect based on the `inTeams` param or the `Sec-Fetch-Dest: iframe` header.

#### What NOT to do

- Do NOT remove existing auth. Browser access still needs it.
- Do NOT require a separate Teams build or deployment. One deployment serves both.
- Do NOT add Azure AD app registration or bot framework. This is a tab app — Teams SSO via the SDK is sufficient for identity.
```

- [ ] **Step 2: Verify the edit is clean**

Read the full Phase 1 section after the edit to make sure the flow from auth → other blockers → header checks → presenting fixes is coherent.

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat: replace auth stripping with proven dual-auth pattern from talent-management-next"
```

---

### Task 2: Update SKILL.md Phase 2 manifest template to include `?inTeams=true`

**Files:**
- Modify: `SKILL.md:148-159` (staticTabs template)
- Modify: `SKILL.md:161-170` (configurableTabs template)

The manifest contentUrl must append `?inTeams=true` so middleware can detect Teams context server-side.

- [ ] **Step 1: Update the staticTabs template**

Change the `contentUrl` in the personal tab template:

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

Note: `websiteUrl` stays without the param — it's the fallback URL when opened in browser.

- [ ] **Step 2: Update the configurableTabs template**

Change the `configurationUrl`:

```json
"configurableTabs": [
  {
    "configurationUrl": "{{app_url}}/config?inTeams=true",
    "canUpdateConfiguration": true,
    "scopes": ["team", "groupChat"]
  }
]
```

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat: manifest contentUrl includes ?inTeams=true for server-side Teams detection"
```

---

### Task 3: Add privacy/terms stub page generation to Phase 2

**Files:**
- Modify: `SKILL.md` (after the "Present and confirm" section in Phase 2, before Phase 3)

The skill warns that privacy/terms pages need to exist but doesn't offer to create them. Add a sub-phase.

- [ ] **Step 1: Add stub page generation section**

Insert after the "Present and confirm" subsection of Phase 2:

```markdown
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
      <p>User identity is provided by Microsoft Teams or your organization's SSO provider.
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
      <p>Use of this application is subject to your organization's acceptable use policies.
         This tool is provided as-is for internal productivity purposes.</p>
      <p>For questions, contact your IT administrator.</p>
    </main>
  );
}
```

**For other frameworks**, generate equivalent simple HTML pages at the right paths.

These are intentionally minimal. Tell the user: "These are stub pages that satisfy the Teams manifest requirement. You can customize them later, but they must exist at these URLs before submission."

Make sure these routes are excluded from auth middleware (they need to be publicly accessible).
```

- [ ] **Step 2: Commit**

```bash
git add SKILL.md
git commit -m "feat: Phase 2 offers to generate privacy/terms stub pages if missing"
```

---

### Task 4: Enhance Phase 1 blocker fixes with concrete replacement code

**Files:**
- Modify: `SKILL.md:74-83` (the "Other blockers to detect" table and surrounding area)

The current table tells Claude what to replace but doesn't show the concrete fix code. Add implementation patterns for each blocker.

- [ ] **Step 1: Expand the blockers section with fix patterns**

Replace the "Other blockers to detect" table and add detailed fix patterns after it:

```markdown
### Other blockers to detect and fix

| Pattern | Why it breaks | Fix |
|---|---|---|
| `alert(` / `confirm(` / `prompt(` | Native dialogs blocked in Teams iframe | Replace with a modal component |
| `window.open(` | Popups blocked in iframe | Conditional: Teams `app.openLink()` vs browser `window.open()` |
| `localStorage` / `sessionStorage` | May be blocked in third-party iframe context | Wrap in try/catch with in-memory fallback |
| Dark mode toggle / theme switcher | Teams controls the theme | In Teams context, hide toggle and sync to Teams theme |

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
```

- [ ] **Step 2: Commit**

```bash
git add SKILL.md
git commit -m "feat: Phase 1 blockers have concrete fix patterns with code examples"
```

---

### Task 5: Enhance Phase 3 with icon generation commands

**Files:**
- Modify: `SKILL.md` (Phase 3, after "Help find existing assets")

Add concrete commands for converting existing SVGs or generating placeholder icons.

- [ ] **Step 1: Add icon conversion helpers**

After the "Help find existing assets" subsection, add:

```markdown
### Convert or generate icons

If an SVG favicon or logo exists, offer to convert it:

**Using sips (macOS built-in, no dependencies):**

If a PNG source exists:
```bash
# Resize to 192x192 for color icon
sips -z 192 192 source.png --out ./teams-app/color.png

# Resize to 32x32 for outline icon (user must make it white-on-transparent separately)
sips -z 32 32 source.png --out ./teams-app/outline.png
```

**Using ImageMagick (if available):**
```bash
# Convert SVG to 192x192 PNG
magick favicon.svg -resize 192x192 -background none -gravity center -extent 192x192 ./teams-app/color.png

# Convert SVG to 32x32 white-on-transparent (outline)
magick favicon.svg -resize 32x32 -background none -gravity center -extent 32x32 -colorspace gray -fill white -opaque black ./teams-app/outline.png
```

**Check if tools are available:**
```bash
which sips magick convert 2>/dev/null
```

If no conversion tool is available and no icons exist, tell the user exactly what to provide:
- `color.png`: 192x192, full-color, PNG format, placed in `./teams-app/`
- `outline.png`: 32x32, white shapes on transparent background, PNG format, placed in `./teams-app/`

Do NOT skip this step or proceed to packaging without icons. The zip will be rejected.
```

- [ ] **Step 2: Commit**

```bash
git add SKILL.md
git commit -m "feat: Phase 3 adds concrete icon conversion commands (sips, ImageMagick)"
```

---

### Task 6: Create scripts/validate-package.sh

**Files:**
- Create: `scripts/validate-package.sh`

A standalone bash script that validates a Teams app package before submission. The skill references this in Phase 4.

- [ ] **Step 1: Write the validation script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Teams App Package Validator
# Usage: bash validate-package.sh [teams-app-dir]
# Defaults to ./teams-app if no argument given

DIR="${1:-./teams-app}"
ERRORS=0
WARNINGS=0

pass() { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "  WARN  $1"; WARNINGS=$((WARNINGS + 1)); }

echo "Validating Teams app package in: $DIR"
echo "---"

# 1. manifest.json exists
if [ ! -f "$DIR/manifest.json" ]; then
  fail "manifest.json not found in $DIR"
  echo ""
  echo "Result: $ERRORS error(s), $WARNINGS warning(s)"
  exit 1
else
  pass "manifest.json exists"
fi

# 2. Valid JSON
if ! python3 -c "import json; json.load(open('$DIR/manifest.json'))" 2>/dev/null; then
  fail "manifest.json is not valid JSON"
else
  pass "manifest.json is valid JSON"
fi

# 3. Required fields
for field in '\$schema' manifestVersion id version name description icons developer accentColor validDomains; do
  if python3 -c "
import json, sys
m = json.load(open('$DIR/manifest.json'))
key = '$field'.replace('\$', '$')
if key not in m:
    sys.exit(1)
" 2>/dev/null; then
    pass "Required field '$field' present"
  else
    fail "Required field '$field' missing"
  fi
done

# 4. UUID format for id
if python3 -c "
import json, re, sys
m = json.load(open('$DIR/manifest.json'))
if not re.match(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', m.get('id', ''), re.I):
    sys.exit(1)
" 2>/dev/null; then
  pass "id is valid UUID format"
else
  fail "id is not a valid UUID (expected xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
fi

# 5. Icons exist
if [ -f "$DIR/color.png" ]; then
  pass "color.png exists"
else
  fail "color.png not found in $DIR"
fi

if [ -f "$DIR/outline.png" ]; then
  pass "outline.png exists"
else
  fail "outline.png not found in $DIR"
fi

# 6. No extra files
EXPECTED_FILES="color.png manifest.json outline.png"
ACTUAL_FILES=$(ls "$DIR" 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')
if [ "$ACTUAL_FILES" = "$EXPECTED_FILES" ]; then
  pass "No extra files in package directory"
else
  warn "Extra files found in $DIR (Teams may reject): $ACTUAL_FILES"
fi

# 7. staticTabs + sharedChannels conflict
if python3 -c "
import json, sys
m = json.load(open('$DIR/manifest.json'))
has_static = bool(m.get('staticTabs'))
has_shared = False
for tab in m.get('configurableTabs', []):
    if 'sharedChannels' in str(tab.get('scopes', [])):
        has_shared = True
if has_static and has_shared:
    sys.exit(1)
" 2>/dev/null; then
  pass "No staticTabs + sharedChannels conflict"
else
  fail "staticTabs and sharedChannels combined — this causes silent deployment failures"
fi

# 8. contentUrl includes ?inTeams=true
if python3 -c "
import json, sys
m = json.load(open('$DIR/manifest.json'))
urls = []
for tab in m.get('staticTabs', []):
    urls.append(tab.get('contentUrl', ''))
for tab in m.get('configurableTabs', []):
    urls.append(tab.get('configurationUrl', ''))
if not urls:
    sys.exit(0)  # no tabs to check
for url in urls:
    if 'inTeams=true' not in url:
        sys.exit(1)
" 2>/dev/null; then
  pass "contentUrl includes ?inTeams=true for Teams context detection"
else
  warn "contentUrl missing ?inTeams=true — middleware won't detect Teams context"
fi

echo "---"
echo "Result: $ERRORS error(s), $WARNINGS warning(s)"

if [ "$ERRORS" -gt 0 ]; then
  echo "Fix errors before packaging."
  exit 1
else
  echo "Package is valid."
  exit 0
fi
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/validate-package.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/validate-package.sh
git commit -m "feat: add standalone Teams package validation script"
```

---

### Task 7: Update SKILL.md Phase 4 to use validate-package.sh

**Files:**
- Modify: `SKILL.md` (Phase 4 "Validate before packaging" section)

- [ ] **Step 1: Add script reference to Phase 4**

After the existing validation checklist, add:

```markdown
### Run the validation script

If the skill's `scripts/validate-package.sh` is available, run it:

```bash
bash ~/.claude/skills/teams-publish/scripts/validate-package.sh ./teams-app
```

This checks all of the above automatically. If it's not available (skill installed without scripts), run the manual checks above.
```

- [ ] **Step 2: Commit**

```bash
git add SKILL.md
git commit -m "feat: Phase 4 references validate-package.sh for automated checking"
```

---

### Task 8: Update install.sh to copy full skill directory

**Files:**
- Modify: `install.sh`

Currently copies only SKILL.md. Update to copy scripts/ too.

- [ ] **Step 1: Rewrite install.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$HOME/.claude/skills/teams-publish"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Clean previous install
rm -rf "$SKILL_DIR"
mkdir -p "$SKILL_DIR"

# Copy skill file
cp "$SCRIPT_DIR/SKILL.md" "$SKILL_DIR/SKILL.md"

# Copy scripts if they exist
if [ -d "$SCRIPT_DIR/scripts" ]; then
  cp -r "$SCRIPT_DIR/scripts" "$SKILL_DIR/scripts"
fi

echo "Installed teams-publish skill to $SKILL_DIR"
echo ""
echo "Usage: Open Claude Code in any project and run:"
echo "  /teams-publish https://your-app.vercel.app"
```

- [ ] **Step 2: Commit**

```bash
git add install.sh
git commit -m "feat: install.sh copies full skill directory including scripts"
```

---

### Task 9: Update README.md

**Files:**
- Modify: `README.md`

Reflect the dual-auth pattern, validation script, and updated phase descriptions.

- [ ] **Step 1: Update README.md**

Update the phase table to mention auth bypass instead of just "codebase scan":

```markdown
| Phase | What happens |
|---|---|
| **0 — Collect inputs** | Asks for URL, app name, description, and tab type (personal or configurable) |
| **1 — Codebase scan** | Sets up dual-auth (Teams bypasses login, browser keeps existing auth), fixes iframe blockers (`alert()`, `confirm()`, `window.open()`, `localStorage`, theme toggles), adds Teams SDK |
| **2 — Generate manifest** | Creates `./teams-app/manifest.json` with `?inTeams=true` in contentUrl, auto-generated UUID, correct scopes. Generates privacy/terms stub pages if missing. |
| **3 — Icon guidance** | Tells you what icon files are needed, offers to convert existing SVG/PNG assets, warns that name/logo lock after submission |
| **4 — Package & validate** | Runs validation script, then zips `manifest.json` + icons into `teams-app-package.zip` |
| **5 — Submission checklist** | Prints a copy-paste checklist and direct link to Teams Admin Center — this is the only step that needs IT |
```

Add a "Files" section:
```markdown
## Files

| File | Purpose |
|---|---|
| `SKILL.md` | The skill instruction payload — Claude reads this when `/teams-publish` is invoked |
| `install.sh` | Copies the skill + scripts into `~/.claude/skills/teams-publish/` |
| `README.md` | This file |
| `scripts/validate-package.sh` | Standalone validator — checks manifest, icons, UUID, no conflicts |
```

Update the "Known gotchas" section:
```markdown
## Known gotchas

- **Auth still works in browser** — the skill sets up dual-auth, not auth removal. Teams users skip login, browser users get normal auth.
- **`?inTeams=true` in manifest** — this is how middleware knows to bypass auth. The manifest contentUrl includes this param; the websiteUrl does not.
- **staticTabs + sharedChannels can't coexist** in one manifest — the skill and validation script both enforce this
- **Cookie SameSite** — Teams iframe requires `sameSite: 'none'` + `secure: true`. Browser uses `sameSite: 'lax'`. The skill patches this based on context.
- **App name and logo are locked after first submission** — the skill warns you before packaging
- **Upload succeeds but app doesn't appear** — normal, it's waiting for IT approval in Admin Center
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README with dual-auth pattern, validation script, revised phases"
```

---

### Task 10: Reinstall and test against cortex-control-center

**Files:**
- No new files — this is a test run

- [ ] **Step 1: Reinstall the updated skill**

```bash
bash ~/teams-app-automate/install.sh
```

- [ ] **Step 2: Verify installation**

```bash
ls -la ~/.claude/skills/teams-publish/
cat ~/.claude/skills/teams-publish/SKILL.md | head -5
ls ~/.claude/skills/teams-publish/scripts/
```

Expected: SKILL.md and scripts/validate-package.sh both present.

- [ ] **Step 3: Open cortex-control-center and invoke the skill**

```bash
cd ~/Cortex-Control-Center
# Invoke: /teams-publish https://cortex.sonance.com
```

Run through each phase and verify:

**Phase 0 check:**
- Does it auto-infer "Cortex Control Center" from package.json?
- Does it ask for description (since package.json has none)?
- Does it default to personal tab type?

**Phase 1 check:**
- Does it find `src/middleware.ts` and offer the `inTeams` bypass?
- Does it generate a TeamsContext provider?
- Does it find `confirm()` on line ~214 of connections/page.tsx?
- Does it find `window.open()` on line ~199 of connections/page.tsx?
- Does it find localStorage in layout.tsx, ThemeToggle.tsx, Topbar.tsx?
- Does it offer to hide ThemeToggle in Teams context?
- Does it install `@microsoft/teams-js`?

**Phase 2 check:**
- Does manifest have `?inTeams=true` in contentUrl?
- Does it include `cortex.sonance.com` and `*.vercel.app` in validDomains?
- Does it offer to create /privacy and /terms stub pages?

**Phase 3 check:**
- Does it find `public/favicon.svg` and offer to convert?
- Does it warn about name/logo lock?

**Phase 4 check:**
- Does validate-package.sh run and pass (after icons are provided)?

**Phase 5 check:**
- Is the checklist populated with cortex.sonance.com URLs?

- [ ] **Step 4: Document any issues found**

If any phase doesn't work as expected, note the issue and which part of SKILL.md needs adjustment. Fix in a follow-up commit.

- [ ] **Step 5: Final commit if test-driven fixes were needed**

```bash
git add -A
git commit -m "fix: adjustments from cortex-control-center test run"
```
