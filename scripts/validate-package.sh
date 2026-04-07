#!/usr/bin/env bash
set -euo pipefail

# Teams App Package Validator
# Validates a Teams app package directory before zipping.
# Usage: validate-package.sh [directory]
#   directory: path to the Teams app directory (default: ./teams-app)

DIR="${1:-./teams-app}"
ERRORS=0
WARNINGS=0

pass()  { echo "  PASS  $1"; }
fail()  { echo "  FAIL  $1"; ERRORS=$((ERRORS + 1)); }
warn()  { echo "  WARN  $1"; WARNINGS=$((WARNINGS + 1)); }

echo "Validating Teams app package in: $DIR"
echo ""

# --- 1. manifest.json exists ---
MANIFEST="$DIR/manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
  fail "manifest.json not found in $DIR"
  echo ""
  echo "Summary: $ERRORS error(s), $WARNINGS warning(s)"
  exit 1
fi
pass "manifest.json exists"

# --- 2. manifest.json is valid JSON ---
if ! python3 -c "import json, sys; json.load(open(sys.argv[1]))" "$MANIFEST" 2>/dev/null; then
  fail "manifest.json is not valid JSON"
  echo ""
  echo "Summary: $ERRORS error(s), $WARNINGS warning(s)"
  exit 1
fi
pass "manifest.json is valid JSON"

# --- 3. Required fields present ---
REQUIRED_FIELDS='["$schema", "manifestVersion", "id", "version", "name", "description", "icons", "developer", "accentColor", "validDomains"]'
MISSING=$(python3 -c "
import json, sys
manifest = json.load(open(sys.argv[1]))
required = json.loads(sys.argv[2])
missing = [f for f in required if f not in manifest]
print('\n'.join(missing))
" "$MANIFEST" "$REQUIRED_FIELDS")

if [[ -n "$MISSING" ]]; then
  while IFS= read -r field; do
    fail "Required field missing: $field"
  done <<< "$MISSING"
else
  pass "All required fields present"
fi

# --- 4. id is a valid UUID ---
ID_VALID=$(python3 -c "
import json, sys, re
manifest = json.load(open(sys.argv[1]))
app_id = manifest.get('id', '')
pattern = r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
print('valid' if re.match(pattern, app_id) else 'invalid')
" "$MANIFEST")

if [[ "$ID_VALID" == "valid" ]]; then
  pass "id is a valid UUID"
else
  fail "id is not a valid UUID (expected xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
fi

# --- 5. color.png exists ---
if [[ -f "$DIR/color.png" ]]; then
  pass "color.png exists"
else
  fail "color.png not found in $DIR"
fi

# --- 6. outline.png exists ---
if [[ -f "$DIR/outline.png" ]]; then
  pass "outline.png exists"
else
  fail "outline.png not found in $DIR"
fi

# --- 7. No unexpected extra files ---
EXTRA_FILES=$(python3 -c "
import os, sys
expected = {'manifest.json', 'color.png', 'outline.png'}
actual = set(os.listdir(sys.argv[1]))
extra = sorted(actual - expected)
print('\n'.join(extra))
" "$DIR")

if [[ -n "$EXTRA_FILES" ]]; then
  while IFS= read -r f; do
    warn "Unexpected file in package directory: $f"
  done <<< "$EXTRA_FILES"
else
  pass "No unexpected files in package directory"
fi

# --- 8. No staticTabs + sharedChannels conflict ---
CONFLICT=$(python3 -c "
import json, sys
manifest = json.load(open(sys.argv[1]))
has_static = 'staticTabs' in manifest
has_shared = False
for tab in manifest.get('configurableTabs', []):
    scopes = [s.lower() for s in tab.get('scopes', [])]
    if 'sharedchannels' in scopes or 'sharedchannel' in scopes:
        has_shared = True
        break
# Also check context
for tab in manifest.get('configurableTabs', []):
    context = [c.lower() for c in tab.get('context', [])]
    if 'channelsharedtab' in context:
        has_shared = True
        break
print('conflict' if has_static and has_shared else 'ok')
" "$MANIFEST")

if [[ "$CONFLICT" == "conflict" ]]; then
  fail "staticTabs and sharedChannels scopes cannot coexist in the same manifest"
else
  pass "No staticTabs + sharedChannels conflict"
fi

# --- 9. contentUrl / configurationUrl includes ?inTeams=true ---
INTEAMS_MISSING=$(python3 -c "
import json, sys
manifest = json.load(open(sys.argv[1]))
missing = []
for tab in manifest.get('staticTabs', []):
    url = tab.get('contentUrl', '')
    if url and 'inTeams=true' not in url:
        missing.append('staticTabs[].contentUrl: ' + url)
for tab in manifest.get('configurableTabs', []):
    url = tab.get('configurationUrl', '')
    if url and 'inTeams=true' not in url:
        missing.append('configurableTabs[].configurationUrl: ' + url)
print('\n'.join(missing))
" "$MANIFEST")

if [[ -n "$INTEAMS_MISSING" ]]; then
  while IFS= read -r url_info; do
    warn "URL missing ?inTeams=true: $url_info"
  done <<< "$INTEAMS_MISSING"
else
  pass "All contentUrl/configurationUrl entries include ?inTeams=true"
fi

# --- Summary ---
echo ""
echo "Summary: $ERRORS error(s), $WARNINGS warning(s)"

if [[ "$ERRORS" -gt 0 ]]; then
  exit 1
fi
exit 0
