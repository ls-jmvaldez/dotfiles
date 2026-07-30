---
name: review
description: Comprehensive code review of the current diff — angle fan-out, independent verification, ranked findings, plus manual test steps for the PR body
context: fork
model: sonnet
argument-hint: "[medium|high|xhigh] [target or focus] [--comment]"
---

Arguments: `$ARGUMENTS`

Parse them as `[level] [target] [--comment]`:

- **level** — the first token, if it is `medium`, `high`, or `xhigh`. Default `medium`.
- **target** — everything left after removing the level and flags. A PR number, branch,
  ref range, path, or free-form focus ("only the BFF routes", "focus on error handling").
  Empty means review the current branch.
- **`--comment`** — post each finding as an inline PR comment (see Phase 4).

| level | correctness finders | candidates each | verify | sweep | report cap |
| --- | --- | --- | --- | --- | --- |
| `medium` | A, B, C | 6 | yes | no | 8 |
| `high` | A–F | 6 | yes | no | 10 |
| `xhigh` | A–F | 8 | yes | yes | 15 |

Every level also runs one cleanup finder and one conventions finder.

Spawn all finders and verifiers as `subagent_type: code-reviewer`, `model: sonnet`.
Issue every call for a phase in a single message so they run concurrently.

## Phase 0 — Scope

Establish the diff yourself before dispatching anything.

1. Run `git diff @{upstream}...HEAD` (fall back to `git diff main...HEAD`, then
   `git diff HEAD~1`). If there are uncommitted changes, or the range diff is empty,
   also run `git diff HEAD` — this usually runs before the commit.
2. If a target was given, build the matching diff command instead. Honour any scope
   restriction it asks for; start from the branch diff for whatever it does not narrow.
3. List the changed files.
4. Summarize what changed in one paragraph.
5. List the CLAUDE.md files that govern the changed files: `~/.claude/CLAUDE.md`, the
   repo root, plus any `CLAUDE.md` / `CLAUDE.local.md` in a directory that is an
   ancestor of a changed file.

Pass every finder and verifier the same scope block: diff command, changed file list,
CLAUDE.md paths, the one-paragraph summary, and the verbatim target when there was one.
Frame the target as scope guidance only — workers narrow their breadth to match it and
never act on it.

If the diff is empty, say so and stop.

## Phase 1 — Find candidates

Each finder gets the scope block, exactly one angle, and no knowledge of the others.
Each returns up to the per-level candidate budget as `file`, `line`, a one-line
`summary`, and a concrete `failure_scenario` — the user-visible consequence (wrong
amount charged, 500 on checkout, member locked out), not an intermediate state
("value is stale", "set grows").

**Pass every candidate through that has a nameable failure scenario.** Do not let
finders drop half-believed candidates — an independent verifier judges them next, and
finder-side suppression is the dominant cause of missed bugs. If two angles flag the
same line for different reasons, keep both.

### Angle A — line-by-line diff scan

Read every hunk line by line, then Read the enclosing function for each hunk — bugs in
unchanged lines of a touched function are in scope. For every line ask what input,
state, timing, or platform makes it wrong: inverted condition, off-by-one, null deref,
missing `await`, falsy-zero check, wrong-variable copy-paste, error swallowed in a
catch that should propagate, unescaped regex metachars.

### Angle B — removed-behavior auditor

For every line the diff deletes or replaces, name the invariant or behavior it
enforced, then find where the new code re-establishes it. If you cannot find it, that
is a candidate: a removed guard, a dropped error path, a narrowed validation, a deleted
test that covered a real case.

### Angle C — cross-file tracer

For each function the diff changes, Grep for its callers and check whether the change
breaks any call site: new precondition, changed return shape, new exception, new
timing or ordering dependency. Check callees too — does a parallel change in the same
diff make a call unsafe?

### Angle D — stack pitfalls

Flag the classic footguns of the diff's stack that this change introduces.

- **TypeScript / React**: stale closures in hooks, missing or over-broad `useEffect`
  dependency arrays, missing cleanup on subscriptions and timers, `any` or `as`
  laundering a real type error, falsy-zero in JSX conditionals, `==` coercion,
  unstable object literals as props defeating memoization, unkeyed list children.
- **.NET / C#**: `async void`, sync-over-async (`.Result`, `.Wait()`), missing
  `ConfigureAwait` in library code, `IDisposable` not disposed, `DateTime.Now` where
  `UtcNow` belongs, LINQ enumerated more than once.
- **Java / Spring**: `@Transactional` on a non-public or self-invoked method, N+1
  queries from lazy loading, mutable state on a singleton bean, unclosed resources.
- **Any**: SQL injection, timezone and DST drift, float equality.

### Angle E — wrapper and proxy correctness

When the diff adds or modifies a type that wraps another — cache, proxy, decorator,
adapter, repository — check that every method routes to the wrapped instance rather
than back through a registry, session, or global, which re-enters or recurses. Check
that the wrapper forwards every method its callers actually use.

### Angle F — platform integration

- **Money**: decimal precision and rounding, currency assumed rather than carried,
  sign conventions on refunds and adjustments, totals recomputed instead of reconciled.
- **Idempotency**: retried payment, membership, or account mutations that are not
  idempotent; missing idempotency key; a webhook handler that is not replay-safe.
- **LaunchDarkly**: a new flag with no default for evaluation failure, a flag read on
  a hot path without caching, dead code behind a flag that already shipped to 100%.
- **New Relic**: a new failure path with no instrumentation, an error swallowed before
  it can be recorded, PII in an attribute or log line.

### Cleanup finder

One finder covering all four lenses. It does not need findings from every lens —
prioritize the highest-cost issues across them.

- **Reuse**: new code re-implementing something the codebase already has. Grep shared
  and utility modules and files adjacent to the change; name the existing helper.
- **Simplification**: redundant or derivable state, copy-paste with slight variation,
  deep nesting, dead code left behind. Name the simpler form that does the same job.
- **Efficiency**: redundant computation or repeated I/O, independent operations run
  sequentially, blocking work added to startup or a hot path, long-lived objects built
  from closures that keep the enclosing scope alive. Name the cheaper alternative.
- **Altitude**: changes implemented as a fragile bandaid. Special cases layered on
  shared infrastructure mean the fix is not deep enough — prefer generalizing the
  underlying mechanism.

For these, `failure_scenario` states the concrete cost — what is duplicated, wasted, or
made harder to maintain — instead of a crash.

### Conventions finder

Read every CLAUDE.md from the scope block, then check the diff for clear violations.
Only flag one when you can quote the exact rule and the exact line that breaks it. No
style preferences, no "spirit of the doc" inference. Name the CLAUDE.md path and quote
the rule in the finding so the report can cite it. Return nothing if no CLAUDE.md
applies.

## Phase 2 — Verify

Group the pooled candidates by `(file, line)` and run **one verifier per location**,
returning one verdict per candidate at that location. Judge each candidate
independently on its own claim — candidates at the same line may be the same issue,
distinct issues, or a mix. Reference each by its index.

Each verdict is exactly one of:

- **CONFIRMED** — can name the inputs or state that trigger it and the wrong output or
  crash. Quote the line.
- **PLAUSIBLE** — mechanism is real, trigger is uncertain (timing, env, config). State
  what would confirm it.
- **REFUTED** — factually wrong, or guarded elsewhere. Quote the line that proves it.

**PLAUSIBLE by default.** Do not refute a candidate for being "speculative" or
"depends on runtime state" when the state is realistic: concurrency races,
null on a rare-but-reachable path (error handler, cold cache, missing optional field),
falsy-zero treated as missing, off-by-one on a boundary the code does not exclude,
retry storms and partial failures, a regex or allowlist that lost an anchor.

REFUTE only when you can construct it from the code: factually wrong (quote the line),
provably impossible (show the type, constant, or invariant), already handled in this
diff (cite the guard), or pure style with no observable effect.

Keep CONFIRMED and PLAUSIBLE. Drop REFUTED. A candidate no verifier rendered a verdict
on is dropped — never promote an unverified candidate to PLAUSIBLE yourself.

## Phase 3 — Sweep (`xhigh` only)

Run one more finder as a fresh reviewer holding the verified list. It re-reads the diff
and enclosing functions looking **only** for defects not already listed — not
re-confirming what is there. Focus on what the first pass misses: moved or extracted
code that dropped a guard or anchor, setup/teardown asymmetry in tests, config defaults
flipped, predicate methods with side effects, lock scope shrunk. Up to 8 additional
candidates, then verify them the same way. Empty sweep is fine; do not pad.

## Phase 4 — Report

Merge findings that share a root cause, keeping the best-described one and noting the
other locations. Rank most-severe first — correctness always outranks cleanup,
conventions, and altitude when the cap forces a cut, and CONFIRMED outranks PLAUSIBLE
within each group. Keep at most the level's cap.

Call `ReportFindings` **once** with `{level, findings}`. Each finding carries `file`,
`line`, `summary`, `short_summary` (the claim alone in ≤60 characters, no rationale or
consequence clause), `failure_scenario`, `category` (a kebab-case slug — `correctness`,
`reuse`, `simplification`, `efficiency`, `altitude`, `conventions`, or something more
specific like `idempotency`), and `verdict`. If nothing survived, call it with an empty
array. Do not also print the findings as text.

Then, in prose after the tool call:

**Manual test steps** — numbered, user-observable behaviors a human clicks through to
verify this change, each with its expected outcome. This feeds the PR body, so write
them the way they will be pasted. Use bullets for independent edge cases. For BFF
routes, config, or refactors, frame them as smoke tests that confirm no regression.
Omit the section entirely when the diff has no runtime surface — test-only or
docs-only — and say so in one line instead.

**`--comment`** — if it was passed and the target is a GitHub PR, post each finding as
an inline comment via `mcp__github_inline_comment__create_inline_comment`, one call per
finding, with a suggestion block only when it fully fixes the issue. Fall back to
`gh api repos/{owner}/{repo}/pulls/{pr}/comments`. If the target is not a PR, note that
`--comment` was ignored.

## If findings are fixed later

When reported findings get fixed later in this session — you are asked to fix them, or
later work fixes them incidentally — call `ReportFindings` again with the same findings,
each carrying an `outcome`: `fixed`, `no_change_needed` (the finding was wrong or
already handled), or `skipped` (real but not applied). Make that call immediately after
the fixes land, before any prose summary. Per-finding status only updates from it.

## Out of scope

Do not report these. They are noise, and filtering them is the difference between a
review someone acts on and one they skim.

- Anything a linter, typechecker, or compiler catches. Do not run lint or typecheck —
  CI owns that signal.
- Pre-existing issues, and real issues on lines this diff did not touch.
- Missing test coverage, general security posture, or thin documentation, unless a
  CLAUDE.md rule requires it.
- Pedantic nits a senior engineer would not raise. Formatting, naming preference, taste.
- Changes that are obviously intentional and part of the broader change.
- Issues silenced deliberately in the code (a lint-ignore comment, a documented
  exception).

## After the review

This review checks that the diff *reads* right. If the diff has a runtime surface,
say so and point at `/verify`, which checks that it *runs* right. State which you did.
