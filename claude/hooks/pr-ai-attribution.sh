#!/usr/bin/env bash
# PostToolUse dispatcher: attributes Claude Ocodius to PR descriptions, reviews,
# review bodies, inline review comments, and top-level PR/issue comments.
#
# Replaces four single-purpose hooks (pr-attribution.sh, pr-comment-attribution.sh,
# pr-issue-comment-attribution.sh, pr-review-attribution.sh). Existing hooks may
# run alongside this during rollout — idempotency guard ("Claude Ocodius" marker
# check) prevents double attribution.
#
# Debug logging: set CLAUDE_ATTRIBUTION_DEBUG=1 to trace routing decisions to
# ~/.claude/hooks/.attribution.log.

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

LOG_FILE="$HOME/.claude/hooks/.attribution.log"

log() {
  [ "${CLAUDE_ATTRIBUTION_DEBUG:-0}" = "1" ] || return 0
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >>"$LOG_FILE"
}

if [ "$TOOL_NAME" != "Bash" ]; then
  log "skip tool=$TOOL_NAME"
  exit 0
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
RESPONSE=$(echo "$INPUT" | jq -r '.tool_response.stdout // empty')

ATTRIB_DESCRIPTION=$'\n\n---\nContributed by Claude Ocodius'
ATTRIB_INLINE=$'\n\n\\- Claude Ocodius'

already_attributed() {
  echo "$1" | grep -q "Claude Ocodius"
}

# ---- Classify ---------------------------------------------------------------

ROUTE=""
if echo "$CMD" | grep -qE '(^|[^[:alnum:]_-])gh pr create( |$)'; then
  ROUTE="pr_create"
elif echo "$CMD" | grep -qE '(^|[^[:alnum:]_-])gh pr edit( |$)' \
  && echo "$CMD" | grep -qE '(^| )--body( |=)'; then
  ROUTE="pr_edit_body"
elif echo "$CMD" | grep -qE '(^|[^[:alnum:]_-])gh pr review( |$)'; then
  # No --body requirement — approve-only reviews still need inline comment attribution.
  ROUTE="pr_review"
elif echo "$CMD" | grep -qE '(^|[^[:alnum:]_-])gh pr comment( |$)'; then
  ROUTE="pr_comment"
elif echo "$CMD" | grep -qE 'gh api[^|;&]*repos/[^/ ]+/[^/ ]+/pulls/[0-9]+/reviews( |$|/)' \
  && echo "$CMD" | grep -qE '(-X ?POST|--method POST|(-f|-F|--field|--raw-field) +body=)'; then
  ROUTE="api_review"
elif echo "$CMD" | grep -qE 'gh api[^|;&]*repos/[^/ ]+/[^/ ]+/pulls/[0-9]+/comments(/[0-9]+/replies)?' \
  && echo "$CMD" | grep -qE '(-X ?POST|--method POST|(-f|-F|--field|--raw-field) +body=)'; then
  ROUTE="api_inline_comment"
elif echo "$CMD" | grep -qE 'gh api[^|;&]*repos/[^/]+/[^/]+/issues/[0-9]+/comments' \
  && echo "$CMD" | grep -qE '(-X ?POST|--method POST|(-f|-F|--field|--raw-field) +body=)'; then
  ROUTE="api_issue_comment"
else
  log "no match for cmd=${CMD:0:120}"
  exit 0
fi

log "route=$ROUTE cmd=${CMD:0:200}"

# ---- Helpers ---------------------------------------------------------------

extract_pr_url_from_stdout() {
  echo "$RESPONSE" | tr -d '[:space:]' | grep -oE 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+' | head -1
}

pr_url_to_repo_path() {
  echo "$1" | sed -E 's|https://github\.com/([^/]+/[^/]+)/.*|repos/\1|'
}

pr_url_to_number() {
  echo "$1" | sed -E 's|.*/pull/([0-9]+).*|\1|'
}

# ---- Per-route logic --------------------------------------------------------

route_pr_create() {
  local PR_URL=$(extract_pr_url_from_stdout)
  if [ -z "$PR_URL" ]; then log "pr_create: no PR URL in stdout"; return; fi
  local BODY=$(gh pr view "$PR_URL" --json body -q '.body' 2>/dev/null)
  if already_attributed "$BODY"; then log "pr_create: already attributed"; return; fi
  gh pr edit "$PR_URL" --body "${BODY}${ATTRIB_DESCRIPTION}" >/dev/null 2>&1
  log "pr_create: attributed $PR_URL"
}

route_pr_edit_body() {
  local PR_URL=$(echo "$CMD" | grep -oE 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+' | head -1)
  if [ -z "$PR_URL" ]; then
    local REPO=$(echo "$CMD" | grep -oE -- '--repo [^ ]+' | awk '{print $2}' | head -1)
    local NUM=$(echo "$CMD" | grep -oE 'gh pr edit +[0-9]+' | awk '{print $NF}' | head -1)
    if [ -n "$REPO" ] && [ -n "$NUM" ]; then
      PR_URL="https://github.com/${REPO}/pull/${NUM}"
    fi
  fi
  if [ -z "$PR_URL" ]; then log "pr_edit_body: no PR URL resolvable"; return; fi
  local BODY=$(gh pr view "$PR_URL" --json body -q '.body' 2>/dev/null)
  if already_attributed "$BODY"; then log "pr_edit_body: already attributed"; return; fi
  gh pr edit "$PR_URL" --body "${BODY}${ATTRIB_DESCRIPTION}" >/dev/null 2>&1
  log "pr_edit_body: attributed $PR_URL"
}

# Attribute review body (if non-empty) + all inline comments belonging to the review.
attribute_review() {
  local REPO_PATH="$1" PR_NUMBER="$2" REVIEW_ID="$3"
  if [ -z "$REPO_PATH" ] || [ -z "$PR_NUMBER" ] || [ -z "$REVIEW_ID" ]; then
    log "attribute_review: missing ids repo=$REPO_PATH pr=$PR_NUMBER review=$REVIEW_ID"
    return
  fi

  local CURRENT_BODY
  CURRENT_BODY=$(gh api "$REPO_PATH/pulls/$PR_NUMBER/reviews/$REVIEW_ID" -q '.body' 2>/dev/null) || {
    log "attribute_review: fetch body failed"; return;
  }

  if [ -n "$CURRENT_BODY" ] && ! already_attributed "$CURRENT_BODY"; then
    gh api "$REPO_PATH/pulls/$PR_NUMBER/reviews/$REVIEW_ID" -X PUT \
      -f body="${CURRENT_BODY}${ATTRIB_INLINE}" >/dev/null 2>&1
    log "attribute_review: body attributed review=$REVIEW_ID"
  fi

  local COMMENT_IDS
  COMMENT_IDS=$(gh api "$REPO_PATH/pulls/$PR_NUMBER/reviews/$REVIEW_ID/comments" --jq '.[].id' 2>/dev/null)
  for cid in $COMMENT_IDS; do
    local CBODY
    CBODY=$(gh api "$REPO_PATH/pulls/comments/$cid" -q '.body' 2>/dev/null)
    if [ -z "$CBODY" ] || already_attributed "$CBODY"; then continue; fi
    gh api "$REPO_PATH/pulls/comments/$cid" -X PATCH \
      -f body="${CBODY}${ATTRIB_INLINE}" >/dev/null 2>&1
    log "attribute_review: inline comment attributed id=$cid"
  done
}

route_pr_review() {
  local PR_URL REPO_PATH PR_NUMBER
  PR_URL=$(echo "$CMD" | grep -oE 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+' | head -1)
  if [ -n "$PR_URL" ]; then
    REPO_PATH=$(pr_url_to_repo_path "$PR_URL")
    PR_NUMBER=$(pr_url_to_number "$PR_URL")
  else
    local REPO_FLAG NUM
    REPO_FLAG=$(echo "$CMD" | grep -oE -- '--repo [^ ]+' | awk '{print $2}' | head -1)
    NUM=$(echo "$CMD" | grep -oE 'gh pr review +[0-9]+' | awk '{print $NF}' | head -1)
    if [ -n "$REPO_FLAG" ] && [ -n "$NUM" ]; then
      REPO_PATH="repos/$REPO_FLAG"
      PR_NUMBER="$NUM"
    fi
  fi
  if [ -z "$REPO_PATH" ] || [ -z "$PR_NUMBER" ]; then
    log "pr_review: could not resolve repo/pr from cmd"
    return
  fi
  local REVIEW_ID
  REVIEW_ID=$(gh api "$REPO_PATH/pulls/$PR_NUMBER/reviews" --jq 'sort_by(.submitted_at) | last | .id' 2>/dev/null)
  if [ -z "$REVIEW_ID" ] || [ "$REVIEW_ID" = "null" ]; then
    log "pr_review: no review ID"; return
  fi
  attribute_review "$REPO_PATH" "$PR_NUMBER" "$REVIEW_ID"
}

route_api_review() {
  local REVIEW_ID REPO_PATH PR_NUMBER
  REVIEW_ID=$(echo "$RESPONSE" | jq -r '.id // empty' 2>/dev/null)
  if [ -z "$REVIEW_ID" ] || [ "$REVIEW_ID" = "null" ]; then
    log "api_review: no review id in response"; return
  fi
  REPO_PATH=$(echo "$CMD" | grep -oE 'repos/[^/ ]+/[^/ ]+' | head -1)
  PR_NUMBER=$(echo "$CMD" | grep -oE 'pulls/[0-9]+' | head -1 | sed 's|pulls/||')
  attribute_review "$REPO_PATH" "$PR_NUMBER" "$REVIEW_ID"
}

route_api_inline_comment() {
  local COMMENT_ID REPO_PATH
  COMMENT_ID=$(echo "$RESPONSE" | jq -r '.id // empty' 2>/dev/null)
  if [ -z "$COMMENT_ID" ] || [ "$COMMENT_ID" = "null" ]; then
    log "api_inline_comment: no id"; return
  fi
  REPO_PATH=$(echo "$CMD" | grep -oE 'repos/[^/ ]+/[^/ ]+' | head -1)
  if [ -z "$REPO_PATH" ]; then log "api_inline_comment: no repo path"; return; fi
  local CURRENT_BODY
  CURRENT_BODY=$(gh api "$REPO_PATH/pulls/comments/$COMMENT_ID" -q '.body' 2>/dev/null) || return
  if [ -z "$CURRENT_BODY" ] || already_attributed "$CURRENT_BODY"; then return; fi
  gh api "$REPO_PATH/pulls/comments/$COMMENT_ID" -X PATCH \
    -f body="${CURRENT_BODY}${ATTRIB_INLINE}" >/dev/null 2>&1
  log "api_inline_comment: attributed id=$COMMENT_ID"
}

route_pr_comment() {
  local URL COMMENT_ID OWNER_REPO REPO_PATH
  URL=$(echo "$RESPONSE" | tr -d '[:space:]' | grep -oE 'https://github\.com/[^/]+/[^/]+/(pull|issues)/[0-9]+#issuecomment-[0-9]+' | head -1)
  if [ -z "$URL" ]; then log "pr_comment: no URL in stdout"; return; fi
  COMMENT_ID=$(echo "$URL" | grep -oE 'issuecomment-[0-9]+' | sed 's/issuecomment-//')
  OWNER_REPO=$(echo "$URL" | sed -E 's|https://github\.com/([^/]+/[^/]+)/.*|\1|')
  REPO_PATH="repos/$OWNER_REPO"
  patch_issue_comment "$REPO_PATH" "$COMMENT_ID"
}

route_api_issue_comment() {
  local COMMENT_ID HTML_URL REPO_PATH
  COMMENT_ID=$(echo "$RESPONSE" | jq -r '.id // empty' 2>/dev/null)
  HTML_URL=$(echo "$RESPONSE" | jq -r '.html_url // empty' 2>/dev/null)
  if [ -z "$COMMENT_ID" ] || [ "$COMMENT_ID" = "null" ]; then log "api_issue_comment: no id"; return; fi
  if ! echo "$HTML_URL" | grep -q 'issuecomment-'; then log "api_issue_comment: not an issue comment"; return; fi
  REPO_PATH=$(echo "$CMD" | grep -oE 'repos/[^/ ]+/[^/ ]+' | head -1)
  if [ -z "$REPO_PATH" ]; then return; fi
  patch_issue_comment "$REPO_PATH" "$COMMENT_ID"
}

patch_issue_comment() {
  local REPO_PATH="$1" COMMENT_ID="$2"
  local CURRENT_BODY
  CURRENT_BODY=$(gh api "$REPO_PATH/issues/comments/$COMMENT_ID" -q '.body' 2>/dev/null) || return
  if [ -z "$CURRENT_BODY" ] || already_attributed "$CURRENT_BODY"; then return; fi
  gh api "$REPO_PATH/issues/comments/$COMMENT_ID" -X PATCH \
    -f body="${CURRENT_BODY}${ATTRIB_INLINE}" >/dev/null 2>&1
  log "issue_comment: attributed id=$COMMENT_ID"
}

# ---- Dispatch --------------------------------------------------------------

case "$ROUTE" in
  pr_create) route_pr_create ;;
  pr_edit_body) route_pr_edit_body ;;
  pr_review) route_pr_review ;;
  pr_comment) route_pr_comment ;;
  api_review) route_api_review ;;
  api_inline_comment) route_api_inline_comment ;;
  api_issue_comment) route_api_issue_comment ;;
esac

exit 0
