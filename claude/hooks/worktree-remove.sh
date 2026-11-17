#!/usr/bin/env bash
# WorktreeRemove hook: pairs with worktree-create.sh. Claude Code calls it only
# for worktrees a WorktreeCreate hook made, after it has decided removal is OK.
#
# Deliberately conservative: no --force, so git refuses to drop a worktree with
# uncommitted or untracked changes, and the branch is deleted with -d, so a
# branch holding unmerged commits survives. Claude Code treats the removal as
# failed only if the directory still exists, and shows stderr.

set -uo pipefail

INPUT=$(cat)
field() { jq -r --arg k "$1" '.[$k] // empty' <<<"$INPUT"; }

WORKTREE_PATH=$(field worktree_path)
NAME=$(field name)
START_DIR=$(field source_path)
START_DIR=${START_DIR:-$(field cwd)}

if [ -z "$WORKTREE_PATH" ] && [ -n "$NAME" ] && [ -n "$START_DIR" ]; then
	COMMON_DIR=$(git -C "$START_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || true
	[ -n "$COMMON_DIR" ] && WORKTREE_PATH="$(cd "$COMMON_DIR/.." && pwd -P)/.claude/worktrees/$NAME"
fi

if [ -z "$WORKTREE_PATH" ]; then
	echo "worktree-remove: no worktree_path, or name plus cwd, in hook input" >&2
	exit 1
fi

[ -d "$WORKTREE_PATH" ] || exit 0

BRANCH=$(git -C "$WORKTREE_PATH" symbolic-ref --quiet --short HEAD 2>/dev/null) || true
COMMON_DIR=$(git -C "$WORKTREE_PATH" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
	echo "worktree-remove: $WORKTREE_PATH is not a git worktree; leaving it in place" >&2
	exit 1
}
REPO_ROOT=$(cd "$COMMON_DIR/.." && pwd -P)

git -C "$REPO_ROOT" worktree remove "$WORKTREE_PATH" >&2 || exit 1

# Only the branch worktree-create.sh made; a branch the agent switched to is not ours.
case "$BRANCH" in
worktree-*) git -C "$REPO_ROOT" branch -d "$BRANCH" >&2 || true ;;
esac
exit 0
