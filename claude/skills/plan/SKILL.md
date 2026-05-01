---
name: plan
description: Create a detailed implementation plan for a feature or task, optionally loading Jira context first
argument-hint: Jira key (e.g. COREAPP1-3307) or a free-text feature description
model: opus[1m]
---

Create an implementation plan. Read the knowledge file at `~/.claude/knowledge/writing-plans.md` before proceeding.

Arguments: $ARGUMENTS (Jira key or feature description)

## Process

1. **Read the knowledge file** at `~/.claude/knowledge/writing-plans.md` so the template shape is current.

2. **Resolve the source material** from the first argument:

   - **If the argument matches a Jira key pattern** (`[A-Z][A-Z0-9]+-[0-9]+`, e.g. `COREAPP1-3307`, `OPSUC-2260`):
   spawn a subagent to load ticket context before authoring. Use the Agent tool with:

     ```
     subagent_type: general-purpose
     model: haiku
     description: Load Jira ticket context
     prompt: |
       Fetch Jira ticket <KEY> and return a compact context block. Use the pattern in
       ~/.claude/knowledge/jira/jira.md for authentication and the `Get Issue Details`
       endpoint. Return:
         - Title
         - Description (raw text, not ADF)
         - Acceptance criteria (if present)
         - Parent epic key and title
         - Linked issues (blocked by / blocks / relates)
         - Current status
       Keep the block under 400 words. Do not speculate — if a field is empty, say "(none)".
     ```

     Wait for the subagent to return. Use its output as the authoritative source for the plan's Specification section.

   - **Otherwise**: treat the argument as a free-text feature description. No subagent call.

3. **Clarify any ambiguity upfront.** If the ticket or description leaves meaningful tradeoffs unresolved, ask the user before authoring.
Corrections before writing are cheap.

4. **Author the plan** following the template structure from `writing-plans.md`. The author model is already Opus (this skill's frontmatter),
so there is no further handoff.

5. **Required sections** — the plan is incomplete without all of these:

   - `## Specification` — goal and success criteria
   - `## PR Strategy` — split choice with Independence Check
   - `## Branch Plan` — one row per PR, with branch name, worktree path, base
   - `## Context Loading` — files/globs to read before executing
   - `## Phase N:` sections — one per Branch Plan row

6. **Decide split — approval cost is the math that matters.**

   Every PR costs 2 approvals in this org. N PRs cost 2N. Any push after approval dismisses existing approvals. Factor both into the split choice, not just "is the diff small."

   - **Default: single PR.** Especially when the work is the same pattern applied N times (e.g., three modal ports, five endpoint migrations). The reviewer loads the pattern once from the first file and skims the rest. One PR = 2 approvals; N stacked PRs = 2N. For repetitive work, bundling is cheaper reviewer attention *and* faster to merge.
   - **Split off main (independent PRs)** when the PRs cover *different* patterns, risk profiles, or reviewer audiences — work a reviewer can't meaningfully skim. Trivial merge conflicts (import sort, JSX tag swaps in a shared consumer) are not a reason to avoid independent splits; they resolve in seconds. Prefer independent splits over stacks whenever the only overlap is cosmetic.
   - **Stack** only when a later PR *genuinely imports* types, functions, or exports introduced by an earlier PR, or builds on shared infrastructure added mid-plan. Stacks convert trivial merge conflicts into dependency chains, and dependency chains pay review cost every day they exist (rebase cascades, reset approvals down the chain, one stalled reviewer blocks everything downstream). Only accept that tax when the dependency is real at the code level.
   - **Independence Check** applies to independent splits, but treat small overlaps (import lines, a JSX tag rename in a shared consumer) as acceptable — the conflict is seconds to resolve and does not justify the stacking tax.

   When in doubt, ask: "Is this N times the same pattern?" → single PR. "Is there a real code-level dependency?" → stack. Otherwise → independent off main.

7. **Save to** `~/.claude/plans/YYYY-MM-DD-<slug>.md`:

   - If the source was a Jira key: slug = lowercase ticket key (e.g. `coreapp1-3307`).
   - If free-text: slug = kebab-case of a short feature name.

8. **Set status to DRAFT** and report the path. The user reviews the file.
`/execute` invocation acts as approval (it flips status to `IN_PROGRESS`).

## Key Principles

- Each phase maps to one PR and one worktree.
- A phase should be mergeable on its own. No plans where nothing works until everything lands.
- Explicit file paths, not vague descriptions. Say `create src/utils/helpers.ts`, not `create a utility`.
- Every task ends with a verification command.
- Max 3-4 tasks per subsystem group inside a phase; split larger sections.
- **Verification before ready, not after.** Approvals dismiss on push in this org, so CI failures caught *after* review cost the approval. Every phase's task list must end with the full local gate (`format:check && arch:check && security:* && lint && typecheck && test`) so the executor runs it before flipping the PR from draft → ready.
- **Bundle same-pattern repeats.** If phases 1–N are "apply refactor X to file A, then B, then C," collapse them into one phase / one PR. Splitting repetitive work multiplies approvals without multiplying review value.

## Large Plans

For plans over ~500 lines, split into phases in a folder:

```
~/.claude/plans/YYYY-MM-DD-feature/
├── README.md           # Overview + phase tracking
├── phase-1-setup.md
└── phase-2-feature.md
```
