---
description: Audit and clean up code comments following best practices
---

Review and clean up comments in the specified files or directory.

**Arguments**: $ARGUMENTS
(File path, directory, or glob pattern to audit. Defaults to current directory if not specified.)

## Process

Load and apply the `documenting-code-comments` skill guidelines:

### 1. Scan for Comments

Find all comments in the target files:
- Single-line comments (`//`, `#`)
- Multi-line comments (`/* */`, `""" """`)
- Doc comments (`/** */`, `///`)

### 2. Audit Each Comment

Apply the audit checklist:

1. **Necessity** - Can the code be refactored to eliminate the comment?
2. **Accuracy** - Does the comment match current behavior?
3. **Value** - Does it explain WHY, not WHAT?
4. **Actionability** - Do TODOs have ticket references?

### 3. Categorize Issues

- **Remove**: Comments that restate code or are stale/inaccurate
- **Refactor**: Code that needs renaming/restructuring to be self-documenting
- **Update**: Comments that are outdated but still valuable
- **Keep**: Comments that explain WHY or document gotchas

### 4. Apply Changes

For each issue:
- Remove redundant comments
- Refactor code to be self-documenting where possible
- Update stale comments
- Add ticket references to orphan TODOs

### 5. Report Summary

Provide a summary of changes:
- Comments removed (with reasons)
- Code refactored for clarity
- Comments updated
- TODOs that need ticket references
