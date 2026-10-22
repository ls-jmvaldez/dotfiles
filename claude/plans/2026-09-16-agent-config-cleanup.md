# Agent Config Cleanup Implementation Plan

> **Status:** DRAFT

## Specification

**Goal:** Make `claude/` generic and publishable with zero employer content. Clean up the
existing tree in place, absorb the voice system that currently lives in a private marketplace
plugin, and add a thin bootstrap so a fresh machine can link the config in one command.

This plan implements the smallest of three designs. A 142-file platform design and an 87-file
capability-contract design were both rejected. See "Rejected alternatives" at the bottom.

**Hard constraint.** Out of the repo entirely: company names, tracker and wiki hostnames,
internal repo names, project keys, custom field IDs, internal service and table names,
employer domain vocabulary, the 1Password dependency, and the New Relic dependency. Those
values may exist only as machine-local runtime config outside the repo.

**File count arithmetic** (verified against `git ls-files` in `claude/`, 83 tracked today):

| Phase | Change | Tracked after |
| - | - | - |
| start | | 83 |
| A | -31 | 52 |
| B | +21 | 73 |
| C | +1 | 74 |
| D | +6 | 80 |

Correction to the brief: the end state is **80** tracked files, not "roughly 78". The brief's
Phase D list names 5 new files but the secrets section adds a sixth (`scripts/secret.sh`), and
Phase C adds `scripts/leak-check.sh`. Renames are net zero.

**Success Criteria:**

- [ ] `grep -rniE 'legalshield|pplsi|atlassian|newrelic|snowflake|launchdarkly|op://'` over
      `git ls-files` returns zero hits
- [ ] `bash claude/scripts/leak-check.sh` exits 0 and prints which rule sets ran
- [ ] `bash claude/hooks/test-voice-hooks.sh` reports 0 failed and 0 skipped
- [ ] `bash claude/hooks/test-pr-text-style.sh` reports 0 failed
- [ ] `settings.json` names no plugin, no marketplace, and no model ID
- [ ] `bash claude/bootstrap.sh` on a clean machine leaves the repo working tree clean
- [ ] `~/.claude/AGENTS.md` and `~/.claude/CLAUDE.md` resolve to the same inode

## PR Strategy

**Split:** independent PRs

**Rationale:** This is a solo personal dotfiles repo with no CI and no reviewer. Each phase is
one branch and one commit series that leaves the repo working, so each can merge alone. Phase A
is independently valuable on its own: it removes 31 files of employer content whether or not
anything else lands.

**Independence Check:**

- [x] Each PR's diff touches zero files edited by another PR in this plan
- [x] Each PR's branch passes its own checks when rebased onto main by itself
- [x] Reverting one PR does not break the others

Two caveats on strict independence, both accepted:

- Phase B and Phase C both edit `settings.json`. Phase B changes seven keys, Phase C changes
  zero. The hook rename in Phase C is pre-applied in Phase B change 5, so Phase C touches only
  the script file. If the phases land out of order, Phase C's rename must move to Phase C.
- Phase C's `pr-tracker-links.sh` reads `integrations.json`, which Phase D creates. Phase C
  handles the missing file by exiting 0, so a Phase-C-only repo is inert rather than broken.

## Branch Plan

_Consumed by `/execute` to provision git state. One row per phase._

| # | Branch | Base |
| - | - | - |
| 1 | chore/delete-employer-content | main |
| 2 | feat/absorb-voice-system | main |
| 3 | refactor/scrub-vendor-strings | main |
| 4 | feat/slots-and-bootstrap | main |

Worktree paths: `.claude/worktrees/cleanup-pr<N>` for N in 1 to 4.

## Context Loading

_Run before starting:_

```bash
read /Users/valdezjm/.config/dotfiles/claude/settings.json
read /Users/valdezjm/.config/dotfiles/claude/CLAUDE.md
read /Users/valdezjm/.config/dotfiles/claude/agents/chief-of-staff.md
read /Users/valdezjm/.config/dotfiles/claude/hooks/pr-text-style.sh
read /Users/valdezjm/.config/dotfiles/claude/hooks/pr-jira-links.sh
read /Users/valdezjm/.config/dotfiles/.gitignore
glob /Users/valdezjm/Public/source/legalshield-claude-marketplace/plugins/experimental/ls-jmvaldez/voice/**
```

Never read `.env`, `.envrc`, `.env.*`, `credentials.json`, `*.pem`, `*.key`, or
`settings.local.json`. Two of those exist on this machine and are relevant:
`~/.claude/settings.local.json` and `claude/.claude/settings.local.json`. Both stay unread.

---

## Phase A: Delete

_Maps to Branch Plan row 1. About 1 hour. Ships alone and is independently valuable._

Deletes 31 tracked files. Every path below was verified to exist.

### Repo deletions

#### Task A.1: Delete employer-only skills and agents

**Context:** `claude/skills/`, `claude/agents/`

**Steps:**

1. [ ] `git rm -r` these nine skill directories, 22 files total, counts verified:
       `skills/confluence/` (1), `skills/dependabot-sweep/` (4), `skills/jira/` (1),
       `skills/log-hours/` (2), `skills/move-repo-to-gha/` (7), `skills/newrelic/` (1),
       `skills/release-notes-onboard/` (1), `skills/snowflake-report/` (3),
       `skills/standup/` (2)
2. [ ] `git rm agents/data-detective.md agents/ticket-clerk.md`
3. [ ] Confirm nothing surviving references a deleted skill by name. Known forward
       references that Phase C must fix, not this task: `agents/chief-of-staff.md` rows 31 and
       36, and `skills/rollup/SKILL.md` which consumes the standup output directory.

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && git ls-files | wc -l   # expect 59
```

---

#### Task A.2: Delete the four superseded attribution hooks

**Context:** `claude/hooks/`, `claude/settings.json`

Four files, 273 lines, counts verified: `pr-attribution.sh` (55),
`pr-comment-attribution.sh` (55), `pr-issue-comment-attribution.sh` (76),
`pr-review-attribution.sh` (87).

**Correction to the brief.** The brief says "their own headers say pr-ai-attribution.sh
replaced them". That is backwards. The four dead files say nothing about their replacement.
It is `hooks/pr-ai-attribution.sh` lines 5 to 8 that name all four as superseded. The claim
still holds, and the confirmation is stronger than the brief suggested: `settings.json` wires
only `pr-ai-attribution.sh` in its `PostToolUse` / `Bash` block, so all four are unreachable.

**Steps:**

1. [ ] Confirm the wiring before deleting:
       `grep -c 'pr-attribution\|pr-comment-attribution\|pr-issue-comment-attribution\|pr-review-attribution' settings.json`
       must return 0
2. [ ] `git rm` the four files
3. [ ] Edit `hooks/pr-ai-attribution.sh` lines 7 to 8. The sentence "Existing hooks may run
       alongside this during rollout" is now false. Replace with a note that the idempotency
       guard keys on the attribution marker.

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && \
  grep -rn 'pr-attribution\|pr-review-attribution' . --include='*.json' --include='*.sh' \
  | grep -v pr-ai-attribution ; echo "exit=$?"   # expect no matches
```

---

#### Task A.3: Untrack plan docs, drop the obsolete script, fix gitignore

**Context:** `claude/plans/`, `claude/scripts/`, `/Users/valdezjm/.config/dotfiles/.gitignore`

`scripts/check-output-style.sh` is 122 lines. Its header states it exists because a
plugin-namespaced output style resolves to `null` rather than erroring. Phase B moves the
style into `output-styles/direct.md` and sets `outputStyle` to the bare name `direct`, so the
failure mode the script guards stops existing.

**Steps:**

1. [ ] `git rm --cached plans/2026-08-20-output-voice-control.md
       plans/done/2026-04-16-workflow-improvements.md`. Untrack only. Do not scrub and do not
       delete from disk.
2. [ ] `git rm scripts/check-output-style.sh`
3. [ ] Add `claude/plans/` to `/Users/valdezjm/.config/dotfiles/.gitignore`. That file already
       uses `claude/`-prefixed paths, so root placement matches the existing convention. Note
       that `claude/.gitignore` also exists and is the alternative home.
4. [ ] **New, not in the brief.** Add `claude/skills/synced/` to the same gitignore.
       `git status` today reports `?? skills/synced/` as untracked and unignored. It holds
       harness-synced third-party skills. One `git add -A` sweeps 40-plus vendored files into
       the repo. It is clutter rather than a leak, but it is one keystroke from being tracked.
5. [ ] Confirm this plan file becomes untracked once step 3 lands. That is intended.

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles && git status --short && git check-ignore -v claude/plans claude/skills/synced
```

---

### Machine-local cleanup

#### Task A.4: Remove the credential-caching MCP launcher and settle two path defects

**Context:** `~/.claude/`, `~/.claude.json`, `~/.config/opencode`

None of this is tracked, so none of it appears in the diff. Do it by hand in the same sitting.

**Steps:**

1. [ ] Delete `~/.claude/mcp-launchdarkly.sh`. Verified present, 1194 bytes, mode 700. It
       cached a credential in `$TMPDIR` for 720 minutes.
2. [ ] Remove the `launchdarkly` entry from `~/.claude.json`. Note for the record: that server
       already fails to connect with `CONNECTION_CLOSED`, so nothing is lost.
3. [ ] Write the standing rule into `CLAUDE.md` under Sensitive Files in Phase C: no script in
       this config writes a credential to disk, to `$TMPDIR`, or to any cache, for any TTL.
4. [ ] **Dangling symlink.** `~/.config/opencode` points at
       `/Users/valdezjm/.config/dotfiles/opencode`, which does not exist. Verified broken,
       link created 2026-03-12. **Decision: remove the symlink.** Phase D's OpenCode story is
       `AGENTS.md` plus the already-shared `~/.claude/skills`, so nothing needs a
       `dotfiles/opencode` directory. Creating an empty target would be a second config root
       with nothing in it. Run `rm ~/.config/opencode`.
5. [ ] **Two plans directories.** `~/.claude/plans` is a real directory holding 9 plan files
       plus a `done/` subdirectory with 82 more. `claude/plans/` in the repo holds 3 files.
       `~/.claude/{agents,hooks,knowledge,skills,CLAUDE.md,settings.json}` are all symlinks
       into the repo, so `plans` is the odd one out. **Decision: `~/.claude/plans` wins and
       stays a real directory. Do not symlink.** It has 30 times the content, `/plan` and
       `/execute` already write there, and Phase A gitignores the repo copy so a symlink would
       only create a tracked-looking path that git ignores. Move the three repo plan files into
       `~/.claude/plans/` and leave `claude/plans/` as a gitignored scratch directory, or
       delete it. Record the choice in `README.md` in Phase D.

**Verify:**

```bash
ls -la ~/.claude/mcp-launchdarkly.sh ~/.config/opencode 2>&1 | grep -c 'No such file'  # expect 2
jq -e '.mcpServers.launchdarkly // empty' ~/.claude.json ; echo "expect exit 1, got $?"
```

---

## Phase B: Absorb the voice system

_Maps to Branch Plan row 2. About 4 hours. **Highest risk phase.**_

**Correction to the brief: the source root is wrong.** The brief gives
`.../plugins/experimental/voice/`. That path does not exist. The real root is:

```
/Users/valdezjm/Public/source/legalshield-claude-marketplace/plugins/experimental/ls-jmvaldez/voice/
```

The writer guide path in the brief is correct:
`.../plugins/experimental/internal-tools/knowledge/writer/`.

**Correction: eight files copy with zero edits, not nine.** The brief's zero-edit list has
eight entries plus `test-hooks.sh`, which needs five separate edits. Twenty-one files total
still holds: 9 voice files plus 12 writer files.

**Risk.** `test-hooks.sh` is 867 lines and resolves its own plugin root by walking four
directories up. `test-pr-text-style.sh` is 398 lines and sandboxes `HOME` per test to control
a plugin manifest lookup that Phase C deletes. Path rewrites inside both are fiddly and the
second needs its fixtures reworked. This is where the plan is most likely to stall. Task B.2
is the single riskiest task in the plan.

### Voice hooks and scripts

#### Task B.1: Copy the eight zero-edit voice files

**Context:** the source root above, `claude/hooks/`, `claude/scripts/`, `claude/output-styles/`

`claude/output-styles/` does not exist yet. Create it.

**Steps:**

1. [ ] `mkdir -p claude/output-styles claude/hooks/lib`
2. [ ] Copy with zero edits, line counts verified:
       `output-styles/direct.md` (76) from `voice/output-styles/`;
       `hooks/lib/voice-patterns.sh` (266) and `hooks/lib/contract.sh` (15) from
       `voice/hooks/lib/`; `hooks/inject-voice-digest.sh` (30),
       `hooks/subagent-voice.sh` (54), `hooks/voice-check.sh` (83), `hooks/meter.py` (271)
       from `voice/hooks/`; `scripts/voice-report.py` (176) from `voice/scripts/`
3. [ ] Confirm zero edits are actually needed. Verified: the three hooks that source a library
       use `source "$HOOK_DIR/lib/<file>"` with `HOOK_DIR` derived from `$0`, so the
       `hooks/lib/` layout carries over unchanged. No file under `voice/hooks/`,
       `voice/scripts/`, or `voice/output-styles/` references `CLAUDE_PLUGIN_ROOT`.
4. [ ] Confirm zero employer strings. Verified: a case-insensitive grep for the company name,
       the Atlassian host, the tracker, New Relic, Snowflake, 1Password, `op://`, and two
       project keys across `voice/hooks/`, `voice/scripts/`, `voice/output-styles/`, and
       `voice/tests/` returns no matches.
5. [ ] Do **not** copy `voice/hooks/hooks.json` (40 lines, folds into `settings.json` in
       Task B.4) or `voice/.claude-plugin/plugin.json` (10 lines, holds an employer email
       address at line 6). Verified.
6. [ ] `chmod +x` the four shell hooks and the two Python files.

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && \
  bash -n hooks/inject-voice-digest.sh hooks/subagent-voice.sh hooks/voice-check.sh \
          hooks/lib/voice-patterns.sh hooks/lib/contract.sh && \
  python3 -m py_compile hooks/meter.py scripts/voice-report.py && echo OK
```

---

#### Task B.2: Copy the hook test suite and repoint five path sites

**Context:** `voice/tests/test-hooks.sh` (867 lines), `claude/hooks/`

Copy to `claude/hooks/test-voice-hooks.sh`.

**Correction to the brief: five edit sites, not one.** The brief names only `GUIDE_RELPATH`
around line 775. Verified sites:

| Line | What | Change |
| - | - | - |
| 2 | plugin name in header | repo-relative wording |
| 5 | `Run:` path | `bash claude/hooks/test-voice-hooks.sh` |
| 9-11 | `TESTS_DIR`/`PLUGIN_ROOT`/`HOOKS_DIR` | tests now live in `hooks/` |
| 761-772 | drift-test comment | rewrite, PR #216 is gone |
| 775-777 | `GUIDE_RELPATH`, `REPO_ROOT` | same-repo paths |

Line 9 to 11 read `TESTS_DIR=$(dirname $0)`, `PLUGIN_ROOT="$TESTS_DIR/.."`,
`HOOKS_DIR="$PLUGIN_ROOT/hooks"`. The suite moves from `voice/tests/` into `hooks/` itself, so
`HOOKS_DIR` becomes `$(cd "$(dirname "$0")" && pwd)` directly and `PLUGIN_ROOT` collapses to
the repo `claude/` directory one level up. Line 777 computes
`REPO_ROOT="$(cd "$PLUGIN_ROOT/../../../.." && pwd)"`, a four-level walk out of the marketplace
worktree. Same-repo it becomes a two-level walk from `hooks/` to the dotfiles root, or drop
`REPO_ROOT` and use a path relative to `HOOKS_DIR`.

**The drift guard goes live, and this is a real win.** Verified: line 782 gates on
`[ -f "$REPO_ROOT/$GUIDE_RELPATH" ]` and the whole block falls through to
`skip "drift: guide vs library"` when nothing resolves. The guide lived on an unmerged branch
of a different repo, so the test has been skipping. Same-repo the path resolves from the
working tree on the first try, so the assertion runs. Two extra properties worth keeping: the
block already fails, not skips, when the guide resolves but zero `[regex]` entries parse
(lines 819 to 824), and the `origin/main` and local-`main` fallbacks at lines 788 to 796
become dead code that can be deleted.

**Steps:**

1. [ ] Copy the file, then apply the five edits in the table above
2. [ ] Delete the `origin/main` and local-`main` fallback branches, lines 786 to 796
3. [ ] Delete the `skip` branch at 799 to 801 and replace with a `fail`. Same-repo, an
       unresolvable guide is a broken repo, not an expected state.
4. [ ] Run the suite and confirm the drift test now reports PASS, not SKIP

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && bash hooks/test-voice-hooks.sh 2>&1 | tail -20
# expect "0 failed, 0 skipped" and a PASS line for "drift: guide vs library"
```

---

### Writer guide

#### Task B.3: Copy the writer guide and scrub three employer sentences

**Context:** `.../experimental/internal-tools/knowledge/writer/`, `claude/knowledge/writer/`

Twelve markdown files: `writer.md` (80), `forbidden-patterns.md` (144), and ten personas.
The source directory also holds a `.DS_Store`. Do not copy it.

**Correction to the brief: three scrub sites, not two.** The brief names `writer.md` and
`personas/analyst.md`, then asks to check four more personas. Verified results:

| File | Line | Content |
| - | - | - |
| `writer.md` | 28 | names the tracker skill |
| `analyst.md` | 24 | names the employer |
| `contributor.md` | 28 | employer project key |

`marketer.md`, `pm.md`, and `qa-tester.md` are clean. `architect.md`, `educator.md`,
`engineer.md`, `researcher.md`, and `ux-writer.md` are clean.

`contributor.md` line 28 ends a sample commit body with `Closes COREAPP1-1234`. That is a real
employer project key, not a placeholder. It matters beyond tidiness: Phase C's `leak-check.sh`
flags ticket-key shapes, so leaving it in makes the new check fail on a file this phase just
added.

**Steps:**

1. [ ] `mkdir -p claude/knowledge/writer/personas` and copy the 12 markdown files
2. [ ] `writer.md` line 28: "The Jira skill" becomes "The tracker skill"
3. [ ] `analyst.md` line 24: swap the employer name out of the example subject. Use a generic
       subject such as "The two closest competitors have shifted toward self-serve onboarding".
4. [ ] `contributor.md` line 28: `Closes COREAPP1-1234` becomes `Closes TICKET-1234`
5. [ ] Re-run the grep from the verify block below and confirm zero hits

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && \
  grep -rniE 'legalshield|pplsi|atlassian|jira|newrelic|snowflake|COREAPP|OPSUC' knowledge/writer/ \
  ; echo "expect exit 1, got $?"
```

---

### Settings

#### Task B.4: Fold the voice plugin into settings.json

**Context:** `claude/settings.json`, `voice/hooks/hooks.json`

Seven changes.

1. [ ] Delete `enabledPlugins` (three keys: the internal tools plugin, an HTML doc plugin, and
       the voice plugin) and `extraKnownMarketplaces` (one entry pointing at a local directory
       path under `~/Public/source/`). Verified present.
2. [ ] Change `outputStyle` from the plugin-namespaced value to `direct`. It resolves from the
       new `output-styles/` directory created in Task B.1.
3. [ ] Remove `Bash(jira:*)` and `Bash(newrelic:*)` from `permissions.allow`. Verified present.
4. [ ] Move the `env` block to `settings.local.json`. Four keys, all model IDs. Those are
       account shape, not config. **`settings.local.json` is on the never-read list, so this
       step is an instruction for you to perform by hand, not an agent edit.** `bootstrap.sh`
       in Phase D writes the same block by merging with `jq`, never by overwriting.
5. [ ] Rename the `pr-jira-links.sh` hook entry to `pr-tracker-links.sh`. The script file is
       renamed in Phase C Task C.2. Pre-applying the settings half here keeps Phase C's diff to
       script files only.
6. [ ] Transcribe four hook entries from `voice/hooks/hooks.json`, rewriting
       `${CLAUDE_PLUGIN_ROOT}` as `~/.claude` to match the existing entries:

```json
"UserPromptSubmit": [
  { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/inject-voice-digest.sh" } ] }
]
```

  plus a `PreToolUse` entry with `"matcher": "Agent"` running `subagent-voice.sh`, and two
  `Stop` entries in one block: `bash ~/.claude/hooks/voice-check.sh` then
  `python3 ~/.claude/hooks/meter.py` with `"timeout": 10`. The `PreToolUse` addition is a new
  matcher block. `settings.json` already has `PreToolUse` blocks for `Read` and `Bash`, so
  append rather than replace.

7. [ ] Leave `statusLine.command` pointing at `~/.claude/statusline-command.sh`. Phase D
       Task D.1 makes that path a symlink into the repo.

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && jq -e '
  (.enabledPlugins == null) and (.extraKnownMarketplaces == null) and
  (.outputStyle == "direct") and (.env == null) and
  ([.permissions.allow[] | select(test("jira|newrelic"))] | length == 0) and
  (.hooks.Stop | length == 1)
' settings.json && echo OK
```

---

## Phase C: Scrub strings

_Maps to Branch Plan row 3. About 3 hours. 15 files, corrected up from the brief's 14._

The extra file is `knowledge/documenting-code-comments.md`, explained in Task C.7.

### Prose and identity

#### Task C.1: Rewrite four CLAUDE.md sections

**Context:** `claude/CLAUDE.md` (3762 bytes)

**Steps:**

1. [ ] **Identity**, line 5. Delete the plugin-manifest resolution clause and the fallback
       sentence. Replace with direct paths: `~/.claude/knowledge/writer/writer.md`,
       `~/.claude/knowledge/writer/forbidden-patterns.md`, and
       `~/.claude/knowledge/writer/personas/<name>.md`. Those paths become real in Phase B.
2. [ ] **PR Descriptions**, line 25. "linking every Jira ticket" becomes "linking every tracker
       ticket".
3. [ ] **Tech Stack Context**, lines 51 to 57. Delete line 51 (employer GitHub org), the
       internal repo name patterns on the first stack bullet, line 56 (feature flag vendor),
       and line 57 (observability vendor). Keep the four generic stack bullets: the pnpm
       monorepo bullet with the repo-name patterns stripped, the .NET bullet, the Java Spring
       bullet, and the Playwright bullet.
4. [ ] **Sensitive Files.** Add the rule from Phase A Task A.4 step 3: no script in this config
       writes a credential to disk, to `$TMPDIR`, or to any cache, for any TTL.
5. [ ] **Verification** is already generic. Leave it alone. Verified: no vendor names.

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && \
  grep -niE 'legalshield|atlassian|jira|newrelic|new relic|launchdarkly|installed_plugins' CLAUDE.md \
  ; echo "expect exit 1, got $?"
```

---

#### Task C.2: Rename pr-jira-links.sh and drop both host literals

**Context:** `claude/hooks/pr-jira-links.sh` (41 lines)

Two hardcoded host sites, verified:

- line 23, the already-linked guard: `grep -q "atlassian.net/browse/"`
- line 36, the link template: `https://legalshield.atlassian.net/browse/$ticket`

The brief says "a guard near line 25". It is line 23.

**Steps:**

1. [ ] `git mv hooks/pr-jira-links.sh hooks/pr-tracker-links.sh`
2. [ ] Read `tracker.browse_url` from `~/.claude/integrations.json` with `jq`. Exit 0 when the
       file is missing or the key is absent, so a fresh clone is inert. Phase D creates the
       file, and this hook must not require it.
3. [ ] Rebuild the guard from the configured URL rather than a literal host
4. [ ] Rebuild the link template as `[$ticket](${BROWSE_URL}${ticket})`
5. [ ] Keep the ticket-key extractor at line 28 unchanged. Verified generic:
       `grep -oE '[A-Z][A-Z0-9]+-[0-9]+'`. Its trailing comment names an employer branch
       pattern, so scrub the comment text.
6. [ ] Update the header comment on lines 1 to 3: "Jira links" becomes "tracker links"

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && bash -n hooks/pr-tracker-links.sh && \
  grep -c atlassian hooks/pr-tracker-links.sh ; echo "expect 0" && \
  echo '{}' | HOME=$(mktemp -d) bash hooks/pr-tracker-links.sh ; echo "inert exit=$?"
```

---

### Enforcement hooks

#### Task C.3: Point pr-text-style.sh at the in-repo library and cut four host sites

**Context:** `claude/hooks/pr-text-style.sh` (197 lines), `claude/hooks/lib/voice-patterns.sh`

**Correction to the brief, and this is the largest one in Phase C.** The brief lists only the
manifest resolution block and a header comment. Verified employer-host sites in this file:

| Lines | Kind | Brief mentions it |
| - | - | - |
| 7-8 | header comment | partly |
| 21-24 | header comment | partly |
| 32-60 | manifest jq block | yes |
| 174-183 | live grep, surface 3 | no |
| 187-193 | live grep, surface 4 | no |

Lines 180 and 190 are **live code**, not comments. They read
`grep -qE 'legalshield\.atlassian\.net/rest'` and `grep -qE 'legalshield\.atlassian\.net/wiki'`
and they gate whether the style scan runs on a `curl` write at all. The brief missed them. They
cannot be deleted without deciding what replaces them.

**Recommendation: make both surfaces host-agnostic.** Collapse surfaces 3 and 4 into one gate:
any `curl` carrying a data flag gets `scan_cmd`. The file's own design note at lines 11 to 14
already argues that the scope gate should key on body-writing flags rather than endpoint path,
because `gh api $REPO/...` bypasses a path regex. The host check is the last place that
reasoning was not applied. Removing it widens coverage to every `curl` body write, which is the
correct behavior for a style gate and removes the vendor coupling with no config dependency.

The alternative is reading the tracker and wiki hosts from `integrations.json`, matching
Task C.2. Rejected here: it re-narrows a gate that should have been broad, and it makes the
style hook depend on Phase D.

Cost of the recommendation, stated plainly: the hook now scans banned phrases inside unrelated
`curl` POST bodies. It only ever blocks on a phrase from the voice library, so a false positive
means a genuine banned phrase in a genuine outbound body. Acceptable.

**Steps:**

1. [ ] Delete the manifest resolution block, lines 32 to 60, 29 lines. Replace with
       `source "$(dirname "$0")/lib/voice-patterns.sh"`. The fail-open warning goes with it: a
       missing in-repo library is a broken repo, so fail loudly instead.
2. [ ] Rewrite the header comment. Lines 7 and 8 name the employer host twice. Lines 21 to 24
       describe the plugin resolution and the fail-open contract, both now gone.
3. [ ] Collapse surfaces 3 and 4 into one host-agnostic `curl` gate. Keep the existing data-flag
       regex `(-d|--data(-raw|-binary)?)[[:space:]]` and the note that start-anchored
       `BODY_ONLY_PATTERNS` are not applied to arbitrary `curl` invocations.
4. [ ] Confirm the two `scan_cmd` call sites collapse to one and the final `exit 0` survives

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && bash -n hooks/pr-text-style.sh && \
  grep -c 'atlassian\|installed_plugins' hooks/pr-text-style.sh ; echo "expect 0"
```

---

#### Task C.4: Rework the style hook's test fixtures

**Context:** `claude/hooks/test-pr-text-style.sh` (398 lines)

Verified edit sites:

1. [ ] Lines 13 to 34, library resolution. Drop the `VOICE_PATTERNS_LIB` env override and the
       manifest branch. Source `hooks/lib/voice-patterns.sh` relative to `SCRIPT_DIR`. The
       comment at 17 to 19 arguing against a hardcoded checkout path no longer applies, because
       the library is now in the same repo as the test.
2. [ ] Lines 53 to 70, the `inject_lib` helper. It writes a sandbox
       `installed_plugins.json` naming the plugin. Delete the whole function.
3. [ ] Lines 72 to 88, `run_hook`. It calls `inject_lib` and sandboxes `HOME` so the hook sees
       the fake manifest. Keep the `HOME` sandbox (other assertions rely on it) and drop the
       `inject_lib` call.
4. [ ] Lines 90 to 104, `run_hook_no_plugin`. Writes an empty manifest to assert the fail-open
       path. That path is deleted in Task C.3, so delete this helper and every test that calls
       it. Count those calls before deleting.
5. [ ] Lines 288 to 318, the curl fixture group. Three fixtures use the employer host, at 294,
       303, and 312. Line 303 also carries an employer project key
       (`/rest/api/3/issue/COREAPP1-123`). The brief flagged the hosts but not the key. Change
       all four values to a neutral example host such as `https://tracker.example.com`, and the
       key to `TICKET-123`. Rename the group heading at 288 and 291 from the vendor name to
       "tracker writes".

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && bash hooks/test-pr-text-style.sh 2>&1 | tail -10
# expect "0 failed"
```

---

### Agents and skills

#### Task C.5: Generalize chief-of-staff.md

**Context:** `claude/agents/chief-of-staff.md` (116 lines)

The largest judgement call in the plan. Keep the file's shape and cut only what is employer
specific.

**Correction: the second-person rewrite is bigger than the brief implies.** The brief says
"replace the user's first name with second person". Verified: the first name appears at lines
15, 21, 61, 83, and 94, and third-person pronouns run through lines 87 to 88 and 94 to 109.
That is 5 name sites plus roughly 12 pronouns, so the rewrite touches five sections rather than
one line.

**Steps:**

1. [ ] Delete routing rows 31 and 36, the two agents removed in Phase A
2. [ ] Delete the pinned model IDs at lines 47 to 49, not 47 to 48 as the brief says. Keep the
       alias names. The sentence "Sonnet 5 and Fable were removed in mid-August 2026" is
       account history, so drop it and keep "never assume a tier exists" plus the fallback
       ladder at 51 to 57.
3. [ ] Line 67, inside the parallel-dispatch section: "read-only against Snowflake and New
       Relic" becomes "read-only against a data warehouse or observability tool". The section
       itself stays.
4. [ ] Delete the three named serial paths at lines 72 to 76. Line 72 carries an internal app
       name and two internal component file names. Replace all three bullets with one rule:
       serialize any two agents that share a file.
5. [ ] Line 99: "Never open a Jira ticket speculatively" becomes "Never open a tracker ticket
       speculatively".
6. [ ] Rewrite the first name and third-person pronouns to second person across lines 15, 21,
       61, 83 to 88, and 94 to 109. Line 15's dated quote attribution becomes "You told me
       this, after saying it four times first". Line 62's "180 delegations" is personal
       telemetry, not employer content, and can stay or go.
7. [ ] **Add the escalation protocol** (Borrowed idea 2, specified in Phase D). New section,
       roughly 12 lines. A worker subagent cannot prompt for a vendor or a credential. When one
       hits an unconfigured slot: it stops that line of inquiry immediately, does not retry,
       and returns a `NEEDS_SETUP` marker naming the slot, the exact value it wanted, and every
       partial finding already collected. You catch the marker, ask the user, run the setup step
       in the foreground so credential entry happens on the TTY and never in model context, then
       re-dispatch the same worker with the same brief plus the partial findings so nothing is
       redone. The worker aborts. The task continues.
8. [ ] Keep unchanged: the standing rule (13 to 21, text aside), the fallback ladder, the
       parallel-dispatch section, the Gates section, "Do not ask", and "Skills first". Line 114
       names `/debug` and `/trace-number`, both of which survive Phase A.

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && \
  grep -niE 'snowflake|new relic|jira|int-membership|claude-opus-5|claude-sonnet|claude-haiku|data-detective|ticket-clerk' agents/chief-of-staff.md \
  ; echo "expect exit 1, got $?"
```

---

#### Task C.6: Replace the plan skill's tracker branch with a slot block

**Context:** `claude/skills/plan/SKILL.md` (133 lines)

**Correction: the tracker branch is 53 lines, not "roughly 40".** It runs from line 18 to line
70. It contains a Python manifest resolver (lines 24 to 31), a plugin install instruction naming
the marketplace (33), a path into the deleted tracker skill's reference file (41), and the same
custom field ID four times (43, 45, 50, and the surrounding prose).

**Correction: the approval count appears at three sites, not one.** Verified: line 97 ("Every PR
costs 2 approvals in this org"), line 99 ("One PR = 2 approvals; N stacked PRs = 2N"), and line
121 ("Approvals dismiss on push in this org"). Line 121 also states an org policy, not a count.

**Steps:**

1. [ ] Replace lines 18 to 70 with an 8-line tracker-slot block. Shape: read `tracker.kind`
       from `~/.claude/integrations.json`; when it is `none` or absent, treat the argument as a
       free-text description; otherwise dispatch a worker to fetch the ticket and return title,
       description, acceptance criteria, parent, links, status, comments, and attachments. No
       vendor field IDs and no auth instructions.
2. [ ] Frontmatter lines 3 and 4, plus line 10 and line 108, name the tracker. Change all four
       to "tracker key".
3. [ ] Generalize the approval count. Read `pr.approvals` from `integrations.json` with a
       default of 1. Rewrite line 97 as "Every PR costs N approvals, where N comes from
       `pr.approvals` (default 1)". Rewrite line 99's arithmetic in terms of N. Rewrite line
       121 to drop "in this org" and keep the substantive rule that a push after approval can
       dismiss it.
4. [ ] Add the `NEEDS_SETUP` contract to the dispatched worker's brief, matching Task C.5
       step 7.

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && \
  grep -niE 'jira|customfield|installed_plugins|legalshield|COREAPP|OPSUC|2 approvals' skills/plan/SKILL.md \
  ; echo "expect exit 1, got $?"
```

---

#### Task C.7: Sweep the remaining six files

**Context:** `skills/pr/`, `skills/review/`, `skills/execute/`, `skills/rollup/`, `knowledge/`

**Steps:**

1. [ ] `skills/pr/SKILL.md` line 58. One HTML comment: "A post-tool-use hook populates this".
       Verified it does not name the hook file, so the only change needed is none. **Correction
       to the brief:** the brief says the line names the hook. It does not. Leave the file
       unchanged, or tighten the wording to "the tracker-links hook" for clarity. Either way,
       zero employer strings.
2. [ ] `skills/review/SKILL.md` lines 113 to 116, Angle F. Two vendor-named bullets, each
       spanning two lines, not one line each as the brief states. The feature-flag bullet
       becomes "**Feature flags**: a new flag with no default for evaluation failure, a flag
       read on a hot path without caching, dead code behind a flag already at 100%". The
       observability bullet becomes "**Instrumentation**: a new failure path with no
       instrumentation, an error swallowed before it can be recorded, PII in an attribute or
       log line".
3. [ ] `skills/execute/SKILL.md` line 90. "link the Jira ticket(s)" becomes "link the tracker
       ticket(s)".
4. [ ] `skills/rollup/SKILL.md`, **more sites than the brief lists and one wrong default.** The
       brief says three lines plus a cross-reference at 150 to 153, and says to repoint the
       input directory to `${AGENT_HIGHLIGHTS_DIR:-~/Documents/highlights}`. Verified: the real
       input directory is `~/Documents/standup-log/`, referenced at line 5 and again at line 143
       for the `rollups/` output subdirectory. **Defaulting to `~/Documents/highlights` orphans
       every existing highlights doc.** Use
       `${AGENT_HIGHLIGHTS_DIR:-~/Documents/standup-log}` instead, so existing data keeps
       working and the override still exists. Then: line 5 also names the tracker and the
       observability vendor; lines 80 and 101 carry an employer project key placeholder
       (`COREAPP1-XXXX`, change to `TICKET-XXXX`); and the Integration section at 147 to 155
       references the deleted standup skill twice. Drop the first two Integration bullets and
       keep the third.
5. [ ] `knowledge/executing-plans.md`, **three sites, not one.** The brief says "one word near
       line 89". Verified: line 89 says "any Jira tickets" (change to "any tracker tickets"),
       and the example branch-plan table at lines 32 to 33 uses an employer project key six
       times. Change the table to `feat/TICKET-123-a` and `.claude/worktrees/TICKET-123-pr1`.
       The table matters more than line 89: `leak-check.sh` flags ticket-key shapes.
6. [ ] `knowledge/documenting-code-comments.md`, **not in the brief at all.** Lines 44 and 66
       use `JIRA-1234` and `TODO(JIRA-567)` as comment examples. They are placeholders rather
       than real keys, but they match the ticket-key shape `leak-check.sh` flags, so the choice
       is scrub or allowlist. Scrub: change both to `TICKET-1234` and `TODO(TICKET-567)`.
       Allowlisting a prefix named after a specific vendor's product is the worse option.
7. [ ] `skills/render-sql-template/SKILL.md`: **no change, deliberately.** It mentions a data
       warehouse at lines 28, 30, and 42. Line 30 sits in a list beside `psycopg2.connect`, and
       line 42 pairs it with BigQuery. Those are driver and product names in a list of drivers
       and products, not employer content. Stated here explicitly so a future pass does not
       "fix" it. `leak-check.sh` uses structural rules only and will not flag it.
8. [ ] Files verified already clean, no action: `hooks/prettier-write.sh` (50),
       `hooks/worktree-conflict.sh` (113), `hooks/worktree-env-symlink.sh` (95),
       `hooks/pr-ai-attribution.sh` (236, after the Task A.2 comment fix).

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && \
  grep -rniE 'jira|new relic|newrelic|launchdarkly|COREAPP|OPSUC|standup-log/\b' \
    skills/pr skills/review skills/execute skills/rollup knowledge/executing-plans.md \
    knowledge/documenting-code-comments.md ; echo "expect exit 1, got $?"
```

---

#### Task C.8: Add scripts/leak-check.sh

**Context:** `claude/scripts/`

Structural rules only. A committed deny list of employer strings would itself be the leak.

**Rule sets:**

| Rule | Matches | Notes |
| - | - | - |
| ticket keys | `[A-Z][A-Z0-9]{1,9}-[0-9]+` | allowlist below |
| vault refs | `op://`, `op read`, `op item` | any hit fails |
| host shapes | tracker/wiki/IdP subdomains | see below |
| account URLs | vendor account-ID URL shapes | see below |

- **Ticket keys.** Allowlist entries live in the script, each requiring an inline reason.
  Seed it with `TICKET` (generic placeholder used in examples), `RFC`, and `ISO`. Anything
  else fails with the file, line, and matched key.
- **Host shapes.** Match `*.atlassian.net`, `*.jira.com`, `*.okta.com`, `*.onelogin.com`,
  `*.slack.com/archives/`, and `*.sharepoint.com`. These are product-domain shapes, not
  employer names, so committing them leaks nothing.
- **Account URLs.** Match URL forms that embed a numeric or GUID account or org identifier,
  such as `one.newrelic.com/.../accounts/<digits>` and `app.launchdarkly.com/<org>/`.
- **Output.** Print one line per rule set with a ran/skipped marker and a hit count, so a
  silently empty run is visible. Exit non-zero on any hit. This is the same failure mode the
  voice drift test guards against, and it must not reappear here.

**What structural rules cannot catch.** Stated plainly, because this check will give false
confidence otherwise:

- A bare company name in prose. No pattern distinguishes it from any other proper noun.
- An internal service, table, or repo name. `int-membership-details` and `members_v2` look
  exactly like open-source names.
- Employer domain vocabulary. Product tier names, plan codes, and internal jargon are ordinary
  English words.
- An internal hostname on a company domain that does not match a known vendor shape.
- Anything in a plan doc, a commit message, or a branch name. This script reads tracked files
  in the working tree only.

The scrub in Tasks C.1 through C.7 is the actual control. `leak-check.sh` is a regression guard
for the shapes that recur, not a substitute for reading the diff.

**Steps:**

1. [ ] Write `scripts/leak-check.sh`. Iterate `git ls-files` so untracked scratch files are out
       of scope. Skip `scripts/leak-check.sh` itself, since it contains every pattern.
2. [ ] Wire it into both test suites, or add a `scripts/test-all.sh` that runs
       `hooks/test-voice-hooks.sh`, `hooks/test-pr-text-style.sh`, and `scripts/leak-check.sh`
       and sums the counts. `bootstrap.sh` calls the same three in Phase D.
3. [ ] Document in `README.md` (Phase D) that this runs before any push, and that it does not
       replace reading the diff.
4. [ ] Run it against the Phase C branch and fix every hit

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && bash scripts/leak-check.sh
# expect 4 rule-set lines, all "ran", 0 hits, exit 0
```

---

## Phase D: Slots, bootstrap, docs

_Maps to Branch Plan row 4. About 5 hours. Adds 6 files._

`scripts/statusline.sh`, `scripts/secret.sh`, `bootstrap.sh`, `AGENTS.md` (symlink),
`README.md`, `integrations.example.json`.

### Vendor slots

#### Task D.1: Bring the statusline into the repo

**Context:** `~/.claude/statusline-command.sh`, `claude/scripts/`, `claude/settings.json`

**Steps:**

1. [ ] Copy `~/.claude/statusline-command.sh` to `claude/scripts/statusline.sh`, zero edits.
       **Correction: 49 lines, not "about 46".** Verified generic: a grep for the company name,
       the Atlassian host, three vendors, `op://`, two project keys, an internal app name, and
       the user's own name returns no matches.
2. [ ] Change `settings.json` `statusLine.command` to
       `bash ~/.claude/scripts/statusline.sh`. `~/.claude/scripts` becomes a symlink into the
       repo in Task D.4.
3. [ ] Delete the real file at `~/.claude/statusline-command.sh` only after the new path works

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && \
  echo '{}' | bash scripts/statusline.sh && \
  jq -r '.statusLine.command' settings.json   # expect the scripts/ path
```

---

#### Task D.2: Define the slot config and the query cache

**Context:** `claude/integrations.example.json`, affected skill outlines

**Config.** `~/.claude/integrations.json`, mode 600. It sits outside any git repo, so it is
untracked with no gitignore rule needed. The template is committed as
`integrations.example.json`.

Six flat keys, no schema version:

```json
{
  "tracker": { "kind": "none", "browse_url": "" },
  "wiki": { "base_url": "" },
  "obs": { "name": "" },
  "pr": { "approvals": 1 },
  "highlights": { "dir": "~/Documents/standup-log" }
}
```

Never a query. Names and URLs only.

**Learned queries.** Cached at `~/.claude/cache/queries/<slot>.<intent>.txt`, for example
`obs.error-rate.txt` and `tracker.my-open.txt`. A skill reads the file. On a miss it asks the
user to paste the query once, echoes it back for confirmation, and writes it there. The repo
never learns vendor query syntax, so the no-warehouse-SQL, no-tracker-query-language,
no-metrics-query-language constraint holds by construction rather than by review.

**The path convention already exists on this machine.** Verified: `~/.claude/` holds
`voice-meter.jsonl` (382 KB, written by `meter.py` via `pathlib.Path.home() / ".claude" /
"voice-meter.jsonl"` at line 231), a `cache/` directory with `changelog.md`,
`my-closed-issues.json`, and a `model-catalog/` subdirectory, plus `jira-cache.json`,
`gh-pr-status-cache.json`, and `stats-cache.json`. Untracked runtime state under `~/.claude`
is the existing pattern, not a new one. `cache/queries/` is a new subdirectory in a directory
that already exists.

**No adapter registry.** A skill outline says "read the observability query from cache slot
`obs.error-rate`, or ask". That is about 3 lines in a skill and zero registry files.

**Shortfalls, stated plainly:**

- The cache is per machine, unversioned, and unbacked. A new machine means re-answering every
  prompt.
- A wrong cached query stays silently wrong. There is no review gate and no expiry.
- The confirmation echo is the only validation. A query that parses but measures the wrong
  thing passes it.

**Steps:**

1. [ ] Write `integrations.example.json` with the six keys, all at safe defaults
2. [ ] Add the cache-slot read-or-ask block to the skills that need it: `skills/plan/SKILL.md`
       (tracker), `skills/rollup/SKILL.md` (highlights dir), and any skill that wants an
       observability query
3. [ ] Add the `NEEDS_SETUP` escalation contract to each of those outlines, matching Task C.5
       step 7
4. [ ] Document the cache path and the read-or-ask flow in `README.md`

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && jq -e '
  (.tracker.kind != null) and (.wiki.base_url != null) and (.obs.name != null) and
  (.pr.approvals == 1) and (.highlights.dir != null)
' integrations.example.json && echo OK
```

---

#### Task D.3: Add scripts/secret.sh

**Context:** `claude/scripts/`

**The 1Password claim from the brief is verified true.** A grep for `op read`, `op://`,
`op item`, and the vendor name across all 83 tracked files returns 24 hits in 10 files:
`agents/ticket-clerk.md`, `skills/confluence/SKILL.md`, `skills/dependabot-sweep/SKILL.md`,
`skills/dependabot-sweep/references/clearing-alerts-npm.md`, `skills/jira/SKILL.md`,
`skills/log-hours/SKILL.md`, `skills/log-hours/scripts/log_hours.py`,
`skills/newrelic/SKILL.md`, `skills/release-notes-onboard/SKILL.md`, and
`skills/standup/SKILL.md`. **All ten are inside the Phase A deletions.** After Phase A, zero
surviving files reference a password manager. No further scrub is needed.

What remains needs no vault. `pr-ai-attribution.sh` and `pr-tracker-links.sh` both shell out
to `gh`, which owns its own auth.

**Steps:**

1. [ ] Write `scripts/secret.sh`, about 6 lines: if `$AGENT_SECRET_CMD` is set, run it with the
       key name as its argument and echo stdout; otherwise echo nothing and exit 1.
2. [ ] Skills read a plain environment variable and fail with one line naming the variable.
       No skill calls a vault directly.
3. [ ] Hard rules, written into the script header and `README.md`: never write a secret to
       disk, never cache one, never log one. This is the rule the deleted MCP launcher broke.

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && \
  bash scripts/secret.sh SOME_KEY ; echo "expect exit 1, got $?" && \
  AGENT_SECRET_CMD='echo stub' bash scripts/secret.sh SOME_KEY   # expect "stub"
```

---

### Bootstrap

#### Task D.4: Write bootstrap.sh

**Context:** `claude/bootstrap.sh`, `~/.agents/.skill-lock.json`

Target about 150 lines.

**Steps, in order:**

1. [ ] Preflight `bash`, `git`, `jq`, `gh`. Report every missing tool at once, then exit 1.
       Do not stop at the first.
2. [ ] Resolve the repo root from `$0` and print it
3. [ ] Back up any real file or directory found at a link target into
       `~/.claude/backups/<timestamp>/`. That directory already exists on this machine and
       holds 6 entries, so the convention is established.
4. [ ] Create symlinks in `~/.claude`: `CLAUDE.md`, `settings.json`, `agents`, `hooks`,
       `knowledge`, `skills`, `output-styles`, `scripts`. Use absolute targets. The six links
       that exist today already use absolute targets (verified, all of the form
       `/Users/valdezjm/.config/dotfiles/claude/<name>`), so the brief's warning about a
       relative `../../../../` form does not describe the current state. Keep absolute anyway.
       `output-styles` and `scripts` are new links.
5. [ ] Write the model env block into `~/.claude/settings.local.json` **by merging with `jq`,
       never by overwriting**. That file exists today (203 bytes) and is on the never-read
       list, so the script must treat it as opaque: read it with `jq`, merge, write back.
6. [ ] Write `~/.claude/integrations.json` at mode 600 from the answers below
7. [ ] Install third-party skills. Loop `~/.agents/.skill-lock.json` into `~/.agents/skills/`,
       then symlink each into `claude/skills/`. Verified shape: top-level `version: 3` and a
       `skills` object keyed by skill name, each value carrying `source`, `sourceType`,
       `sourceUrl`, `skillPath`, `skillFolderHash`, `pluginName`, `installedAt`, and
       `updatedAt`. The file is 16075 bytes and `~/.agents/skills/` holds 38 entries. The
       resulting symlinks are already enumerated in `/Users/valdezjm/.config/dotfiles/.gitignore`,
       so they stay untracked.
8. [ ] Link `AGENTS.md` if asked
9. [ ] Run `hooks/test-voice-hooks.sh`, `hooks/test-pr-text-style.sh`, and
       `scripts/leak-check.sh`. Print pass and fail counts. Exit non-zero on any failure.

**Questions, in order, each with a default:**

| Question | Default |
| - | - |
| repo root correct | detected path |
| which model tiers | all three |
| tracker kind | none |
| ticket browse URL | asked only if "other" |
| wiki base URL | none |
| observability name | none |
| approvals per PR | 1 |
| enable voice hooks | no |
| install locked skills | yes |
| OpenCode AGENTS.md path | none |

The tracker question offers `github`, `other`, `none`. The observability question takes a
**name only, never a query**. The OpenCode path defaults to none because that location could
not be verified from this machine: the only OpenCode config path present was
`~/.config/opencode`, a dangling symlink removed in Phase A Task A.4.

**What bootstrap refuses to do:**

- Install Homebrew, a language runtime, `gh`, or `jq`
- Write, read, or cache any secret
- Overwrite a real file at a link target
- Guess a tracker, wiki, or observability vendor
- Write anything inside the repo, so the working tree stays clean
- Run `git commit`, `git push`, or any network call except the skill clones in step 7
- Touch `settings.json`. Machine-shaped answers land only in `settings.local.json` and
  `integrations.json`.

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && bash -n bootstrap.sh && \
  bash bootstrap.sh --dry-run && git status --short   # expect empty working tree
```

---

### Docs

#### Task D.5: README.md and the AGENTS.md symlink

**Context:** `claude/README.md`, `claude/AGENTS.md`

**Steps:**

1. [ ] `ln -s CLAUDE.md claude/AGENTS.md` and `git add` it. Git tracks the symlink, so both
       harnesses read identical text and drift is impossible by construction.
2. [ ] Write `README.md`. Cover: what the repo is, `bootstrap.sh` usage, the
       `integrations.json` slots, the query cache convention, the invariant from Borrowed idea
       1, the secrets rules from Task D.3, the plans-directory decision from Task A.4 step 5,
       and running `leak-check.sh` before any push.
3. [ ] Include the OpenCode surface table below and the asymmetry paragraph under it

**OpenCode: symlinks only, no build step, no hook port.**

Skill work required is **zero**. OpenCode reads `.claude/skills` as well as `.agents/skills`,
and `~/.claude/skills` is already a symlink to `claude/skills`, so OpenCode already sees every
repo skill. Note that this could not be end-to-end verified on this machine: the only OpenCode
config path present was the dangling `~/.config/opencode` symlink, and no OpenCode binary or
config directory was found.

| Surface | Claude Code | OpenCode |
| - | - | - |
| Prose rules | yes | yes |
| Skills | yes | yes |
| Hooks | yes | no |
| Output style | yes | no |
| Statusline | yes | no |

**Do not port the hooks.** After Phase B the enforcement layer is 1170 lines across 10 hook
files, plus 281 lines in two shared libraries. (**Correction to the brief**, which says "about
1403 lines across 7 live hooks". Verified today: 6 file-based hooks totaling 732 lines, plus
one inline `jq` hook with no file. Phase B adds 4 more files totaling 438 lines. The corrected
post-Phase-B figure is 1170 across 10 files, 1451 including libraries.) A TypeScript plugin
mirroring that is a second implementation of the same rules, guaranteed to diverge. There is
already one hand-sync defect in this repo: `hooks/lib/voice-patterns.sh` is maintained by hand
against `knowledge/writer/forbidden-patterns.md`, and the drift test that catches it has been
skipping because the two files lived in different repos. Document the asymmetry instead:
OpenCode gets the prose rules and loses the mechanical backstop.

**Verify:**

```bash
cd /Users/valdezjm/.config/dotfiles/claude && \
  [ "$(readlink AGENTS.md)" = "CLAUDE.md" ] && git ls-files | wc -l   # expect 80
```

---

## Invariants

Two ideas borrowed from the rejected designs. Both are stated as invariants, not preferences.

**1. Generated state lives outside the repo. It is never gitignored inside it.** A gitignored
file holding employer hostnames is one `git add -f` from a leak, and one `git add -A` from a
leak if the ignore rule is ever edited. Everything machine specific lands in `~/.claude` or
`~/.agents`, never in the repo. The one exception is `claude/plans/`, gitignored in Phase A,
and Task A.4 step 5 resolves that by moving the content to `~/.claude/plans` so the ignored
directory holds nothing worth leaking.

**2. The orchestrator owns the conversation.** Worker subagents are non-interactive. They
cannot prompt for a vendor or a credential. An unconfigured slot hit mid-task must escalate,
never guess and never retry. The full sequence is in Task C.5 step 7. The worker aborts. The
task continues.

## What you give up

No hedging on any of these.

- **Employer tooling stops working on the work machine.** Phase A deletes nine skills, two
  agents, and every vault integration. Without a private overlay, ticket reads, wiki writes,
  warehouse queries, observability lookups, hour logging, standup generation, the Dependabot
  sweep, the CI migration skill, and the release-notes onboarding are all gone from this
  machine. **This is the largest unrecoverable cost in the plan** and the reason Phase A ships
  as its own PR: you should feel the loss before committing to Phases B through D.
- **The voice regex hand-sync survives as a hand-sync.** `voice-patterns.sh` is still
  maintained by hand against `forbidden-patterns.md`. The plan does not build a generator. The
  only improvement is that the drift test now asserts instead of skipping, so you find out at
  test time rather than never.
- **One vendor per slot.** `integrations.json` has one `tracker`, one `wiki`, one `obs`. Two
  trackers on one machine does not fit.
- **No schema version on `integrations.json`.** Adding or renaming a key means every machine
  hand-edits its own file with no migration path and no error message.
- **No multi-machine story.** The query cache and `integrations.json` are per machine,
  unversioned, and unbacked. A new laptop means re-answering every prompt and re-pasting every
  query.
- **OpenCode behavior stays untested forever.** No OpenCode install was found on this machine.
  The skill-sharing claim in Task D.5 is reasoned from documented behavior, not observed. The
  hook asymmetry is permanent by design.
- **No packaging or distribution.** No plugin manifest, no marketplace entry, no versioning.
  Installation is `git clone` plus `bootstrap.sh`.
- **No validation of the config file.** A typo in a key name means the slot silently reads as
  absent and the dependent skill goes inert with no error.
- **No per-project overrides.** Every project on the machine gets the same tracker, the same
  approval count, and the same highlights directory.

## Breaking point

Observable triggers, not guesses.

**Primary.** A second entry appears for one slot in `~/.claude/integrations.json`. Two trackers
or two observability tools on one machine. The flat six-key shape has no room for it, and
working around it means either a nested array (which needs a schema version) or a second config
file (which needs composition).

**Secondary, each observable:**

- A non-author opens a GitHub issue against the repo. Someone other than you now depends on the
  config shape, so `integrations.json` needs a schema version and a validator.
- `git log --oneline -- hooks/lib/voice-patterns.sh knowledge/writer/forbidden-patterns.md`
  shows the two files no longer appearing in the same commit. The hand-sync has started
  drifting in practice. Build the generator.
- `bootstrap.sh` runs on a second machine. Shared query state is now needed, which means the
  cache has to move somewhere both machines read.

**The honest one.** The day employer tooling and the public repo must coexist on one machine.
That is the trigger this plan cannot absorb. It forces a private overlay repo and a real
composition mechanism: two config roots, a merge order, and a rule for which one wins per key.
Both rejected designs existed to solve exactly that, and both were rejected because that day
has not arrived. When it does, this plan's output is the public half and the work is building
the private half plus the merge.

## Stopped halfway

This is a spare-time project. Treat stalling as expected. At every phase boundary the repo is
working.

**After Phase A, before Phase B.** Everything still works except the nine deleted skills and
two deleted agents. The voice system still runs from the installed plugin, because
`settings.json` still lists it. `scripts/check-output-style.sh` is gone but was only a check.
Back to working: nothing to do, this is a valid resting state.
Recovery command if needed: `git revert <phase-A-merge>`.

**After Phase B, before Phase C.** The voice system now runs from the repo. The marketplace
plugin can be uninstalled. Employer strings are still present in 15 files, so the repo is not
publishable yet. Both test suites pass.
Back to working: `bash claude/hooks/test-voice-hooks.sh && bash claude/hooks/test-pr-text-style.sh`.

**Stalled mid-Phase-B.** The risky state. If `settings.json` has been edited (Task B.4) but the
voice files are not fully in place, hooks fire against missing paths and every prompt errors.
Back to working: `git checkout main -- claude/settings.json`. That restores the plugin-based
config, which still works as long as the marketplace directory exists.

**After Phase C, before Phase D.** The repo is publishable. `leak-check.sh` passes.
`pr-tracker-links.sh` is inert because `integrations.json` does not exist yet, so PRs get no
tracker section. That is the only functional loss and it is by design.
Back to working: `bash claude/scripts/leak-check.sh`.

**Stalled mid-Phase-C.** Task C.3 is the one that can leave a broken hook, because
`pr-text-style.sh` gates on `PreToolUse` for `Bash` and a syntax error there blocks every Bash
call.
Back to working: `git checkout main -- claude/hooks/pr-text-style.sh`.

**After Phase D.** Done. `bootstrap.sh` is the entry point.
Back to working: `bash claude/bootstrap.sh` re-links everything and re-runs all three checks.

## Rejected alternatives

One line each. Do not relitigate these.

- **The 142-file platform design.** Correct architecture for a team, roughly 20 times the file
  count for one person on one machine.
- **The 87-file capability-contract design.** A real abstraction over vendors, but the contract
  surface exceeded the config it was abstracting.
- **A generator for `voice-patterns.sh` from `forbidden-patterns.md`.** The drift test now
  asserts instead of skipping, which catches the same defect for zero new files.
- **An adapter registry.** One config lookup in a skill outline replaces it at about 3 lines
  and zero registry files.
- **Committed vendor adapter files.** Committing vendor query syntax is the leak the query
  cache exists to prevent.
- **A capability contract subsystem.** Declaring what a vendor can do is only useful with more
  than one vendor per slot, which the breaking point covers.
- **A slot state machine.** Six flat keys with a default each do not have states worth
  modeling.
- **A probe framework.** Detecting an installed vendor by probing means guessing, and bootstrap
  refuses to guess a vendor.
- **A secret resolver subsystem.** After Phase A nothing in the repo needs a vault, so
  `secret.sh` is 6 lines and `gh` owns its own auth.
- **An OpenCode hook port.** A TypeScript mirror of 1170 lines of enforcement is a second
  implementation of the same rules and would diverge.
