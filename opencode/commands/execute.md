---
description: Execute an implementation plan from the plans folder
---

Execute an implementation plan using the `executing-plans` skill.

Arguments: $ARGUMENTS (Optional path to plan file)

## If no arguments provided

1. **Find available plans:**
   Search for plan files:
   ```bash
   # Look for plans in common locations
   find . -path "*/plans/*.md" -type f 2>/dev/null
   find . -name "*-plan.md" -o -name "*-PLAN.md" -type f 2>/dev/null
   ```

2. **Filter to incomplete plans:**
   - Read each plan file
   - Check the `> **Status:**` header
   - Only show plans with status `DRAFT`, `APPROVED`, or `IN_PROGRESS`
   - Skip plans marked `COMPLETED`

3. **Ask user which plan to execute**

## If plan path provided

1. Read the plan file
2. Verify plan exists and status is not `COMPLETED`
3. Proceed to execution

## Execution Process

1. **Review the plan:**
   - Display specification and success criteria
   - Show high-level task breakdown

2. **Setup (for larger plans):**
   - Create a feature branch
   - Consider git worktree for isolation

3. **Execute using the skill:**
   - Group related tasks by subsystem
   - Run groups in parallel when independent
   - Track progress with TodoWrite
   - Auto-recover from failures (retry once, then ask user)

4. **Verify before completion:**
   - Code review with `@code-reviewer`
   - Run test suite
   - Manual verification of changes
   - Check DX quality

5. **Commit and cleanup:**
   - Stage only files from this plan
   - Write descriptive commit message
   - Mark plan as COMPLETED
   - Move to `./plans/done/` if applicable

## Key Principles

- You are an orchestrator; spawn sub-agents for actual implementation
- Fewer agents with broader scope = faster execution
- Verify all four checks before marking complete
- If same error occurs twice, stop and ask user
