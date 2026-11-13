#!/usr/bin/env bash
# PostToolUse dispatcher: attributes Claude Ocodius to PR descriptions.
#
# Comments, replies, reviews and inline review comments are deliberately left
# unsigned (signature dropped 2026-11-13).
#
# Replaces the single-purpose pr-attribution.sh. The idempotency guard
# ("Claude Ocodius" marker check) prevents double attribution.
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
else
  log "no match for cmd=${CMD:0:120}"
  exit 0
fi

log "route=$ROUTE cmd=${CMD:0:200}"

# ---- Helpers ---------------------------------------------------------------

extract_pr_url_from_stdout() {
  echo "$RESPONSE" | tr -d '[:space:]' | grep -oE 'https://github\.com/[^/]+/[^/]+/pull/[0-9]+' | head -1
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

# ---- Dispatch --------------------------------------------------------------

case "$ROUTE" in
  pr_create) route_pr_create ;;
  pr_edit_body) route_pr_edit_body ;;
esac

exit 0
