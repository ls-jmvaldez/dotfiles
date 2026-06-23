---
name: trace-number
description: Trace a value shown in a data app (Streamlit, dashboard, report) back through application code and SQL to its source tables. Produces a top-down lineage report covering CTEs, joins, date windows, and any in-app transformations (adjustments, sign flips, subtractions). Use when reconciling a number on screen with a number the user computed by hand, when a stakeholder asks "where does X come from", or when two numbers that should agree don't.
---

# trace-number

Walk a displayed value back to its source. The user will name a label they see in a UI (or paste a screenshot). Your job is to produce a clear lineage report from the render site down to the warehouse.

This skill is data-app-agnostic — it works for Streamlit, Dash, Jupyter dashboards, BI tool extracts, or any code path that reads SQL → transforms in Python/another language → renders. Adapt the steps to whatever stack you're in.

## Inputs to gather

Before tracing, confirm:
- **Which app / file** is rendering the value? If unclear, default to the most recently edited entry point.
- **Which label/value**? Exact UI text is best (e.g. "Forecast total in the daily-units table footer").
- **Any filter context** that affects the value (channel, region, date range, user role).

If any are ambiguous, ask before tracing — don't guess.

## Tracing procedure

1. **Find the render site.** Grep the entry-point file for the label string, the column header, or a nearby unique fragment. Note the line that emits the value (`st.metric`, `st.dataframe`, `print`, template render, etc.).
2. **Walk the variable backward.** For each intermediate variable, find its assignment. Record any:
   - Arithmetic (multiplications by adjustment factors, sums, subtractions).
   - Column extractions from a dataframe — note which dataframe and which column.
   - Conditional branches (channel-specific logic, null-coalescing, fallback paths).
   - Caching boundaries (`@st.cache_data`, memoization) — note them, since a stale cache can cause a "wrong number" that isn't really a code bug.
3. **Identify the SQL source.** Each dataframe traces back to a loader function and a SQL file or inline query. Open that SQL.
4. **Read the SQL.** Walk the CTEs top-down. Note:
   - Which tables are read (fully-qualified names).
   - Date windows — especially boundaries like "month-start through yesterday" vs "through today", inclusive/exclusive `BETWEEN`, and timezone assumptions.
   - Filters (channel, status, type).
   - Joins, unions, or `qualify` clauses that combine multiple sources (a common reconciliation gotcha is one CTE supplying actuals and another supplying forecast under the same column name).
5. **Watch for sign flips and double-counting.** Reductions to a base metric are sometimes represented as negative values in the source data (e.g. cancellations, returns, non-takens). If the same concept is also subtracted later in code, you may be double-counting. Flag both occurrences.
6. **Note placeholder substitution.** If the SQL has `{name}` placeholders, identify what value is being passed and whether it could differ from the user's mental model.

## Output format

Produce a numbered chain, top-down from UI to warehouse, with file paths and line numbers at each step:

```
1. UI label "<label>" → <entry_file>:<line> → variable `<name>`
2. `<name>` = <expression>   [<file>:<line>]
3. `<intermediate>` from <dataframe>, column <COLUMN>
4. <dataframe> is loaded from <sql_file_or_inline>
5. <sql_file> CTEs:
     - <cte_1>: <one-line description>, reads <table>, date range <range>
     - <cte_2>: ...
6. Final select combines <cte_1> + <cte_2> via <union/join>
```

End with a **Reconciliation notes** section that calls out:
- Any two data sources that could plausibly disagree (different forecast tables, different actuals tables, different time grains).
- Adjustments applied in code that wouldn't appear in a SQL-only audit (multiplicative factors, subtractions, NTK/cancellation accounting).
- Date-window boundaries that commonly surprise people (excludes today, fiscal vs calendar, UTC vs local).
- Caching that could be serving stale data.

## When NOT to use this skill

- If the user just wants the SQL behind a number, point them at the file — don't write a full lineage report.
- For one-off ad-hoc queries (notebooks, scratch scripts), this is overkill.
- If the answer is obvious from one grep, just answer.
