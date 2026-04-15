---
name: debug
description: Start systematic debugging session for a bug
argument-hint: Description of the bug or error message
model: sonnet
---

Debug and fix a bug. Read the knowledge file at `~/.claude/knowledge/systematic-debugging/systematic-debugging.md` before proceeding.

Arguments: $ARGUMENTS (Description of the bug or error message)

## Process

1. Read the knowledge file at ~/.claude/knowledge/systematic-debugging/systematic-debugging.md before proceeding
2. Understand the bug and gather reproduction steps
3. If logs are involved, read the knowledge file at ~/.claude/knowledge/reading-logs.md before proceeding
4. Systematically investigate the codebase
5. Form and test hypotheses
6. Implement a fix for the root cause
7. Verify the fix thoroughly

## Key Principles

- Find root cause before attempting fixes
- Make the SMALLEST possible change to test hypotheses
- Create failing test case first when implementing fix
- Verify fix and run tests before claiming completion
