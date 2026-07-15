#!/usr/bin/env python3
"""Scan Claude Code session transcripts for research/investigation tasks kicked off
within a time window, pulling the *why* (the prompt) and the *outcome* (the result).

Emits JSON to stdout: a list of {when, repo, branch, kind, title, why, outcome, session}.
The standup skill formats this; this script holds all the fiddly JSONL parsing so the
model never has to read raw transcripts.

Window: defaults to "since your last workday" (Mon reaches back to Fri, else yesterday).
Override with --since=Nd for a rolling N-day window.
"""

import argparse
import datetime as dt
import glob
import json
import os
import re
import sys

PROJECTS_GLOB = os.path.expanduser("~/.claude/projects/*/*.jsonl")

# Skills worth surfacing as research/investigation work (not routine ops).
RESEARCH_SKILLS = {"plan", "debug", "review", "trace-number", "render-sql-template"}
RESEARCH_AGENTS = {"Explore", "Plan", "general-purpose", "devils-advocate", "claude"}

WHY_MAX = 600
OUTCOME_MAX = 800


def window_start(since: str | None) -> dt.datetime:
    """Return an aware (local tz) datetime for the start of the window."""
    now = dt.datetime.now().astimezone()
    if since:
        s = since.strip().lower()
        if s.endswith("d"):
            days = int(s[:-1])
            start = (now - dt.timedelta(days=days)).replace(
                hour=0, minute=0, second=0, microsecond=0
            )
            return start
        raise SystemExit(f"unrecognized --since value: {since!r} (use e.g. 3d)")
    # last workday: Monday(0) -> Friday, else yesterday
    back = 3 if now.weekday() == 0 else 1
    start = (now - dt.timedelta(days=back)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    return start


def parse_ts(raw: str | None) -> dt.datetime | None:
    if not raw:
        return None
    try:
        return dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


def repo_from(cwd: str | None, branch: str | None) -> str:
    """Human repo label from cwd; strip worktree suffixes."""
    if cwd:
        name = os.path.basename(cwd.rstrip("/"))
        # collapse "repo--claude-worktrees-..." back to the repo name
        if "--claude-worktrees-" in name:
            name = name.split("--claude-worktrees-")[0]
        if name:
            return name
    return branch or "unknown"


# A backgrounded agent's tool_result is a launch stub, not the answer. It points at the
# subagent's own JSONL transcript via `output_file:`; the real outcome is that transcript's
# last assistant text. The stub also carries internal agentId metadata we must never surface.
OUTPUT_FILE_RE = re.compile(r"output_file:\s*(\S+)")


def last_assistant_text(path: str) -> str | None:
    """Final non-empty assistant message from a subagent transcript = its result."""
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError:
        return None
    result = None
    for line in lines:
        try:
            o = json.loads(line)
        except json.JSONDecodeError:
            continue
        if o.get("type") != "assistant":
            continue
        msg = o.get("message")
        if not isinstance(msg, dict):
            continue
        txt = "".join(
            b.get("text", "")
            for b in msg.get("content", [])
            if isinstance(b, dict) and b.get("type") == "text"
        ).strip()
        if txt:
            result = txt
    return result


def resolve_outcome(raw: str) -> str | None:
    """Turn a captured tool_result into a real outcome. If it's an async launch stub,
    follow output_file to the subagent transcript; otherwise return it verbatim."""
    if not raw:
        return None
    if "output_file:" in raw:
        m = OUTPUT_FILE_RE.search(raw)
        if m:
            outcome = last_assistant_text(m.group(1))
            if outcome:
                return outcome
        return None  # backgrounded but transcript gone/unfinished — never leak the stub
    return raw


def as_text(content) -> str:
    """tool_result content can be a str or a list of blocks."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for b in content:
            if isinstance(b, dict) and b.get("type") == "text":
                parts.append(b.get("text", ""))
            elif isinstance(b, str):
                parts.append(b)
        return "\n".join(parts)
    return ""


def scan_file(path: str, start: dt.datetime):
    """Yield task dicts from one transcript. Two-pass: collect results, then tasks."""
    results: dict[str, str] = {}
    pending = []  # (tool_use_id, task dict)
    session = os.path.splitext(os.path.basename(path))[0]

    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError:
        return

    events = []
    for line in lines:
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue

    # First pass: harvest every tool_result by id (results may precede or follow).
    for o in events:
        msg = o.get("message")
        if not isinstance(msg, dict):
            continue
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for b in content:
            if isinstance(b, dict) and b.get("type") == "tool_result":
                tid = b.get("tool_use_id")
                if tid:
                    results[tid] = as_text(b.get("content"))

    # Second pass: find research task spawns in-window.
    for o in events:
        ts = parse_ts(o.get("timestamp"))
        if ts is None or ts < start:
            continue
        msg = o.get("message")
        if not isinstance(msg, dict):
            continue
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        repo = repo_from(o.get("cwd"), o.get("gitBranch"))
        branch = o.get("gitBranch") or ""
        for b in content:
            if not isinstance(b, dict) or b.get("type") != "tool_use":
                continue
            name = b.get("name")
            inp = b.get("input", {}) if isinstance(b.get("input"), dict) else {}
            if name in ("Agent", "Task"):
                sub = inp.get("subagent_type", "?")
                if sub not in RESEARCH_AGENTS:
                    continue
                why = (inp.get("prompt") or "").strip()
                title = (inp.get("description") or "").strip() or why[:60]
                outcome = resolve_outcome(results.get(b.get("id"), "").strip())
                outcome = outcome.strip() if outcome else None
                pending.append(
                    {
                        "when": ts.astimezone().isoformat(),
                        "repo": repo,
                        "branch": branch,
                        "kind": f"agent:{sub}",
                        "title": title,
                        "why": why[:WHY_MAX],
                        "outcome": outcome[:OUTCOME_MAX] if outcome else None,
                        "session": session,
                    }
                )
            elif name == "Skill":
                skill = inp.get("skill", "")
                if skill not in RESEARCH_SKILLS:
                    continue
                args = (inp.get("args") or "").strip()
                pending.append(
                    {
                        "when": ts.astimezone().isoformat(),
                        "repo": repo,
                        "branch": branch,
                        "kind": f"skill:{skill}",
                        "title": f"/{skill} {args}".strip()[:60],
                        "why": args[:WHY_MAX],
                        "outcome": None,
                        "session": session,
                    }
                )
    yield from pending


def dedupe(tasks):
    """Collapse near-identical spawns (same repo + title + prompt head)."""
    seen = set()
    out = []
    for t in sorted(tasks, key=lambda x: x["when"]):
        key = (t["repo"], t["kind"].split(":")[0], t["title"][:50], t["why"][:80])
        if key in seen:
            continue
        seen.add(key)
        out.append(t)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--since", help="rolling window like 3d; default: last workday")
    ap.add_argument("--only", help="filter to a repo substring (default: all repos)")
    args = ap.parse_args()

    start = window_start(args.since)
    start_utc = start.astimezone(dt.timezone.utc)

    tasks = []
    for path in glob.glob(PROJECTS_GLOB):
        try:
            mtime = dt.datetime.fromtimestamp(os.path.getmtime(path)).astimezone()
        except OSError:
            continue
        if mtime < start:
            continue  # fast prefilter: file untouched in window
        tasks.extend(scan_file(path, start_utc))

    if args.only:
        needle = args.only.lower()
        tasks = [t for t in tasks if needle in t["repo"].lower()]

    tasks = dedupe(tasks)
    json.dump(
        {"window_start": start.isoformat(), "count": len(tasks), "tasks": tasks},
        sys.stdout,
        indent=2,
    )
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
