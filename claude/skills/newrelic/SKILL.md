---
name: newrelic
description: Query New Relic for service health, error triage, and bug investigation across payment services and internal tooling. Read-only diagnostic skill — never makes deployments, rollbacks, or config changes.
argument-hint: "describe what to investigate"
model: sonnet
---

Your personal New Relic entry point. It owns auth — the `newrelic` CLI profile for NRQL plus
injecting your NerdGraph API creds from 1Password — and otherwise defers to the
`internal-tools` plugin's newrelic router, which holds the NRQL catalog, NerdGraph recipes,
interpretation thresholds, app registry, and bug report template. Do not duplicate the
plugin's routing here.

**This skill is read-only/diagnostic.** It queries observability data but never makes
deployments, rollbacks, or configuration changes.

Arguments: $ARGUMENTS

## 1. Auth (this is the part that's yours)

NRQL / CLI queries (the bulk of this skill) run off the `newrelic` CLI profile, configured
once. Verify it:

```bash
newrelic profile list >/dev/null 2>&1 && echo "profile present" || echo "no NR profile — run: newrelic profile add ..."
```

NerdGraph recipes (error groups, service dependencies, alert violations) need API creds. The
plugin is vault-agnostic and won't inject them; do it here. If unset, pull the key from
1Password and set the account ID:

```bash
[ -z "$NEW_RELIC_API_KEY" ] && export NEW_RELIC_API_KEY="$(op read 'op://PPLSI/NewRelic CLI/credential' 2>/dev/null)"
export NEW_RELIC_ACCOUNT_ID="${NEW_RELIC_ACCOUNT_ID:-124794}"
[ -z "$NEW_RELIC_API_KEY" ] && echo "no NR API key — run: op signin (or nr-auth)" || echo "NerdGraph creds present"
```

## 2. Resolve the plugin root

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

## 3. Follow the plugin's router

Read `$ROOT/skills/newrelic/SKILL.md` and follow it exactly, treating every
`${CLAUDE_PLUGIN_ROOT}` in that file (and the references it points to) as `$ROOT`. It covers
my teams (OpSuccess + Internal Tools), dynamic app discovery, the per-workflow reference
routing (health / triage / deep-dive / reader / frontend / marketing / tracing / checkout),
interpretation thresholds, and the bug-report template.

## Integration

- Create bug tickets from a report → `/jira`.
- Investigate code paths after identifying the repo from a stack trace → `/debug`.
