#!/usr/bin/env bash
# PostToolUse hook: appends Claude Ocodius attribution to inline PR review comments
# created or edited via `gh api` calls. Covers:
#   - top-level review comments:    POST /repos/{o}/{r}/pulls/{n}/comments
#   - review comment replies:       POST /repos/{o}/{r}/pulls/{n}/comments/{id}/replies
#   - review comment edits:         PATCH /repos/{o}/{r}/pulls/comments/{id}
# Does NOT rely on the body being present in the tool_response (e.g. when
# the caller used --jq to filter the response). Body is fetched fresh via API.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Must be a gh api call targeting a PR review-comment path (create, reply, or edit).
if ! echo "$CMD" | grep -qE 'gh api[^|;&]*repos/[^/ ]+/[^/ ]+/pulls/([0-9]+/comments(/[0-9]+/replies)?|comments/[0-9]+)'; then
  exit 0
fi

# Must be a write. POST creates; PATCH edits. Default gh api method is POST when a body
# field is set, so a bare `-f body=` without an explicit method also counts as a write.
if ! echo "$CMD" | grep -qE '(-X ?POST|--method POST|-X ?PATCH|--method PATCH|(-f|-F|--field|--raw-field) +body=)'; then
  exit 0
fi

RESPONSE=$(echo "$INPUT" | jq -r '.tool_response.stdout // empty')
COMMENT_ID=$(echo "$RESPONSE" | jq -r '.id // empty' 2>/dev/null)

if [ -z "$COMMENT_ID" ] || [ "$COMMENT_ID" = "null" ]; then
  exit 0
fi

REPO_PATH=$(echo "$CMD" | grep -oE 'repos/[^/ ]+/[^/ ]+' | head -1)
if [ -z "$REPO_PATH" ]; then
  exit 0
fi

# Fetch body fresh from the API. The tool_response may have been filtered by --jq.
if ! CURRENT_BODY=$(gh api "$REPO_PATH/pulls/comments/$COMMENT_ID" -q '.body' 2>/dev/null); then
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

gh api "$REPO_PATH/pulls/comments/$COMMENT_ID" -X PATCH -f body="$UPDATED_BODY" >/dev/null 2>&1

exit 0
