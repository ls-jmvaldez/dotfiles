---
name: newrelic
description: Query New Relic for service health, error triage, and bug investigation across payment services and internal tooling. Read-only diagnostic skill — never makes deployments, rollbacks, or config changes.
argument-hint: "describe what to investigate"
model: sonnet
---

Your personal New Relic entry point. Auth is just the `newrelic` CLI profile (nothing to
inject), so this skill mostly defers to the `internal-tools` plugin's newrelic router, which
holds the NRQL catalog, NerdGraph recipes, interpretation thresholds, app registry, and bug
report template. Do not duplicate the plugin's routing here.

**This skill is read-only/diagnostic.** It queries observability data but never makes
deployments, rollbacks, or configuration changes.

Arguments: $ARGUMENTS

## 1. Verify auth

```bash
newrelic profile list >/dev/null 2>&1 && echo "profile present" || echo "no NR profile — see the plugin's troubleshooting.md"
```

NerdGraph recipes also need `NEW_RELIC_API_KEY` and `NEW_RELIC_ACCOUNT_ID` (a Personal API
Key, `NRAK-...`).

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
