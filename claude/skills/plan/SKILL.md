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
   spawn a subagent to load ticket context before authoring. First resolve the plugin
   root so the subagent reads the team's canonical read policy (`${CLAUDE_PLUGIN_ROOT}`
   only resolves inside the plugin, so resolve the install path from the manifest):

     ```bash
     ROOT=$(python3 -c "
     import json, os
     m = json.load(open(os.path.expanduser('~/.claude/plugins/installed_plugins.json')))
     e = m['plugins'].get('internal-tools-jira@legalshield-marketplace')
     print(e[0]['installPath'] if e else '', end='')
     ")
     ```

     If `$ROOT` is empty, tell the user to run
     `claude plugin install internal-tools-jira@legalshield-marketplace` and stop.
     Otherwise spawn the subagent with the Agent tool:

     ```
     subagent_type: general-purpose
     model: haiku
     description: Load Jira ticket context
     prompt: |
       Fetch Jira ticket <KEY> and return a context block. Read <ROOT>/skills/jira/references/reading.md
       first and follow it exactly: it covers auth, the Default Read Policy (which fields to
       request, including customfield_10600 Acceptance Criteria), the ADF-to-text renderer,
       the comments policy, and the attachments policy. Use its full field list — do not
       trim it; AC in particular lives in customfield_10600 and is easy to miss.

       Return:
         - Title
         - Description (raw text, not ADF)
         - Acceptance criteria: surface customfield_10600 if populated; if it's empty, scan
           the description for an "Acceptance Criteria" heading or a Given/When/Then block
           and report that (per the AC-fallback note in reading.md). Do not report "none"
           just because the field is empty.
         - Parent epic key and title
         - Linked issues (blocked by / blocks / relates)
         - Current status
         - **Comments**: chronological list of `author @ YYYY-MM-DD: <one-line gist>`.
           Flatten ADF bodies to plain text. If a comment carries a decision, edge case,
           or clarification not in the description, expand it to 1–2 sentences.
         - **Attachments**: for each, list `filename (mimeType, size)` plus a one-line
           summary of why it matters. Auto-download per the attachments policy in reading.md:
             - text-like files: inline contents (truncate to ~80 lines if long)
             - images: save to `${TMPDIR:-/tmp}/jira-assets/<KEY>/` and report the path
               so the parent agent can Read them with the multimodal tool
             - large binaries / video: list metadata only

       Keep prose under 600 words; attachment file contents and image paths are exempt
       from that budget. Do not speculate — if a field is empty, say "(none)".
     ```

     Substitute the resolved `$ROOT` for `<ROOT>` in the prompt before spawning.

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
