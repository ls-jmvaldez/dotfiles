---
name: writing-plans
description: Create implementation plans with tasks grouped by subsystem. Related tasks share agent context; groups parallelize across subsystems.
license: MIT
---

# Writing Plans

Write step-by-step implementation plans for agentic execution. Each task should be a **complete unit of work** that one agent handles entirely.

**Clarify ambiguity upfront:** If the plan has unclear requirements or meaningful tradeoffs, ask the user before writing the plan. Present options with descriptions explaining the tradeoffs. Don't guess when the user can clarify in 10 seconds.

**Save to:** `~/.claude/plans/YYYY-MM-DD-<feature-name>.md`

## Plan Template

````markdown
# [Feature Name] Implementation Plan

> **Status:** DRAFT | APPROVED | IN_PROGRESS | COMPLETED

## Specification

**Goal:** [What we're building and why]

**Success Criteria:**

- [ ] Criterion 1
- [ ] Criterion 2

## PR Strategy

**Split:** single PR | stacked PRs | independent PRs

**Rationale:** [One sentence on why this shape was chosen]

**Independence Check** (required if split = independent PRs):

- [ ] Each PR's diff touches zero files edited by another PR in this plan
- [ ] Each PR's branch passes CI when rebased onto main by itself
- [ ] Reverting one PR does not break the others

_If any Independence Check box cannot be ticked, downgrade to `stacked PRs`._

## Branch Plan

_Consumed by `/execute` to provision git state. One row per PR in the strategy above._

| # | Branch                     | Worktree Path                      | Base                  |
| - | -------------------------- | ---------------------------------- | --------------------- |
| 1 | feat/<TICKET>-<slug>       | .claude/worktrees/<TICKET>-pr1     | main                  |
| 2 | feat/<TICKET>-<slug2>      | .claude/worktrees/<TICKET>-pr2     | feat/<TICKET>-<slug>  |

## Context Loading

_Run before starting:_

```bash
read src/relevant/file.ts
glob src/feature/**/*.ts
```

## Phase 1: [Phase Name]

_Maps to Branch Plan row 1. For single-PR plans, this is the only phase._

### Task 1.1: [Complete Feature Unit]

**Context:** `src/auth/`, `tests/auth/`

**Steps:**

1. [ ] Create `src/auth/login.ts` with authentication logic
2. [ ] Add tests in `tests/auth/login.test.ts`
3. [ ] Export from `src/auth/index.ts`

**Verify:** `npm test -- tests/auth/`

---

### Task 1.2: [Another Complete Unit]

**Context:** `src/billing/`

**Steps:**

1. [ ] ...

**Verify:** `npm test -- tests/billing/`

## Phase 2: [Phase Name]

_Maps to Branch Plan row 2. Omit this section entirely if the plan has only one PR._

### Task 2.1: ...
````

## Phasing Doctrine

Each phase maps to one PR and one worktree. A well-shaped phase is **mergeable on its own** — it builds, its tests pass, and it delivers a thin slice of user-observable value. Avoid plans where nothing works until every phase lands.

When `split = stacked PRs`, a later phase may depend on an earlier one at the code level (imports, exports) — that is expected and fine. The independence check only applies when you're declaring phases as truly independent.

**Rule of thumb:** If you find yourself writing "Phase 3 is just tests for Phase 2," merge them. Tests belong to the phase that introduces the behavior.

## Task Sizing

A task includes **everything** to complete one logical unit:

- Implementation + tests + types + exports
- All steps a single agent should do together

**Right-sized:** "Add user authentication" - one agent does model, service, tests, types
**Wrong:** Separate tasks for model, service, tests - these should be one task

**Bundle trivial items:** Group small related changes (add export, update config, rename) into one task.

## Parallelization & Grouping

Within a phase, tasks can still be grouped by subsystem for parallel agent execution. Use `###` subsystem sub-headings under the `## Phase N:` heading:

```markdown
## Phase 1: Auth and billing foundations

### Authentication subsystem

#### Task 1.1: Add login

#### Task 1.2: Add logout

### Billing subsystem

#### Task 1.3: Add billing API

#### Task 1.4: Add webhooks

### Integration (sequential — depends on above)

#### Task 1.5: Wire auth + billing
```

**Execution model:**

- Phases run sequentially (each maps to a PR boundary)
- Subsystems within a phase run in parallel agents
- Tasks within a subsystem run sequentially in one agent
- Max 3-4 tasks per subsystem group

Tasks in the **same subsystem** should be sequential or combined into one task.

## Rules

1. **Explicit paths:** Say "create `src/utils/helpers.ts`" not "create a utility"
2. **Context per task:** List files the agent should read first
3. **Verify every task:** End with a command that proves it works
4. **One agent per task:** All steps in a task are handled by the same agent

## Large Plans

For plans over ~500 lines, split into phases in a folder:

```
~/.claude/plans/YYYY-MM-DD-feature/
+-- README.md           # Overview + phase tracking
+-- phase-1-setup.md
+-- phase-2-feature.md
```
