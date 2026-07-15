---
name: rollup
description: Roll up your saved standup highlights into one summary, reframed for the audience you need — a neutral highlights reel, resume bullets, promotion-packet evidence, or manager/VP 1:1 talking points. Reads the dated docs in ~/Documents/standup-log written by /standup. Fire it off whenever for reviews, brag docs, promo evidence, or 1:1 prep.
argument-hint: "[--for resume|promo|1on1] [--audience manager|vp] [--year 2026|--month 2026-07|--since 90d]"
model: sonnet
---

Aggregate the dated highlights docs `/standup` writes to `~/Documents/standup-log/` into a
single, deduped highlights reel. Read-only — it never touches Jira, GitHub, or New Relic; it
only reads what's already been logged. That's the point of the durable record: "highlights so
far" is exactly what you've captured, no live queries.

Arguments: $ARGUMENTS

## Arguments

**Range** (pick one; default = all-time):
- *(none)* / `--all` — every doc on file.
- `--year=YYYY` — one calendar year.
- `--month=YYYY-MM` — one month.
- `--since=Nd` — the last N days.

**Lens** — `--for=<audience>` reframes the same aggregated data (default = neutral highlights reel):
- `--for=resume` — impact bullets for a resume/CV.
- `--for=promo` — promotion-packet evidence, grouped by competency, every claim traceable.
- `--for=1on1` — talking points for a 1:1; pair with `--audience=manager` (default) or `--audience=vp` to set altitude.

## 1. Select and read the docs

`SKILL_DIR` is this skill's directory. `select_docs.py` handles the glob, the date filter,
and the empty-range / no-dir cases, then prints the matching docs concatenated. Pass through
whichever range flag the user gave (none = all-time):

```bash
python3 "$SKILL_DIR/select_docs.py" ${YEAR:+--year=$YEAR} ${MONTH:+--month=$MONTH} ${SINCE:+--since=$SINCE}
```

Its first line is `# rollup input: <N> docs, <first> → <last>` — use that for the range and
day count. If it prints a "no highlights…" line instead, relay that and stop.

## 2. Synthesize

The daily docs overlap by design — the same spike or initiative recurs across many days, and
a shipped PR is logged the day it merged. **Collapse recurrences into one entry per real
thing.** Cluster related daily bullets into initiatives rather than replaying them day by day.

### Honesty guardrail (applies to every lens, non-negotiable for `promo`/`resume`)

Every claim must trace to something actually logged — a PR, ticket, spike, or NR reading.
**Never invent metrics, impact, or scope that isn't in the docs.** If a strong bullet is
missing its impact (adoption, latency, revenue, users unblocked), say what's known and mark
the gap — e.g. `[impact TBD: confirm adoption numbers]` — so you can fill it, rather than
fabricating a number. Self-advocacy, not fiction. Tone follows the global style: concrete,
quantified where real, no hedging, no corporate filler, no em dashes, no emojis.

### Default lens — neutral highlights reel

```
# Highlights — <range>   (<N> days logged, <first date> → <last date>)

<one-paragraph lead: the story of the period — what shipped, what got figured out>

## Shipped
- PR #NNN <title> (repo) → PROJ-XXXX        # deduped; one line per merged PR

## Initiatives & research
- <initiative> — <what it was, what came out of it>   # collapse multi-day spikes into one

## Investigations & fixes
- <one-liner with the finding>

## By the numbers
- N PRs shipped · M spikes/research efforts · K investigations
```

### `--for=resume`

Impact-first bullets, XYZ shape ("Did X that achieved Y, measured by Z"), strong action verbs,
quantified where the data supports it. Surface the tech/stack. Drop internal ticket noise
(keep a parenthetical repo/tech, not `COREAPP1-XXXX`). Group under role/project headers.

```
## <Project / Area>  (stack: <langs, frameworks>)
- Shipped <thing> that <impact>, <metric if real>.
- Led <initiative> spanning <N repos/systems>, resolving <the hard question>.
```

### `--for=promo`

Promotion evidence mapped to engineering competencies, each backed by traceable artifacts.
Default competency dimensions (tune to a specific rubric if the user names one): **Scope &
Impact, Technical Quality & Depth, Autonomy & Ownership, Collaboration & Influence, Leadership
& Direction.** Lead with a scope statement, then per-competency evidence with PR/ticket links.

```
# Promotion Evidence — <range>

**Scope this period:** <cross-team reach, systems touched, hardest problems owned>

## Scope & Impact
- <accomplishment> — evidence: PR #NNN, COREAPP1-XXXX. <why it mattered / who it unblocked>

## Technical Quality & Depth
- <deep investigation or design> — evidence: <spike, trace, doc>. <the non-obvious call made>

## Collaboration & Influence
- <cross-team work> — evidence: <repos/services outside your team you moved>

## Autonomy & Ownership / Leadership & Direction
- <self-directed effort, ambiguity resolved, direction set>

## Gaps to close
- <competency thin on evidence this period — what to go do/log>
```

The `Gaps to close` section is the point: it tells you where the packet is weak *now*, while
there's still time to earn the evidence.

### `--for=1on1` (`--audience=manager` default, `--audience=vp`)

Talking points, not a report. **manager**: tactical — wins since the window start, what's
in-flight, blockers/risks, where you want feedback or air cover. **vp**: raise the altitude —
outcomes and business impact over implementation detail, cross-team themes, strategic bets;
2-4 crisp points a VP can act on, skip the ticket-level noise.

```
# 1:1 Talking Points — <range>   (<audience>)

## Wins
- <outcome-framed, not task-framed>

## In flight / next
- <what's moving, expected landing>

## Risks / needs   (manager)  |  Themes / bets   (vp)
- <blocker + the ask>          |  <strategic thread across the work>
```

Across all lenses: group by initiative/theme, not by date; keep artifacts traceable
(explicitly so for `promo`). If a range has thin coverage, say so plainly rather than padding.

## 3. (optional) save

Print to the terminal by default. If asked to keep it, write to
`~/Documents/standup-log/rollups/<lens>-<range>.md` (e.g. `promo-2026.md`, create the dir) so
rollups don't mix with the daily docs the `--year`/`--month` globs read.

## Integration

- The daily docs come from `/standup` (section 6). Resume/promo lenses are only as strong as
  the impact captured there — if bullets keep hitting `[impact TBD]`, start logging the
  outcome (adoption, latency, users unblocked) in standup, not just what shipped.
- Widen the window on a single day's detail → `/standup --since=Nd`.
- Draft the actual promo narrative or resume prose from this evidence → hand the output to
  your writing workflow; this skill produces the evidence, not the final polished copy.
