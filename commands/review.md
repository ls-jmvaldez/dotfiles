---
description: Comprehensive code review using the code-reviewer agent
agent: code-reviewer
subtask: true
---

Perform a comprehensive code review.

Arguments: $ARGUMENTS (Optional instructions for the review)

## If no arguments provided

1. Check git status to see if there are uncommitted changes
2. Check current branch name
3. Determine what to review:
   - If uncommitted changes exist: Review uncommitted changes
   - If no uncommitted changes and on a feature branch: Review all changes against main
4. Check changed files via:
   `git diff --name-only $([ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] && echo "HEAD^" || echo "main...HEAD")`

## Review covers

- **Technical**: Correctness, security, performance, maintainability, conventions
- **Product & UX**: User flow completeness, edge cases, accessibility
- **Developer Experience**: API design, discoverability, error messages, cognitive load
- **Documentation**: README updates, API docs, code comments

## Output format

Structured review with Critical Issues, Important Issues, Product/UX Issues, DX Issues, Documentation Updates, Suggestions, and a final Verdict (APPROVE or REQUEST CHANGES).
