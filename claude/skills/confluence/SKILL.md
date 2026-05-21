---
name: confluence
description: Execute Confluence operations against legalshield.atlassian.net (read, create, update, search pages; attachments; comments). Defaults to Joe's personal space for creation unless an org space is named.
argument-hint: "Confluence operation to perform"
model: sonnet
---

Read the knowledge file at `~/.claude/knowledge/confluence/confluence.md` before proceeding. When composing page content, follow `~/.claude/knowledge/writer.md` and select the persona from the table below.

Arguments: $ARGUMENTS

## Defaults

**Creation target**: Joe's personal space unless the user names a different one.

- Space key: `~61b7a02191c049006fa846ee`
- Space ID (numeric, required by v2 API): `2712174601`
- Owner account ID: `61b7a02191c049006fa846ee`

Any other space (`CP`, `NPI`, `PT`, etc.) is opt-in. If the user says "create a page about X" with no target, default to the personal space and surface the URL.

## Persona selection (from `~/.claude/knowledge/writer.md`)

Pick before writing. State the choice in one line at the top of your draft so the user can redirect.

| Content type | Persona |
|--------------|---------|
| Technical docs, API refs, READMEs, code explanations | The Engineer |
| ADRs, design docs, architecture docs, tradeoff analyses | The Architect |
| Strategy docs, analysis, product specs, roadmaps | The PM |
| Tutorials, onboarding, walkthroughs, getting started | The Educator |
| Landing pages, pitch decks, vision docs, blog posts | The Marketer |
| Release notes, changelogs | The Contributor |
| Error messages, UI copy, notifications, empty states | The UX Writer |

When a page has both strategic and technical halves (e.g. an overview + technical-details child), use the Architect on the parent and the Engineer on the child.

**Hard rules from the style guide:**
- No em dashes. Use commas, parentheses, or two sentences.
- No "it's worth noting", "powerful", "seamless", "delve", "at its core", "leverage", "utilize".
- Lead with the answer. Short paragraphs (3-4 sentences). Tables for comparisons, not prose.
- Have opinions; name tradeoffs.

## Examples

```
/confluence get page 4463984714
/confluence find pages titled "Payment Diagrams"
/confluence list children of 5353013302
/confluence create page titled "GA tracking notes"           # defaults to personal space
/confluence create child page under 4463984714 titled "Refunds runbook"
/confluence update page 4942233631 — append a section on retry semantics
/confluence add label "payments" to page 4598267923
/confluence start a P1 postmortem for OPSUC-2407 — checkout 500s
```

## Process

1. Verify auth: `$CONFLUENCE_AUTH_TOKEN` is base64 of `joevaldez@pplsi.com:<API_TOKEN>` from 1Password (`op://PPLSI/Confluence API Token/credential`). If 401, run `confluence-auth` in the shell to refresh.
2. Resolve the target. Creation defaults to the personal space above; reads/updates use the ID or title the user supplied.
3. Pick a persona from the table and announce it before drafting body content.
4. For updates, fetch current `version.number` first and submit `version.number + 1` in the PUT.
5. For complex storage-format payloads (tables, macros), write the JSON body to a temp file and pass with `curl -d @file` to avoid shell escaping bugs.
6. Report the page ID and a clickable `https://legalshield.atlassian.net/wiki/...` URL on success.

## When to defer to another skill

- **Release notes onboarding** for a repo → `/release-notes-onboard`. Wires up the workflow plus the per-repo Confluence parent under the Releases hub.
- **Jira ticket creation** referenced from a Confluence page → `/jira`. Embed the resulting key with the `jira` storage macro.
