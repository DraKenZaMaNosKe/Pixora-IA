#!/usr/bin/env bash
# PostToolUse hook — run `dart format` on any .dart file that was just Edit'd or Write'n.
# Reads the tool call JSON from stdin, extracts file_path, acts only if .dart.
set -e

INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | python -c "
import sys, json
try:
    data = json.load(sys.stdin)
    fp = data.get('tool_input', {}).get('file_path', '')
    print(fp)
except Exception:
    pass
" 2>/dev/null)

# Only act on .dart files
case "$FILE" in
  *.dart)
    if command -v dart >/dev/null 2>&1; then
      dart format "$FILE" >/dev/null 2>&1 || true
    fi
    ;;
esac

exit 0
