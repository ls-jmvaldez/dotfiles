# Clearing Dependabot alerts — .NET / NuGet repos

Recipe for a sub-agent clearing NuGet alerts, keyed on a `.csproj` / `packages.config` /
`Directory.Packages.props` manifest. Route here **per alert** by `manifest_path`, not by
repo. Work in the provided worktree on `chore/<ticket-lower>-deps`.

> **Status: still unvalidated.** This mirrors the pnpm recipe's structure but has **not**
> been proven against a real LegalShield NuGet alert. Notably, the two `.NET`-named
> tickets exercised so far (COREAPP1-3824 internal-resolutions-service, COREAPP1-3821
> internal-iseries-gateway-service) turned out to carry **npm-only** alerts in their test
> harnesses — zero NuGet alerts. Under epic COREAPP1-3576, a `-service` name does not
> imply the alerts are NuGet; check `manifest_path` first. Treat this file as a starting
> point — on the first real NuGet alert, verify each step against how the repo actually
> pins packages and update this file. Flag surprises to Joe rather than forcing a fix.

## 1. Inventory the alerts

```bash
gh api /repos/LegalShield/<repo>/dependabot/alerts --paginate \
  -q '.[] | select(.state=="open") | {sev: .security_advisory.severity, pkg: .dependency.package.name, patched: .security_vulnerability.first_patched_version.identifier}'
```

Cross-check what's actually resolved:

```bash
dotnet restore
dotnet list package --vulnerable --include-transitive
```

## 2. Direct vs transitive

- **Direct**: the package appears as a `<PackageReference>` in a `.csproj` (or as a
  version entry in `Directory.Packages.props` under central package management). Bump it
  there.
- **Transitive**: pulled in by another package, not referenced directly. Pin it.

## 3. Fix direct deps

- **Central Package Management** (`Directory.Packages.props` with
  `ManagePackageVersionsCentrally=true`): bump the `<PackageVersion>` entry there — it's
  the single source of truth for the whole solution.
- Otherwise: bump `<PackageReference Version="...">` in each owning `.csproj`.

## 4. Fix transitive deps

Pin the patched version explicitly so the resolver picks it up:

- **CPM**: add a `<PackageVersion Include="<pkg>" Version="<patched>" />` in
  `Directory.Packages.props`, promoting the transitive package to a pinned version.
- **Non-CPM**: add a direct `<PackageReference>` for the vulnerable transitive package at
  the patched version (NuGet nearest-wins will prefer the direct reference). Add a comment
  referencing the alert so the pin's purpose is clear.

## 5. Restore + verify

```bash
dotnet restore
dotnet build
dotnet test
```

`dotnet list package --vulnerable --include-transitive` should come back clean for the
alerts you targeted. Anything requiring a major bump with breaking API changes that can't
be resolved without a product call: **defer and report**, don't force.

## 6. Dependabot config

If `.github/dependabot.yml` is absent, add one grouping NuGet minor/patch into a single
weekly PR with a cooldown, matching the cadence hardening the pnpm repos use. If it
exists, confirm the cooldown/grouping is present.

## 7. Confirm the alert count

Note in the PR body that a reviewer should confirm
`gh api /repos/LegalShield/<repo>/dependabot/alerts` drops to 0 open after re-scan, and
close any superseded one-off Dependabot PRs.
