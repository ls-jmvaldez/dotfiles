#!/usr/bin/env bash
# PostToolUse hook: after `git worktree add`, symlink gitignored env files
# from the main repo into the new worktree so dev servers pick them up.
# Never blocks — logs to stderr on success/issues.
#
# Covered patterns: any file matching `.env*` (e.g. .env, .env.local,
# .env.development.local, .env.dev.local, .env.uat.local, .env.prod.local)
# plus .envrc. Example/sample/template suffixes are skipped since those
# are committed and would already exist in the worktree via git.
#
# Bypass: include "# no-env-symlink" in the git worktree add command.

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

[ "$TOOL_NAME" = "Bash" ] || exit 0

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only run for `git worktree add`. Anchor on `worktree add` (not `git worktree
# add`) so global git options between the binary and the subcommand still match,
# e.g. `git -C /path worktree add ...`.
echo "$CMD" | grep -qE '(^|[^[:alnum:]_-])worktree add( |$)' || exit 0

# Honor bypass marker.
if echo "$CMD" | grep -qE '# +no-env-symlink'; then
  exit 0
fi

# Extract target path from the `worktree add` segment. Anchoring on `worktree
# add` keeps any `git -C <path>` prefix out of the positionals.
SEGMENT=$(echo "$CMD" | sed -nE 's/.*(worktree add[^|;&]*).*/\1/p' | head -1)
POSITIONALS=$(echo "$SEGMENT" \
  | sed -E 's/worktree add//' \
  | sed -E 's/(-b|-B) +[^ ]+//g' \
  | sed -E 's/(--track|--guess-remote|--detach|--force|--lock|--no-checkout|--checkout|-f)//g' \
  | awk '{$1=$1; print}')

# shellcheck disable=SC2206
ARGV=($POSITIONALS)
TARGET_PATH="${ARGV[0]:-}"

[ -n "$TARGET_PATH" ] || exit 0

# Worktree add may have failed — only proceed if the directory exists.
[ -d "$TARGET_PATH" ] || exit 0

# Resolve absolute path.
TARGET_ABS=$(cd "$TARGET_PATH" 2>/dev/null && pwd)
[ -n "$TARGET_ABS" ] || exit 0

# Find the main repo. git --git-common-dir returns the shared .git dir path;
# its parent is the primary worktree.
COMMON_DIR=$(git -C "$TARGET_ABS" rev-parse --git-common-dir 2>/dev/null)
[ -n "$COMMON_DIR" ] || exit 0
# --git-common-dir is relative to the worktree; resolve it.
COMMON_ABS=$(cd "$TARGET_ABS" 2>/dev/null && cd "$COMMON_DIR" 2>/dev/null && pwd)
[ -n "$COMMON_ABS" ] || exit 0
MAIN_REPO=$(dirname "$COMMON_ABS")

# Skip if the target IS the main repo.
[ "$TARGET_ABS" = "$MAIN_REPO" ] && exit 0

# Walk main repo for gitignored env files, pruning the usual suspects.
LINKED=0
SKIPPED=0
while IFS= read -r -d '' src; do
  rel="${src#$MAIN_REPO/}"
  dst="$TARGET_ABS/$rel"
  dst_dir=$(dirname "$dst")

  # Skip if the target directory doesn't exist in the worktree (e.g. a new
  # app was added in main but the worktree was branched from before).
  [ -d "$dst_dir" ] || { SKIPPED=$((SKIPPED + 1)); continue; }

  # Skip if destination already exists (file, dir, or symlink).
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if ln -s "$src" "$dst" 2>/dev/null; then
    LINKED=$((LINKED + 1))
  fi
done < <(find "$MAIN_REPO" \
  \( -path "*/node_modules" -o -path "*/.next" -o -path "*/.claude/worktrees" -o -path "*/dist" -o -path "*/.git" \) -prune \
  -o -type f \
  \( \( -name ".env*" ! -name "*.example" ! -name "*.sample" ! -name "*.template" \) -o -name ".envrc" \) \
  -print0 2>/dev/null)

if [ "$LINKED" -gt 0 ]; then
  echo "worktree-env-symlink: linked $LINKED env file(s) into $TARGET_PATH" >&2
fi

exit 0
