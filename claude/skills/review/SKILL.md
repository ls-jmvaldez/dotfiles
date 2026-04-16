---
name: review
description: Comprehensive code review using the code-reviewer agent
context: fork
agent: code-reviewer
model: sonnet
argument-hint: Optional instructions, or --deep to re-run flagged files in Opus
---

Perform a comprehensive code review.

Arguments: $ARGUMENTS (Optional instructions, or `--deep` to re-review flagged files in Opus)

## If no arguments provided

1. Check git status to see if there are uncommitted changes
2. Check current branch name
3. Determine what to review:
   - If uncommitted changes exist: Review uncommitted changes
   - If no uncommitted changes and on a feature branch: Review all changes against main
4. Check changed files via:
   `git diff --name-only $([ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] && echo "HEAD^" || echo "main...HEAD")`

## --deep mode

When `$ARGUMENTS` contains `--deep`:

1. Run the standard Sonnet review first.
2. Collect the list of files that received Critical or Important findings.
3. Re-invoke the `code-reviewer` agent with `model: opus[1m]` scoped to only those files, prompt: "deep re-review of the following files, using the same filter rules."
4. Merge any net-new findings from the Opus pass under a `## Deep Review Additions` section. Do not duplicate findings already reported.

Default model is `sonnet`. `--deep` is experimental — the Opus-vs-Sonnet value on top of already-filtered Sonnet findings is unverified. Use it when stakes are high (security-critical change, high-visibility feature) and skip it otherwise.

## Review covers

- **Technical**: Correctness, security, performance, maintainability, conventions
- **Product & UX**: User flow completeness, edge cases, accessibility
- **Developer Experience**: API design, discoverability, error messages, cognitive load
- **Documentation**: README updates, API docs, code comments

## Output format

Structured review with Critical Issues, Important Issues, Product/UX Issues, DX Issues, Documentation Updates, Suggestions, a final Verdict (APPROVE or REQUEST CHANGES), a **Manual Test Steps** section (numbered user-observable behaviors to verify), and a **Run Locally** block (paste-ready `cd <worktree> && <start-cmd>` derived from project CLAUDE.md).

The Manual Test Steps and Run Locally sections are mandatory unless the change has zero user-visible surface — in which case the Manual Test Steps section should explicitly say so.
