---
name: confluence
description: Execute Confluence operations against legalshield.atlassian.net (read, create, update, search pages; attachments; comments). Defaults to Joe's personal space for creation unless an org space is named.
argument-hint: "Confluence operation to perform"
model: sonnet
---

Your personal Confluence entry point. It owns two things — injecting auth from 1Password and
your personal-space default — and otherwise defers to the `internal-tools` plugin's
confluence router so the team's page/postmortem standard stays the single source of truth.
Do not duplicate the plugin's routing here.

Arguments: $ARGUMENTS

## 1. Auth (this is the part that's yours)

The plugin is vault-agnostic and will not inject a token. Do it here, mirroring your
`confluence-auth` shell function: read the raw Atlassian API token from 1Password and
base64-encode `email:token` into `$CONFLUENCE_AUTH_TOKEN`. If it's unset:

```bash
if [ -z "$CONFLUENCE_AUTH_TOKEN" ]; then
  ATLASSIAN_EMAIL='joevaldez@pplsi.com'
  ATLASSIAN_TOKEN="$(op-cached 'op://PPLSI/Confluence API Token/credential' 2>/dev/null)"
  [ -n "$ATLASSIAN_TOKEN" ] && export CONFLUENCE_AUTH_TOKEN="$(printf '%s:%s' "$ATLASSIAN_EMAIL" "$ATLASSIAN_TOKEN" | base64 | tr -d '\n')"
fi
[ -z "$CONFLUENCE_AUTH_TOKEN" ] && echo "no token — run: op signin (or confluence-auth)" || \
curl -sS -o /dev/null -w "%{http_code}\n" -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  "https://legalshield.atlassian.net/wiki/api/v2/spaces?limit=1"
# 200 = ok. Use the token directly in Authorization: Basic — never re-base64 it, never curl -u.
```

## 2. Personal creation default (also yours)

When the user says "create a page" with no space, default to **Joe's personal space** and
surface the URL:

- Space key: `~61b7a02191c049006fa846ee`
- Space ID (numeric, required by v2 API): `2712174601`
- Owner account ID: `61b7a02191c049006fa846ee`

Any other space (`CP`, `NPI`, `PT`, …) is opt-in by name.

## 3. Resolve the plugin root

`${CLAUDE_PLUGIN_ROOT}` only resolves inside the plugin, so resolve the install path from
the manifest (version-stamped — never hardcode it):

```bash
ROOT=$(python3 -c "
import json, os
m = json.load(open(os.path.expanduser('~/.claude/plugins/installed_plugins.json')))
e = m['plugins'].get('internal-tools@legalshield-marketplace')
print(e[0]['installPath'] if e else '', end='')
")
echo "$ROOT"
```

If `$ROOT` is empty, the plugin isn't installed. Tell the user to run
`claude plugin install internal-tools@legalshield-marketplace` and stop.

## 4. Before any page create: duplicate check

Run this before calling `POST /api/v2/pages`, for any status (current or draft). It prevents
duplicate drafts caused by timeout retries where the create succeeded server-side but the
response was lost. Read `references/drafts.md` for the full draft API reference.

```bash
SPACE_KEY="~61b7a02191c049006fa846ee"  # swap for target space
TITLE_ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$TITLE")

# Drafts — v2 space-pages does NOT list drafts; v1 required
DRAFTS=$(curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  "https://legalshield.atlassian.net/wiki/rest/api/content?spaceKey=$SPACE_KEY&status=draft&type=page&title=$TITLE_ENC&limit=50")

# Current pages
CURRENT=$(curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  "https://legalshield.atlassian.net/wiki/rest/api/content?spaceKey=$SPACE_KEY&status=current&type=page&title=$TITLE_ENC&limit=50")

echo "Drafts:"; echo "$DRAFTS" | python3 -I -c "import json,sys; [print(f'  id={r[\"id\"]}  {r[\"title\"]}  status={r[\"status\"]}') for r in json.load(sys.stdin).get('results',[])]"
echo "Current:"; echo "$CURRENT" | python3 -I -c "import json,sys; [print(f'  id={r[\"id\"]}  {r[\"title\"]}  status={r[\"status\"]}') for r in json.load(sys.stdin).get('results',[])]"
```

**Decision rules:**

| Lookup result | Action |
|---|---|
| No matches | Proceed to create. |
| Match(es) exist | Report every ID and URL. Do NOT create. If the caller asked to update, update the existing page. Otherwise stop and ask. |
| After a create error or timeout | Re-run this lookup before retrying — the create may have landed. |
| After a successful create | Re-run this lookup. Confirm exactly one result. Report every ID found. |

## 5. Follow the plugin's router

Read `$ROOT/skills/confluence/SKILL.md` and follow it exactly, with three substitutions:

- Treat every `${CLAUDE_PLUGIN_ROOT}` in that file (and the references it points to) as `$ROOT`.
- Skip its auth step — you already did auth in section 1.
- For the creation default, use Joe's personal space from section 2 instead of the generic "the user's personal space."

That router handles progressive loading (reading vs writing vs storage-format vs postmortem),
the persona selection from `$ROOT/knowledge/writer/`, and the response checklist. You inherit
it; you do not copy it.

## Examples

```
/confluence get page 4463984714
/confluence find pages titled "Payment Diagrams"
/confluence list children of 5353013302
/confluence create page titled "GA tracking notes"           # defaults to personal space
/confluence create child page under 4463984714 titled "Refunds runbook"
/confluence update page 4942233631 — append a section on retry semantics
/confluence start a P1 postmortem for OPSUC-2407 — checkout 500s
```

## When to defer to another skill

- **Release notes onboarding** for a repo → `/release-notes-onboard`.
- **Jira ticket creation** referenced from a page → `/jira`. Embed the key with the `jira` storage macro.
