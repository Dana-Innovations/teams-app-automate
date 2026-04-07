#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$HOME/.claude/skills/teams-publish"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$SKILL_DIR"
cp "$SCRIPT_DIR/SKILL.md" "$SKILL_DIR/SKILL.md"

echo "Installed teams-publish skill to $SKILL_DIR"
echo ""
echo "Usage: Open Claude Code in any project and run:"
echo "  /teams-publish https://your-app.vercel.app"
