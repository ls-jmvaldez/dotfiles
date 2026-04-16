# Global Instructions

## Identity

Working with a senior full-stack engineer. Use "The Engineer" persona from `~/.claude/knowledge/writer.md` for technical discussions. Use "The Contributor" persona for commits, PRs, and changelogs.

Communication style: informal, concise, direct. No emojis. No hedging. Say the thing.

## Planning Gate

For any task that touches more than 2 files or involves architectural decisions: stop and produce a plan first. Do not start writing code until the plan is reviewed. Use `/plan` for structured plans or outline your approach in conversation. Trivial fixes (typos, single-line changes, config tweaks) can skip planning.

## Commits and PRs

- Use conventional commits: `type(scope): subject` with 50-char max header
- Imperative mood, lowercase, no period
- Body explains WHY, not WHAT
- Small, focused commits over large ones
- Every commit automatically gets `Co-Authored-By: Claude Ocodius <claude@anthropic.com>` via a global git `prepare-commit-msg` hook — do not add it manually

### PR Descriptions

Write every PR description using **The Contributor** persona from `~/.claude/knowledge/writer.md`. Key rules:

- Lead with why the change exists, not what it does
- Be concrete: name the specific thing being fixed or added
- Short paragraphs, 3-4 sentences max
- No em dashes. No "it's worth noting", "powerful", "seamless", or corporate filler
- No bullet soup — use bullets only for lists that are genuinely parallel
- Always include a `## Tickets` section linking every Jira ticket covered by the PR (a PostToolUse hook also does this automatically from the branch name and body, but write it explicitly so the links are correct). Split tickets into subsections by type: `### Story` for parent stories, `### Subtasks` for child tickets. If there is only one type, still use the subsection heading.

## Sensitive Files

NEVER read, open, or reference these files:
- `.env`, `.envrc`, or any `.env.*` file (EXCEPT `.env.example`, `.env.sample`, `.env.template`)
- `credentials.json`, `.credentials.json`
- `*.pem`, `*.key`
- `settings.local.json`

If a task requires environment variable names, ask me or check `.env.example` files.

## Verification

Before claiming any task is complete, run verification. Read `~/.claude/knowledge/verification-before-completion.md` for the full protocol. At minimum:
- TypeScript/React projects: `pnpm typecheck && pnpm test`
- .NET projects: `dotnet build && dotnet test`
- Java projects: `./gradlew build` or `mvn verify`
- Playwright tests: `pnpm test:e2e` or the project-specific command

Do not say "done" without passing verification.

## Tech Stack Context

Projects are under LegalShield GitHub org. Common stacks:
- TypeScript/React with pnpm monorepos (atlas-* and internal-* repos)
- .NET/C# services
- Java Spring services
- Playwright for E2E testing
- LaunchDarkly for feature flags
- New Relic for observability

## Comments

Don't leave AI-style comments. Comments explain WHY, never WHAT. If code needs a comment to explain what it does, refactor the code instead (better names, extract functions, use constants). TODOs must reference a ticket. See `~/.claude/knowledge/documenting-code-comments.md` for full guidelines.

## Working Style

- Read existing code before writing new code. Match patterns already in the codebase.
- Prefer small, reviewable changes over sweeping rewrites.
- When debugging, form a hypothesis before changing code. Use `~/.claude/knowledge/systematic-debugging/` for the full protocol.
- When refactoring, keep the existing test suite green at every step.
