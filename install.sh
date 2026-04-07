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
