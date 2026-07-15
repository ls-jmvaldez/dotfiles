---
name: dependabot-sweep
description: Orchestrate Dependabot alert remediation across LegalShield microservice and frontend repos from a Jira epic. Pulls child tickets, claims them to you, dispatches one sub-agent per repo to clear all open Dependabot alerts (direct bumps + transitive overrides) into one hardening PR in parallel, then re-entrantly resolves Copilot/CodeQL review feedback.
argument-hint: "<EPIC-KEY> [--review]"
model: sonnet
---

Orchestrate Dependabot updates across many repos, driven by a Jira epic. You are an
**orchestrator**: you own Jira state, repo resolution, worktree provisioning, and
sub-agent dispatch. You never edit dependency code yourself — sub-agents do that.

Arguments: $ARGUMENTS

State lives in **Jira + GitHub, not in this skill's memory.** Every invocation
reconstructs "what's left" from ticket status and PR state, so the skill is safe to
re-run. There are two passes:

- **Remediate pass** (default): clear all open Dependabot **alerts** for the repo into
  one hardening PR, add/verify the `dependabot.yml` cooldown config, get the verify gate
  green, open it as a **draft**, then run Joe's `/review` skill as an orchestrator gate
  before promoting the PR to human-visible. Moves tickets `Work In Progress` → `Code Review`,
  then exits. The unit of work is **alerts, not existing Dependabot PRs** — a repo can
  have one open bot PR but dozens of open alerts.
- **Review pass** (`--review`): re-enter after Copilot + CodeQL have posted feedback;
  resolve diff-introduced comments/alerts, push, re-request review.

## Step 0: Auth (Jira)

The Jira plugin is vault-agnostic and will not inject a token. Do it here, exactly as
the `jira` skill does. If `$JIRA_AUTH_TOKEN` is unset, export it from 1Password:

```bash
[ -z "$JIRA_AUTH_TOKEN" ] && export JIRA_AUTH_TOKEN="$(op read 'op://PPLSI/Jira - Base64/credential' 2>/dev/null)"
[ -z "$JIRA_AUTH_TOKEN" ] && echo "no token — run: op signin, or export JIRA_AUTH_TOKEN manually" || echo "token present"
```

Resolve the plugin root (version-stamped — never hardcode):

```bash
ROOT=$(python3 -c "
import json, os
m = json.load(open(os.path.expanduser('~/.claude/plugins/installed_plugins.json')))
e = m['plugins'].get('internal-tools@legalshield-marketplace')
print(e[0]['installPath'] if e else '', end='')
")
echo "$ROOT"
```

If `$ROOT` is empty, tell the user to run
`claude plugin install internal-tools@legalshield-marketplace` and stop. For all Jira
reads/transitions/assignment/comments, follow `$ROOT/skills/jira/SKILL.md`, treating
every `${CLAUDE_PLUGIN_ROOT}` as `$ROOT` and skipping its auth step (done above).

`gh` is authed as `ls-jmvaldez`. The GitHub org is **`LegalShield`**.

**Registry token (required for npm work).** Repos with private `@legalshield/*` deps need
a `read:packages` token — the `gh` token does **not** have it. Export it here so sub-agents
inherit it, and pass it in each agent's task:

```bash
export GIT_PERSONAL_ACCESS_TOKEN="$(op read 'op://Personal/GIT_PERSONAL_ACCESS_TOKEN/credential')"
```

Without it, `npm install` rolls back on a 403 and commits a lockfile `npm ci` (and CI)
will reject. See `references/clearing-alerts-npm.md`.

## Step 1: Parse arguments

- First token is the **epic key** (e.g. `COREAPP1-3576`). If omitted, stop and ask.
- `--review` selects the **review pass**. Absent → **remediate pass**.

**Epic guard.** Fetch the key and check its issue type. If it is **not** an `Epic`
(e.g. it's a Task/Story that is itself a child), **stop and confirm**: report that it's a
child of `<parent-key> "<parent-summary>"` and ask whether the user meant the epic. Do
not fan out from a non-epic key without confirmation. (The `dependabot-sweep` epic is
`COREAPP1-3576 "Dependabot Alerts"`; its children are the per-repo tasks like
`COREAPP1-3577 "Membership Details"`.)

## Workflow status vocabulary (COREAPP1)

This project's workflow does **not** use "In Progress"/"In Review". Map to the real
transition names (all transition freely from any status):

- claimed / actively remediating → **`Work In Progress`**
- PR open, awaiting review → **`Code Review`**
- terminal → **`Done`** (you never set this; the human merges)

## Step 2: Pull epic children

Query children: `parent=<EPIC-KEY>`. Filter by pass:

- **Remediate pass** — candidates are children that are **unassigned** and not in a
  downstream status (`Code Review`, `QA In progress`, `Ready for *`, `Done`). **Never
  claim a ticket assigned to someone else** — that's a coworker's in-flight work. For
  re-entrancy of the skill's *own* partial runs, also include tickets already assigned to
  **Joe** in `Work In Progress` for which a `chore/<ticket-lower>-deps` branch or draft PR
  exists (resume those); leave Joe-assigned tickets with no sweep branch alone (they're
  hand-authored, like 3577).
- **Review pass** — children **assigned to Joe** in **`Code Review`** (PRs this sweep
  promoted, now awaiting Copilot/CodeQL feedback).

If there are no matching children, report that and stop.

## Step 3: Resolve the repo per ticket (infer, don't skip)

Each ticket names its repo in the summary or a field (e.g. summary
`Dependabot: internal-membership-web`). Resolve with a confidence ladder — never
silently skip, only pause for genuine ambiguity:

1. **Clean local match** — a single dir under `~/Public/source` whose name equals or
   clearly contains the hint → use it.
2. **No clean local match** — infer via `gh`:
   `gh search repos --owner LegalShield <hint> --json fullName --limit 10`, then
   fuzzy-rank the results against the hint.
3. **Confident single match** (one clearly-best `LegalShield/<repo>`) → use it. If it
   isn't cloned locally, clone into the worktree base in Step 4.
4. **Genuinely ambiguous** (several plausible, or nothing close) → report that specific
   ticket with the candidates and ask. Keep processing the rest.

## Step 4: Claim + provision (per resolved ticket)

Do this as each ticket is dispatched, so the board reflects live state:

1. **Assign the ticket to Joe** (`JoeValdez@pplsi.com`) and transition to
   **`Work In Progress`** (remediate pass only; review pass leaves status at
   `Code Review`).
2. Provision a worktree on branch **`chore/<ticket-key-lowercased>-deps`** — keyed to the
   **child ticket**, not the epic (e.g. `chore/coreapp1-3577-deps` for the Membership
   Details ticket; one PR per repo/ticket):
   - If the repo is local: `git -C ~/Public/source/<repo> worktree add -b chore/<ticket-lower>-deps <worktree-path> origin/main`
   - If not local: clone first, then add the worktree.
   - `git worktree add` on an existing path errors — that's the resume signal; reuse it.

Worktree base path: a scratch dir (e.g. under the session scratchpad or
`~/Public/source/.worktrees/`), one per repo. Never provision inside the primary
checkout.

## Step 5a: Remediate pass — dispatch fix agents

Spawn one sub-agent per repo, **max 4 concurrent**, `subagent_type: general-purpose`,
`cwd: <worktree-path>`. Route by **ecosystem per alert**, from each alert's
`manifest_path` — **not** by repo type. A single repo mixes ecosystems: a .NET service
can carry npm alerts in a `tests/` harness (observed on COREAPP1-3824). Read the
`manifest_path` of every open alert and hand the agent the recipe for each ecosystem
present:

- `pnpm-lock.yaml` → **pnpm**: read `references/clearing-alerts-pnpm.md`.
- `package-lock.json` → **npm**: read `references/clearing-alerts-npm.md`.
- `*.csproj` / `packages.config` / `Directory.Packages.props` → **NuGet**: read
  `references/clearing-alerts-nuget.md`.

If a ticket's repo has alerts in more than one ecosystem, clear each with its own recipe
in the same PR. A repo also commonly has **multiple manifests in the same ecosystem** —
e.g. several `package-lock.json` files (a React `ClientApp/`, an `automation-tests/` or
`tests/` harness, a root lockfile). Enumerate every distinct `manifest_path` and clear
each; do not assume one manifest per repo. (Under epic COREAPP1-3576 every remaining repo
is npm — the pnpm recipe applies only to internal-membership-web, already done; NuGet is
unused.)

The shared contract every agent works to, in `<worktree-path>` on branch
`chore/<ticket-lower>-deps`:

> 1. Enumerate **open Dependabot alerts**:
>    `gh api /repos/LegalShield/<repo>/dependabot/alerts --paginate -q '.[] | select(.state=="open")'`.
>    Group by severity; the goal is to drive open alerts to **0**.
> 2. Clear them per the ecosystem recipe — **direct** deps bumped in their owning
>    manifest, **transitive** vulns pinned via the ecosystem's override mechanism.
>    Respect the repo's supply-chain guards (e.g. pnpm `minimumReleaseAge`): only pick
>    target versions old enough to clear quarantine, and **never** use a bypass flag.
> 3. Add or verify the repo's Dependabot config with a cooldown (see recipe). If none
>    exists, add one; if it exists, confirm the cooldown is present.
> 4. Regenerate the lockfile the normal way, run the verify gate (Step 6), iterate.
>    Anything that can't be cleared without a product decision (too-new-only fix,
>    breaking major) is **deferred and reported**, not forced.
> 5. Commit (`git -C <worktree-path>`, `chore(deps): clear dependabot alerts + ...`,
>    body explaining WHY), push `-u origin chore/<ticket-lower>-deps`.
> 6. Open a **draft** PR per the PR shape below. Do **not** add any reviewer — the
>    orchestrator review gate below promotes the PR and handles reviewers. Report the PR
>    URL, the cleared-vs-deferred alert counts by severity, and honest verify status
>    (Step 6).

### PR shape (The Contributor persona)

Model it on the reference PR (`LegalShield/internal-membership-web#186`):

- **Title**: `chore(deps): clear dependabot alerts + config hardening`.
- **Body lead**: why the change exists — the open-alert count by severity and what was
  letting them accumulate. Then concrete paragraphs: direct deps bumped, transitive
  vulns pinned via overrides, lockfile-regen note (no bypass flag), the `dependabot.yml`
  cooldown addition.
- **`## Manual test steps`**: a reviewer smoke test (pull branch, install, run tests).
  Be **honest** about suites that can't run locally (browser/Storybook suites, E2E
  needing secrets) — flag them for CI rather than claiming green. Include post-merge
  checks: confirm the alert count drops to 0 after re-scan, and close any one-off
  Dependabot PRs this supersedes.
- **`## Tickets`**: a PostToolUse hook populates this from the branch/body, but write the
  `### Story` subsection with the epic link explicitly so it's correct.

### Orchestrator review gate (last line of defense before human eyes)

When a fix agent reports back, **you review its work before any human sees it.** This is
where you catch what the ecosystem recipes can't fully specify — a too-broad transitive
override, an unnecessary major bump, a lockfile change that resolved something the alert
didn't ask for.

1. Run Joe's `/review` skill scoped to the worktree's diff (`main...HEAD` in
   `<worktree-path>`). Pass the worktree path and base as the instruction argument so it
   reviews the right tree. If the skill can't be scoped to the worktree cleanly, fall
   back to spawning the `code-reviewer` agent directly with `cwd: <worktree-path>` and
   the same diff.
2. **Be extra watchful on two things** (per Joe): **.NET repos** — the NuGet recipe is
   unvalidated — and **transitive-override-heavy diffs** in any repo. When the diff is
   either, run `/review --deep` (Opus re-review of flagged files), not the standard pass.
3. Read the verdict:
   - **REQUEST CHANGES**, or any **Critical / Important** finding → dispatch a follow-up
     fix agent in the same worktree to address them, re-run the verify gate, re-commit,
     and re-review. Bounded to a few cycles.
   - **APPROVE** (only Suggestions / minor left) → promote the PR (next block).
4. Fold the review's **Manual Test Steps** into the PR body's `## Manual test steps` so
   the human reviewer inherits them.

If after the bounded cycles the review still says REQUEST CHANGES, do **not** promote to a
human-visible PR: leave the ticket at `Work In Progress`, keep the PR draft, comment the
unresolved review findings on the ticket, and surface it to Joe.

### On a passing review

- Mark the PR **ready for review**: `gh pr ready <n> --repo LegalShield/<repo>`.
- The sweep runs as `ls-jmvaldez`, who **authors** the PR — GitHub won't let the author
  be a reviewer. So instead: set Joe as **assignee** (`gh pr edit <n> --add-assignee
  ls-jmvaldez`) so it lands in his queue, and **request Copilot review** (a bot can review
  an author's PR):
  `gh api repos/LegalShield/<repo>/pulls/<n>/requested_reviewers -X POST -f 'reviewers[]=copilot-pull-request-reviewer[bot]'`
  (Copilot then shows up as the requested reviewer "Copilot".)
- Comment the PR URL + cleared/deferred alert summary + review verdict on the ticket.
- Transition the ticket to **`Code Review`** (stays assigned to Joe — you do the final merge).
- **Watch CI before calling it done**: `gh pr checks <n> --repo LegalShield/<repo> --watch`.
  A local verify gate is not a substitute for CI — a lockfile can pass local `npm install`
  yet fail CI's stricter `npm ci` (COREAPP1-3819). If CI goes **red**, pull the failing
  log (`gh run view --job <id> --log-failed`), fix in the same worktree, push, and
  re-watch. Only a green CI run means the PR is genuinely ready for Joe. Note: .NET repos'
  CI does **not** run `npm ci` on their test harnesses, so a green check there does not
  prove the npm lockfile is consistent — verify `npm ci` locally regardless.

Fail-fast per repo: if an agent can't clear alerts into a green PR at all, leave the
ticket at `Work In Progress`, comment what blocked it, and surface it. Do not open a broken PR.

## Step 5b: Review pass (`--review`) — resolve feedback

For each `Code Review` ticket, find its PR by the `chore/<ticket-lower>-deps` branch. Gather:

- **Copilot review comments**: `gh pr view <n> --repo LegalShield/<repo> --json reviews,comments` (Copilot's review threads).
- **CodeQL / code-scanning alerts** on the PR ref: `gh api repos/LegalShield/<repo>/code-scanning/alerts?ref=refs/heads/chore/<ticket-lower>-deps`.
  **Scope: diff-introduced only** — alerts the PR's changes newly caused. Ignore
  pre-existing alerts on the branch; do not expand scope to unrelated findings.

If there is actionable feedback, spawn a fix agent (same worktree/branch) to resolve the
Copilot comments and diff-introduced CodeQL alerts appropriately, re-run the verify gate,
push, and **re-request Copilot review**. If a Copilot comment is a false positive,
reply on the thread with the rationale rather than changing code.

If a PR is clean (no open feedback), leave it: ticket stays `Code Review`, assigned to
Joe, awaiting your merge.

**Bounded:** iterate a PR at most a few cycles per invocation. This pass is re-entrant —
if feedback is still pending or Copilot/CodeQL haven't run yet, report that and let the
user re-invoke `--review` later. Do not busy-poll waiting for the bots.

## Step 6: Verify gate (repo-type detection)

Detect type in the worktree and run the matching gate (from the global verification
protocol); iterate until it passes:

- **.NET** (`*.sln` / `*.csproj`): `dotnet build && dotnet test`
- **npm** (`package-lock.json`): export `GIT_PERSONAL_ACCESS_TOKEN`, match the CI node
  version (`.node-version`), then **`rm -rf node_modules && npm ci`** (this is the gate CI
  runs — `npm audit` passing is not enough), then `npm run build && npm run lint && npm test`.
- **pnpm** (`pnpm-lock.yaml`): `pnpm install` (clean, no bypass) then `pnpm -r test`.

If a repo defines its own verify/CI command, prefer it.

**Be honest about coverage.** Some suites legitimately can't run locally — browser /
Storybook / vitest-browser suites that need a live harness, or E2E suites that need
secrets not in this environment. Do not claim those green. Run what you can, and in the
PR body flag the excluded suites for CI (the source of truth) so a reviewer with local
creds can cover them. Never report a gate as passing when part of it was skipped.

## Git command safety (worktrees)

The Bash tool's working directory **silently resets to the primary checkout between
calls** — a `cd` does not persist, so a bare git command can run against `main`.

- Prefix **every** git invocation with `git -C <worktree-path>`.
- Before any history-mutating op (`commit`, `amend`, `reset`, `push`), confirm the
  branch: `git -C <worktree-path> branch --show-current` must equal
  `chore/<ticket-lower>-deps`. If it reports `main`, stop.

## What this skill does NOT do

- **Auto-merge.** Ready PR + `Code Review` is the terminal state; you merge.
- **Resolve pre-existing CodeQL alerts.** Only diff-introduced findings are in scope.
- **Busy-poll for async bots.** The review pass is re-entrant; you (or `/loop`) trigger it.
- **Guess low-confidence repo matches.** Genuine ambiguity is reported, not assumed.

## Key principles

- Orchestrator dispatches; sub-agents do the code work. Max 4 parallel repos.
- **You are the last line of defense.** Every repo passes Joe's `/review` gate (draft →
  reviewed → promoted) before a human sees it. Extra scrutiny (`--deep`) on .NET repos
  and transitive-override-heavy diffs.
- State is in Jira + GitHub — any invocation resumes from ticket status + PR state.
- Every git command targets the worktree with `git -C`; branch verified before writes.
- Tickets are claimed to Joe at dispatch and stay assigned through merge.

## Examples

```
/dependabot-sweep COREAPP1-3577            # remediate pass: open the PRs
/dependabot-sweep COREAPP1-3577 --review   # later: resolve Copilot/CodeQL feedback
```
