#!/usr/bin/env bash
# WorktreeCreate hook: creates the git worktree Claude Code asked for and prints
# its absolute path. Registering any WorktreeCreate hook replaces Claude Code's
# built-in git logic, so this script has to do the whole job.
#
# Why a hook at all: Claude Code's built-in creation does not fire git's
# post-checkout hook, so repos that link gitignored .env*.local files from
# post-checkout get a worktree without them. A plain `git worktree add` does
# fire it.
#
# Mirrors the built-in defaults: <main checkout>/.claude/worktrees/<name> on
# branch worktree-<name>, based on origin's default branch (fetched first),
# falling back to local HEAD when there is no usable remote.
#
# Contract: stdout carries exactly one line, the real (symlink-free) directory
# path. Everything else goes to stderr. Non-zero exit fails the creation and
# Claude Code shows stderr.
#
# Input (Claude Code 2.1.325): {"cwd", "name", ...}. The documented
# worktree_path/source_path fields are honored when present.

set -euo pipefail

fail() {
	echo "worktree-create: $*" >&2
	exit 1
}

INPUT=$(cat)
field() { jq -r --arg k "$1" '.[$k] // empty' <<<"$INPUT"; }

NAME=$(field name)
CWD=$(field cwd)
SOURCE_PATH=$(field source_path)
REQUESTED_PATH=$(field worktree_path)

START_DIR=${SOURCE_PATH:-$CWD}
[ -n "$START_DIR" ] || fail "no cwd or source_path in hook input"

# The main checkout, even when the session is already inside a linked worktree.
COMMON_DIR=$(git -C "$START_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
	fail "$START_DIR is not inside a git repository"
REPO_ROOT=$(cd "$COMMON_DIR/.." && pwd -P)

if [ -z "$NAME" ] && [ -n "$REQUESTED_PATH" ]; then
	NAME=$(basename "$REQUESTED_PATH")
fi
[ -n "$NAME" ] || fail "no name or worktree_path in hook input"
case "$NAME" in
*/* | . | .. | -*) fail "refusing unsafe worktree name: $NAME" ;;
esac

WORKTREE_PATH=${REQUESTED_PATH:-$REPO_ROOT/.claude/worktrees/$NAME}
BRANCH="worktree-$NAME"

if [ -d "$WORKTREE_PATH" ]; then
	# Reusing a name reopens the existing worktree, matching the built-in behavior.
	git -C "$WORKTREE_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
		fail "$WORKTREE_PATH exists but is not a git worktree"
	(cd "$WORKTREE_PATH" && pwd -P)
	exit 0
fi

base_ref() {
	local remote_head default_branch
	remote_head=$(git -C "$REPO_ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) || true
	if [ -z "$remote_head" ]; then
		echo HEAD
		return
	fi
	default_branch=${remote_head#origin/}
	# Never wait on a password, passphrase, or host-key prompt; a hung fetch
	# would stall the agent dispatch. A failed fetch falls back to the cached ref.
	GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" \
		perl -e 'alarm shift; exec @ARGV' 15 \
		git -C "$REPO_ROOT" fetch --quiet origin "$default_branch" >&2 ||
		echo "worktree-create: fetch of origin/$default_branch failed, using cached ref" >&2
	echo "$remote_head"
}

mkdir -p "$(dirname "$WORKTREE_PATH")"

# git output, including any post-checkout hook output, must stay off stdout.
if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
	git -C "$REPO_ROOT" worktree add "$WORKTREE_PATH" "$BRANCH" >&2 ||
		fail "git worktree add failed for existing branch $BRANCH"
else
	git -C "$REPO_ROOT" worktree add --no-track -b "$BRANCH" "$WORKTREE_PATH" "$(base_ref)" >&2 ||
		fail "git worktree add failed for $WORKTREE_PATH"
fi

(cd "$WORKTREE_PATH" && pwd -P)
