#!/usr/bin/env python3
"""Run one or more read-only Snowflake queries and print/save the results.

Read-only by design: refuses anything that isn't a SELECT/WITH statement unless
--allow-write is passed explicitly. Multiple --sql/--sql-file args run in parallel
via collect_nowait(), matching the pattern the snowflake-streamlit-apps repo's own
pages use for multi-query fetches.

Examples:
    run_query.py --sql "SELECT CURRENT_VERSION()"
    run_query.py --sql-file a.sql --sql-file b.sql --format csv --out /tmp/out
    run_query.py --sql "SELECT * FROM GARD_DB.GARD_SCHEMA.ANALYTICS_INTRADAY_287967785__VIEW" --force
"""

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from connect import get_session  # noqa: E402

READ_ONLY_RE = re.compile(r"^\s*(--.*\n|\s)*\b(SELECT|WITH)\b", re.IGNORECASE)

# Objects known to be huge / full-history — a query against them with no visible
# WHERE clause is almost certainly an accidental full scan, not an intentional one.
LARGE_OBJECT_PATTERNS = [
    re.compile(r"ANALYTICS_INTRADAY_\d+__VIEW", re.IGNORECASE),
    re.compile(r"ANALYTICS_FRESH_\d+__VIEW", re.IGNORECASE),
]


def load_queries(args) -> list[str]:
    queries = list(args.sql or [])
    for path in args.sql_file or []:
        queries.append(Path(path).read_text())
    if not queries:
        sys.exit("No query given — pass --sql or --sql-file (one or more).")
    return queries


def check_safety(sql: str, allow_write: bool, force: bool) -> None:
    if not allow_write and not READ_ONLY_RE.match(sql):
        sys.exit(
            "Refusing: doesn't look like a SELECT/WITH statement. "
            "Pass --allow-write if this is intentional (e.g. a CTE-only read wrapped oddly)."
        )
    if not force:
        for pat in LARGE_OBJECT_PATTERNS:
            if pat.search(sql) and "where" not in sql.lower():
                sys.exit(
                    f"Refusing: query touches a known-large object ({pat.pattern}) with no "
                    "visible WHERE clause — this view holds full history (hundreds of millions "
                    "of rows), not just a recent window. Add a date filter, or pass --force to "
                    "run it anyway."
                )


def emit(df, fmt: str, out: str | None, label: str) -> None:
    if fmt == "table":
        print(f"\n=== {label} ({len(df)} rows) ===")
        with __import__("pandas").option_context("display.max_rows", 50, "display.width", 200):
            print(df)
    elif fmt == "csv":
        text = df.to_csv(index=False)
        if out:
            Path(out).write_text(text)
            print(f"{label}: wrote {len(df)} rows to {out}")
        else:
            print(f"\n=== {label} ===")
            print(text)
    elif fmt == "json":
        text = df.to_json(orient="records", date_format="iso")
        if out:
            Path(out).write_text(text)
            print(f"{label}: wrote {len(df)} rows to {out}")
        else:
            print(f"\n=== {label} ===")
            print(text)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sql", action="append", help="inline SQL (repeatable for parallel queries)")
    ap.add_argument("--sql-file", action="append", help="path to a .sql file (repeatable)")
    ap.add_argument("--format", choices=["table", "csv", "json"], default="table")
    ap.add_argument("--out", help="write output here (single query only; for multiple, use a prefix)")
    ap.add_argument("--allow-write", action="store_true", help="permit non-SELECT statements")
    ap.add_argument("--force", action="store_true", help="skip the large-object date-filter guard")
    args = ap.parse_args()

    queries = load_queries(args)
    for q in queries:
        check_safety(q, args.allow_write, args.force)

    session = get_session()
    jobs = [session.sql(q).collect_nowait() for q in queries]
    for i, (q, job) in enumerate(zip(queries, jobs)):
        df = job.result("pandas")
        df.columns = [c.lower() for c in df.columns]
        out = args.out
        if out and len(queries) > 1:
            out = f"{out}.{i}"
        emit(df, args.format, out, label=f"query {i + 1}/{len(queries)}")
    session.close()


if __name__ == "__main__":
    main()
