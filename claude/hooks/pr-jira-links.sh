#!/usr/bin/env bash
# PostToolUse hook: prepends a Tickets section with Jira links to any PR created via gh pr create.
# Extracts ticket numbers from the branch name, PR title, and PR body.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if ! echo "$CMD" | grep -qE 'gh pr create'; then
  exit 0
fi

PR_URL=$(echo "$INPUT" | jq -r '.tool_response.stdout // empty' | tr -d '[:space:]')

if ! echo "$PR_URL" | grep -qE 'https://github\.com/.+/pull/[0-9]+'; then
  exit 0
fi

BRANCH=$(gh pr view "$PR_URL" --json headRefName -q '.headRefName' 2>/dev/null)
TITLE=$(gh pr view "$PR_URL" --json title -q '.title' 2>/dev/null)
CURRENT_BODY=$(gh pr view "$PR_URL" --json body -q '.body' 2>/dev/null)

# Skip if already has Jira links
if echo "$CURRENT_BODY" | grep -q "atlassian.net/browse/"; then
  exit 0
fi

# Extract ticket numbers from branch, title, and body — covers combined branches like COREAPP1-3296-3298
TICKETS=$(echo "$BRANCH $TITLE $CURRENT_BODY" | grep -oE '[A-Z][A-Z0-9]+-[0-9]+' | sort -u)

if [ -z "$TICKETS" ]; then
  exit 0
fi

TICKET_SECTION="## Tickets"$'\n'
while IFS= read -r ticket; do
  TICKET_SECTION+="- [$ticket](https://legalshield.atlassian.net/browse/$ticket)"$'\n'
done <<< "$TICKETS"

gh pr edit "$PR_URL" --body "${TICKET_SECTION}"$'\n'"${CURRENT_BODY}" >/dev/null 2>&1

exit 0
