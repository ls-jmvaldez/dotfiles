# Clearing Dependabot alerts — pnpm / TS-React repos

Recipe for a sub-agent clearing open Dependabot alerts in a pnpm workspace. Modeled on
`LegalShield/internal-membership-web#186`, which cleared 26 alerts (2 critical, 7 high,
12 medium, 5 low) in one PR. Work in the provided worktree on `chore/<epic-lower>-deps`.

## 1. Inventory the alerts

```bash
gh api /repos/LegalShield/<repo>/dependabot/alerts --paginate \
  -q '.[] | select(.state=="open") | {sev: .security_advisory.severity, pkg: .dependency.package.name, scope: .dependency.scope, vuln: .security_vulnerability.vulnerable_version_range, patched: .security_vulnerability.first_patched_version.identifier}'
```

`scope` is the tell: `runtime`/`development` on a package that appears in a workspace
`package.json` → **direct**. A package that only shows up in the lockfile → **transitive**.

## 2. Respect the repo's supply-chain guards

Check root `package.json` `pnpm` config before choosing versions:

- **`minimumReleaseAge`** (membership uses 7 days / `10080` min): a version must be at
  least this old or `pnpm install` refuses it. Pick the oldest patched version that both
  clears the vuln range **and** has aged past the window. Do **not** pass
  `--ignore-minimum-release-age` — that bypass is the exact hole this repo closed.
- **`blockExoticSubdeps`**: no git/tarball/link specifiers in resolutions.

If the only fix for an alert is a version too new to clear quarantine, **defer it** —
list it in the PR body, don't force it.

## 3. Fix direct deps

Bump the version range in the owning workspace `package.json` (root, `apps/*`,
`packages/**`) to the patched version. Example from #186: `vitest ^3.2.4 -> ^3.2.6`,
`@vitest/browser ^3.2.4 -> ^3.2.5`, `dompurify ^3.4.0 -> ^3.4.11`.

## 4. Fix transitive deps via root `pnpm.overrides`

Most alerts are transitive. Pin the patched version in root `package.json`
`pnpm.overrides`, and raise the upper bound of any existing override the alert now
demands. #186 pinned: `ws`, `@grpc/grpc-js`, `form-data`, `protobufjs`,
`@opentelemetry/core`, `js-yaml`, `uuid`, `esbuild`, `@babel/core`, plus a `dompurify`
override so no stale copy survives dedupe, and raised the two existing `vite` overrides.

Prefer the narrowest override that clears the vuln so you don't over-pin the tree.

## 5. Regenerate the lockfile — the normal way

```bash
pnpm install     # NO --ignore-minimum-release-age
```

Must resolve clean. If it fails on `minimumReleaseAge`, your target version is too new —
go back to step 2 and pick an older patched version or defer.

## 6. Add / verify Dependabot config

If `.github/dependabot.yml` is absent (alerts were on org defaults), add one that groups
npm minor/patch into a single weekly PR per ecosystem with a **7-day `cooldown`**, so the
bot stops opening a PR the instant a release publishes (the one path that sidesteps
pnpm's `minimumReleaseAge` at resolution time). Security PRs for active alerts still fire
immediately by design. If the file exists, confirm the cooldown is present.

## 7. Verify (honestly)

```bash
pnpm -r test
```

Some suites can't run locally and that's expected — do not fake them green:

- **vitest-browser / Storybook suites** (e.g. `ui-storybook`) need a live
  Storybook/Playwright harness; excluded from the local gate on purpose. CI is the
  source of truth.
- **E2E** (e.g. `pnpm -w membership-details-e2e`) needs secrets like
  `E2E_USER_EMAIL` / `E2E_USER_PASSWORD` not present locally.

Flag both in the PR's Manual test steps for a reviewer with creds / CI to cover.

## 8. Confirm the alert count

After pushing, note in the PR body that a reviewer should confirm
`gh api /repos/LegalShield/<repo>/dependabot/alerts` drops to **0 open** once Dependabot
re-scans the pushed lockfile, and close any one-off Dependabot PRs this supersedes
(e.g. an existing grouped-bump PR) as superseded.
