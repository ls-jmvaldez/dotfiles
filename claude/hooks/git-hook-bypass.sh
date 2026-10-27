#!/usr/bin/env bash
# PreToolUse hook: blocks git hook-bypass flags and env vars.
#
# Denied:
#   - git commit --no-verify / git push --no-verify / git merge --no-verify
#   - git commit -n (standalone) and combined short flags like -an, -nm
#   - git -c core.hooksPath=<val>
#   - HUSKY=0 (as a standalone env-var assignment)
#   - SKIP_VALIDATE= (any value)
#
# Allowed:
#   - grep -- --no-verify file  (no git subcommand)
#   - echo --no-verify          (no git subcommand)
#   - git log -n 5              (not commit/push/merge)
#   - git commit -am "msg"      (no -n short flag, no --no-verify)
#
# Stdout MUST be clean JSON. All diagnostic noise goes to stderr.

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$TOOL_NAME" = "Bash" ] || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0

deny() {
    local reason_json
    reason_json=$(printf '%s' "$1" | jq -Rs . 2>/dev/null)
    printf '{"decision":"block","reason":%s}' "$reason_json"
    exit 0
}

DENY_MSG="Hook bypass blocked: this command skips git hooks. Git hook bypasses need Joe to run the command himself. Automated sessions may not skip them."

# Detect 'git <subcmd>' in CMD, handling:
#   - env-var prefixes:  VAR=val git commit
#   - flag-only options: git -c foo=bar commit
#   - -C path form:      git -C /some/path commit  (separate branch below)
#   - chained commands:  ; && ||
_git_flags='([[:space:]]+-[^[:space:]]+)*'
_env_prefix='([A-Z_][A-Z_0-9]*=[^[:space:]]+[[:space:]]+)*'
_chain='(^|;[[:space:]]*|&&[[:space:]]*|\|\|[[:space:]]*)'

has_git_subcmd() {
    local sub="$1"
    # Standard: (env) git [short/long flags] <sub>
    printf '%s' "$CMD" | grep -qE \
        "${_chain}${_env_prefix}git${_git_flags}[[:space:]]+${sub}\b" || \
    # -C path form: (env) git -C <path> [flags] <sub>
    printf '%s' "$CMD" | grep -qE \
        "${_chain}${_env_prefix}git[[:space:]]+-C[[:space:]]+[^[:space:]]+${_git_flags}[[:space:]]+${sub}\b"
}

# 1. --no-verify on commit, push, or merge
if printf '%s' "$CMD" | grep -qE -- '--no-verify'; then
    if has_git_subcmd "commit" || has_git_subcmd "push" || has_git_subcmd "merge"; then
        deny "$DENY_MSG"
    fi
fi

# 2. git commit -n (short flag, incl. combined: -an, -nm, etc.)
#    Pattern: -[letters]n[letters]: won't match --no-verify because that starts with --.
if has_git_subcmd "commit"; then
    if printf '%s' "$CMD" | grep -qE -- '[[:space:]]-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)'; then
        deny "$DENY_MSG"
    fi
fi

# 3. git -c core.hooksPath= (redirects hook execution to a different directory)
if printf '%s' "$CMD" | grep -qE \
    "${_chain}${_env_prefix}git[[:space:]]+-c[[:space:]]+core\.hooksPath="; then
    deny "$DENY_MSG"
fi

# 4. HUSKY=0 as a standalone env assignment (not inside a string literal)
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]])HUSKY=0([[:space:]]|$)'; then
    deny "$DENY_MSG"
fi

# 5. SKIP_VALIDATE= (any value)
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]])SKIP_VALIDATE='; then
    deny "$DENY_MSG"
fi

exit 0
