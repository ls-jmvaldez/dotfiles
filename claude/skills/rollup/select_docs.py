#!/usr/bin/env python3
"""Select and concatenate the dated standup-highlights docs for a rollup.

Reads ~/Documents/standup-log/YYYY-MM-DD.md (written by /standup) and prints the matching
docs for a range so the rollup skill can synthesize them. Keeps all the date filtering and
glob-empty edge cases out of the shell.

Ranges (pick one; default = all-time):
  --year=YYYY     one calendar year
  --month=YYYY-MM one month
  --since=Nd      the last N days
"""

import argparse
import datetime as dt
import glob
import os
import re
import sys

LOG_DIR = os.path.expanduser("~/Documents/standup-log")
NAME_RE = re.compile(r"^(\d{4})-(\d{2})-(\d{2})\.md$")


def matching(year, month, since):
    docs = []
    for path in glob.glob(os.path.join(LOG_DIR, "*.md")):
        m = NAME_RE.match(os.path.basename(path))
        if not m:
            continue
        date = os.path.basename(path)[:-3]  # YYYY-MM-DD
        if year and not date.startswith(f"{year}-"):
            continue
        if month and not date.startswith(f"{month}-"):
            continue
        if since:
            n = int(since[:-1]) if since.endswith("d") else int(since)
            cutoff = (dt.date.today() - dt.timedelta(days=n)).isoformat()
            if date < cutoff:
                continue
        docs.append((date, path))
    return sorted(docs)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--year")
    g.add_argument("--month")
    g.add_argument("--since")
    args = ap.parse_args()

    if not os.path.isdir(LOG_DIR):
        print("no highlights logged yet — run /standup first")
        return

    docs = matching(args.year, args.month, args.since)
    if not docs:
        print("no highlights docs match that range")
        return

    dates = [d for d, _ in docs]
    print(f"# rollup input: {len(docs)} docs, {dates[0]} → {dates[-1]}\n")
    for _, path in docs:
        with open(path, encoding="utf-8") as fh:
            print(fh.read().rstrip())
        print("\n---\n")


if __name__ == "__main__":
    main()
