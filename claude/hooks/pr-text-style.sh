#!/usr/bin/env bash
# PreToolUse hook: lints PR-text gh calls for sycophantic style and em dashes.
#
# Scope: any Bash call that invokes `gh api`, `gh pr`, or `gh issue` AND carries a
# body-writing flag (`-f/-F/--field/--raw-field body=`, `--body`, `--body-file`, `-b`).
# Scope deliberately does NOT key on the endpoint path: URLs factored into shell
# variables (`gh api $REPO/...`) previously bypassed the old `repos/.../pulls/`
# regex. The lint runs over the whole command text, so bodies hiding in variable
# assignments within the same command are still scanned; the extracted body= value
# is additionally checked so the start-of-body anchored patterns keep working.
#
# Stdout MUST be clean JSON per the hook protocol. All subprocess noise is routed
# to /dev/null, and the only stdout write is the final block-decision JSON.
#
# Pattern set is shape-based, not a closed list. Drop a new pattern in the array
# below to extend.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Scope check 1: a gh invocation that can write PR/issue text.
if ! echo "$CMD" | grep -qE 'gh[[:space:]]+(api|pr|issue)[[:space:]]' 2>/dev/null; then
	exit 0
fi

# Scope check 2: a body-writing flag is present.
if ! echo "$CMD" | grep -qE '((-f|-F|--field|--raw-field)[[:space:]]+body=|--body(-file)?([[:space:]]|=)|[[:space:]]-b[[:space:]])' 2>/dev/null; then
	exit 0
fi

# Extract the body value when it is inline (everything after the first body flag).
# Empty when the body itself hides behind a variable or file; the whole-command
# scan below still covers the variable case.
BODY=$(echo "$CMD" | sed -nE 's/.*(-f|-F|--field|--raw-field)[[:space:]]+body=(.*)$/\2/p')
if [ -z "$BODY" ]; then
	BODY=$(echo "$CMD" | sed -nE 's/.*--body[[:space:]]+(.*)$/\1/p')
fi

# Strip a single layer of surrounding quotes if present.
case "$BODY" in
	'"'*'"') BODY="${BODY%\"}"; BODY="${BODY#\"}" ;;
	"'"*"'") BODY="${BODY%\'}"; BODY="${BODY#\'}" ;;
esac

# Style patterns — case-insensitive ERE. Shape-based, not exhaustive.
declare -a PATTERNS=(
	# Sycophantic adjective + validation noun
	'(good|nice|great|excellent|brilliant|fantastic|sharp|smart|right)[[:space:]]+(catch|point|question|find|observation|spot|call|idea|suggestion|feedback|eye)'
	# Hedging acknowledgments
	'fair[[:space:]]+(point|concern|question|enough|forward-looking)'
	# AI-agreement openers
	"(you're|that's|youre|thats)[[:space:]]+(absolutely|exactly|completely|totally|spot-on|spot on)[[:space:]]+(right|correct)"
	'absolutely[[:space:]]+(correct|right)'
	'exactly[[:space:]]+(right|correct)'
	# Gratitude / enthusiasm
	'thanks[[:space:]]+for[[:space:]]+(flagging|pointing|catching|noticing|raising|highlighting)'
	'(love|appreciate)[[:space:]]+(this|the|your)'
	# Em dash
	'—'
)

# Start-of-body validators and the double-hyphen em-dash surrogate only run
# against the extracted body: against the full command text, `^` would anchor to
# every line of a multi-line command, and gh's own ` -- ` argument separators
# would false-positive.
declare -a BODY_ONLY_PATTERNS=(
	'^[[:space:]]*(agreed|absolutely|definitely|certainly|sure|yep)[[:space:],.!]'
	'^[[:space:]]*makes[[:space:]]+sense'
	'[[:space:]]--[[:space:]]'
)

block() {
	REASON="PR-text style violation: matched \"$1\". Drop the pleasantry/em dash; state the assessment and what was done. See ~/.claude/hooks/pr-text-style.sh for the rule set."
	REASON_JSON=$(printf '%s' "$REASON" | jq -Rs . 2>/dev/null)
	printf '{"decision":"block","reason":%s}' "$REASON_JSON"
	exit 0
}

for PATTERN in "${PATTERNS[@]}"; do
	MATCH=$(echo "$CMD" | grep -oiE "$PATTERN" 2>/dev/null | head -1)
	[ -n "$MATCH" ] && block "$MATCH"
done

if [ -n "$BODY" ]; then
	for PATTERN in "${BODY_ONLY_PATTERNS[@]}"; do
		MATCH=$(echo "$BODY" | grep -oiE "$PATTERN" 2>/dev/null | head -1)
		[ -n "$MATCH" ] && block "$MATCH"
	done
fi

exit 0
