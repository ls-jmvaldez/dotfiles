---
name: confluence
description: Execute Confluence operations against legalshield.atlassian.net (read, create, update, search pages; attachments; comments)
argument-hint: "Confluence operation to perform"
model: sonnet
---

Read the knowledge file at `~/.claude/knowledge/confluence/confluence.md` before proceeding. When composing page content (tech specs, runbooks, READMEs, design docs), follow `~/.claude/knowledge/writer.md` using **The Engineer** persona (or **The Architect** for design docs and ADRs).

Arguments: $ARGUMENTS

## Examples

```
/confluence get page 4463984714
/confluence find pages titled "Payment Diagrams"
/confluence list children of 5353013302
/confluence create child page under 4463984714 titled "Refunds runbook"
/confluence update page 4942233631 — append a section on retry semantics
/confluence add label "payments" to page 4598267923
/confluence start a P1 postmortem for OPSUC-2407 — checkout 500s
```

## Process

1. Verify `$CONFLUENCE_AUTH_TOKEN` is set (already base64 `email:apitoken`, sourced from 1Password in zshrc).
2. Resolve the target page/space — by ID when supplied, by title search via CQL otherwise. Confirm before mutating.
3. For updates, fetch current `version.number` first and submit `version.number + 1` in the PUT.
4. For complex storage-format payloads (tables, macros), write the JSON body to a temp file and pass with `curl -d @file` to avoid shell escaping bugs.
5. Report the page ID and a clickable `https://legalshield.atlassian.net/wiki/...` URL on success.

## When to defer to another skill

- **Release notes onboarding** for a repo → `/release-notes-onboard` (separate skill, wires up the workflow + per-repo Confluence parent under the Releases hub).
- **Jira ticket creation** referenced from a Confluence page → `/jira`. Embed the resulting key with the `jira` storage macro.
