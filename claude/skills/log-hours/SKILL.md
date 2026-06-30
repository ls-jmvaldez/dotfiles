---
name: log-hours
description: Backfill estimated work hours onto your assigned Jira tickets. Scopes to a project + lookback window + worked statuses, logs subtask hours that roll up to parents, fills only zero-hour tickets, and backdates each worklog to when the work shipped. Defaults to a dry-run preview.
argument-hint: "[--project COREAPP1] [--days 60] [--apply]"
model: sonnet
---

Periodically log estimated hours onto Jira tickets assigned to you. This is a
timekeeping backfill, not a planning or execution task — it runs on its own cadence
(point `/schedule` or `/loop` at it for a weekly run).

Arguments: $ARGUMENTS

## What it does

For every issue assigned to you in the project, updated within the lookback window,
sitting in a **worked** status (default: `Done`, `IN UAT STATUS`, `Code Review`,
`QA In progress`):

- **Fills only zeros.** Tickets that already have logged time are left untouched — no double-logging.
- **Logs on the leaf.** Parent stories with subtasks get nothing directly; their
  subtasks are logged and Jira rolls the total up to the parent (`aggregatetimespent`).
  Epics are skipped — they aggregate from children.
- **Estimates by issue type**, calibrated to the team's existing logs. Defaults:
  Story 4h, Sub-task 2h, Bug 4h, New Feature 5h, Improvement 5h, Spike 4h,
  Task (Dev Work) 3h, Task (Non Dev Work) 2h, Refactor 3h. Unknown types fall back to 3h.
- **Backdates** each worklog to the ticket's resolution date (or last-updated if
  unresolved), so hours spread across the window instead of dumping on today.
- **Skips grooming/blocked.** Anything outside the worked-status allowlist (Needs
  Grooming, GROOMED, BLOCKED, backlog) is left alone.

## Auth (the part that's yours)

The script reads `JIRA_AUTH_TOKEN` from the environment. Export it from 1Password first:

```bash
[ -z "$JIRA_AUTH_TOKEN" ] && export JIRA_AUTH_TOKEN="$(op read 'op://PPLSI/Jira - Base64/credential' 2>/dev/null)"
[ -z "$JIRA_AUTH_TOKEN" ] && echo "no token — run: op signin, or export JIRA_AUTH_TOKEN manually" || echo "token present"
```

## Run it

Default is a **dry run** — it prints exactly what it would log and totals, changing nothing.
Review the preview, then re-run with `--apply`.

```bash
# preview
python3 "$HOME/.claude/skills/log-hours/scripts/log_hours.py" --project COREAPP1 --days 60

# commit the worklogs
python3 "$HOME/.claude/skills/log-hours/scripts/log_hours.py" --project COREAPP1 --days 60 --apply
```

Tuning flags:

- `--days N` — lookback window (default 60).
- `--project KEY` — Jira project key (default COREAPP1).
- `--hours Story=6,Bug=3` — override per-type estimates for this run.
- `--statuses "Done,Code Review"` — override the worked-status allowlist.

After `--apply`, the script re-reads every parent that has subtasks and prints its
rolled-up total so you can confirm the rollup landed.

## Notes

- Worked-status names are **instance-specific** (this Jira uses `IN UAT STATUS`,
  `QA In progress`, etc.). If a status is renamed, update the default in the script or
  pass `--statuses`.
- Hours live on subtasks for stories that have them; a parent's *own* `timeSpent` stays
  empty by design — reports must read `aggregatetimespent`.
