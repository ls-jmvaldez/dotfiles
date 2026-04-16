#!/usr/bin/env bash
# PostToolUse hook: appends Claude Ocodius attribution to PR descriptions.
# Runs on `gh pr create` and on `gh pr edit --body`.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

IS_CREATE=0
IS_EDIT=0
if echo "$CMD" | grep -qE '(^|[^[:alnum:]_-])gh pr create( |$)'; then
  IS_CREATE=1
elif echo "$CMD" | grep -qE '(^|[^[:alnum:]_-])gh pr edit( |$)' \
  && echo "$CMD" | grep -qE '(^| )--body( |=)'; then
  IS_EDIT=1
else
  exit 0
fi

RESPONSE=$(echo "$INPUT" | jq -r '.tool_response.stdout // empty')
PR_URL=""

if [ "$IS_CREATE" = "1" ]; then
  # gh pr create prints the PR URL on stdout.
  PR_URL=$(echo "$RESPONSE" | tr -d '[:space:]' | grep -oE 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+' | head -1)
else
  # gh pr edit: the PR can be specified as a URL, a number, or the current branch.
  PR_URL=$(echo "$CMD" | grep -oE 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+' | head -1)
  if [ -z "$PR_URL" ]; then
    # Try --repo + number form, e.g. `gh pr edit 37 --repo foo/bar --body "..."`
    REPO=$(echo "$CMD" | grep -oE -- '--repo [^ ]+' | awk '{print $2}' | head -1)
    NUM=$(echo "$CMD" | grep -oE 'gh pr edit +[0-9]+' | awk '{print $NF}' | head -1)
    if [ -n "$REPO" ] && [ -n "$NUM" ]; then
      PR_URL="https://github.com/${REPO}/pull/${NUM}"
    fi
  fi
fi

if ! echo "$PR_URL" | grep -qE 'https://github\.com/.+/pull/[0-9]+'; then
  exit 0
fi

CURRENT_BODY=$(gh pr view "$PR_URL" --json body -q '.body' 2>/dev/null)

if echo "$CURRENT_BODY" | grep -q "Claude Ocodius"; then
  exit 0
fi

UPDATED_BODY="${CURRENT_BODY}

---
Contributed by Claude Ocodius"

gh pr edit "$PR_URL" --body "$UPDATED_BODY" >/dev/null 2>&1

exit 0
