#!/usr/bin/env bash
# PreToolUse hook: lints PR-text gh api calls for sycophantic style and em dashes.
#
# Scope: any `gh api` Bash call that writes a body to /pulls/* or /issues/* endpoints
# (inline review comments, review-comment replies, review-comment edits via PATCH,
# issue/PR conversation comments, top-level review summaries).
#
# Stdout MUST be clean JSON per the hook protocol. All subprocess noise is routed
# to /dev/null, and the only stdout write is the final block-decision JSON.
#
# Pattern set is shape-based, not a closed list. Drop a new pattern in the array
# below to extend.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Scope check: gh api → repos/<o>/<r>/(pulls|issues)/...
if ! echo "$CMD" | grep -qE 'gh api[^|;&]*repos/[^/ ]+/[^/ ]+/(pulls|issues)/' 2>/dev/null; then
	exit 0
fi

# Body field must be present (-f / -F / --field / --raw-field body=...).
if ! echo "$CMD" | grep -qE '(-f|-F|--field|--raw-field)[[:space:]]+body=' 2>/dev/null; then
	exit 0
fi

# Extract everything after the first `body=` to end of command. Patterns below are
# specific enough that trailing shell tokens don't cause false positives.
BODY=$(echo "$CMD" | sed -nE 's/.*(-f|-F|--field|--raw-field)[[:space:]]+body=(.*)$/\2/p')

# Strip a single layer of surrounding quotes if present.
case "$BODY" in
	'"'*'"') BODY="${BODY%\"}"; BODY="${BODY#\"}" ;;
	"'"*"'") BODY="${BODY%\'}"; BODY="${BODY#\'}" ;;
esac

# Style patterns — case-insensitive ERE. Shape-based, not exhaustive.
declare -a PATTERNS=(
	# Sycophantic adjective + validation noun
	'(good|nice|great|excellent|brilliant|fantastic|sharp|smart)[[:space:]]+(catch|point|question|find|observation|spot|call|idea|suggestion|feedback|eye)'
	# Hedging acknowledgments
	'fair[[:space:]]+(point|concern|question|enough|forward-looking)'
	# AI-agreement openers
	"(you're|that's|youre|thats)[[:space:]]+(absolutely|exactly|completely|totally|spot-on|spot on)[[:space:]]+(right|correct)"
	'absolutely[[:space:]]+(correct|right)'
	'exactly[[:space:]]+(right|correct)'
	# Gratitude / enthusiasm
	'thanks[[:space:]]+for[[:space:]]+(flagging|pointing|catching|noticing|raising|highlighting)'
	'(love|appreciate)[[:space:]]+(this|the|your)'
	# Leading-position validators (start of body only)
	'^[[:space:]]*(agreed|absolutely|definitely|certainly|sure|yep)[[:space:],.!]'
	'^[[:space:]]*makes[[:space:]]+sense'
	# Em dash and double-hyphen surrogate
	'—'
	'[[:space:]]--[[:space:]]'
)

for PATTERN in "${PATTERNS[@]}"; do
	MATCH=$(echo "$BODY" | grep -oiE "$PATTERN" 2>/dev/null | head -1)
	if [ -n "$MATCH" ]; then
		REASON="PR-text style violation: matched \"$MATCH\". Drop the pleasantry/em dash; state the assessment and what was done. See ~/.claude/hooks/pr-text-style.sh for the rule set."
		REASON_JSON=$(printf '%s' "$REASON" | jq -Rs . 2>/dev/null)
		printf '{"decision":"block","reason":%s}' "$REASON_JSON"
		exit 0
	fi
done

exit 0
