#!/usr/bin/env bash
# PostToolUse hook: auto-format files edited via Edit/MultiEdit/Write with the
# project's own prettier. Skips silently when the file's project has no local
# prettier install, so non-JS projects and scratchpad files are untouched.
#
# When prettier actually rewrites the file, exits 2 so the harness feeds the
# stderr note back to Claude — otherwise the next Edit would fail on stale
# file state.
#
# Stdout stays empty per the hook protocol; all prettier noise goes to /dev/null.

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0

case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.json|*.css|*.scss|*.md|*.mdx|*.yaml|*.yml|*.html) ;;
  *) exit 0 ;;
esac

# Walk up from the file to the nearest project-local prettier binary. No npx:
# deterministic resolution, never downloads, works from pnpm workspace subdirs
# (bin is hoisted to the workspace root).
DIR=$(cd "$(dirname "$FILE")" 2>/dev/null && pwd) || exit 0
ROOT="$DIR"
PRETTIER=""
while [ "$ROOT" != "/" ]; do
  if [ -x "$ROOT/node_modules/.bin/prettier" ]; then
    PRETTIER="$ROOT/node_modules/.bin/prettier"
    break
  fi
  ROOT=$(dirname "$ROOT")
done
[ -n "$PRETTIER" ] || exit 0

BEFORE=$(cksum "$FILE" 2>/dev/null)

# Run from the project root so .prettierignore / .gitignore there are respected.
# --ignore-unknown covers extensions prettier has no parser for.
(cd "$ROOT" && "$PRETTIER" --write --ignore-unknown "$FILE") >/dev/null 2>&1 || exit 0

AFTER=$(cksum "$FILE" 2>/dev/null)

if [ "$BEFORE" != "$AFTER" ]; then
  echo "prettier-write: reformatted $FILE — file contents changed on disk; re-read it before making further edits to it" >&2
  exit 2
fi

exit 0
