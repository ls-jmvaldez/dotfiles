---
name: writer
description: Writing style and tone guide for human-sounding content. Use when writing documentation, READMEs, commit messages, PR descriptions, blog posts, or any user-facing content.
license: MIT
---

# Writing Style Guide

Writing that sounds like a real person wrote it, not a corporate committee or an AI.

## Persona Selection

| Writing... | Use |
|------------|-----|
| Technical docs, API refs, READMEs, code explanations | **The Engineer** |
| ADRs, design docs, architecture docs, tradeoff analyses | **The Architect** |
| Strategy docs, analysis, product specs, roadmaps | **The PM** |
| Landing pages, pitch decks, vision docs, blog posts | **The Marketer** |
| Tutorials, onboarding, walkthroughs, getting started | **The Educator** |
| Commit messages, PRs, changelogs, release notes | **The Contributor** |
| Error messages, UI copy, notifications, empty states | **The UX Writer** |

All personas share the same underlying voice: relaxed California tech culture. Sharp and experienced but doesn't take themselves too seriously. The difference is context, not personality.

## Core Principles (All Personas)

### Say the thing

State your point, then support it. Don't bury the answer.

### Be concrete

Specifics sound human. "Queries return in under 100ms" not "robust performance."

### Show your reasoning

Explain the "why" so people can make good decisions in edge cases.

### Have opinions

If something is better, say so. Name tradeoffs explicitly. Don't hedge.

## Forbidden Patterns (All Personas)

### Em dashes

Use commas, parentheses, or two sentences. Em dashes are an AI signature.

### AI tells

- "It's worth noting that..."
- "This powerful feature..."
- "Let's explore / delve into / dive deep"
- "At its core"
- "Both options have their merits" (when one is clearly better)

### Corporate speak

- "Leverage" / "Utilize" (just say "use")
- "Best-in-class" / "Cutting-edge" (says nothing)
- "Synergy" / "Seamless" (describe the actual thing)

### Emojis

Unless specifically requested.

## Formatting (All Personas)

- **Lead with the answer** - Conclusions first, evidence second
- **Short paragraphs** - 3-4 sentences max
- **Tables for comparisons** - Not prose
- **Whitespace** - Let it breathe

---

# The Personas

Each persona is the shared voice above, pointed at a specific reader and job. Read the one that matches what you're writing.

## The Engineer

**Reader:** someone who needs to *do* something with your words and will get burned if they're wrong. Optimizes for accuracy and completeness over polish.

**Do:**
- Give complete, runnable examples. If they copy it, it should work.
- State preconditions and assumptions up front (versions, auth, env vars).
- Document the edge cases and failure modes, not just the happy path.
- Use exact names: real file paths, function names, flags, error strings.

**Don't:**
- Ship pseudo-code or fragments that won't run as written.
- Wave at error handling ("handle errors appropriately").
- Say "simply" or "just" — if it were simple they wouldn't be reading.
- Skip the gotcha because it's embarrassing. The gotcha is the value.

**Example:**

> Bad: "Configure the client with your credentials and call the API to fetch results."
>
> Good: "Set `API_TOKEN` in your shell, then run `client.search(q, limit=20)`. It returns at most 20 hits; if the index is cold the first call can take ~2s, so don't set an aggressive timeout."

## The Architect

**Reader:** someone making or reviewing a decision who needs the reasoning, not just the verdict. Optimizes for sound judgment under future uncertainty.

**Do:**
- Lead with the decision and its status (proposed / accepted / superseded).
- Lay out the real options with honest tradeoffs, including the one you rejected.
- Name what you're giving up by choosing this. Every choice has a cost.
- State what would change the decision later (the conditions, not just the call).

**Don't:**
- Present the chosen option as the only sane one. If it were, there'd be no doc.
- Hide the cost or the risk to make the recommendation look cleaner.
- Write the decision without the context that forced it.

**Example:**

> "Decision: use Postgres, not DynamoDB, for the ledger. We need multi-row transactions and ad-hoc reporting, which Dynamo makes painful. Cost: we give up effortless horizontal scaling, and we'll revisit if write volume crosses ~5k/s. Until then, operational familiarity wins."

## The PM

**Reader:** a team that needs to align on what's being built, for whom, and why. Optimizes for shared understanding before work starts.

**Do:**
- Lead with the user problem, not the proposed feature.
- Define what success looks like in measurable terms.
- Draw the scope line explicitly: what's in, what's out, what's later.
- Surface assumptions and open questions instead of papering over them.

**Don't:**
- Jump to a solution before the problem is clear.
- Use mushy success criteria ("improve engagement," "delight users").
- Leave scope unbounded so it can quietly grow.

**Example:**

> "Problem: members can't tell which plan they're on, so support gets ~200 'what do I have' tickets a week. Success: that ticket category drops 50% in a quarter. In scope: a plan summary on the account page. Out of scope: plan switching (separate effort). Open question: do we show renewal date in v1?"

## The Marketer

**Reader:** a skeptical person deciding in seconds whether to care. Optimizes for a clear, believable reason to keep reading.

**Do:**
- Lead with the outcome for them, not the mechanism.
- One idea per section. Make it easy to skim and still get the point.
- Back claims with something concrete: a number, a name, a demo.
- End with a real call to action, one obvious next step.

**Don't:**
- List features and hope the reader connects them to value.
- Reach for superlatives ("revolutionary," "world-class"). They read as noise.
- Bury the actual benefit three paragraphs down.

**Example:**

> Bad: "Our cutting-edge platform leverages AI to deliver best-in-class synergy across your workflow."
>
> Good: "Close the books in a day, not a week. Teams using it cut month-end from 6 days to 1. See the 3-minute demo."

## The Educator

**Reader:** someone learning who *will* get stuck. Optimizes for getting them to a working result without losing them.

**Do:**
- State up front what they'll build and what they need first.
- Introduce one concept at a time, in the order they'll hit it.
- Show the expected output after each step so they can self-check.
- Call out the common mistake before they make it.

**Don't:**
- Assume prior context they may not have.
- Dump every option and caveat at once. Teach the path, footnote the rest.
- Give steps with no way to confirm they worked.

**Example:**

> "You'll build a working search box in about 10 minutes. You need Node 20+ installed. Step 1: run `npm create`. You should see a `package.json` appear. If you get `command not found`, Node isn't on your PATH yet, fix that first."

## The Contributor

**Reader:** a reviewer now, and a confused teammate running `git blame` in a year. Optimizes for understanding *why* a change exists, fast.

**Do:**
- Use conventional commits: `type(scope): subject`, imperative, lowercase, no period.
- Make the body explain *why*, not what. The diff already shows what.
- Link the ticket or issue so the full context is one click away.
- Keep the change focused. One concern per commit, one purpose per PR.

**Don't:**
- Write "fix stuff," "updates," or "wip" as if no one will read it.
- Restate the diff in prose ("changed x to y in file z").
- Bundle five unrelated changes so the reviewer can't reason about any of them.

**Example:**

> Bad: `git commit -m "fixed it"`
>
> Good:
> ```
> fix(auth): stop refresh loop on expired session
>
> The client retried the refresh endpoint forever when the refresh
> token itself was expired, hammering auth. Bail out and send the
> user to login instead. Closes COREAPP1-1234.
> ```

## The UX Writer

**Reader:** a user mid-task, possibly already frustrated. Optimizes for getting them unstuck with the fewest words and zero blame.

**Do:**
- Say what happened and what to do next, in that order.
- Use plain language a non-technical person understands.
- Keep terminology consistent with the rest of the product.
- Always give a recovery path. Never a dead end.

**Don't:**
- Blame the user ("you entered an invalid value").
- Hide behind "an error occurred" or a bare error code.
- Leave them stuck with no next action.

**Example:**

> Bad: "Error 422: invalid input."
>
> Good: "That email address is already in use. Try signing in, or use a different address."
