---
name: pr
description: Create a pull request with auto-generated description
context: fork
agent: fast-task
argument-hint: Optional base branch. Default: main or master
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

**Title** (under 70 chars, imperative mood, conventional-commit style):
- `feat: add user authentication flow`
- `fix: resolve race condition in data sync`
- `refactor: simplify payment processing logic`

**Body template (guide, not gate — skip sections with nothing meaningful to say):**

```markdown
[One-paragraph lead: why the change exists, what it enables or fixes. Be concrete; name the specific thing being fixed or added.]

[Optional second paragraph for additional context if the diff isn't self-explanatory.]

## Manual test steps

1. [First action a human takes]
2. [Next action + expected result]
3. [Edge case: input X, confirm Y]

## Screenshots / videos

<!-- Drop images/gifs. Skip this section for non-UI PRs. -->

## Tickets

<!-- A post-tool-use hook populates this from branch name + body. Write it explicitly so the links are right. -->
```

**Rules:**

- Lead with *why*, not *what*. Don't restate the diff as bullets.
- Manual test steps = what a human clicks through. Number happy path, bullet independent edges. For non-UI PRs, frame as smoke tests.
- Screenshots live in the PR, not the ticket. Skip for non-UI PRs.
- **No automation checklists.** No "☐ Unit tests pass," "☐ Lint green," "☐ Types clean," "☐ Added tests." CI owns these; checkboxes add zero signal.
- No em dashes. No "it's worth noting," "seamless," "powerful," or corporate filler.
- Short paragraphs, 3-4 sentences max. No bullet soup.
- Spike/research PRs: replace Manual test steps with "how to reproduce the investigation."

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
