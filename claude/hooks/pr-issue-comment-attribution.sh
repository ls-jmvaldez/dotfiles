#!/usr/bin/env bash
# PostToolUse hook: appends Claude Ocodius attribution to top-level PR issue comments
# created via `gh pr comment` or `gh api .../issues/{num}/comments` POST calls.
# Complements pr-comment-attribution.sh (handles inline review-comment replies)
# and pr-attribution.sh (handles PR descriptions).

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Quick bail: not gh at all
if ! echo "$CMD" | grep -qE 'gh (pr comment|api)'; then
  exit 0
fi

# Classify: `gh pr comment` OR `gh api .../repos/.../issues/.../comments` (excluding inline review comments)
IS_PR_COMMENT=0
IS_API_COMMENT=0
if echo "$CMD" | grep -qE '(^|[^[:alnum:]_-])gh pr comment( |$)'; then
  IS_PR_COMMENT=1
elif echo "$CMD" | grep -qE 'gh api[^|;&]*repos/[^/]+/[^/]+/issues/[0-9]+/comments' \
  && echo "$CMD" | grep -qE '(-X ?POST|--method POST|(-f|-F|--field|--raw-field) +body=)'; then
  IS_API_COMMENT=1
else
  exit 0
fi

RESPONSE=$(echo "$INPUT" | jq -r '.tool_response.stdout // empty')

COMMENT_ID=""
REPO_PATH=""

if [ "$IS_PR_COMMENT" = "1" ]; then
  # `gh pr comment` prints the comment URL on stdout
  URL=$(echo "$RESPONSE" | tr -d '[:space:]' | grep -oE 'https://github\.com/[^/]+/[^/]+/(pull|issues)/[0-9]+#issuecomment-[0-9]+' | head -1)
  if [ -z "$URL" ]; then
    exit 0
  fi
  COMMENT_ID=$(echo "$URL" | grep -oE 'issuecomment-[0-9]+' | sed 's/issuecomment-//')
  OWNER_REPO=$(echo "$URL" | sed -E 's|https://github\.com/([^/]+/[^/]+)/.*|\1|')
  REPO_PATH="repos/$OWNER_REPO"
else
  # `gh api` POST returns JSON; look for a created comment (has id + issuecomment URL)
  COMMENT_ID=$(echo "$RESPONSE" | jq -r '.id // empty' 2>/dev/null)
  HTML_URL=$(echo "$RESPONSE" | jq -r '.html_url // empty' 2>/dev/null)
  if [ -z "$COMMENT_ID" ] || [ "$COMMENT_ID" = "null" ]; then
    exit 0
  fi
  if ! echo "$HTML_URL" | grep -q 'issuecomment-'; then
    exit 0
  fi
  REPO_PATH=$(echo "$CMD" | grep -oE 'repos/[^/ ]+/[^/ ]+' | head -1)
  if [ -z "$REPO_PATH" ]; then
    exit 0
  fi
fi

# Fetch current body; abort on any non-2xx (gh api exits non-zero)
if ! CURRENT_BODY=$(gh api "$REPO_PATH/issues/comments/$COMMENT_ID" -q '.body' 2>/dev/null); then
  exit 0
fi

if [ -z "$CURRENT_BODY" ]; then
  exit 0
fi

if echo "$CURRENT_BODY" | grep -q "Claude Ocodius"; then
  exit 0
fi

UPDATED_BODY="${CURRENT_BODY}

\\- Claude Ocodius"

gh api "$REPO_PATH/issues/comments/$COMMENT_ID" -X PATCH -f body="$UPDATED_BODY" >/dev/null 2>&1

exit 0
