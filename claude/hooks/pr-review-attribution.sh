#!/usr/bin/env bash
# PostToolUse hook: appends Claude Ocodius attribution to PR review bodies AND
# all inline review comments created via `gh pr review` or
# `gh api .../pulls/{num}/reviews` POST calls.
# Review body is only edited when non-empty; inline comments are always attributed.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

IS_PR_REVIEW=0
IS_API_REVIEW=0
if echo "$CMD" | grep -qE '(^|[^[:alnum:]_-])gh pr review( |$)' \
  && echo "$CMD" | grep -qE '(^| )--body( |=)'; then
  IS_PR_REVIEW=1
elif echo "$CMD" | grep -qE 'gh api[^|;&]*repos/[^/ ]+/[^/ ]+/pulls/[0-9]+/reviews( |$|/)' \
  && echo "$CMD" | grep -qE '(-X ?POST|--method POST|(-f|-F|--field|--raw-field) +body=)'; then
  IS_API_REVIEW=1
else
  exit 0
fi

RESPONSE=$(echo "$INPUT" | jq -r '.tool_response.stdout // empty')
REPO_PATH=""
PR_NUMBER=""
REVIEW_ID=""

if [ "$IS_API_REVIEW" = "1" ]; then
  REVIEW_ID=$(echo "$RESPONSE" | jq -r '.id // empty' 2>/dev/null)
  if [ -z "$REVIEW_ID" ] || [ "$REVIEW_ID" = "null" ]; then
    exit 0
  fi
  REPO_PATH=$(echo "$CMD" | grep -oE 'repos/[^/ ]+/[^/ ]+' | head -1)
  PR_NUMBER=$(echo "$CMD" | grep -oE 'pulls/[0-9]+' | head -1 | sed 's|pulls/||')
else
  # gh pr review — derive repo + PR number from the command.
  PR_URL=$(echo "$CMD" | grep -oE 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+' | head -1)
  if [ -n "$PR_URL" ]; then
    REPO_PATH=$(echo "$PR_URL" | sed -E 's|https://github\.com/([^/]+/[^/]+)/.*|repos/\1|')
    PR_NUMBER=$(echo "$PR_URL" | sed -E 's|.*/pull/([0-9]+).*|\1|')
  else
    REPO_FLAG=$(echo "$CMD" | grep -oE -- '--repo [^ ]+' | awk '{print $2}' | head -1)
    NUM=$(echo "$CMD" | grep -oE 'gh pr review +[0-9]+' | awk '{print $NF}' | head -1)
    if [ -n "$REPO_FLAG" ] && [ -n "$NUM" ]; then
      REPO_PATH="repos/$REPO_FLAG"
      PR_NUMBER="$NUM"
    fi
  fi

  if [ -z "$REPO_PATH" ] || [ -z "$PR_NUMBER" ]; then
    exit 0
  fi

  # No review ID in gh pr review output — fetch the most recent review on the PR.
  REVIEW_ID=$(gh api "$REPO_PATH/pulls/$PR_NUMBER/reviews" --jq 'sort_by(.submitted_at) | last | .id' 2>/dev/null)
  if [ -z "$REVIEW_ID" ] || [ "$REVIEW_ID" = "null" ]; then
    exit 0
  fi
fi

if [ -z "$REPO_PATH" ] || [ -z "$PR_NUMBER" ] || [ -z "$REVIEW_ID" ]; then
  exit 0
fi

if ! CURRENT_BODY=$(gh api "$REPO_PATH/pulls/$PR_NUMBER/reviews/$REVIEW_ID" -q '.body' 2>/dev/null); then
  exit 0
fi

if [ -n "$CURRENT_BODY" ] && ! echo "$CURRENT_BODY" | grep -q "Claude Ocodius"; then
  UPDATED_BODY="${CURRENT_BODY}

\\- Claude Ocodius"
  gh api "$REPO_PATH/pulls/$PR_NUMBER/reviews/$REVIEW_ID" -X PUT -f body="$UPDATED_BODY" >/dev/null 2>&1
fi

# Attribute all inline comments belonging to this review.
COMMENT_IDS=$(gh api "$REPO_PATH/pulls/$PR_NUMBER/reviews/$REVIEW_ID/comments" --jq '.[].id' 2>/dev/null)
for cid in $COMMENT_IDS; do
  CBODY=$(gh api "$REPO_PATH/pulls/comments/$cid" -q '.body' 2>/dev/null)
  if [ -z "$CBODY" ] || echo "$CBODY" | grep -q "Claude Ocodius"; then
    continue
  fi
  gh api "$REPO_PATH/pulls/comments/$cid" -X PATCH -f body="${CBODY}

\\- Claude Ocodius" >/dev/null 2>&1
done

exit 0
