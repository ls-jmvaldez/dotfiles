---
name: render-sql-template
description: Render a SQL file with placeholder substitution (e.g. `{channel}`, `{region}`, `{date}`), preview the rendered SQL, and optionally execute it. Use this instead of editing the SQL file to hardcode a value for debugging — that habit causes near-misses where the hardcode gets pushed. Works with any project that uses Python-style `{name}` templating in `.sql` files (common in Streamlit/Dash apps, Airflow tasks, dbt-free data pipelines).
---

# render-sql-template

SQL files in data apps often use Python `str.format`-style placeholders like `'{channel}'` or `'{start_date}'`, substituted at runtime by the calling code. When debugging, the temptation is to edit the file and hardcode a value — but that change is easy to forget and dangerous to commit.

This skill substitutes placeholders **without modifying the file** and shows the rendered SQL.

## Inputs to gather

- **SQL file path**. If the user gives just a filename, grep for it under common locations (`sql/`, `queries/`, `apps/*/sql/`).
- **Placeholder values.** Scan the file for `{name}` placeholders and ask for any unspecified. Don't assume defaults — the wrong default produces a confidently-wrong result.
- **Whether to execute** or just preview. Default to preview-only — ask before running.

## Rendering

1. Read the SQL file.
2. Identify all `{name}` placeholders with a regex like `\{([a-zA-Z_]\w*)\}`. Flag anything ambiguous (rare, but SQL strings with literal `{}` can appear in JSON-handling queries — treat with care).
3. Substitute via Python: `sql.format(**values)`.
4. Print the rendered SQL in a fenced ```sql block so the user can copy it.

## Executing (only if requested)

Detect the project's connection pattern by reading the entry-point file (`streamlit_app.py`, `app.py`, etc.) or any existing `conftest.py` / `db.py`. Common patterns:
- Snowflake Snowpark: `get_active_session()` with a `secrets.toml` fallback to `Session.builder.configs(...)`.
- SQLAlchemy: an engine factory.
- Raw driver: `psycopg2.connect`, `snowflake.connector.connect`, etc.

Match what the project already uses. For one-off CLI runs, write a small temp script in a scratch location (not in the repo tree) that:
1. Builds a session/connection using the project's existing pattern.
2. Runs the query and captures results into a dataframe.
3. Prints `head(20)` and the row count.

**Never** write the rendered SQL back to the original file. **Never** commit a substituted version of a SQL template.

## Safety checks before executing

- Confirm the query is SELECT-only. Refuse to execute `INSERT`, `UPDATE`, `DELETE`, `CREATE`, `DROP`, `MERGE`, `TRUNCATE`, `ALTER` without explicit user confirmation naming the destructive verb.
- Warn if the query lacks a date filter on what looks like a large fact table — those scans get expensive on Snowflake/BigQuery.
- Note current warehouse/database/role if visible, so the user can sanity-check they're hitting the right environment (prod vs dev).

## Output

For preview-only:

```
Rendered SQL (channel=Primerica, start_date=2026-05-01):
```sql
...rendered query...
```
```

For execute:
- Rendered SQL block (as above)
- Row count
- First 20 rows as a markdown table
- Any warnings (full table scan, slow query, unexpected null counts, etc.)

## When NOT to use this skill

- If the user wants to permanently change the SQL (e.g. switch which value a query targets in production), edit the file normally — don't use this skill as a substitute for a real change.
- If the user is running the app locally and the app already substitutes the placeholder, just run the app — don't duplicate that work.
- For queries that don't use `{name}` templating at all (raw `.sql` files, dbt models with Jinja, etc.), this skill doesn't apply.
