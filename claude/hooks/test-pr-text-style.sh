#!/usr/bin/env bash
# Tests for claude/hooks/pr-text-style.sh.
#
# No external deps beyond bash and jq. Sandboxed HOME per test so the manifest
# lookup is fully controlled. Run from any directory:
#   bash claude/hooks/test-pr-text-style.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/pr-text-style.sh"

# Resolve the library path so tests exercise real patterns, not stubs.
# Resolution order:
#   1. VOICE_PATTERNS_LIB env var, for running against an unpublished checkout
#   2. Live installed-plugins manifest, the path once the plugin is installed
# No third fallback on purpose: a hardcoded checkout path would be machine
# specific and would rot the moment that directory moved. If neither source
# resolves, the pattern tests skip loudly instead of silently passing.

MANIFEST="$HOME/.claude/plugins/installed_plugins.json"
LIB_PATH=""

if [ -n "${VOICE_PATTERNS_LIB:-}" ] && [ -f "${VOICE_PATTERNS_LIB:-}" ]; then
    LIB_PATH="$VOICE_PATTERNS_LIB"
elif [ -f "$MANIFEST" ]; then
    INSTALL_PATH=$(jq -r \
        '.plugins["ls-jmvaldez-voice@legalshield-marketplace"][0].installPath // empty' \
        "$MANIFEST" 2>/dev/null)
    if [ -n "$INSTALL_PATH" ]; then
        CANDIDATE="$INSTALL_PATH/hooks/lib/voice-patterns.sh"
        [ -f "$CANDIDATE" ] && LIB_PATH="$CANDIDATE"
    fi
fi

PASS=0
FAIL=0
ERRORS=()

pass() { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); ERRORS+=("$1: $2"); printf '  FAIL: %s: %s\n' "$1" "$2"; }

# make_sandbox: create a temp dir with a home subdir and print the path.
make_sandbox() {
    local d
    d=$(mktemp -d)
    mkdir -p "$d/home/.claude/plugins"
    printf '%s' "$d"
}

# inject_lib: write a fake installed_plugins.json that points at the real library.
# Usage: inject_lib <sandbox> <lib_path>
inject_lib() {
    local sandbox="$1"
    local lib="$2"
    local plugin_root
    # The manifest points installPath at the plugin root; the hook appends
    # hooks/lib/voice-patterns.sh from there.
    plugin_root="$(dirname "$(dirname "$(dirname "$lib")")")"
    cat >"$sandbox/home/.claude/plugins/installed_plugins.json" <<EOF
{
  "version": 2,
  "plugins": {
    "ls-jmvaldez-voice@legalshield-marketplace": [
      { "scope": "user", "installPath": "$plugin_root", "version": "0.0.0-test" }
    ]
  }
}
EOF
}

# run_hook: pipe a fixture JSON to the hook with a sandboxed HOME.
# HOME must be set on the `bash` invocation, not on `printf`, so the hook
# sees the sandboxed manifest. Setting it on `printf | bash` only exports it
# to the first command in the pipeline.
# Sets: RH_STDOUT RH_STDERR RH_EXIT
run_hook() {
    local fixture="$1"
    local sandbox
    sandbox=$(make_sandbox)
    if [ -n "$LIB_PATH" ]; then
        inject_lib "$sandbox" "$LIB_PATH"
    fi
    local stderr_file="$sandbox/stderr"
    RH_STDOUT=$(printf '%s' "$fixture" | HOME="$sandbox/home" bash "$HOOK" 2>"$stderr_file")
    RH_EXIT=$?
    RH_STDERR=$(cat "$stderr_file")
    rm -rf "$sandbox"
}

# run_hook_no_plugin: same but with an empty manifest (no plugin installed).
run_hook_no_plugin() {
    local fixture="$1"
    local sandbox
    sandbox=$(make_sandbox)
    echo '{"version":2,"plugins":{}}' >"$sandbox/home/.claude/plugins/installed_plugins.json"
    local stderr_file="$sandbox/stderr"
    RH_STDOUT=$(printf '%s' "$fixture" | HOME="$sandbox/home" bash "$HOOK" 2>"$stderr_file")
    RH_EXIT=$?
    RH_STDERR=$(cat "$stderr_file")
    rm -rf "$sandbox"
}

# gh_fixture: build a PreToolUse Bash fixture for a gh command.
gh_fixture() {
    local cmd="$1"
    printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
        "$(printf '%s' "$cmd" | jq -Rs .)"
}

# ────────────────────────────────────────────────────────────────────────────
# Group: fail-open when plugin is not installed
# ────────────────────────────────────────────────────────────────────────────
echo "=== fail-open (plugin missing) ==="

FIXTURE=$(gh_fixture "gh pr create --title 'Foo' --body 'great question from the team'")
run_hook_no_plugin "$FIXTURE"
if [ "$RH_EXIT" -ne 0 ]; then
    fail "no-plugin exit code" "expected 0, got $RH_EXIT"
elif [ -n "$RH_STDOUT" ]; then
    fail "no-plugin stdout" "expected empty stdout, got: $RH_STDOUT"
elif printf '%s' "$RH_STDERR" | grep -qi "style check skipped"; then
    pass "no-plugin: exits 0 with warning and allows command through"
else
    fail "no-plugin stderr" "expected warning message, got: $RH_STDERR"
fi

# ────────────────────────────────────────────────────────────────────────────
# Remaining tests require the real library.
# ────────────────────────────────────────────────────────────────────────────
if [ -z "$LIB_PATH" ]; then
    printf '\nSKIP: ls-jmvaldez-voice plugin not installed; cannot run pattern tests.\n'
    printf 'Set VOICE_PATTERNS_LIB to a voice-patterns.sh path to run them.\n'
    printf '\nResult: %d passed, %d failed (plugin tests skipped)\n' "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ] && exit 0 || exit 1
fi

# ────────────────────────────────────────────────────────────────────────────
# Group: gh PR body writes - blocking cases
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== gh body writes: blocking ==="

# Sycophantic opener in body
FIXTURE=$(gh_fixture "gh pr create --title 'Fix thing' --body 'Great catch on the edge case'")
run_hook "$FIXTURE"
if printf '%s' "$RH_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    pass "gh: sycophantic body blocks"
else
    fail "gh: sycophantic body" "expected block, got: $RH_STDOUT"
fi

# Em dash in body
FIXTURE=$(gh_fixture "gh pr create --title 'Fix' --body 'Here is the fix — it should work'")
run_hook "$FIXTURE"
if printf '%s' "$RH_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    pass "gh: em dash in body blocks"
else
    fail "gh: em dash" "expected block, got: $RH_STDOUT"
fi

# ────────────────────────────────────────────────────────────────────────────
# Group: gh PR body writes - passing cases
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== gh body writes: passing ==="

# Clean gh PR body passes
FIXTURE=$(gh_fixture "gh pr create --title 'Fix null check' --body 'Prevents NPE when user has no profile.'")
run_hook "$FIXTURE"
if [ -z "$RH_STDOUT" ] || printf '%s' "$RH_STDOUT" | jq -e '.decision != "block"' >/dev/null 2>&1; then
    pass "gh: clean body passes"
else
    fail "gh: clean body" "expected pass, got: $RH_STDOUT"
fi

# Regression: value extraction must stop at the closing quote. A greedy match to
# end of line pulled gh's own argument separator into the body and blocked a
# legitimate command; same for a chained shell operator after a commit message.
SEP=" $(printf '\x2d\x2d') "
FIXTURE=$(gh_fixture "gh pr create --body 'Prevents NPE when profile is absent.'${SEP}extra")
run_hook "$FIXTURE"
if [ -z "$RH_STDOUT" ] || printf '%s' "$RH_STDOUT" | jq -e '.decision != "block"' >/dev/null 2>&1; then
    pass "gh: argument separator after clean body passes"
else
    fail "gh: argument separator after clean body" "expected pass, got: $RH_STDOUT"
fi

FIXTURE=$(gh_fixture "git commit -m 'fix null deref in parser' && echo done${SEP}now")
run_hook "$FIXTURE"
if [ -z "$RH_STDOUT" ] || printf '%s' "$RH_STDOUT" | jq -e '.decision != "block"' >/dev/null 2>&1; then
    pass "commit: chained command after message passes"
else
    fail "commit: chained command after message" "expected pass, got: $RH_STDOUT"
fi

# Read-only gh command (no body flag) passes
FIXTURE=$(gh_fixture "gh pr list --state open")
run_hook "$FIXTURE"
if [ -z "$RH_STDOUT" ]; then
    pass "gh: read-only command passes"
else
    fail "gh: read-only" "expected empty stdout, got: $RH_STDOUT"
fi

# ────────────────────────────────────────────────────────────────────────────
# Group: git commit - blocking cases
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== git commit: blocking ==="

# Bare banned phrase in commit message
FIXTURE=$(gh_fixture "git commit -m 'great point from the review'")
run_hook "$FIXTURE"
if printf '%s' "$RH_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    pass "git commit -m: bare banned phrase blocks"
else
    fail "git commit -m: bare banned phrase" "expected block, got: $RH_STDOUT"
fi

# --message= form
FIXTURE=$(gh_fixture "git commit --message='excellent catch on the auth flow'")
run_hook "$FIXTURE"
if printf '%s' "$RH_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    pass "git commit --message=: banned phrase blocks"
else
    fail "git commit --message=: banned phrase" "expected block, got: $RH_STDOUT"
fi

# Em dash in commit message
FIXTURE=$(gh_fixture "git commit -m 'Fix token refresh — see ticket for context'")
run_hook "$FIXTURE"
if printf '%s' "$RH_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    pass "git commit -m: em dash blocks"
else
    fail "git commit -m: em dash" "expected block, got: $RH_STDOUT"
fi

# ────────────────────────────────────────────────────────────────────────────
# Group: git commit - backtick carve-out (backticked banned phrase must PASS)
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== git commit: backtick carve-out ==="

# Banned phrase in backticks must not block
FIXTURE=$(gh_fixture "git commit -m 'avoid using \`great point\` openers in PR bodies'")
run_hook "$FIXTURE"
if [ -z "$RH_STDOUT" ] || printf '%s' "$RH_STDOUT" | jq -e '.decision != "block"' >/dev/null 2>&1; then
    pass "git commit -m: backtick-quoted banned phrase passes"
else
    fail "git commit -m: backtick carve-out" "expected pass, got: $RH_STDOUT"
fi

# Same phrase bare (no backticks) must block - confirms carve-out is specific
FIXTURE=$(gh_fixture "git commit -m 'great point raised in review'")
run_hook "$FIXTURE"
if printf '%s' "$RH_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    pass "git commit -m: bare banned phrase still blocks after carve-out test"
else
    fail "git commit -m: bare phrase post-carve-out" "expected block, got: $RH_STDOUT"
fi

# ────────────────────────────────────────────────────────────────────────────
# Group: git commit - passing cases
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== git commit: passing ==="

# Clean commit message
FIXTURE=$(gh_fixture "git commit -m 'fix(auth): handle null refresh token'")
run_hook "$FIXTURE"
if [ -z "$RH_STDOUT" ] || printf '%s' "$RH_STDOUT" | jq -e '.decision != "block"' >/dev/null 2>&1; then
    pass "git commit -m: clean message passes"
else
    fail "git commit -m: clean message" "expected pass, got: $RH_STDOUT"
fi

# git log read command (no commit, no body flag) passes
FIXTURE=$(gh_fixture "git log --oneline -10")
run_hook "$FIXTURE"
if [ -z "$RH_STDOUT" ]; then
    pass "git log: read command passes"
else
    fail "git log: read command" "expected empty stdout, got: $RH_STDOUT"
fi

# ────────────────────────────────────────────────────────────────────────────
# Group: Jira writes - blocking and passing
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== Jira writes ==="

# Sycophantic text in Jira curl write blocks
FIXTURE=$(gh_fixture "curl -s -X POST https://legalshield.atlassian.net/rest/api/3/issue -d '{\"fields\":{\"summary\":\"great catch\"}}'")
run_hook "$FIXTURE"
if printf '%s' "$RH_STDOUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    pass "Jira curl: banned phrase in command blocks"
else
    fail "Jira curl: banned phrase" "expected block, got: $RH_STDOUT"
fi

# Jira curl read (GET, no data flag) passes
FIXTURE=$(gh_fixture "curl -s https://legalshield.atlassian.net/rest/api/3/issue/COREAPP1-123")
run_hook "$FIXTURE"
if [ -z "$RH_STDOUT" ]; then
    pass "Jira curl: GET (no data flag) passes"
else
    fail "Jira curl: GET" "expected empty stdout, got: $RH_STDOUT"
fi

# Jira curl with backtick-quoted banned phrase passes
FIXTURE=$(gh_fixture "curl -s -X POST https://legalshield.atlassian.net/rest/api/3/issue -d '{\"fields\":{\"description\":\"\`great catch\` is a banned sycophantic phrase\"}}'")
run_hook "$FIXTURE"
if [ -z "$RH_STDOUT" ] || printf '%s' "$RH_STDOUT" | jq -e '.decision != "block"' >/dev/null 2>&1; then
    pass "Jira curl: backtick-quoted banned phrase passes"
else
    fail "Jira curl: backtick carve-out" "expected pass, got: $RH_STDOUT"
fi

# ────────────────────────────────────────────────────────────────────────────
# Group: false-positive checks on ordinary commands
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== false-positive checks ==="

# --verbose flag must not trip the double-hyphen surrogate
FIXTURE=$(gh_fixture "gh pr list --verbose --state open")
run_hook "$FIXTURE"
if [ -z "$RH_STDOUT" ]; then
    pass "no false positive: --verbose flag"
else
    fail "false-positive: --verbose" "expected empty stdout, got: $RH_STDOUT"
fi

# gh with ' -- ' as argument separator must not block
FIXTURE=$(gh_fixture "gh pr view 42 -- extra-arg")
run_hook "$FIXTURE"
if [ -z "$RH_STDOUT" ]; then
    pass "no false positive: gh with argument separator"
else
    fail "false-positive: argument separator" "expected empty stdout, got: $RH_STDOUT"
fi

# git commit with a flag that contains matching substring but clean message
FIXTURE=$(gh_fixture "git commit --no-verify -m 'refactor: simplify token resolver'")
run_hook "$FIXTURE"
if [ -z "$RH_STDOUT" ] || printf '%s' "$RH_STDOUT" | jq -e '.decision != "block"' >/dev/null 2>&1; then
    pass "no false positive: git commit with extra flags and clean message"
else
    fail "false-positive: git commit extra flags" "expected pass, got: $RH_STDOUT"
fi

# curl to unrelated host must not be intercepted
FIXTURE=$(gh_fixture "curl -s -d '{\"key\":\"val\"}' https://example.com/api")
run_hook "$FIXTURE"
if [ -z "$RH_STDOUT" ]; then
    pass "no false positive: curl to unrelated host"
else
    fail "false-positive: unrelated curl" "expected empty stdout, got: $RH_STDOUT"
fi

# ────────────────────────────────────────────────────────────────────────────
# Group: malformed input resilience
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== malformed input ==="

# Empty stdin
RH_STDOUT=$(printf '' | bash "$HOOK" 2>/dev/null)
RH_EXIT=$?
if [ "$RH_EXIT" -eq 0 ] && [ -z "$RH_STDOUT" ]; then
    pass "empty stdin: exits 0 with no output"
else
    fail "empty stdin" "exit=$RH_EXIT stdout=$RH_STDOUT"
fi

# Non-JSON stdin
RH_STDOUT=$(printf 'not json at all' | bash "$HOOK" 2>/dev/null)
RH_EXIT=$?
if [ "$RH_EXIT" -eq 0 ] && [ -z "$RH_STDOUT" ]; then
    pass "non-JSON stdin: exits 0 with no output"
else
    fail "non-JSON stdin" "exit=$RH_EXIT stdout=$RH_STDOUT"
fi

# ────────────────────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────────────────────
echo ""
printf 'Result: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "${#ERRORS[@]}" -gt 0 ]; then
    echo "Failures:"
    for e in "${ERRORS[@]}"; do
        printf '  %s\n' "$e"
    done
fi

[ "$FAIL" -eq 0 ]
