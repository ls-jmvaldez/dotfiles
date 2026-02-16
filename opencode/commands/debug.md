---
description: Start systematic debugging session for a bug
---

Debug and fix a bug using the `systematic-debugging` skill methodology.

Arguments: $ARGUMENTS (Description of the bug or error message)

## Process

1. Load the `systematic-debugging` skill for the four-phase debugging framework
2. Understand the bug and gather reproduction steps
3. If logs are involved, use the `reading-logs` skill for efficient log analysis
4. Systematically investigate the codebase
5. Form and test hypotheses
6. Implement a fix for the root cause
7. Verify the fix thoroughly

## Key Principles

- Find root cause before attempting fixes
- Make the SMALLEST possible change to test hypotheses
- Create failing test case first when implementing fix
- Verify fix and run tests before claiming completion
