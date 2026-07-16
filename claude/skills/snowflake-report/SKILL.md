---
name: snowflake-report
description: Ad-hoc Snowflake reporting from any directory — query one of the snowflake-streamlit-apps dashboards using its own SQL helpers (so numbers match what's on screen), or run arbitrary read-only SQL against anything else in Snowflake. Read-only; guards against accidental full scans of known-huge GA views.
argument-hint: "describe what to query, e.g. 'membership dashboard adoption last 30 days' or a table/view name"
model: sonnet
---

Personal Snowflake reporting skill. Two paths depending on what's being asked:

- **A known dashboard/app** ("the membership dashboard", "elle intake") → import that
  app's own `config.py`/`ga.py` helpers and build the query the same way its Streamlit
  page does, so the numbers match the dashboard exactly. See **Known sources** below.
- **Anything else** (a table name, a one-off question, "what does X look like in
  Snowflake") → run raw SQL through `scripts/run_query.py`, which handles auth, safety
  checks, and parallel execution for you.

This skill is self-contained (its own venv) — it works from any cwd, not just inside
`snowflake-streamlit-apps`.

Arguments: $ARGUMENTS

## 1. One-time bootstrap

```bash
SKILL_DIR="$HOME/.claude/skills/snowflake-report"
if [ ! -x "$SKILL_DIR/.venv/bin/python" ]; then
  python3.11 -m venv "$SKILL_DIR/.venv"
  "$SKILL_DIR/.venv/bin/pip" install --quiet \
    snowflake-snowpark-python "snowflake-connector-python[pandas,secure-local-storage]" pandas
fi
```

The `secure-local-storage` extra installs `keyring`, which caches the SSO id token —
without it, **every new process** re-prompts a full browser login. The `pandas` extra
pulls in `pyarrow`, which the connector's `fetch_pandas_all()` needs even though `pandas`
itself is already installed separately — omitting it fails every `.result("pandas")` call
with a `255002` pandas-not-installed error that's misleading about the real missing package.

## 2. Auth

Credentials live in `~/.streamlit/secrets.toml` (the same file the snowflake-streamlit-apps
repo's local-dev fallback reads), under a `[snowflake]` section — typically Okta
external-browser SSO. **Never read or print this file's contents**; only `connect.py`
touches it.

**First query of a session will likely pop a browser window** for SSO approval. The
harness's foreground tool calls time out at 2 minutes, which is often not enough time
for a human to notice and click through the popup — so **run the first query of a
session with `run_in_background: true`**, then read its output file once it completes.
Subsequent queries in the same session reuse the cached token and return fast.

Sanity check the connection:

```bash
"$HOME/.claude/skills/snowflake-report/.venv/bin/python" \
  "$HOME/.claude/skills/snowflake-report/scripts/run_query.py" --sql "SELECT CURRENT_VERSION()"
```

## 3. Querying a known dashboard/app

Don't hand-roll SQL against a dashboard's GA view from scratch — import the app's own
helpers so the result matches what's on screen (session-key construction, host-based
app attribution, percentile-over-completed-only, etc. are all non-obvious and already
solved there). Pattern:

```python
import sys, tomllib
sys.path.insert(0, "/Users/valdezjm/Public/source/snowflake-streamlit-apps/apps/<app>")
from snowflake.snowpark import Session
from config import GA_VIEW, ...          # app-specific constants
from ga import param, host_expr, app_label_case, app_scoped_where, session_expr  # shared SQL helpers

with open("/Users/valdezjm/.streamlit/secrets.toml", "rb") as f:
    cfg = tomllib.load(f)["snowflake"]
s = Session.builder.configs(cfg).create()
# build query with the imported helpers, s.sql(q).collect_nowait() for parallel fetches,
# job.result("pandas") to gather — mirrors each page's own fetch_* function.
```

Write this as a throwaway script in the scratchpad directory (not in the app repo), run
it with the *app's own* venv if it has snowpark installed (`apps/../../.venv`), or with
this skill's venv — either works since both have snowpark installed.

### Known sources

| Ask about | Repo path | Data source | Notes |
|---|---|---|---|
| Membership / int-membership-details dashboard | `snowflake-streamlit-apps/apps/membership-ga-analytics` | `GARD_DB.GARD_SCHEMA.ANALYTICS_INTRADAY_287967785__VIEW` (GA4 property 287967785) | INTRADAY-named but full history (~790M rows, back to 2021-11-30). App attribution is by **hostname**, not the `app_name` param — see that app's `ga.py`/`CLAUDE.md`. |
| elle-intake-agent / elle-feature-analysis | `snowflake-streamlit-apps/apps/elle-intake-agent`, `.../elle-feature-analysis` | GA4 property 411123695 (FRESH view — different table naming than membership's) | Different property from membership — don't reuse its table name or taxonomy assumptions. |
| General service/ops data | — | `ODS.PROD.*` tables (e.g. `ODS.PROD.SERVICE_REQUESTS`) | Fully-qualified names; no special helpers, just query directly via `run_query.py`. |

Extend this table as new apps/sources come up — it's the whole point of keeping this
skill personal and living outside any one repo.

## 4. Querying anything else

```bash
PY="$HOME/.claude/skills/snowflake-report/.venv/bin/python"
RQ="$HOME/.claude/skills/snowflake-report/scripts/run_query.py"

# single query, printed as a table
"$PY" "$RQ" --sql "SELECT COUNT(*) FROM ODS.PROD.SERVICE_REQUESTS WHERE created_date >= DATEADD('day', -7, CURRENT_DATE)"

# multiple queries in parallel, saved as CSV
"$PY" "$RQ" --sql-file q1.sql --sql-file q2.sql --format csv --out /tmp/results
```

`run_query.py` is **read-only by default** — it refuses anything that isn't a
`SELECT`/`WITH` statement (`--allow-write` overrides, only if truly intentional; this
skill has no business running DML/DDL). It also refuses queries against known-huge GA
views (`ANALYTICS_INTRADAY_*__VIEW`, `ANALYTICS_FRESH_*__VIEW`) that have no visible
`WHERE` clause, since those hold full history, not a recent window — `--force` overrides
if a full scan is genuinely intended.

## 5. Query pattern crib sheet

Lifted from `membership-ga-analytics/ga.py` — generalize these when querying similar
event-flattened / session-grain data elsewhere:

- **Session key** (GA4's `ga_session_id` collides across users): `user_pseudo_id || '-' || ga_session_id`.
- **Flattened event param**: `EVENT_PARAMS__FLATTENED:<key>::<type>` (no `LATERAL FLATTEN`).
- **Percentile over "completed" rows only**: `PERCENTILE_CONT(p) WITHIN GROUP (ORDER BY IFF(success = 'true', duration_ms, NULL))` — cancels/errors shouldn't drag down a latency percentile.
- **Ordered funnel** (event A must precede event B within a window, same session): a window `MAX(...) OVER (PARTITION BY session ORDER BY ts ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)` to find the last qualifying prior event, then `DATEDIFF` against it — plain co-occurrence in a session overstates funnels.
- **Rating/bucket distribution with a floor**: `QUALIFY SUM(COUNT(*)) OVER (PARTITION BY <slice>) >= <min_samples>` — floors the whole slice, not individual small rows within it (which would distort the distribution).

## 6. Output

Default to `--format table` printed inline for quick looks. Use `--format csv`/`json`
with `--out` when the result should feed further analysis (e.g. a scratchpad file another
script reads) or is too wide/long to read comfortably as printed text.

## Notes

- This skill queries; it never writes, deploys, or changes anything in Snowflake.
- If a query needs a role/warehouse switch, add `USE ROLE ...` / `USE WAREHOUSE ...` as a
  separate statement before the real query — `run_query.py` runs each `--sql`/`--sql-file`
  independently, so session-level `USE` statements won't carry across separate
  invocations; put them in the same file/string as the query if needed in one shot.
