---
name: standup
description: Generate a standup summary from Jira, GitHub, your Claude Code sessions, and New Relic. Reports tickets moved, PRs shipped, research you kicked off (with why/outcome), and int-membership-details health/anomalies over the last 24h. Saves a dated highlights doc to ~/Documents/standup-log each run for later yearly aggregation.
argument-hint: "[--since 3d] [--only coreapp1|opsuc|<repo>] [--no-log]"
model: sonnet
---

Your standup prep, assembled from four sources so you don't reconstruct it by hand. Read-only
against every source except the local highlights log (append-only). Coverage is **cross-team by
default** — everything you touched, grouped by repo/project, never filtered down to one team.

Arguments: $ARGUMENTS

## Arguments

- `--since=Nd` — rolling N-day window. Default: **since your last workday** (Monday reaches
  back to Friday; otherwise yesterday).
- `--only=coreapp1|opsuc|<repo>` — narrow to one team/repo. Off by default — nothing is dropped
  unless you ask.
- `--no-log` — print the summary but skip the highlights-log append.

## 1. Auth (owned here)

```bash
[ -z "$JIRA_AUTH_TOKEN" ] && export JIRA_AUTH_TOKEN="$(op read 'op://PPLSI/Jira - Base64/credential' 2>/dev/null)"
[ -z "$NEW_RELIC_API_KEY" ] && export NEW_RELIC_API_KEY="$(op read 'op://PPLSI/NewRelic CLI/credential' 2>/dev/null)"
export NEW_RELIC_ACCOUNT_ID="${NEW_RELIC_ACCOUNT_ID:-124794}"
[ -z "$JIRA_AUTH_TOKEN" ] && echo "no Jira token — run: op signin" || echo "jira ok"
[ -z "$NEW_RELIC_API_KEY" ] && echo "no NR key — run: op signin" || echo "nr ok"
gh auth status >/dev/null 2>&1 && echo "gh ok" || echo "gh not authed — run: gh auth login"
```

## 2. Resolve the plugin root once

```bash
ROOT=$(python3 -c "
import json, os
m = json.load(open(os.path.expanduser('~/.claude/plugins/installed_plugins.json')))
e = m['plugins'].get('internal-tools@legalshield-marketplace')
print(e[0]['installPath'] if e else '', end='')
")
echo "$ROOT"
```

If `$ROOT` is empty the plugin isn't installed — tell the user to run
`claude plugin install internal-tools@legalshield-marketplace` and stop.

## 3. Compute the window

`SKILL_DIR` is this skill's directory. Get the window start once and reuse it everywhere
(Jira `updated >=`, `gh --merged-at`, the session scan):

```bash
# Default: last workday. --since=Nd overrides.
WIN_START=$(python3 -c "
import datetime as dt, sys
now = dt.datetime.now().astimezone()
back = 3 if now.weekday()==0 else 1
print((now - dt.timedelta(days=back)).replace(hour=0,minute=0,second=0,microsecond=0).date())
")
echo "$WIN_START"   # e.g. 2026-07-08
```

When `--since=Nd` is passed, set `WIN_START=$(date -v-Nd +%F)` instead. Pass the same
`--since` straight through to `scan_sessions.py`.

## 4. Gather (run the independent queries together)

**Jira** — all projects (append `AND project = COREAPP1|OPSUC` only when `--only` names a team).
Follow `$ROOT/skills/jira/SKILL.md` for the search recipe (skip its auth — done in §1). JQL:

```
assignee = currentUser() AND updated >= "<WIN_START>" ORDER BY updated DESC
```

Pull `key, summary, status, issuetype, project` for each. Flag `Spike`-type or
`research`-labeled tickets — they feed the Research section.

**GitHub** — across all orgs/repos, no repo filter (unless `--only=<repo>`):

```bash
gh search prs --author=@me --merged --merged-at=">=$WIN_START" \
  --json repository,number,title,url --limit 50
gh search prs --author=@me --updated=">=$WIN_START" --state open \
  --json repository,number,title,url,state --limit 50
```

Extract `[PROJ-XXXX]` refs from titles (any project key) to cross-link with Jira.

**Research** — evidence from your own sessions, merged with Jira spikes:

```bash
python3 "$SKILL_DIR/scan_sessions.py" ${SINCE:+--since=$SINCE} ${ONLY:+--only=$ONLY}
```

Each task carries `repo`, `kind`, `title`, `why` (the prompt), and `outcome` (the agent's
result). Distill why/outcome to one line each. Dedupe against Jira spike tickets by repo/key.
Curate: collapse multi-step agent chains for one effort into a single line; drop pure
implementation grunt-work that isn't investigation.

**New Relic — `int-membership-details` (fixed daily review, last 24h)** — read
`$ROOT/skills/newrelic/SKILL.md` and its health + anomaly references, then report throughput,
error rate, latency p95/p99, and Apdex over the last 24h, plus error-group and deploy-marker
deltas vs the prior baseline. Defer all interpretation thresholds to the plugin. State
**"nothing anomalous"** explicitly when it's clean.

## 5. Synthesize (terminal markdown)

```
# Standup — <today>   (since <WIN_START>)

## Talking points
- 2–4 bullets you can read aloud

## Shipped / merged
- PR #NNN <title>  → PROJ-XXXX  (repo)

## In progress / in review
- PROJ-XXXX <summary> — <status>  [PR #NNN]

## Research
- <title> — why: <one line> · outcome: <one line>  (repo, source)

## int-membership-details — New Relic (last 24h)
- Health: throughput / error rate / p95 / Apdex
- Anomalies: <spikes/regressions/new error groups>   or   "nothing anomalous"
```

Group Jira by project and GitHub by repo. Cross-link PRs ↔ tickets via the title refs.

## 6. Save the day's highlights doc (unless `--no-log`)

Each run writes one dated highlights doc to `~/Documents/standup-log/`, named `YYYY-MM-DD.md`.
One doc per day: a same-day re-run **regenerates (overwrites)** that day's file with the fuller
picture. Because each doc is scoped to its own date, there's no cross-day double-logging to
guard against. This directory is the durable, user-owned record — concatenate a year of it
(`cat ~/Documents/standup-log/2026-*.md`) to build annual highlights.

```bash
DIR=~/Documents/standup-log
mkdir -p "$DIR"
DOC="$DIR/$(date +%F).md"
```

Write the day's highlights to `$DOC` (overwrite any existing same-day file). Highlights =
merged PRs, tickets moved to Done, completed research, resolved NR incidents. Keep each line
self-contained (name the PR/ticket, the repo, and the outcome) so a year of these aggregates
cleanly without needing the surrounding standup. **Capture impact when it's visible** —
adoption, latency/error deltas from the NR review, users or teams unblocked — because the
`/rollup --for=resume|promo` lenses build on it; what isn't logged can't be rolled up. Format:

```
# Standup Highlights — <today>

- Shipped: PR #NNN <title> (repo) → PROJ-XXXX
- Resolved: <NR incident one-liner>
- Research: <title> — <outcome one-liner>
```

Close the terminal output with: `Saved highlights to ~/Documents/standup-log/<today>.md`
(or `--no-log: highlights not written`).

## Integration

- Turn an NR anomaly into a bug ticket → `/jira`.
- Backfill hours on the tickets this surfaces → `/log-hours`.
- Schedule a daily run → `/schedule` or `/loop`.
