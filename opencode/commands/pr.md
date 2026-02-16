---
description: Create a pull request with auto-generated description
agent: fast-task
subtask: true
---

Create a pull request for the current branch.

Arguments: $ARGUMENTS (Optional base branch. Default: main or master)

## Step 1: Check Prerequisites

- Run `git status` to check for uncommitted changes
- If uncommitted changes exist, STOP and report: "Please commit your changes first"
- Check if branch is pushed to remote
- If not pushed, push with: `git push -u origin $(git branch --show-current)`

## Step 2: Determine Base Branch

- If user provided a base branch, use that
- Otherwise, detect default: check for `main` first, fall back to `master`

## Step 3: Gather Context

- Get merge base: `git merge-base HEAD origin/<base>`
- List commits: `git log <merge-base>..HEAD --oneline`
- Get diff stats: `git diff <merge-base>..HEAD --stat`
- Get full diff for analysis

## Step 4: Generate PR Content

**Title** (50 chars max, imperative mood):
- `feat: add user authentication flow`
- `fix: resolve race condition in data sync`
- `refactor: simplify payment processing logic`

**Body template:**
```markdown
## Summary

[2-3 sentences explaining what this PR does and why]

## Changes

- [Bullet list of key changes]

## Testing

- [ ] Tests added/updated

## Notes

[Any additional context for reviewers]
```

## Step 5: Create the PR

```bash
gh pr create --title "<title>" --base <base-branch> --body "$(cat <<'EOF'
<body content>
EOF
)"
```

## Step 6: Report Results

- Print the PR URL
- Note any warnings (draft status, failing checks)

## Failure Handling

- If `gh` not installed: "GitHub CLI (gh) is required. Install with: brew install gh"
- If not authenticated: "Please authenticate with: gh auth login"
