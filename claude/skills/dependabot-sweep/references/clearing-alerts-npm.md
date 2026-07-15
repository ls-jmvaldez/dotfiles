# Clearing Dependabot alerts — npm repos (`package-lock.json`)

Recipe for a sub-agent clearing npm alerts, keyed on a `package-lock.json` manifest.
Route here **per alert** by `manifest_path`, not by repo — an npm harness often lives
inside a non-JS repo (e.g. `tests/` in a .NET service; observed on COREAPP1-3824). Work
in the provided worktree on `chore/<ticket-lower>-deps`.

npm is **not** pnpm: it uses the `overrides` field (npm 8.3+), `npm install` regenerates
`package-lock.json`, and there is **no `minimumReleaseAge` guard**. Do not apply the pnpm
recipe's quarantine rules here.

## 0. Enumerate ALL manifests first — a repo usually has several

Under epic COREAPP1-3576, npm alerts cluster in multiple `package-lock.json` files per
repo: a React `ClientApp/` under an ASP.NET host, an `automation-tests/` or `tests/`
harness, and sometimes a root lockfile. Some repos have three (internal-resolutions-web:
`automation-tests/`, `tests/`, root) or two separate app dirs (internal-tools). List the
distinct manifest directories and repeat steps 1–5 for **each**:

```bash
gh api /repos/LegalShield/<repo>/dependabot/alerts --paginate \
  -q '.[] | select(.state=="open") | .dependency.manifest_path' | sort -u
```

## 1. Inventory the alerts for this manifest

```bash
gh api /repos/LegalShield/<repo>/dependabot/alerts --paginate \
  -q '.[] | select(.state=="open") | select(.dependency.manifest_path=="<dir>/package-lock.json") | {sev: .security_advisory.severity, pkg: .dependency.package.name, scope: .dependency.scope, range: .security_vulnerability.vulnerable_version_range, patched: .security_vulnerability.first_patched_version.identifier}'
```

`<dir>` is the manifest's directory (e.g. `tests`, `automation-tests`, `SomeApp/ClientApp`). Confirm the currently-resolved
version in the lockfile so you know the delta:
`python3 -c "import json; d=json.load(open('<dir>/package-lock.json')); print(d['packages']['node_modules/<pkg>']['version'])"`.

## 2. Direct vs transitive

- **Direct**: the package is in `<dir>/package.json` `dependencies`/`devDependencies` →
  bump its range there.
- **Transitive**: only in the lockfile → pin via the `overrides` field.

## 3. Fix via `overrides`

In `<dir>/package.json`, add (or **merge into** — check first, one may already exist) an
`overrides` block pinning the patched versions with a caret to stay same-major:

```json
"overrides": { "form-data": "^4.0.6", "js-yaml": "^4.2.0" }
```

Same-major caret ranges avoid dragging in a breaking major. If the only patched version
is a new major, that's a breaking change — **defer and report**, don't force it.

### Multi-major transitives (validated on COREAPP1-3819)

A package often exists in the tree at **two majors at once**, each with its own advisory
(e.g. `undici` 6.x and 7.x, `ws` 7.x and 8.x, `js-yaml` 3.x and 4.x — and 3→4 is a
breaking API change). A blanket top-level override forces **one** version onto every
copy, collapsing majors and potentially breaking a consumer pinned to the old one. Use
npm **version-scoped override keys** to pin each major line independently:

```json
"overrides": {
  "js-yaml@^3.0.0": "^3.15.0",
  "js-yaml@^4.0.0": "^4.2.0",
  "undici@^6.0.0":  "^6.27.0",
  "undici@^7.0.0":  "^7.28.0"
}
```

After regen, confirm the lockfile resolved **both** majors to patched versions — a
malformed key is silently ignored, leaving the alert unfixed. If one major line can't be
patched without a breaking jump onto an incompatible consumer, defer that line and
disclose it (a `## Deferred` section in the PR body — required by Joe's global rules).

## 4. Regenerate the lockfile — preserve its version

```bash
npm --prefix <dir> install
```

**Keep the existing `lockfileVersion`.** Newer npm (11+) rewrites a v2 lockfile to v3,
producing a huge, noisy diff. Check the file's current `lockfileVersion`; if npm bumps
it, re-run with `npm install --lockfile-version 2` (or match whatever it was). Aim for a
minimal diff: only the vulnerable packages move, plus any strictly-required transitive
cascade (e.g. a dependency of the patched version). Note any cascade in the PR body.

## 5. Verify (honestly)

```bash
npm --prefix <dir> ls <pkg1> <pkg2>   # confirm resolved >= patched
npm --prefix <dir> audit               # should report 0 vulnerabilities for the targeted GHSAs
npm --prefix <dir> test                # run it, but see below
```

Test suites often can't pass locally: many need a live service / DB (`docker-compose up`)
or machine-JWT / secret env not present in the worktree (COREAPP1-3824's mocha suite
401'd on missing creds). That's environmental, not the dep change. Do **not** claim it
green — capture the exact failure and flag it for CI in the PR. `npm audit` reporting 0
vulns plus `npm ls` showing patched versions is the real proof the alerts are cleared.

### Private registry auth is MANDATORY — `npm audit` is NOT enough

Repos depending on private `@legalshield/*` packages need registry auth. **Always export
the token before any npm work** (it has `read:packages`; the plain `gh` token does not):

```bash
export GIT_PERSONAL_ACCESS_TOKEN="$(op read 'op://Personal/GIT_PERSONAL_ACCESS_TOKEN/credential')"
```

Without it, `npm install` 403s on the private tarballs and **rolls back, leaving a
lockfile that is internally inconsistent with the manifest** — e.g. an `undici@^7`
override needs `undici-types@8.3.0` / `@types/node@26.x` that never got written.
`npm audit` (metadata-only) passes on that broken lockfile, so it is **NOT proof the work
is done**. `npm ci` (strict) rejects it, and that is exactly what CI runs — it failed
COREAPP1-3819 with `EUSAGE ... Missing: undici-types@8.3.0 from lock file`.

**Gate on `npm ci`, not `npm audit`.** After regenerating, in every manifest dir:

```bash
rm -rf node_modules && npm ci   # must succeed; this is what CI does
```

### Match the CI node version

npm 11 (local) is more lenient than npm 10 (CI on node 20). A lockfile npm 11 accepts can
still fail `npm ci` under npm 10. Regenerate and verify on the **CI node version** — read
`.node-version` / the workflow's `NODE_VERSION` (COREAPP1-3819 pins 20.19.6):

```bash
export NVM_DIR="$HOME/.nvm"; . "$NVM_DIR/nvm.sh"; nvm use 20.19.6
```

With auth + the right node, the **build IS verifiable locally — so verify it**:
`npm ci && npm run build && npm run lint && npm test` on the root app (COREAPP1-3819:
webpack build clean, 1399 jest passing). Only genuinely un-runnable suites (live-service
e2e) defer to CI. After pushing, **watch CI** (`gh pr checks <n> --watch`) and confirm it
goes green before calling the ticket done.

## 6. Dependabot config

If `.github/dependabot.yml` is absent, add a `version: 2` config with a
`package-ecosystem: "npm"` entry for the manifest's directory (e.g. `/tests`), weekly,
minor/patch grouped, `cooldown: { default-days: 7 }`. If the repo also has a .NET
solution, add a `nuget` entry for the solution directory (usually `/`) with the same
hardening. If the file exists, confirm the cooldown/grouping is present.

## 7. Confirm the alert count

Note in the PR body that a reviewer should confirm the repo's Dependabot alerts drop to
0 open after re-scan.
