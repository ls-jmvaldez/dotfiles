---
name: move-repo-to-gha
description: Migrate a LegalShield .NET service or web app repo to GitHub Actions CI/CD, using an already-migrated LegalShield repo as reference. Creates workflow files, GitHub environments, and configures team reviewers.
---

Migrate the current LegalShield repo's CI/CD to GitHub Actions by copying and adapting workflows from a reference repo that has already been migrated.

This skill is scoped to the `LegalShield` org only. It supports two reference patterns:
- **.NET service** (reference: `LegalShield/products-answers-service`) — 5 split reusable workflows
- **Web app** (reference: `LegalShield/internal-events-web`) — 2 monolithic workflows with frontend build

## Inputs

The user must provide:
- **Health endpoint URL**: The service's dev health URL (at minimum), so UAT/prod can be derived

The user may optionally provide:
- **Reference repo**: An already-migrated LegalShield repo (e.g. `LegalShield/some-service`). If omitted, the skill picks one based on the target repo's project type — see step 0c.

The **target repo** is auto-detected from the current directory. Do not ask the user for it.

If the health URL is missing, stop and ask before proceeding.

## Step 0a: Detect target repo

Run in the current working directory:
```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

This gives `{org}/{repo}`. If the command fails, returns nothing, or `{org}` is not `LegalShield`, stop — this skill is LegalShield-only.

All subsequent `gh api` calls use the detected `{repo}` under the `LegalShield` org.

## Step 0b: Detect project type

Inspect the target repo for frontend markers:

- If `package.json` exists at the repo root OR in an obvious client subdirectory (e.g. `ClientApp/`, `client/`, `web/`): project type is **web**.
- Otherwise: project type is **service**.

Report the detected type so the user can override on a re-run if it's wrong.

## Step 0c: Resolve reference repo

- If the user passed a reference repo, use it.
- Otherwise, map from project type:
  - **service** → `LegalShield/products-answers-service`
  - **web** → `LegalShield/internal-events-web`

Report the default that was chosen so the user can override on a re-run.

## Procedure

### 1. Gather context from reference repo

List the reference repo's workflows:
```bash
gh api repos/LegalShield/{reference-repo}/contents/.github/workflows --jq '.[].name'
```

For each file returned, fetch its contents:
```bash
gh api repos/LegalShield/{reference-repo}/contents/.github/workflows/{file} --jq '.content' | base64 -d
```

If any fetch fails (404, auth error, etc.), stop and report which file could not be fetched. Do not proceed with a partial workflow set.

Fetch environment configuration (names, protection rules, reviewers):
```bash
gh api repos/LegalShield/{reference-repo}/environments --jq '.environments[] | {name, id}'
# For each environment with protection rules:
gh api repos/LegalShield/{reference-repo}/environments/{env-name} --jq '{name, protection_rules, reviewers, deployment_branch_policy}'
```

### 2. Inspect target repo

- List existing workflows: `ls .github/workflows/`
- List existing environments: `gh api repos/LegalShield/{repo}/environments --jq '.environments[] | {name, id}'`
- List existing team collaborators: `gh api repos/LegalShield/{repo}/teams --jq '.[] | {name, slug, permission}'`
- Check repo structure based on project type:
  - **service**: `global.json`, `*.sln`, `*.csproj`, `Dockerfile`, source directories
  - **web**: `package.json`, lockfile (`pnpm-lock.yaml` / `package-lock.json` / `yarn.lock`), client subdirectory, any server-side `*.csproj`

### 3. Derive health endpoint URLs

Given a dev URL like `https://{subdomain}.api.dev-legalshield.com/v1/health`, derive:
- UAT: `https://{subdomain}.api.uat-legalshield.com/v1/health`
- Production: `https://{subdomain}.api.legalshield.com/v1/health`

Confirm the derived URLs with the user before writing them into any workflow file.

If the target project has no health endpoint (some web apps), confirm with the user and skip the health-check steps during adaptation.

### 4. Create workflow files

For each workflow file listed in step 1, create the same filename in the target's `.github/workflows/` with adapted contents. Do not hardcode the filename list — drive it from the reference's directory listing.

Adaptation per file:

- **Repo-name references**: replace any `LegalShield/{reference-repo}` with `LegalShield/{repo}`
- **Source-directory paths**: replace reference-repo source dirs (e.g. `ProductsAnswersService/`) with the target repo's actual source dirs
- **Health check URLs**: substitute derived URLs from step 3
- **AI summary / copilot prompts**: update application description, `git diff` paths, and PR link URLs
- **Dynamic references** (e.g. `github.event.repository.name`) need no change

See `references/adaptation-checklist.md` for the full list.

### 5. Update existing workflows

If `pull-request-helpers.yml` exists in the target repo, bump `actions/checkout` to v6 to match.

### 6. Add reviewer teams as repo collaborators

**CRITICAL: This must happen BEFORE creating environments with reviewers.** Teams cannot be assigned as environment reviewers unless they have access to the repo.

Extract team slugs from the reference repo's environment config, then add each:
```bash
gh api orgs/LegalShield/teams/{team-slug}/repos/LegalShield/{repo} -X PUT -f permission=push
```

### 7. Create GitHub environments

For each environment found in the reference repo (step 1), create the matching environment in the target. The set is not fixed — for example, `internal-events-web` has an extra `production-2` environment beyond the standard sandbox/uat/production trio.

**Environments without protection rules** (e.g. sandbox):
```bash
gh api repos/LegalShield/{repo}/environments/{env-name} -X PUT --input - <<< '{}'
```

**Environments with required reviewers** (e.g. uat, production):
```bash
gh api repos/LegalShield/{repo}/environments/{env-name} -X PUT --input - << EOF
{
  "prevent_self_review": false,
  "reviewers": [
    {"type": "Team", "id": {team-id-1}},
    {"type": "Team", "id": {team-id-2}}
  ]
}
EOF
```

Get team IDs from: `gh api orgs/LegalShield/teams/{team-slug} --jq '{id, slug, name}'`

### 8. Verify

Confirm environments have correct reviewers populated:
```bash
gh api repos/LegalShield/{repo}/environments --jq '.environments[] | {name, protection_rules: [.protection_rules[] | {type, reviewers: [.reviewers[] | {type, name: .reviewer.name}]}]}'
```

If reviewers array is empty after creation, the team was likely not added as a collaborator — go back to step 6.
