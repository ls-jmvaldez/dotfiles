#!/usr/bin/env bash
# PreToolUse hook: warns when a new `git worktree add` would land on a branch
# whose committed diff vs main overlaps with files modified or dirty in an
# existing worktree. Never blocks — only writes to stderr.
#
# Limitations:
#   - New branches (-b <name>) have no diff yet, so only the destination-path
#     collision check runs.
#   - Primary consumer is /execute doing automated provisioning. Manual
#     invocations are also supported.
#
# Bypass: include the literal string "# no-conflict-check" in the command.

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

[ "$TOOL_NAME" = "Bash" ] || exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Match `git worktree add` only (not `git worktree list` etc.)
echo "$CMD" | grep -qE '(^|[^[:alnum:]_-])git worktree add( |$)' || exit 0

# Honor bypass marker.
if echo "$CMD" | grep -qE '# +no-conflict-check'; then
  exit 0
fi

# Extract the worktree segment (drop everything before `git worktree add`).
SEGMENT=$(echo "$CMD" | sed -nE 's/.*(git worktree add[^|;&]*).*/\1/p' | head -1)

# Parse: look for -b/-B <new-branch> and positional <path> [<ref>].
NEW_BRANCH=$(echo "$SEGMENT" | grep -oE '(-b|-B) +[^ ]+' | awk '{print $2}' | head -1)

# Strip flags to get positional args.
POSITIONALS=$(echo "$SEGMENT" \
  | sed -E 's/git worktree add//' \
  | sed -E 's/(-b|-B) +[^ ]+//g' \
  | sed -E 's/(--track|--guess-remote|--detach|--force|--lock|--no-checkout|--checkout|-f)//g' \
  | awk '{$1=$1; print}')

# shellcheck disable=SC2206
ARGV=($POSITIONALS)
TARGET_PATH="${ARGV[0]:-}"
REF="${ARGV[1]:-}"

if [ -z "$TARGET_PATH" ]; then
  exit 0
fi

# Destination-path collision with an existing worktree.
EXISTING_WORKTREES=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')
ABS_TARGET=$(cd "$(dirname "$TARGET_PATH")" 2>/dev/null && pwd)/$(basename "$TARGET_PATH")
for wt in $EXISTING_WORKTREES; do
  if [ "$wt" = "$ABS_TARGET" ]; then
    echo "worktree-conflict: path '$TARGET_PATH' is already an active worktree" >&2
    exit 0
  fi
done

# If -b <new-branch> was used, nothing to diff — bail after path check.
if [ -n "$NEW_BRANCH" ]; then
  exit 0
fi

# Resolve the incoming branch: explicit ref > HEAD.
INCOMING_BRANCH="${REF:-HEAD}"

# Need a merge base. Use origin/main if available, else main.
BASE_REF="origin/main"
git rev-parse --verify "$BASE_REF" >/dev/null 2>&1 || BASE_REF="main"
git rev-parse --verify "$BASE_REF" >/dev/null 2>&1 || exit 0

# Files the incoming branch has modified vs main.
INCOMING_FILES=$(git diff --name-only "$BASE_REF"..."$INCOMING_BRANCH" 2>/dev/null)
if [ -z "$INCOMING_FILES" ]; then
  exit 0
fi

# For each OTHER worktree: collect committed-diff files + dirty files.
# Skip worktrees whose current branch matches the incoming branch (same-branch
# comparison would flag every file in that branch as an "overlap" with itself).
INCOMING_REF_NAME=$(git rev-parse --abbrev-ref "$INCOMING_BRANCH" 2>/dev/null)
OVERLAPS=""
while IFS= read -r wt; do
  [ -n "$wt" ] || continue
  WT_BRANCH=$(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ "$WT_BRANCH" = "$INCOMING_REF_NAME" ] && continue

  WT_FILES=$(git -C "$wt" diff --name-only "$BASE_REF"...HEAD 2>/dev/null; \
             git -C "$wt" diff --name-only HEAD 2>/dev/null)
  [ -z "$WT_FILES" ] && continue

  OVERLAP=$(comm -12 \
    <(echo "$INCOMING_FILES" | sort -u) \
    <(echo "$WT_FILES" | sort -u))

  if [ -n "$OVERLAP" ]; then
    OVERLAPS+="${wt} (branch: ${WT_BRANCH}):"$'\n'
    OVERLAPS+=$(echo "$OVERLAP" | sed 's/^/  /')
    OVERLAPS+=$'\n'
  fi
done <<<"$EXISTING_WORKTREES"

if [ -n "$OVERLAPS" ]; then
  {
    echo "worktree-conflict: incoming branch '$INCOMING_BRANCH' overlaps with active worktrees:"
    echo "$OVERLAPS"
    echo "Bypass with '# no-conflict-check' in the command if intentional."
  } >&2
fi

exit 0
