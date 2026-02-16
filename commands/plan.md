---
description: Create a detailed implementation plan for a feature or task
---

Create an implementation plan using the `writing-plans` skill.

Arguments: $ARGUMENTS (Feature or task description)

## Process

1. Load the `writing-plans` skill for guidance on plan structure
2. Clarify ambiguity upfront if needed (ask user about tradeoffs)
3. Create plan following the template structure

## Plan Structure

Save to: `**/plans/YYYY-MM-DD-<feature-name>.md`

```markdown
# [Feature Name] Implementation Plan

> **Status:** DRAFT | APPROVED | IN_PROGRESS | COMPLETED

## Specification

**Goal:** [What we're building and why]

**Success Criteria:**
- [ ] Criterion 1
- [ ] Criterion 2

## Context Loading

_Run before starting:_
[Commands to read relevant files]

## Tasks

### Task 1: [Complete Feature Unit]

**Context:** [Relevant directories/files]

**Steps:**
1. [ ] Step 1
2. [ ] Step 2

**Verify:** [Command to verify task completion]
```

## Key Principles

- Each task is a complete unit of work for one agent
- Group related tasks by subsystem for parallel execution
- Include explicit file paths, not vague descriptions
- End every task with a verification command
- Max 3-4 tasks per group; split larger sections

## Large Plans

For plans over ~500 lines, split into phases in a folder:
```
**/plans/YYYY-MM-DD-feature/
├── README.md           # Overview + phase tracking
├── phase-1-setup.md
└── phase-2-feature.md
```
