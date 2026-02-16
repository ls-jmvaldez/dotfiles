---
description: Create a well-formatted git commit for current changes
---

Create a git commit for the current changes.

Arguments: $ARGUMENTS (Optional context about the changes)

## Decision: Direct vs Investigate

**Commit directly** if you have clear context about the changes:
- You just implemented, fixed, or modified something in this conversation
- You know exactly what files changed and why

**Investigate first** if ambiguous:
- User invoked `/commit` without prior context
- You're unsure what changes exist or their purpose

## Process

1. **Verification:**
   ```bash
   git diff --cached --name-only  # staged changes
   git diff --name-only           # unstaged changes
   ```

2. **Context gathering:**
   ```bash
   git log -n 10 --oneline  # learn project's commit conventions
   git diff --cached        # or git diff for unstaged
   ```

3. **Draft the message** following Conventional Commits:
   - Format: `<type>(<scope>): <subject>`
   - Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`
   - Header: 50 chars max, imperative mood, lowercase, no period
   - Body: 72 char wrap, focus on WHY not WHAT

4. **Execute:**
   ```bash
   git commit -m "your_header" -m "your_body"
   ```

## Failure Handling

If `git commit` fails (pre-commit hooks):
1. STOP - do not attempt to auto-fix
2. Report the error output
3. Show the drafted message that failed
4. Recommend fixing the errors manually

## Important

- Do not add Claude/AI attribution footers
- If the diff is massive, focus on the primary architectural change
- Infer scope from directory name or module (e.g., `src/auth/login.ts` -> `auth`)
