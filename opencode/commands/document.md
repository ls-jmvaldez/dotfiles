---
description: Create or improve documentation
---

Create or improve documentation by analyzing what type of documentation is needed.

Arguments: $ARGUMENTS (File path, doc type, or description of documentation needed)

## Routing Logic

**For CODE COMMENTS (single source files):**
- Single source code file path provided (`.ts`, `.js`, `.py`, `.go`, `.rs`, etc.)
- Request mentions "comments", "inline docs", or "code comments"
- Use the `documenting-code-comments` skill

**For DOCUMENTATION (markdown, multi-file):**
- Markdown file path provided (`.md`)
- Request mentions README, API docs, architecture, or `/docs/`
- Task spans multiple files or requires system-level understanding
- Use the `documenting-systems` skill

## Code Comment Workflow

1. Read target file completely, identify language and patterns
2. Audit comments using skill's checklist:
   - **Necessity**: Can code be refactored to eliminate comment?
   - **Accuracy**: Does comment match current behavior?
   - **Value**: Does it explain WHY, not WHAT?
3. Apply fixes: remove unnecessary comments, rewrite unclear ones
4. Report changes: summarize removals, rewrites, and suggested refactors

## Documentation Workflow

**API Documentation:**
1. Read source files, types, route definitions, error handling paths
2. Plan structure using progressive disclosure layers
3. Write docs in `/docs/api/`

**README Updates:**
1. Audit existing README.md, package.json, configs, entry points
2. Update: quick start within first 30 lines, installation, config, links to /docs

**Architecture Documentation:**
1. Read core modules, trace dependencies, identify design decisions
2. Document decisions focusing on WHY, not just WHAT
3. Add diagrams using `visualizing-with-mermaid` skill for flows

## Location Standards

| Doc Type | Location | Filename Pattern |
|----------|----------|------------------|
| Project overview | Root | README.md |
| API reference | /docs/api/ | {resource-name}.md |
| Architecture | /docs/architecture/ | {topic}.md |
| Guides/How-to | /docs/guides/ | {topic}.md |
