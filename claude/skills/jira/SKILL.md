---
name: jira
description: Execute Jira operations (create stories, search issues, manage sprints)
argument-hint: "Jira operation to perform"
model: sonnet
---

Your personal Jira entry point. It owns one thing — injecting auth from 1Password —
and otherwise defers to the `internal-tools-jira` plugin's router so the team's ticket
contract (structure, persona split, custom fields, CAPEX rules) stays the single source
of truth. Do not duplicate the plugin's routing here.

Arguments: $ARGUMENTS

## 1. Auth (this is the part that's yours)

The plugin is vault-agnostic and will not inject a token. Do it here. If
`$JIRA_AUTH_TOKEN` is unset, export it from 1Password, then verify:

```bash
[ -z "$JIRA_AUTH_TOKEN" ] && export JIRA_AUTH_TOKEN="$(op read 'op://PPLSI/Jira - Base64/credential' 2>/dev/null)"
[ -z "$JIRA_AUTH_TOKEN" ] && echo "no token — run: op signin, or export JIRA_AUTH_TOKEN manually" || echo "token present"
```

## 2. Resolve the plugin root

`${CLAUDE_PLUGIN_ROOT}` only resolves inside the plugin, so resolve the install path
from the manifest (it's version-stamped — never hardcode it):

```bash
ROOT=$(python3 -c "
import json, os
m = json.load(open(os.path.expanduser('~/.claude/plugins/installed_plugins.json')))
e = m['plugins'].get('internal-tools-jira@legalshield-marketplace')
print(e[0]['installPath'] if e else '', end='')
")
echo "$ROOT"
```

If `$ROOT` is empty, the plugin isn't installed. Tell the user to run
`claude plugin install internal-tools-jira@legalshield-marketplace` and stop.

## 3. Follow the plugin's router

Read `$ROOT/skills/jira/SKILL.md` and follow it exactly, with two substitutions:

- Treat every `${CLAUDE_PLUGIN_ROOT}` in that file (and in the references it points to)
  as `$ROOT`.
- Skip its auth step — you already did auth in section 1.

That router handles progressive loading (one reference per operation), the
Engineer-prose / QA-Tester-AC persona split, the custom-field registry, and all
create/read/update/search/transition/comment/link/sprint recipes. You inherit it; you
do not copy it.

## Project flag

Resolve the active project: flag (`--coreapp1`, `--opsuc`) > `$JIRA_PROJECT` > default
`COREAPP1`. The flag is case-insensitive:

- `--opsuc` → OPSUC (Gold Diggers)
- `--coreapp1` → COREAPP1 (Internal Tools)

Pass the resolved project through to the plugin router; board/issue-type/sprint IDs live
in `$ROOT/skills/jira/references/fields.md`.

## Examples

```
/jira create a story called "Fix payment bug" under epic OPSUC-2260 --opsuc
/jira --opsuc list open bugs assigned to me
/jira search for stories under epic COREAPP1-3116
/jira --coreapp1 add subtasks to COREAPP1-3280
```
