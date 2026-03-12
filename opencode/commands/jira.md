---
description: Execute Jira operations (create stories, search issues, manage sprints)
---

Load the `jira` skill and the `writer` skill (use **The Engineer** persona for all ticket content), then execute the following Jira task.

Arguments: $ARGUMENTS

## Project Flag

If the arguments start with a project flag (e.g. `--opsuc`, `--coreapp1`), use the matching project profile from the skill. The flag is case-insensitive and maps to the project key:

- `--opsuc` → OPSUC (Gold Diggers)
- `--coreapp1` → COREAPP1 (Internal Tools)

If no flag is provided, resolve the default project using `$JIRA_PROJECT` env var, or fall back to the skill's Default Project setting.

## Examples

```
/jira create a story called "Fix payment bug" under epic OPSUC-2260 --opsuc
/jira --opsuc list open bugs assigned to me
/jira search for stories under epic COREAPP1-3116
/jira --coreapp1 add subtasks to COREAPP1-3280
```

## Process

1. Verify `$JIRA_AUTH_TOKEN` is set
2. Determine the active project (flag > env var > default)
3. Look up the matching project profile in the skill for board ID, issue type IDs, and sprint IDs
4. Execute the requested Jira operation using curl
5. Report results with issue keys and links
