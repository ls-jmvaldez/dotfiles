#!/usr/bin/env bash
# PreToolUse hook: enforces voice/style rules on text-writing commands.
#
# Covered surfaces (all guarded by a body-writing scope check):
#   - gh api, gh pr, gh issue (with body flags)
#   - git commit -m / --message
#   - curl writes to legalshield.atlassian.net/rest/api/* (Jira)
#   - curl writes to legalshield.atlassian.net/wiki (Confluence)
#
# Design notes (also reproduced in voice-patterns.sh):
#
#   1. Scope gate keys on body-writing flags rather than endpoint path, because
#      `gh api $REPO/...` bypasses an endpoint-path regex. The whole command text
#      is scanned, so bodies embedded in variable assignments are still caught.
#
#   2. Start-anchored patterns run against the EXTRACTED BODY only, not the full
#      command text. `^` in ERE matches the start of every line in a multi-line
#      string, so running them against the full command causes false-positives.
#      gh's own double-hyphen argument separators also trip the surrogate pattern
#      when scanned over the whole command.
#
# Pattern library is sourced from the ls-jmvaldez-voice plugin, resolved at
# runtime from the installed-plugins manifest so a version bump in the cache
# does not break the hook. If the plugin is not installed, the hook FAILS OPEN:
# one warning to stderr, exit 0, command allowed through.
#
# Stdout MUST be clean JSON per the hook protocol. All subprocess noise is routed
# to /dev/null, and the only stdout write is the final block-decision JSON.

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# ── Library resolution ──────────────────────────────────────────────────────
# Find the voice plugin's installPath from the manifest. The manifest key is
# "ls-jmvaldez-voice@legalshield-marketplace". We take the first entry (index 0)
# because that is how the installed-plugins.json format works for user-scoped
# installs, and version-pinned cache paths like "0.2.7/" change on every update.

MANIFEST="$HOME/.claude/plugins/installed_plugins.json"
LIB_PATH=""

if [ -f "$MANIFEST" ]; then
    INSTALL_PATH=$(jq -r \
        '.plugins["ls-jmvaldez-voice@legalshield-marketplace"][0].installPath // empty' \
        "$MANIFEST" 2>/dev/null)
    if [ -n "$INSTALL_PATH" ]; then
        CANDIDATE="$INSTALL_PATH/hooks/lib/voice-patterns.sh"
        [ -f "$CANDIDATE" ] && LIB_PATH="$CANDIDATE"
    fi
fi

if [ -n "$LIB_PATH" ]; then
    # shellcheck source=/dev/null
    source "$LIB_PATH"
else
    printf '%s\n' \
        "pr-text-style: ls-jmvaldez-voice plugin not installed or library missing; style check skipped" \
        >&2
    exit 0
fi

# ── Helpers ─────────────────────────────────────────────────────────────────

block() {
    local match="$1"
    local reason
    reason="PR-text style violation: matched \"$match\". Drop the pleasantry/em dash; state the assessment and what was done. Rules live in the internal-tools writer guide, knowledge/writer/forbidden-patterns.md. To quote a banned phrase on purpose, wrap it in backticks."
    local reason_json
    reason_json=$(printf '%s' "$reason" | jq -Rs . 2>/dev/null)
    printf '{"decision":"block","reason":%s}' "$reason_json"
    exit 0
}

# Scan the full command text against PATTERNS (not BODY_ONLY_PATTERNS).
# BODY_ONLY_PATTERNS are excluded here because start-anchored patterns and the
# double-hyphen surrogate both produce false-positives against a full shell command.
scan_cmd() {
    local clean
    clean=$(voice_strip_quoted "$CMD")
    local match pattern
    for pattern in "${PATTERNS[@]}"; do
        match=$(printf '%s' "$clean" | grep -oiE "$pattern" 2>/dev/null | head -1)
        [ -n "$match" ] && block "$match"
    done
}

# Scan an extracted body or commit message through voice_scan(), which handles
# backtick and fence stripping internally before applying all pattern arrays.
scan_body() {
    local body="$1"
    local match
    match=$(voice_scan "$body")
    [ -n "$match" ] && block "$match"
}

# Take the flag value from the head of a string, stopping at the closing quote
# rather than running to end of line. A greedy match swallows whatever follows
# the value, so `--body "text" -- extra` would pull gh's own argument separator
# into the body and trip the double-hyphen pattern: the exact false positive
# the header warns about.
extract_value() {
    local rest="$1"
    case "$rest" in
        '"'*) rest="${rest#\"}"; printf '%s' "${rest%%\"*}" ;;
        "'"*) rest="${rest#\'}"; printf '%s' "${rest%%\'*}" ;;
        *)    printf '%s' "${rest%% *}" ;;
    esac
}

# ── Surface 1: gh PR / issue / api body writes ───────────────────────────────
# Gating on flag presence rather than endpoint path: `gh api $VAR` bypasses a
# URL regex because the variable is expanded only at execution time.

if printf '%s' "$CMD" | grep -qE 'gh[[:space:]]+(api|pr|issue)[[:space:]]' 2>/dev/null && \
   printf '%s' "$CMD" | grep -qE \
       '((-f|-F|--field|--raw-field)[[:space:]]+body=|--body(-file)?([[:space:]]|=)|[[:space:]]-b[[:space:]])' \
       2>/dev/null; then

    # Extract the inline body value where possible. When the body is behind a
    # variable or file, the whole-command scan below still catches violations
    # that made it into a variable assignment within the same command string.
    REST=$(printf '%s' "$CMD" | \
        sed -nE 's/.*(-f|-F|--field|--raw-field)[[:space:]]+body=(.*)$/\2/p')
    if [ -z "$REST" ]; then
        REST=$(printf '%s' "$CMD" | sed -nE 's/.*--body[[:space:]]+(.*)$/\1/p')
    fi
    BODY=$(extract_value "$REST")

    scan_cmd
    [ -n "$BODY" ] && scan_body "$BODY"
    exit 0
fi

# ── Surface 2: git commit message writes ─────────────────────────────────────
# Covers -m and --message in both "flag VALUE" and "--flag=VALUE" forms.
# Combined short flags like -am are also covered by the [a-zA-Z]*m pattern.
#
# The -F / --file form is deliberately skipped: the message lives in a file,
# not in the command string, and reading the file would require a subprocess
# that introduces timing and permissions complexity for unclear gain. Heredoc
# forms passed through a shell pipe are similarly out of reach at this hook
# boundary. Document the gap rather than produce false negatives silently.

if printf '%s' "$CMD" | grep -qE 'git[[:space:]]+commit\b' 2>/dev/null && \
   printf '%s' "$CMD" | grep -qE \
       '([[:space:]]-[a-zA-Z]*m[[:space:]]|[[:space:]]--message([[:space:]]|=))' \
       2>/dev/null; then

    # Try --message=VALUE first, then --message VALUE, then -m / -am / etc.
    MSG_REST=$(printf '%s' "$CMD" | \
        sed -nE 's/.*--message=([^[:space:]].*)$/\1/p' | head -1)
    if [ -z "$MSG_REST" ]; then
        MSG_REST=$(printf '%s' "$CMD" | \
            sed -nE 's/.*--message[[:space:]]+(.+)$/\1/p' | head -1)
    fi
    if [ -z "$MSG_REST" ]; then
        MSG_REST=$(printf '%s' "$CMD" | \
            sed -nE 's/.*-[a-zA-Z]*m[[:space:]]+(.+)$/\1/p' | head -1)
    fi
    # Stop at the closing quote so a chained `&& git push` or a trailing
    # separator cannot be scanned as part of the message.
    MSG=$(extract_value "$MSG_REST")

    if [ -n "$MSG" ]; then
        scan_body "$MSG"
    else
        # Message not extractable (heredoc or complex quoting); fall back to
        # scanning the whole command against PATTERNS only.
        scan_cmd
    fi
    exit 0
fi

# ── Surface 3: Jira writes via curl ─────────────────────────────────────────
# The skill hits legalshield.atlassian.net/rest/api/3 (and /rest/agile for
# sprints). We gate on the host+path pair and any curl data flag, then scan
# the full command text. JSON extraction from an arbitrary curl invocation is
# unreliable, so BODY_ONLY_PATTERNS (which are start-anchored) are not applied.

if printf '%s' "$CMD" | grep -qE 'legalshield\.atlassian\.net/rest' 2>/dev/null && \
   printf '%s' "$CMD" | grep -qE \
       '(-d|--data(-raw|-binary)?)[[:space:]]' 2>/dev/null; then
    scan_cmd
    exit 0
fi

# ── Surface 4: Confluence page body writes via curl ──────────────────────────
# Same rationale as Surface 3.

if printf '%s' "$CMD" | grep -qE 'legalshield\.atlassian\.net/wiki' 2>/dev/null && \
   printf '%s' "$CMD" | grep -qE \
       '(-d|--data(-raw|-binary)?)[[:space:]]' 2>/dev/null; then
    scan_cmd
    exit 0
fi

exit 0
