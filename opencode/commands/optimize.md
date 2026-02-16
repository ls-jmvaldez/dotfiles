---
description: Find and fix performance issues in code
---

Analyze code for performance issues and suggest optimizations using the `optimizing-performance` skill.

Arguments: $ARGUMENTS (Optional file path or area to focus on. Defaults to unstaged changes.)

## Process

If `$ARGUMENTS` is empty:
1. Run `git diff` to get unstaged changes
2. Focus on optimizing the unstaged changes

If `$ARGUMENTS` is provided:
- Use it as the focus area for optimization

## Analysis should include

- Specific file:line references for each issue
- Explanation of the performance impact
- Code examples showing the optimization
- Estimated improvement (if measurable)
- Cost-benefit analysis for each proposed optimization

## Key Principles

- Measure before optimizing (never optimize without data)
- Readable code that's "fast enough" beats complex code that's "optimal"
- Prioritize high-impact optimizations over micro-optimizations
- If optimization increases complexity, only do it if 10x faster OR fixes critical UX
