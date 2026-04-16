# Claude Workflow Improvements Implementation Plan

> **Status:** COMPLETED

## Specification

**Goal:** Close the highest-friction gaps in the daily Claude workflow — planning, PR review, worktree management — identified from analysis of 26 sessions over Apr 13-16.

**Success Criteria:**

- [ ] AI-authored PR reviews and comments are always attributed to Claude Ocodius regardless of invocation path (`gh pr review`, `gh pr comment`, MCP GitHub tool, approve-only reviews)
- [ ] `/plan` produces plans that load Jira context via a cheap model and author via Opus, with a mandatory "PR Strategy" section that fails loudly if PRs aren't independently mergeable
- [ ] `/review` output includes Manual Test Steps and a ready-to-paste `cd <worktree> && <start-cmd>` block
- [ ] Creating a git worktree warns when its branch would modify files dirty in another worktree
- [ ] Stacked PRs can be rebased onto updated parents without losing approvals on untouched children

## Decisions (confirmed)

1. **Jira context loader**: inline Haiku subagent inside `/plan`, not a separate `/jira` pre-step.
2. **`/stack` skill**: **deferred.** Not building it now. User will hit the stacked-PR pain in practice a few times first, then we design the skill from real scenarios rather than speculation.
3. **Review confidence filter**: port the ">80% sure, skip stylistic noise, consolidate similar issues" rule from `affaan-m/everything-claude-code`'s `code-reviewer.md` into the `code-reviewer` agent prompt.
4. **Manual test steps location**: appended as a top-level section after the review verdict.
5. **Worktree conflict hook**: PreToolUse on `Bash(git worktree add*)`, warn-only. Primary consumer is `/execute`, not the user typing git commands.
6. **Post-approval execution**: `/execute` runs with `context: fork` + `model: sonnet` (fresh context, correct model). **Invocation is approval** — typing `/execute` against a `DRAFT` plan flips it to `IN_PROGRESS` and starts work. No separate status edit required. True auto-clear + restart is not supported by Claude Code today — this is the cleanest achievable flow.
7. **Git lifecycle automation**: `/execute` handles branch creation, worktree creation, commits, push, and opening draft PRs. User does not run git manually post-approval.
8. **Draft PR opening**: automatic at phase completion, not bundled at the end. Lets review start on phase 1 while phase 2 is still being written.
9. **Stack rebase**: manual only (no auto-rebase hook). Defer until `/stack` is designed.

## Context Loading

_Run before starting:_

```bash
read ~/.claude/skills/plan/SKILL.md
read ~/.claude/skills/review/SKILL.md
read ~/.claude/knowledge/writing-plans.md
read ~/.claude/hooks/pr-review-attribution.sh
read ~/.claude/hooks/pr-comment-attribution.sh
read ~/.claude/hooks/pr-issue-comment-attribution.sh
read ~/.claude/settings.json
read ~/.claude/agents/code-reviewer.md
glob ~/.claude/hooks/*.sh
```

## Phases

Each phase ships as its own PR. All phases are independently mergeable — no phase imports from another, settings.json changes touch disjoint hook arrays.

**Independence verification:**

| Phase | Touches | Depends On |
|---|---|---|
| 1 | `hooks/pr-*.sh`, `settings.json` (PostToolUse) | none |
| 2 | `skills/plan/SKILL.md`, `knowledge/writing-plans.md` | none |
| 3 | `skills/review/SKILL.md`, `agents/code-reviewer.md` | none |
| 4 | `hooks/worktree-conflict.sh` (new), `settings.json` (PreToolUse) | none |
| 5 | `skills/execute/SKILL.md`, `knowledge/executing-plans.md` | 2 (for Branch Plan section shape) |

Phase 5 depends on Phase 2 defining the Branch Plan schema. It can still ship independently as long as Phase 2 merges first.

**Deferred (not in this plan):** `/stack` skill. Revisit after 2-3 real stacked-PR scenarios give us concrete requirements.

---

## Phase 1: Attribution hook matcher expansion

**Context:** `~/.claude/hooks/pr-*.sh`, `~/.claude/settings.json`

Already in-progress today. The existing `pr-review-attribution.sh` only matches `gh pr review --body` and `gh api .../reviews` POST. Misses approve-only reviews, `gh pr comment`, MCP GitHub tool calls, and some `gh api` comment paths.

**Steps:**

1. [ ] Audit each attribution hook (`pr-attribution.sh`, `pr-comment-attribution.sh`, `pr-issue-comment-attribution.sh`, `pr-review-attribution.sh`) — enumerate every invocation path each claims to cover
2. [ ] Extend `pr-review-attribution.sh` matcher to handle `gh pr review` without `--body` (approve/request-changes with no body → skip body edit, still attribute inline comments)
3. [ ] Add MCP GitHub tool matcher: detect `mcp__*__create_pull_request_review` / `create_issue_comment` tool calls by inspecting `tool_name` in hook input (not just `.tool_input.command`)
4. [ ] Consolidate the 4 PR hooks into a single dispatcher `pr-ai-attribution.sh` that routes on tool_name + command pattern, to eliminate matcher duplication
5. [ ] Update `settings.json` PostToolUse to call the single dispatcher; keep old hooks in place during rollout, remove after one week of verified firing
6. [ ] Add `~/.claude/hooks/.attribution.log` for debug (append each trigger decision) — gated behind `CLAUDE_ATTRIBUTION_DEBUG=1`

**Verify:**

```bash
# Fire each path manually, then:
gh api repos/LegalShield/<repo>/pulls/<n>/reviews --jq '.[] | select(.body != null) | .body' | grep -c "Claude Ocodius"
# Should match count of AI-authored reviews in the last week
```

---

## Phase 2: `/plan` skill rewrite

**Context:** `~/.claude/skills/plan/SKILL.md`, `~/.claude/knowledge/writing-plans.md`, `~/.claude/skills/jira/SKILL.md`

**Steps:**

1. [ ] Change `/plan` argument contract: first positional arg is a Jira key (e.g. `COREAPP1-3307`) OR a free-text feature description. Detect via regex.
2. [ ] If Jira key: spawn Haiku subagent (`model: haiku`) with prompt "fetch ticket <key> via Jira API, return: title, description, acceptance criteria, linked tickets, parent epic context." Pass result forward as context.
3. [ ] Switch to Opus for plan authoring. Use the existing `writing-plans.md` template, extended with the section below.
4. [ ] Add mandatory **PR Strategy** section to `writing-plans.md` template:
    ```markdown
    ## PR Strategy

    **Split:** single PR | stacked PRs | independent PRs

    **Independence Check** (required if split = independent):
    - [ ] Each PR's diff touches zero files edited by another PR
    - [ ] Each PR's branch has green CI when rebased onto main
    - [ ] Reverting one PR does not break the others

    **If Independence Check fails → split = stacked.**

    **Stack order** (required if split = stacked):
    1. Base PR: <title> (targets main)
    2. Next PR: <title> (targets base PR branch)
    ...
    ```
5. [ ] Update the plan template's phasing language: steal from `affaan-m/everything-claude-code/.kiro/agents/planner.md` — "Each phase should be mergeable independently. Avoid plans that require all phases to complete before anything works."
6. [ ] Add mandatory **Branch Plan** section to `writing-plans.md` template — consumed by `/execute`:
    ```markdown
    ## Branch Plan

    _Derived from PR Strategy. Used by `/execute` to provision git state._

    | # | Branch | Worktree Path | Base |
    |---|---|---|---|
    | 1 | feat/<TICKET>-<slug> | .claude/worktrees/<TICKET>-pr1 | main |
    | 2 | feat/<TICKET>-<slug2> | .claude/worktrees/<TICKET>-pr2 | feat/<TICKET>-<slug> (stacked) or main (independent) |
    ```
7. [ ] Update `skills/plan/SKILL.md` Process section to describe the two-phase flow (Haiku context → Opus plan), PR Strategy requirement, and Branch Plan generation

**Verify:**

```bash
/plan COREAPP1-3307
# Confirm: Jira context appears in the plan, plan saves to plans/YYYY-MM-DD-*.md,
# PR Strategy section is present and non-empty
```

---

## Phase 3: `/review` skill — manual test steps + worktree checkout + confidence filter

**Context:** `~/.claude/skills/review/SKILL.md`, `~/.claude/agents/code-reviewer.md`

**Steps:**

1. [ ] Add two sections to the `/review` output spec in `skills/review/SKILL.md`:
    - `## Manual Test Steps` — numbered list of user-observable behaviors to verify, one per changed feature
    - `## Run Locally` — block with `cd <current-worktree-path> && <start-cmd>` where start-cmd is read from CLAUDE.md (`pnpm -w <prefix>-dev` for membership-web, etc.) or falls back to "see CLAUDE.md"
2. [ ] Update `code-reviewer` agent prompt (`~/.claude/agents/code-reviewer.md`) with confidence filter rules from `affaan-m/everything-claude-code/.kiro/agents/code-reviewer.md`:
    - Only report issues where confidence > 80%
    - Consolidate similar issues into one finding with multiple examples
    - Skip purely stylistic noise (formatting, naming preferences without a clear rule)
3. [ ] Keep `/review` model as Sonnet by default. Add `/review --deep` variant that forces Opus for re-review of files flagged by the Sonnet pass (measurement placeholder — actual Opus-vs-Sonnet value is unverified)

**Verify:**

```bash
/review
# Output contains "Manual Test Steps" and "Run Locally" sections.
# Run the cd+start command and confirm it boots the app.
```

---

## Phase 4: Worktree conflict prevention hook

**Context:** `~/.claude/hooks/` (new file), `~/.claude/settings.json`

**Steps:**

1. [ ] Write `~/.claude/hooks/worktree-conflict.sh`:
    - PreToolUse hook on `Bash` matcher
    - Only fire if command matches `git worktree add`
    - Parse target path and branch from the command
    - For each existing worktree (`git worktree list --porcelain`), run `git -C <path> diff --name-only HEAD` to list dirty files
    - Run `git diff --name-only main..<new-branch>` for the incoming branch
    - If intersection is non-empty: emit a warning to stderr listing the overlapping files. Do not block.
2. [ ] Register the hook in `settings.json` PreToolUse array
3. [ ] Add a `--force` bypass: if the command contains `# no-conflict-check`, skip the hook

**Verify:**

```bash
# From a repo with two worktrees touching the same file:
git worktree add ../test-overlap feature/overlapping-change
# Hook warns about overlapping files; worktree is still created.
```

---

## Phase 5: `/execute` automation — post-approval git lifecycle

**Context:** `~/.claude/skills/execute/SKILL.md`, `~/.claude/knowledge/executing-plans.md`, `~/.claude/hooks/worktree-conflict.sh` (from Phase 4)

Today `/execute` mentions "Consider git worktree for isolation" as a loose suggestion. This phase makes it deterministic and removes all manual git from the post-approval flow.

**Steps:**

1. [ ] Update `skills/execute/SKILL.md` frontmatter — confirm `context: fork` + `model: sonnet` so execution runs in a fresh-context Sonnet agent that reads the plan from disk
2. [ ] Invocation-as-approval: when `/execute` runs with no args, pick the newest plan with `Status: DRAFT` or `APPROVED`. Flip it to `IN_PROGRESS` and write the change back to disk before any git work starts. No manual status edit required.
3. [ ] Update the Execution Process to read the plan's **Branch Plan** section and provision git state before any task runs:
    - For each row: `git worktree add -b <branch> <worktree-path> <base>`
    - Run the Phase 4 worktree-conflict hook's detection inline first; if overlap detected, surface and pause for user confirmation
4. [ ] Route task execution into the correct worktree per phase:
    - Each plan phase maps to one worktree (Branch Plan row)
    - Spawn subagents with `cwd: <worktree-path>` so their file edits land in the right tree
5. [ ] At each phase's completion:
    - Commit in the worktree using the existing conventional-commit pattern
    - `git push -u origin <branch>`
    - `gh pr create --draft --base <base> --title <derived-from-plan> --body <derived-from-plan-spec>`
    - Report the PR URL back to the user so Copilot review can start on phase 1 while phase 2 is still executing
6. [ ] After all phases complete successfully, flip plan status to `COMPLETED` and move to `plans/done/`.
7. [ ] Do NOT auto-rebase stacked branches on parent updates. Leave that manual until the deferred `/stack` skill exists.
8. [ ] Update `knowledge/executing-plans.md` to document: the Branch Plan contract, worktree-per-phase routing, invocation-as-approval semantics, status transitions (`DRAFT`|`APPROVED` → `IN_PROGRESS` → `COMPLETED`).
9. [ ] Failure handling: if worktree provisioning fails or a commit fails pre-hooks, stop and surface the error — do not silently continue. Leave plan at `IN_PROGRESS` with the failing phase noted so a re-run can resume from that point.

**Verify:**

```bash
# With a 2-phase DRAFT plan on disk:
/execute
# Expected:
# - Plan status flipped from DRAFT to IN_PROGRESS on disk
# - Two worktrees created under .claude/worktrees/
# - Commits land in each worktree's branch (verify: git -C <path> log)
# - Two draft PRs appear in `gh pr list --draft`
# - Plan flipped to COMPLETED and moved to plans/done/ on success
# - No `git worktree add`, `gh pr create`, or manual status edit was typed
```

---

## Rollout Order

Recommended merge order based on current pain + in-progress status:

1. Phase 1 (hooks) — already mid-iteration today, finish first
2. Phase 3 (`/review` update) — smallest change, immediate daily benefit
3. Phase 2 (`/plan` rewrite) — defines Branch Plan schema that Phase 5 consumes
4. Phase 4 (worktree hook) — low-risk, primarily consumed by Phase 5
5. Phase 5 (`/execute` automation) — ties it all together, ships last

Phases 1, 3, and 4 can ship in any order. Phase 5 depends on Phase 2's Branch Plan schema.
