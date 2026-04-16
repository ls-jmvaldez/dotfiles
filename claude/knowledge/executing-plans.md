---
name: executing-plans
description: Executes implementation plans. Provisions worktrees from the Branch Plan, routes tasks per phase, opens draft PRs at phase boundaries.
license: MIT
---

# Executing Plans

**You are an orchestrator.** Spawn sub-agents to do the actual implementation. Your job is to read the plan, provision git state from its Branch Plan, route tasks into the right worktree per phase, and commit/push/open draft PRs at phase boundaries. The user never runs git by hand from this flow.

## Status Lifecycle

A plan file's `> **Status:**` header moves through these states:

| From | To | When |
|------|----|------|
| `DRAFT` | `IN_PROGRESS` | `/execute` fires — invocation is approval |
| `APPROVED` | `IN_PROGRESS` | `/execute` fires on a plan already explicitly approved |
| `IN_PROGRESS` | `COMPLETED` | All phases committed, pushed, and draft PRs opened |
| `IN_PROGRESS` | `IN_PROGRESS` | A phase failed — re-run resumes from that phase |
| any | `COMPLETED` | Manually only if work was abandoned or merged elsewhere |

Flip the status on disk before any git work starts. If the plan is already `COMPLETED`, stop immediately.

## Branch Plan Contract

The plan's `## Branch Plan` section is a markdown table. Each row maps to exactly one phase, one branch, one worktree, one draft PR.

```
| # | Branch               | Worktree Path                    | Base                |
| - | -------------------- | -------------------------------- | ------------------- |
| 1 | feat/COREAPP1-3307-a | .claude/worktrees/COREAPP1-3307-pr1 | main             |
| 2 | feat/COREAPP1-3307-b | .claude/worktrees/COREAPP1-3307-pr2 | feat/COREAPP1-3307-a |
```

Rule: row N's base is either `main` (or `origin/main`) or the branch of row N-1 (stacked). Independent PRs always use `main`. Stacked PRs chain through previous rows' branches.

## Provisioning

For each Branch Plan row:

```
git worktree add -b <branch> <worktree-path> <base>
```

The `worktree-conflict.sh` PreToolUse hook runs automatically and warns on stderr if the incoming branch would overlap with files in another active worktree. Surface any warning to the user and pause for direction. Do not silently proceed.

If a worktree already exists at the path (resuming), `git worktree add` errors. That's the signal to skip — the worktree is already provisioned.

## Phase Routing

Each `## Phase N:` heading in the plan maps to Branch Plan row N. All tasks inside the phase run in that phase's worktree.

Spawn subagents with `cwd: <worktree-path>` so every file edit, test run, and git command lands in the right tree. Do not run edits from the main working directory.

Within a phase:

- Subsystem groups (third-level headings like `### Authentication subsystem`) run in parallel agents
- Tasks inside a subsystem group run sequentially inside one agent
- Max 4 parallel agents per phase

| Signal | Group together |
|--------|----------------|
| Same directory prefix | `src/auth/*` tasks |
| Same domain/feature | Auth tasks, billing tasks |
| Same subsystem heading | Tasks under one `###` in the plan |

## Verify Before Committing

Every task in the plan should end with a `**Verify:**` command. Run it before committing that task's work. If verification fails:

1. The subagent attempts to fix the failure (it has the context).
2. If it can't fix, it reports the error output.
3. Dispatch a focused fix agent with the error.
4. If the same error recurs after two attempts, stop the phase and surface to the user.

## Phase Boundary: Commit, Push, Draft PR

After all subsystem groups in a phase finish cleanly:

1. `cd <worktree-path>` or use `git -C <worktree-path>` for every command.
2. Stage only the files this phase modified. `git add <file1> <file2>`. Never `git add -A` or `git add .`.
3. Commit with a conventional-commit message:
   - Header: `<type>(<scope>): <phase-name-kebab-lowercase>` (50 chars max)
   - Body: why this phase exists, pulled from the plan's Specification. 2-3 sentences, no em dashes.
4. `git push -u origin <branch>`
5. `gh pr create --draft --base <base> --title <title> --body <body>` where:
   - Title is the phase name (+ ticket key if present in the plan)
   - Body links the plan file path, any Jira tickets, and summarizes the phase
6. Report the PR URL immediately. Later phases can execute while Copilot reviews this one.

## Completion

Once the last phase ships its PR:

- Flip status to `COMPLETED`
- Move the plan file to `plans/done/<same-name>.md`
- Summary report: plan path, all PR URLs, all branches

## Failure Handling

- Leave plan at `IN_PROGRESS`
- Append under the status header: `**Failed at:** Phase N — <one-line reason>`
- Surface the error to the user
- Re-invoking `/execute` on the same plan skips provisioning for already-created worktrees and resumes at the failing phase

## What This Flow Does Not Do

- **Auto-rebase stacked PRs.** When a parent branch is force-pushed, child PRs need manual rebase. Deferred until a `/stack` skill is built from real scenarios.
- **Auto-merge.** Draft PRs stay draft. Merging is a human decision.
- **Architectural second-guessing.** If the plan says "use library X," use library X. Surface concerns to the user rather than deviating silently.

## Architectural Fit

Changes should integrate cleanly with existing patterns. If a subagent's work is fighting the architecture, that's a signal to escalate — refactor first as a separate phase, or ask the user whether to proceed. Don't reinvent wheels when existing libraries solve the problem, but don't reach for a dependency for trivial things either.

## Principles

- You are an orchestrator. Subagents do the implementation.
- The plan is the source of truth. Wrong plan → stop and fix the plan, don't improvise.
- User never types git commands from this flow.
- Fewer agents with broader scope run faster than many narrow ones.
- Fail fast: a broken phase does not get committed.
