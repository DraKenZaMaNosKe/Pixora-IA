#!/usr/bin/env bash
# SessionStart hook — brief Pixora orientation dump.
# Output is added to Claude's session context so it starts oriented.
set -e
cd "$(dirname "$0")/../.."

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
VERSION=$(grep -E "^version:" pubspec.yaml 2>/dev/null | awk '{print $2}' || echo "?")
UNCOMMITTED=$(git status -s 2>/dev/null | wc -l | tr -d ' ')
LAST_COMMIT=$(git log -1 --format='%h %s' 2>/dev/null || echo "?")

echo "===== Pixora Session Start ====="
echo "Branch:       $BRANCH"
echo "Version:      $VERSION"
echo "Uncommitted:  $UNCOMMITTED files"
echo "Last commit:  $LAST_COMMIT"
echo ""
echo "Recent commits:"
git log --oneline -3 2>/dev/null | sed 's/^/  /'
echo "================================"
