---
name: execute
description: Execute an implementation plan from the plans folder, provisioning worktrees and draft PRs automatically
context: fork
model: sonnet
argument-hint: "Optional path to plan file"
---

Execute an implementation plan. Read the knowledge file at `~/.claude/knowledge/executing-plans.md` before proceeding.

Arguments: $ARGUMENTS (Optional path to plan file)

This skill runs in a forked context with Sonnet so planning artifacts authored by Opus are consumed by a cleaner agent with fresh conversation state. Your job is orchestration: provision git state from the plan, route tasks into the right worktree per phase, commit/push/open-PR at phase boundaries. You never ask the user to run git themselves.

## Step 1: Resolve the plan

**If `$ARGUMENTS` is a path**: read that plan file.

**If no argument**: find the most recent plan file at `~/.claude/plans/*.md` whose status header is `DRAFT`, `APPROVED`, or `IN_PROGRESS`. Skip files in `~/.claude/plans/done/`. If multiple match, pick the newest by mtime and report which one you chose.

Do not search project-local `plans/` or `.opencode/plans/` directories — `/plan` is
required to save to `~/.claude/plans/`.

If none match, stop and tell the user to create a plan with `/plan`.

## Step 2: Validate the plan

The plan must contain:

- `## Specification` with a goal
- `## PR Strategy` with a split choice
- `## Branch Plan` with a markdown table of branch rows
- `## Phase N:` headings matching the Branch Plan row count

If any are missing, stop and tell the user which section to add. Do not try to proceed with a partial plan.

## Step 3: Invocation-as-approval

Flip the plan status header:

- `DRAFT` → `IN_PROGRESS`
- `APPROVED` → `IN_PROGRESS`
- `IN_PROGRESS` → stay as-is (resuming a partial run)
- `COMPLETED` → stop with "plan already completed"

Write the change back to disk before any git work starts. Typing `/execute` is the approval — no separate status edit is expected.

## Step 4: Provision git state

Parse the `## Branch Plan` table. For each row (in order):

1. Resolve `<base>` — if `main`, use `origin/main`; otherwise it's the branch from a previous row.
2. Run `git worktree add -b <branch> <worktree-path> <base>`.
3. The worktree-conflict hook (PreToolUse) will warn on stderr if the incoming branch overlaps with another active worktree. If you see an overlap warning, surface it to the user and ask whether to proceed. Do NOT silently override unless the user says go.

On failure at this step, leave the plan at `IN_PROGRESS` with a note of what failed. Do not half-provision.

## Step 5: Execute phases

Phases run sequentially (each is a PR boundary). Within a phase, subsystem groups can run in parallel.

For each `## Phase N:` section:

1. Look up the matching Branch Plan row for `<worktree-path>` and `<branch>`.
2. Spawn subagent(s) via the Agent tool with:
   - `subagent_type: general-purpose`
   - `cwd: <worktree-path>` (so edits land in the right tree)
   - A prompt that hands the agent the phase's task list, context-loading commands, and verify commands from the plan
3. Wait for each subsystem group to complete. Max 4 parallel.
4. Fail-fast: if an agent reports a verify command failing, stop the phase and surface the error. Do not continue to commit a broken phase.

## Step 6: Commit, push, open draft PR at phase end

After all subsystem groups in a phase finish cleanly:

1. `cd <worktree-path>` (or use `git -C`)
2. Stage only the files the phase modified: `git add <file1> <file2> ...`. Do not use `git add -A`.
3. Commit with a conventional-commit message derived from the phase name and spec:
   - Format: `<type>(<scope>): <phase-name-kebab-lowercase>`
   - Body: 2-3 sentences explaining WHY, pulled from the plan's Specification
4. `git push -u origin <branch>`
5. `gh pr create --draft --base <base> --title "<title>" --body "<body>"`
   - Title from the phase name plus ticket key if present
   - Body: link to the plan spec, link the Jira ticket(s), brief change summary
6. Report the PR URL back to the user immediately so Copilot review can start on this phase while later phases are still executing.

## Step 7: Completion

After every phase commits and pushes successfully:

1. Flip plan status to `COMPLETED`.
2. Move the plan file to `~/.claude/plans/done/<same-name>.md`.
3. Report a summary: plan path, list of PR URLs, branch names.

## Failure handling

If any step fails:

- Leave plan at `IN_PROGRESS`
- Append a line under the status: `**Failed at:** Phase N — <reason>`
- Do not auto-retry. Surface the error to the user and wait for direction.
- When re-invoked, the skill resumes from the failing phase (idempotent worktree provisioning — `git worktree add` on an existing path errors out, which is the signal to skip).

## What this skill does NOT do

- **Auto-rebase stacked branches.** When a parent PR is updated, child PRs need manual rebase. A future `/stack` skill will handle this once we have concrete requirements.
- **Auto-merge PRs.** Draft PRs are opened; merging stays manual.
- **Run the test suite if the plan does not specify verify commands.** Verification is the plan's responsibility.

## Key Principles

- You are an orchestrator; subagents do the actual code work.
- Fewer agents with broader scope = faster execution. Max 4 parallel.
- User never runs git by hand from this skill.
- The plan file is the source of truth. If the plan is wrong, stop and ask the user to fix it.
