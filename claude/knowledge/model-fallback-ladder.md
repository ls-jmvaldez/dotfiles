# Model Fallback Ladder

Claude Code skill/agent frontmatter accepts only a single `model:` value — there is no runtime try/catch, no chain syntax. If the specified tier isn't provisioned on the current account, the skill fails before its body executes. So resilience = keep every `model:` line pointing at a tier the account actually has, and re-walk the ladder whenever Anthropic shuffles availability.

## The ladder

Preferred → cheapest:

1. **fable** — premium reasoning tier
2. **opus** — heavy tasks (default in most Claude Code sessions)
3. **sonnet** — routine work, the workhorse tier
4. **haiku** — fastest, cheapest, for narrow lookups

Rule: **if the preferred tier isn't available in the current session, step down to the next one on this list.** Never skip more than one tier without checking whether the intent still holds — a task that needs Fable's reasoning may need a plan restructure, not a silent drop to Sonnet.

## Current availability (as of 2026-08-14)

Verified via `/model` picker output:

| Tier   | Available | Notes                                 |
| ------ | --------- | ------------------------------------- |
| fable  | NO        | Not on org plan                       |
| opus   | YES       | Opus 4.7 (default), Opus 5 (1M ctx)   |
| sonnet | YES       | Sonnet 4.6                            |
| haiku  | YES       | Haiku 4.5                             |

**Effective ladder for this account today:** `opus → sonnet → haiku`. Anything specifying `fable` should be walked down to `opus`.

## Updating when the ladder shifts

1. Run `/model` in a fresh session, read the picker.
2. Update the availability table above with today's date.
3. Grep every skill/agent frontmatter: `grep -rE "^model:" ~/.claude/skills ~/.claude/agents`.
4. Walk every `model:` line down until it points at an available tier.
5. Also check prose inside skill bodies for hard references to the old tier name (search terms: `Fable`, `Sonnet 5`, `Opus 5`, specific version strings). Update those too so the reasoning still reads correctly.
6. For Agent-tool `model:` params inside skill bodies, apply the same walk-down. Those are executed by the parent agent reading the body, so they can (in principle) include a "if X isn't there use Y" note — but keep them concrete: name the current best tier and the fallback in one line.

## Why not just omit `model:` and inherit?

Inheritance defeats intent. If `/plan` inherits Opus but the session is on Haiku, plan quality collapses. If `/execute`'s workers inherit Fable, spend spikes ~3x. Explicit tiers preserve the design; the ladder above keeps them from breaking when Anthropic changes availability.
