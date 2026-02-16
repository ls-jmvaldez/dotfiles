---
description: Refactor code following best practices
---

Refactor code to improve quality, maintainability, and adherence to best practices using the `refactoring-code` skill.

Arguments: $ARGUMENTS (File path, function name, or pattern to refactor. If not provided, refactors unstaged changes.)

## Determining what to refactor

**If `$ARGUMENTS` is provided:**
- Use the provided file path, pattern, or user instructions directly

**If `$ARGUMENTS` is empty:**
- If there are unstaged changes, use those as the refactoring target
- If no unstaged changes, detect changed files with:
  `git diff --name-only $([ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] && echo "HEAD^" || echo "main...HEAD")`

## Process

1. Load the `refactoring-code` skill for the five-phase refactoring framework
2. Understand current behavior before changing anything
3. Verify behavior-driven tests exist (add them if missing)
4. Identify issues (complexity, duplication, poor naming, type gaps)
5. Plan incremental steps (high impact + low risk first)
6. Execute with continuous verification (run tests after each change)

## Key Principles

- Refactoring changes structure, not functionality
- Tests must verify BEHAVIOR, not implementation
- Make one change at a time, verify, then continue
- If something breaks, STOP and debug before proceeding
