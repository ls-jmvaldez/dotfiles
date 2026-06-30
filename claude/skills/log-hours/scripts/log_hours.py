#!/usr/bin/env python3
"""Backfill estimated work hours onto assigned Jira tickets.

Dry-run by default. Pass --apply to actually create worklogs.
Reads JIRA_AUTH_TOKEN (base64 of email:api-token) from the environment.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime

BASE = "https://legalshield.atlassian.net/rest/api/3"

# Worked statuses: work has actually started. Grooming/blocked/backlog are excluded.
# These names are instance-specific — override with --statuses if they get renamed.
DEFAULT_WORKED = ["Done", "IN UAT STATUS", "Code Review", "QA In progress"]

# Per-type estimates (hours), calibrated to the team's existing logs.
DEFAULT_ESTIMATES = {
	"Story": 4,
	"Sub-task": 2,
	"Bug": 4,
	"New Feature": 5,
	"Improvement": 5,
	"Spike": 4,
	"Task (Dev Work)": 3,
	"Task (Non Dev Work)": 2,
	"Refactor": 3,
}
FALLBACK_HOURS = 3


def req(token, url, method="GET", body=None):
	data = json.dumps(body).encode() if body is not None else None
	r = urllib.request.Request(
		url,
		data=data,
		method=method,
		headers={"Authorization": f"Basic {token}", "Content-Type": "application/json"},
	)
	try:
		with urllib.request.urlopen(r) as resp:
			raw = resp.read()
			return resp.status, (json.loads(raw) if raw else None)
	except urllib.error.HTTPError as e:
		return e.code, e.read().decode()


def started_from(fields):
	"""Worklog 'started' = resolution date, else last-updated. Jira's required format."""
	s = fields.get("resolutiondate") or fields.get("updated")
	dt = datetime.strptime(s[:23], "%Y-%m-%dT%H:%M:%S.%f")
	return dt.strftime("%Y-%m-%dT%H:%M:%S.000+0000")


def parse_overrides(raw):
	out = {}
	for pair in raw.split(","):
		if not pair.strip():
			continue
		k, v = pair.split("=", 1)
		out[k.strip()] = int(v.strip())
	return out


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--project", default="COREAPP1")
	ap.add_argument("--days", type=int, default=60)
	ap.add_argument("--apply", action="store_true", help="actually log; omit for dry run")
	ap.add_argument("--hours", default="", help="per-type overrides, e.g. Story=6,Bug=3")
	ap.add_argument("--statuses", default="", help="comma-separated worked-status allowlist")
	args = ap.parse_args()

	token = os.environ.get("JIRA_AUTH_TOKEN")
	if not token:
		sys.exit("JIRA_AUTH_TOKEN not set — export it from 1Password first (see SKILL.md).")

	worked = [s.strip() for s in args.statuses.split(",") if s.strip()] or DEFAULT_WORKED
	estimates = dict(DEFAULT_ESTIMATES)
	estimates.update(parse_overrides(args.hours))

	jql = (
		f"project = {args.project} AND assignee = currentUser() "
		f"AND updated >= -{args.days}d ORDER BY updated DESC"
	)
	code, res = req(
		token,
		f"{BASE}/search/jql",
		"POST",
		{
			"jql": jql,
			"maxResults": 200,
			"fields": [
				"summary", "status", "issuetype", "subtasks", "timespent",
				"resolutiondate", "updated",
			],
		},
	)
	if code != 200:
		sys.exit(f"search failed ({code}): {res}")

	issues = res["issues"]
	targets = []
	skipped_status = skipped_haslogged = skipped_parent = skipped_epic = 0
	for i in issues:
		f = i["fields"]
		st = f["status"]["name"]
		typ = f["issuetype"]["name"]
		if st not in worked:
			skipped_status += 1
			continue
		if typ == "Epic":
			skipped_epic += 1
			continue
		if f.get("subtasks"):
			skipped_parent += 1  # log on its subtasks instead
			continue
		if f.get("timespent"):
			skipped_haslogged += 1
			continue
		targets.append(i)

	mode = "APPLY" if args.apply else "DRY RUN"
	print(f"=== {mode} · {args.project} · last {args.days}d · worked={worked} ===")
	print(
		f"scanned {len(issues)} · skip(status {skipped_status}, "
		f"epic {skipped_epic}, parent-w-subtasks {skipped_parent}, "
		f"already-logged {skipped_haslogged}) · to log {len(targets)}\n"
	)

	total = 0
	failures = []
	for i in targets:
		f = i["fields"]
		typ = f["issuetype"]["name"]
		hrs = estimates.get(typ, FALLBACK_HOURS)
		total += hrs
		key = i["key"]
		summ = f["summary"][:55]
		if args.apply:
			c, _ = req(
				token,
				f"{BASE}/issue/{key}/worklog",
				"POST",
				{"timeSpentSeconds": hrs * 3600, "started": started_from(f)},
			)
			status = "OK" if c == 201 else f"FAIL {c}"
			if c != 201:
				failures.append((key, c))
		else:
			status = "would log"
		print(f"{key:16} {typ:20} {hrs}h  {status}  {summ}")

	print(f"\n{'logged' if args.apply else 'would log'}: {len(targets)} tickets · {total}h")
	if failures:
		print("FAILURES:", failures)

	# Confirm rollups on parents that have subtasks.
	if args.apply:
		parents = [i["key"] for i in issues if i["fields"].get("subtasks")]
		if parents:
			print("\n=== parent rollups ===")
			for k in parents:
				c, d = req(
					token,
					f"{BASE}/issue/{k}?fields=aggregatetimespent,subtasks",
				)
				if c == 200:
					agg = d["fields"].get("aggregatetimespent")
					n = len(d["fields"].get("subtasks") or [])
					print(f"{k:16} rolled-up={round(agg / 3600, 1) if agg else 0}h ({n} subtasks)")


if __name__ == "__main__":
	main()
