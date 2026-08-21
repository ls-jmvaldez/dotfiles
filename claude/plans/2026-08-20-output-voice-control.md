# Output Voice Control Implementation Plan

> **Status:** COMPLETED
>
> All four phases implemented, committed, pushed, and opened as draft PRs. Nothing is merged.
>
> | Phase | Branch | PR |
> | - | ------ | -- |
> | 1 | `feat/writer-voice-contract` | marketplace #216 |
> | 2 | `feat/voice-plugin` | marketplace #217 |
> | 3 | `feat/voice-digest` | marketplace #218, stacked on #217 |
> | 4 | `feat/output-voice-control` | dotfiles #2 |
>
> **The merge gate in Rollout has not run.** It is a human gate and blocks every merge.
>
> Carried into the gate:
> - `updatedInput` reaching a subagent's prompt is still unconfirmed. Open question 1. The agent
>   definition references in Phase 4 are the floor that does not depend on it.
> - The five broad patterns the drift test surfaced (`leverage`, `robust`, `powerful`,
>   `best practices`, `of course`) need a keep-or-downgrade decision. Documented in #217.
> - The digest in #218 needs a manual rebase if it merges, and may be discarded outright.
>   Open question 3.
> - Run `claude/scripts/check-output-style.sh` after installing the plugin. It fails today by
>   design, because the plugin is unmerged.

## Specification

**Goal:** Make Claude's conversational output, and the output of its subagents, concise and plain
by default, without duplicating style rules into a fourth place.

Today nothing governs chat verbosity: there is no `outputStyle` key set, no `output-styles/`
directory, and the only chat-level rule is one sentence in `CLAUDE.md` ("informal, concise,
direct. No emojis. No hedging."). The persona system already exists and is already wired from the
marketplace into specific skills. The work is to extend it, give it an always-on surface for
chat, push it to subagents, and collapse the copies that have drifted.

**Source of truth: the marketplace, not dotfiles.** The writer guide's real home is
`~/Public/source/legalshield-claude-marketplace/plugins/experimental/internal-tools/knowledge/writer/`
(remote `LegalShield/legalshield-claude-marketplace`, `internal-tools` authored by Joe Valdez).
The `~/.claude/plugins/cache/.../0.2.7/` path is a materialized install, not the source. An
earlier draft proposed vendoring the guide into dotfiles to escape the plugin cache; that was
wrong and would have created the exact divergent copy this plan exists to remove.

**Research basis, and its limits:**

The NeurIPS poster that prompted this work (Zhang/Khan/Papyan, "Attention Sinks: A Catch, Tag,
Release Mechanism for Embeddings", arXiv:2502.00919) does **not** support prompt-layer changes. It
is mechanistic interpretability aimed at KV-cache eviction and quantization, and everything it
describes sits below the API boundary. It is deliberately **not** cited as justification anywhere
in this plan.

The defensible basis is a different literature: instruction adherence decays over turns.

- Laban et al., LLMs Get Lost in Multi-Turn Conversation (arXiv:2505.06120): ~39% average drop
  multi-turn vs single-turn across 200K+ simulated conversations.
- SysBench (arXiv:2408.10943): system-prompt constraint adherence decays turn over turn.
- Wu et al., ICML 2025 (arXiv:2502.01951): position bias is architectural, arising from causal
  masking, so a larger context window does not fix it.

Caveat: this literature measures fact retrieval and constraint following, not style compliance
specifically. "Style rules decay like other instructions" is an inference, supported indirectly.
Phase 3 is the only part resting on it, which is why it is isolated in its own PR that can be
closed unmerged.

**Verified capabilities** (read from the Zod schema in the installed 2.1.238 binary, because two
research agents contradicted each other and both were partly wrong):

| Event | Output field | Real capability |
| --- | --- | --- |
| `MessageDisplay` | `displayContent` | Replaces the delta **on screen only** |
| `Stop` | `additionalContext` | Feedback to model, conversation continues. Cannot rewrite |
| `PreToolUse` | `updatedInput` | Can rewrite tool input |
| `SubagentStart` | `additionalContext` | Inject before subagent runs |
| `SubagentStop` | `additionalContext` | Delivered to the subagent, which continues |

Binary's own words on `MessageDisplay`: "Display-only: replaces the delta on screen without
changing the stored message."

That is why this plan does not port `gvzdv/claudish-to-english`. That plugin paints over the
symptom: you read plain English while the model keeps reasoning in and building on the original
text, and the transcript retains it. Fix generation, not display. (That repo also turns out to
contain no banned-phrase list at all, only four system-prompt strings handed to a second model.)

Plugin packaging, also verified in the binary:

- Plugins **can** ship output styles: manifest key `outputStyles`, "Path to an output-styles
  directory or file, relative to the plugin root."
- Plugins **can** ship hooks: `hooks/hooks.json` at the plugin root is auto-loaded; the manifest
  `hooks` key adds *additional* files and must not re-reference the standard path (the loader
  errors on duplicates).
- Recognized plugin subdirectories include `agents`, `output-styles`, `hooks`, `themes`.
- Bonus lever found while verifying: **skill and agent frontmatter each accept a `hooks` key**
  ("Hooks registered while this skill is active" / "while this agent runs"), same shape as
  `settings.json`. This gives per-agent scoping without global hooks. See Task 2.4.

**Scope decision:** persona and banned-pattern improvements go to `internal-tools`, which the team
already installs, because they are pure improvements to an existing shared guide. The always-on
pieces ship as a **separate personal plugin** (`ls-jmvaldez-voice`) so nobody else's chat behavior
changes on update. Promotable later if the team wants it.

**Success Criteria:**

- [ ] Exactly one file defines the banned-pattern list, and it lives in the marketplace
- [ ] No competing persona system remains in dotfiles
- [ ] The bullets-vs-prose contradiction is resolved with a stated rule
- [ ] Chat responses are governed by an output style shipped from a plugin
- [ ] Subagent prompts carry the voice contract; today they inherit nothing
- [ ] Pattern matching is defined once and shared by the PR hook and the Stop hook
- [ ] Every rule file obeys its own rules (no em dashes in files that ban em dashes)
- [ ] **Every hook ships with tests**, and the suite runs in CI
- [ ] **The whole setup is exercised locally on a real session before anything merges**

**Non-goals:**

- No `MessageDisplay` rewrite hook. Display-only, and it desyncs transcript from screen.
- No forced-redo Stop hook. Risks redo loops and burns tokens on false positives.
- No second local model in the loop.
- No changes under `plugins/vetted/`. Stewards-only per the marketplace CLAUDE.md.

**Testing requirements (apply to every hook task below):**

Hooks are the risky surface here. They run on every turn, they can block work, and a bad one is
felt immediately across every session. Each hook gets a test file before it is wired into any
settings, following the convention already in this marketplace
(`plugins/experimental/lynchtm/word-of-the-day/tests/test-scripts.sh`): plain bash, sandboxed
`$HOME` and `$PATH` per test, mock shims for anything external, `PASS`/`FAIL` counters, nonzero
exit on failure. `bats` is not installed and is not worth adding for this; `shellcheck` is
installed and every hook must pass it clean.

Every hook's tests must cover, at minimum:

- **Happy path:** valid input produces the expected JSON on stdout
- **Clean input:** produces no block and no feedback (the silent case is the common case)
- **Malformed input:** empty stdin, non-JSON stdin, missing expected fields. Must not crash or
  emit garbage to stdout
- **stdout purity:** stdout is parseable JSON or empty, always. This is the contract that breaks
  the session when violated, and subprocess noise leaking into stdout is the way it breaks
- **Exit code:** 0 in every non-catastrophic case, since the JSON carries the decision
- **Determinism**, where the hook claims it (the Phase 3 digest must be byte-identical run to run)

`voice_scan()` and the pattern library get their own table-driven tests: every pattern needs one
matching and one near-miss non-matching fixture. False positives are the failure mode that makes
people disable a hook.

## PR Strategy

**Split:** independent PRs, except PR 3 which stacks on PR 2

**Rationale:** Two separate git remotes, so marketplace work cannot share a branch with dotfiles
work. Within the marketplace, the guide change and the new plugin touch disjoint subtrees. The
digest hook is deliberately isolated in its own stacked PR because it is the piece most likely to
be dropped, and closing one PR is cleaner than unpicking commits.

**Independence Check:**

- [x] PR 1 and PR 2 touch disjoint paths (`internal-tools/knowledge/writer/` vs a new
      `ls-jmvaldez/voice/` subtree). Both touch `.claude-plugin/marketplace.json`, so expect one
      trivial conflict on the second merge
- [x] PR 4 is in a different repo entirely, so no git-level interaction
- [ ] PR 3 is **not** independent. It needs PR 2's plugin scaffold and test harness, so it bases
      on `feat/voice-plugin` rather than `main`

PR 4 depends on PR 1 and PR 2 landing at the content level (it points at the new guide and names
the output style), but shares no git history with them, so it bases on `main`.

## Branch Plan

_Consumed by `/execute` to provision git state. One row per phase per PR._

| # | Branch | Worktree Path | Base |
| - | ------ | ------------- | ---- |
| 1 | `feat/writer-voice-contract` | `/Users/valdezjm/Public/source/legalshield-claude-marketplace/.claude/worktrees/writer-voice-contract` | `main` |
| 2 | `feat/voice-plugin` | `/Users/valdezjm/Public/source/legalshield-claude-marketplace/.claude/worktrees/voice-plugin` | `main` |
| 3 | `feat/voice-digest` | `/Users/valdezjm/Public/source/legalshield-claude-marketplace/.claude/worktrees/voice-digest` | `feat/voice-plugin` |
| 4 | `feat/output-voice-control` | `/Users/valdezjm/.config/dotfiles/.claude/worktrees/output-voice-control` | `main` |

**Two repos.** Rows 1 through 3 provision in
`/Users/valdezjm/Public/source/legalshield-claude-marketplace`. Row 4 provisions in
`/Users/valdezjm/.config/dotfiles`. Worktree paths above are absolute for exactly this reason; do
not resolve them relative to the session's cwd.

**Preconditions before Phase 4:**

- Dotfiles has uncommitted work: modified `claude/settings.json`,
  `claude/skills/{execute,plan,snowflake-report}/SKILL.md`, plus untracked
  `claude/knowledge/model-fallback-ladder.md`. Commit or stash before provisioning row 4.
- An existing worktree `.claude/worktrees/align-plan-execute-paths` is on
  `chore/align-plan-execute-paths` and touches skill files. Check for overlap with Phase 4 before
  starting; that branch may need to land first.

## Context Loading

```bash
cd ~/Public/source/legalshield-claude-marketplace
cat CLAUDE.md
cat plugins/experimental/internal-tools/knowledge/writer/writer.md
ls plugins/experimental/internal-tools/knowledge/writer/personas/
cat .github/CODEOWNERS
cat plugins/experimental/lynchtm/word-of-the-day/tests/test-scripts.sh

cd ~/.config/dotfiles/claude
cat CLAUDE.md knowledge/strategy-writer.md hooks/pr-text-style.sh skills/pr/SKILL.md
```

---

## Phase 1: Extend the shared writer guide

_Maps to Branch Plan row 1. Marketplace repo._

### Task 1.1: Build the canonical banned-pattern list

**Context:** `plugins/experimental/internal-tools/knowledge/writer/`

The guide currently has a short "Forbidden Patterns" section. Three non-identical versions of that
list exist across `writer.md`, dotfiles `CLAUDE.md`, and dotfiles `strategy-writer.md`. Make the
guide's version the real one, structured so a hook can consume it.

**Steps:**

1. [ ] Create `knowledge/writer/forbidden-patterns.md` as a dedicated reference, keeping
       `writer.md` a readable overview that links to it. This matches the progressive-loading
       convention the plugin's skills already use
2. [ ] Build one merged list, curated to roughly 60 to 80 high-signal entries, seeded from
       `hardikpandya/stop-slop` (`references/phrases.md`) and `jalaalrd/anti-ai-slop-writing`
       (`references/banned-words.md`), merged with the three existing lists. Drop entries aimed at
       blog and essay prose that do not fit engineering writing
3. [ ] Organize into the categories the hook will consume, one per section with a stable heading:
       throat-clearing openers, sycophancy, corporate filler, hedging adverbs, meta-commentary,
       em dashes
4. [ ] Mark each entry as regex-enforceable or model-only. The structural rules (binary contrasts,
       rhythm, false agency) cannot be regexed and belong in prose
5. [ ] Keep the existing header philosophy: the pattern set is shape-based, not a closed list

**Verify:** `grep -c '—' knowledge/writer/forbidden-patterns.md` returns 0.

---

### Task 1.2: Resolve the contradictions and fold in the strategy personas

**Context:** `knowledge/writer/writer.md`, `knowledge/writer/personas/`

**Steps:**

1. [ ] **Resolve bullets vs prose.** `writer.md` says "Tables for comparisons, not prose";
       dotfiles `strategy-writer.md` says "Paragraphs over bullets. Lists break narrative flow."
       Both claim to cover all personas. State one default and name the exception by document type
2. [ ] **Resolve answer placement.** "Say the thing / lead with the answer" vs "don't bury the
       lead, but do earn the conclusion." Pick one, note where the other applies
3. [ ] Fold the four dotfiles strategy personas into the marketplace set. Strategist and Advocate
       overlap the existing PM and Marketer; Analyst and Researcher are the genuinely new shapes.
       Either extend the two existing persona files or add `analyst.md` and `researcher.md`,
       whichever reads cleaner after looking at the overlap
4. [ ] Carry over the strategy-specific rules worth keeping: technology-first framing,
       unsupported claims, customer-first framing
5. [ ] Update the persona selection table in `writer.md` with any new rows
6. [ ] Strip the em dashes from `personas/engineer.md` and `personas/contributor.md`, which both
       currently violate the rule they inherit

**Verify:**

```bash
grep -rn '—' plugins/experimental/internal-tools/knowledge/writer/
```

Returns only intentional occurrences inside quoted banned-pattern examples.

---

### Task 1.3: Ship it

**Steps:**

1. [ ] Bump `internal-tools` version in `.claude-plugin/plugin.json` and the matching
       `marketplace.json` entry. Note the repo has a `chore: auto-bump plugin versions [skip ci]`
       workflow; check whether it handles this before doing it by hand
2. [ ] Confirm no skill that references the writer guide breaks. `skills/jira/`,
       `skills/confluence/`, and their `references/authoring.md` all point into
       `knowledge/writer/`
3. [ ] Open PR as The Contributor, with a `## Tickets` section

**Verify:** `./scripts/validate-plugins.sh` passes. `claude plugin install
internal-tools@legalshield-marketplace` picks up the new version, and `/jira` still resolves its
persona references.

---

## Phase 2: Personal voice plugin

_Maps to Branch Plan row 2. Marketplace repo. Output style, subagent contract, enforcement, CI._

### Task 2.1: Scaffold the plugin

Namespace is `ls-jmvaldez` (confirmed). The pre-existing
`/plugins/experimental/internal-tools/ @valdezjm` CODEOWNERS line is a separate, older entry;
leave it alone rather than "fixing" it as a drive-by in this PR.

**Steps:**

1. [ ] Create `plugins/experimental/ls-jmvaldez/voice/` per the documented convention. Note the
       repo has mixed conventions: some namespaces are usernames, `internal-tools` is a plugin
       directly under `experimental/`
2. [ ] Write `.claude-plugin/plugin.json` with `"name": "ls-jmvaldez-voice"`, version `0.1.0`
3. [ ] Register in `.claude-plugin/marketplace.json` with `"category": "experimental"` and
       keywords including `experimental`
4. [ ] Add `/plugins/experimental/ls-jmvaldez/ @ls-jmvaldez` to `.github/CODEOWNERS`
5. [ ] Create `tests/test-hooks.sh` with the shared harness (sandbox helpers, PASS/FAIL counters,
       a `run_hook` helper that pipes a fixture to a hook and captures stdout, stderr, and exit
       code separately). Every later hook task appends to this file
6. [ ] Skip the in-plugin README per the repo's CLAUDE.md

**Verify:** `./scripts/validate-plugins.sh` passes with the new entry registered.

---

### Task 2.2: Write the output style

An output style edits the actual system prompt, unlike context injection which only appends. This
is the mechanism that changes what gets generated.

**Steps:**

1. [ ] Create `output-styles/direct.md` with frontmatter `name`, `description`, and
       `keep-coding-instructions: true`
2. [ ] Declare `"outputStyles": "./output-styles"` in `plugin.json`
3. [ ] Body states the compressed voice contract: lead with the answer, no preamble, no
       restating the question, no summary of what was just done unless asked, short paragraphs,
       tables over prose for comparisons, no emojis, no em dashes, no sycophantic openers
4. [ ] Keep it tight. This rides in the system prompt on every request, so length is a standing
       token cost. Reference the full guide rather than inlining all 60 to 80 patterns

**Verify:** New session, `/config` shows the style active. Ask something whose sloppy answer would
open with "Great question" or a restatement of the question, confirm it does not.

---

### Task 2.3: Spike, confirm `updatedInput` reaches the Agent tool

No agent definition in dotfiles `agents/` references the writer guide or any pattern list, so
subagents inherit zero style. `PreToolUse.updatedInput` exists in the schema, but that it applies
to the `Agent` tool's `prompt` field is **unverified**. Confirm before building on it.

**Steps:**

1. [ ] Throwaway `PreToolUse` hook on matcher `Agent`, returning `updatedInput` with a sentinel
       appended to `prompt`
2. [ ] Dispatch a trivial subagent, have it echo its received prompt
3. [ ] Confirm the sentinel arrives

**Verify:** Sentinel present in the echoed prompt.

**If it fails:** fall back to per-agent `hooks` frontmatter (verified to exist in the agent
schema), or add a voice reference line to each agent definition. The agent-file edits work
regardless and are the guaranteed floor. `SubagentStart` `additionalContext` is a weaker fallback,
since its placement (parent vs subagent) needs verifying first.

---

### Task 2.4: Wire the subagent voice contract

**Steps:**

1. [ ] Promote the spike to `hooks/subagent-voice.sh`, appending the compressed contract to
       `prompt`
2. [ ] Scope via agent frontmatter `hooks` rather than a global matcher where practical. Narrower
       blast radius, and it keeps read-only agents like `Explore` untouched if the contract turns
       out to interfere with their reports
3. [ ] **Tests:** a fixture `Agent` tool payload produces `updatedInput` whose `prompt` contains
       both the original text and the appended contract, in that order. Non-`Agent` tool payloads
       pass through untouched with no `updatedInput` at all. Malformed payload does not crash.
       **A payload whose prompt already contains the contract is not double-appended**, which is
       the bug this hook will otherwise have on any retry path

**Verify:** `bash tests/test-hooks.sh`, then dispatch one of each agent type live and confirm
returned prose carries no banned patterns and no degraded work quality.

---

### Task 2.5: Extract the pattern library

**Context:** dotfiles `hooks/pr-text-style.sh` as the source, new plugin `hooks/lib/`

`pr-text-style.sh` is the working precedent and is well built, but its patterns are inline and it
only fires on `gh` commands carrying a body flag. It catches sycophancy and em dashes and misses
the entire corporate-filler list that four other files ban.

**Steps:**

1. [ ] Create `hooks/lib/voice-patterns.sh` exporting `PATTERNS` and `BODY_ONLY_PATTERNS` plus a
       `voice_scan()` helper returning the first match
2. [ ] Port existing patterns verbatim. Preserve both design notes from the current header: the
       scope gate keys on body-writing flags rather than endpoint path (because `gh api $REPO/...`
       bypassed the old regex), and start-anchored patterns run against the extracted body only
       (because `^` matches every line of a multi-line command, and gh's own ` -- ` separators
       false-positive)
3. [ ] Add the corporate-filler and throat-clearing categories from Task 1.1
4. [ ] Generate the library from `forbidden-patterns.md` if the section headings make that clean.
       Otherwise keep it hand-maintained and note the sync obligation in both files. Do not let
       them silently drift, which is the failure mode this whole plan is about
5. [ ] **Table-driven tests, one matching and one near-miss fixture per pattern.** The near-miss
       is the important half: "right call" must match while "copyright callback" must not, and
       ` -- ` in a gh argument separator must not trip the em-dash surrogate
6. [ ] **Regression lock on current behavior:** capture the existing `pr-text-style.sh`
       block/pass decision for a set of real payloads *before* refactoring, then assert the
       refactored version returns identical decisions
7. [ ] **Decided: hand-maintained, guarded by a drift test.** A generator would silently emit an
       empty library if `forbidden-patterns.md` went missing, under-enforcing without failing.
       Instead keep the library hand-written and add a test asserting every regex-enforceable
       entry in `forbidden-patterns.md` has a corresponding pattern in `voice-patterns.sh`. CI
       fails on drift. This closes the sync obligation that would otherwise reintroduce the exact
       divergence this plan exists to remove
8. [ ] **Decided: exempt inline-backtick spans and fenced code blocks** before scanning, matching
       what `voice-check.sh` already does for fences. Quoting a banned phrase in backticks to
       discuss it passes; using it unquoted in prose still blocks. Apply this in the shared
       library so every consumer inherits one rule. This gap already blocked a legitimate PR body
       on this very work

**Verify:** `bash tests/test-hooks.sh` and `shellcheck hooks/lib/voice-patterns.sh`. Regression
fixtures return byte-identical decisions to the pre-refactor hook.

---

### Task 2.6: Advisory Stop hook

**Steps:**

1. [ ] `hooks/voice-check.sh` reads the Stop payload, scans `last_assistant_message` via
       `voice_scan()`
2. [ ] On match, emit
       `{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"Voice check: matched \"<pattern>\". ..."}}`
3. [ ] **Advisory only.** Never `decision: block`, never exit 2. The landed message cannot be
       rewritten; the point is self-correction next turn
4. [ ] Strip fenced code blocks before scanning, to avoid matching identifiers and command output
5. [ ] Rate-limit so one persistent pattern does not fire every turn
6. [ ] **Tests:** a message with a banned pattern emits `additionalContext` naming it; a clean
       message emits nothing; a message whose only match sits **inside a fenced code block**
       emits nothing (the highest-value test here, since violating it makes the hook fire on
       ordinary code review); the rate limit suppresses a repeat within the window and allows it
       after; **no output path ever sets `decision: block` or exits nonzero**, asserted explicitly
       so a future edit cannot quietly turn this into a redo loop

**Verify:** `bash tests/test-hooks.sh`, then live: force a response with a banned pattern, confirm
feedback arrives and the conversation continues without a redo loop. Confirm a clean response
produces no output.

---

### Task 2.7: Wire the suite into CI

**Context:** `.github/workflows/`

CI currently runs only `validate-plugins.sh` on PRs. Nothing runs the two existing
`tests/test-scripts.sh` suites, so hook tests would rot the same way unless wired in.

**Steps:**

1. [ ] Add a `test-hooks` job. Prefer extending the existing `validate-plugins.yml` over adding a
       workflow, so the repo does not accumulate one workflow per plugin
2. [ ] Run `shellcheck` over every `hooks/**/*.sh` in the voice plugin, failing on warnings
3. [ ] Run `bash plugins/experimental/ls-jmvaldez/voice/tests/test-hooks.sh`, which must exit
       nonzero on any failure
4. [ ] Confirm the runner has `jq` available, since every hook depends on it. Install it in the
       job if not
5. [ ] Consider picking up the two orphaned suites (`word-of-the-day`, `session-review`) in the
       same job. Out of scope if it turns into a yak shave

**Verify:** Push a deliberately broken hook, confirm CI goes red. Revert, confirm green.

---

## Phase 3: Per-turn digest hook

_Maps to Branch Plan row 3. Marketplace repo, stacked on row 2. **Most likely piece to be
dropped**, which is why it is isolated: closing this PR unmerged costs nothing._

### Task 3.1: Inject the voice digest each turn

The only phase resting on the multi-turn decay literature. The output style lands once at the top
of context; SysBench and Laban et al. both show top-of-context constraints losing grip as turns
accumulate.

**Steps:**

1. [ ] Create `hooks/hooks.json` (auto-loaded at plugin root; do **not** also list it under the
       manifest `hooks` key, the loader errors on duplicate hook files)
2. [ ] Add `hooks/inject-voice-digest.sh` emitting
       `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"..."}}`
3. [ ] Digest is a compressed restatement, not the full list. Target under roughly 80 tokens
4. [ ] Reuse the Task 2.4 contract string so there is one string, not two that drift
5. [ ] **Emit byte-identical output every turn.** Any variation degrades prompt caching. No
       timestamps, no conditionals, no per-turn state
6. [ ] Follow the stdout discipline proven in `pr-text-style.sh`: route all subprocess noise to
       `/dev/null`, write only the final JSON
7. [ ] No plugin in this marketplace ships hooks yet, so confirm a plugin-shipped hook actually
       registers before assuming this works
8. [ ] **Tests:** valid payload emits the digest; empty and malformed stdin still emit valid JSON
       and exit 0; stdout is JSON-parseable in every case; **two consecutive runs are
       byte-identical**, the cache-correctness test and the one most likely to regress

**Verify:**

```bash
echo '{}' | bash hooks/inject-voice-digest.sh | jq .
diff <(echo '{}' | bash hooks/inject-voice-digest.sh) <(echo '{}' | bash hooks/inject-voice-digest.sh)
shellcheck hooks/inject-voice-digest.sh
bash tests/test-hooks.sh
```

Then check `/cost` for healthy cache reads across a real multi-turn session.

---

## Phase 4: Dotfiles cleanup

_Maps to Branch Plan row 4. Dotfiles repo._

### Task 4.1: Collapse duplicates and repoint at the marketplace

**Context:** `CLAUDE.md`, `skills/pr/SKILL.md`, `knowledge/`, `agents/`

**Steps:**

1. [ ] Delete `knowledge/strategy-writer.md`, now folded into the marketplace guide (Task 1.2)
2. [ ] Keep the PR contract in `skills/pr/SKILL.md` where it is used; replace the near-verbatim
       `### PR Descriptions` block in `CLAUDE.md` with a pointer plus the two or three rules that
       genuinely need to be always-loaded
3. [ ] Update the `CLAUDE.md` Identity section: the resolve-from-manifest dance stays correct, but
       point at `forbidden-patterns.md` alongside `writer.md`
4. [ ] Repoint `knowledge/documenting-systems.md` at the new reference
5. [ ] Fix `executing-plans.md:85`, a third independent copy of the em-dash rule, to inherit
       instead
6. [ ] Fix the em dash at `CLAUDE.md:19`, nine lines above the em-dash ban
7. [ ] Add a voice reference to `agents/code-reviewer.md`, `devils-advocate.md`, `fast-task.md`,
       `log-reader.md`, and strip the em dashes from `code-reviewer.md`
8. [ ] Install the voice plugin, set `"outputStyle": "direct"` in `settings.json`

**Verify:**

```bash
grep -rn '—' CLAUDE.md knowledge/ skills/ agents/
grep -rin "it's worth noting\|seamless\|best-in-class" CLAUDE.md knowledge/ skills/
```

Only intentional occurrences inside quoted lists remain.

---

### Task 4.2: Extend artifact coverage and retire the dotfiles hook copy

**Steps:**

1. [ ] Rewrite `hooks/pr-text-style.sh` to source the plugin's library, or remove it in favor of
       the plugin's own `PreToolUse` entry. Decide based on whether the plugin's hook path
       resolves reliably from `settings.json`
2. [ ] Extend the Bash scope gate to cover `git commit -m`, `jira` writes, and Confluence page
       bodies, all currently unchecked
3. [ ] Confirm the backtick and fence carve-out from Task 2.5 step 8 applies here too. Widening
       the surface to commits and Jira widens where a quoted example would otherwise be blocked
4. [ ] Confirm no false positives on ordinary commands containing matching substrings

**Verify:** Commit with a banned pattern in the message is blocked; a clean commit passes. Run the
plugin's `tests/test-hooks.sh` against the sourced library to confirm nothing regressed.

---

## Rollout and rollback

### Merge gate: local verification (blocks all merges)

**Nothing merges until this passes.** Unit tests prove each hook handles its fixtures; they prove
nothing about whether the assembled system is pleasant to work in. The failure modes that matter
(a hook firing constantly, cache thrash from a non-deterministic digest, an output style that
makes Claude terse to the point of useless) only show up in a real session.

All four PRs stay in draft until this completes.

1. Install both marketplace plugins from the **local checkout**, not the pushed remote, so the
   unmerged branches are what runs. Verify with `claude plugin list` that the resolved
   `installPath` points at the working tree, not the `0.2.7` cache.
2. Apply the Phase 4 dotfiles changes locally. Start a genuinely fresh session, since output
   styles do not hot-reload.
3. Use it for a real working day. Deliberately hit each surface:
   - **Chat voice** across a long multi-turn session. Confirm the voice holds at turn 30 as well
     as turn 3, which is the entire premise of Phase 3.
   - **Subagents:** dispatch each type. Confirm reports are clean *and* that the contract did not
     degrade their work. A terser `code-reviewer` that misses findings is a regression.
   - **Artifacts:** one real PR body, one commit, one Jira comment. Confirm blocks fire on genuine
     violations and do **not** fire on legitimate text.
   - **False-positive hunt.** The make-or-break. More than a couple in a day means the pattern
     list is too aggressive and Task 1.1 needs pruning before merge.
   - **Cache health** via `/cost`. A drop means the digest is not byte-identical and Phase 3 is
     costing real money.
   - **Escape hatch:** confirm the whole thing can be disabled in one step without editing files,
     and that the session survives a hook erroring or timing out.
4. Decide whether Phase 3 earns its keep. **If the output style alone held the voice, close PR 3
   unmerged** rather than paying a per-turn token cost for nothing. This is an expected outcome.
5. Prune any pattern that produced a false positive. Re-run the full suite plus `shellcheck`.

### Merge order

PR 1 first; confirm the team's `/jira` and `/confluence` flows do not regress against the
published version. Then PR 2 and PR 4 together, since the output style is inert until
`settings.json` names it. Then PR 3, or close it.

Post-merge, reinstall from the published marketplace and confirm behavior matches what was tested.

### Rollback

- Output style: unset `outputStyle` in `settings.json`
- Digest: remove the `UserPromptSubmit` entry from the plugin's `hooks.json`
- Subagent contract: remove the `PreToolUse` `Agent` matcher, or the agent frontmatter
- Enforcement: hooks are advisory, so removing the `Stop` entry restores current behavior exactly
- Everything: `claude plugin uninstall ls-jmvaldez-voice`

## Open questions

1. Does `PreToolUse.updatedInput` reach the `Agent` tool's `prompt`? Task 2.3 settles it.
2. RESOLVED: pattern library stays hand-maintained with a drift test (Task 2.5 step 7).
3. Does the digest measurably beat the output style alone? The merge gate decides it with real
   usage rather than assumption, and closing PR 3 is an expected outcome.
4. Should `internal-tools` eventually absorb the voice plugin so the team shares the chat style?
   Deferred by design; revisit once it has proven itself on one machine.

_Resolved: the new namespace is `ls-jmvaldez`. The existing `@valdezjm` CODEOWNERS line for
`internal-tools` stays as-is._
