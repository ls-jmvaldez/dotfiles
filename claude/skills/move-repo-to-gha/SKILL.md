---
name: move-repo-to-gha
description: Migrate a LegalShield .NET microservice repo to GitHub Actions CI/CD, using an already-migrated LegalShield repo as reference. Creates workflow files, GitHub environments, and configures team reviewers.
---

Migrate the current LegalShield repo's CI/CD to GitHub Actions by copying and adapting workflows from a reference repo that has already been migrated.

This skill is scoped to the `LegalShield` org only.

## Inputs

The user must provide:
- **Health endpoint URL**: The service's dev health URL (at minimum), so UAT/prod can be derived

The user may optionally provide:
- **Reference repo**: An already-migrated LegalShield repo (e.g. `LegalShield/some-service`). Defaults to `LegalShield/products-answers-service`.

The **target repo** is auto-detected from the current directory. Do not ask the user for it.

If the health URL is missing, stop and ask before proceeding.

## Step 0a: Detect target repo

Run in the current working directory:
```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

This gives `{org}/{repo}`. If the command fails, returns nothing, or `{org}` is not `LegalShield`, stop — this skill is LegalShield-only.

All subsequent `gh api` calls use the detected `{repo}` under the `LegalShield` org.

## Step 0b: Resolve reference repo

- If the user passed a reference repo, use it.
- Otherwise, default to `LegalShield/products-answers-service` and report that the default was used so the user can override on a re-run.

## Procedure

### 1. Gather context from reference repo

Fetch all workflow files from the reference repo:
```bash
gh api repos/LegalShield/{reference-repo}/contents/.github/workflows/deploy.yml --jq '.content' | base64 -d
gh api repos/LegalShield/{reference-repo}/contents/.github/workflows/test.yml --jq '.content' | base64 -d
gh api repos/LegalShield/{reference-repo}/contents/.github/workflows/build.yml --jq '.content' | base64 -d
gh api repos/LegalShield/{reference-repo}/contents/.github/workflows/pr.yml --jq '.content' | base64 -d
```

If any of these calls fail (404, auth error, etc.), stop and report which file could not be fetched. Do not proceed with a partial workflow set.

Fetch environment configuration (names, protection rules, reviewers):
```bash
gh api repos/LegalShield/{reference-repo}/environments --jq '.environments[] | {name, id}'
# For each environment with protection rules:
gh api repos/LegalShield/{reference-repo}/environments/{env-name} --jq '{name, protection_rules, reviewers, deployment_branch_policy}'
```

### 2. Inspect target repo

- List existing workflows: `ls .github/workflows/`
- Check repo structure: existing Dockerfile, global.json, solution file, source directories
- List existing environments: `gh api repos/LegalShield/{repo}/environments --jq '.environments[] | {name, id}'`
- List existing team collaborators: `gh api repos/LegalShield/{repo}/teams --jq '.[] | {name, slug, permission}'`

### 3. Derive health endpoint URLs

Given a dev URL like `https://{subdomain}.api.dev-legalshield.com/v1/health`, derive:
- UAT: `https://{subdomain}.api.uat-legalshield.com/v1/health`
- Production: `https://{subdomain}.api.legalshield.com/v1/health`

Confirm the derived URLs with the user before writing them into any workflow file.

### 4. Create workflow files

Create these files in `.github/workflows/`, adapted from the reference:

**test.yml** — Reusable dotnet test workflow. Usually no adaptation needed.

**build.yml** — Reusable Docker build workflow. Usually no adaptation needed (uses `github.event.repository.name` dynamically).

**pr.yml** — PR trigger calling test + build. Usually no adaptation needed.

**deploy.yml** — Full deployment pipeline. Adapt these parts:
- Health check URLs (step 3 values) in `get-uat-commit` and `get-prod-commit` steps
- AI summary copilot prompt: update application description, `git diff` source directory paths, and GitHub PR link URLs pointing to the target repo
- See `references/adaptation-checklist.md` for the full list

### 5. Update existing workflows

If `pull-request-helpers.yml` exists, bump `actions/checkout` to v6 to match.

### 6. Add reviewer teams as repo collaborators

**CRITICAL: This must happen BEFORE creating environments with reviewers.** Teams cannot be assigned as environment reviewers unless they have access to the repo.

Extract team slugs from the reference repo's environment config, then add each:
```bash
gh api orgs/LegalShield/teams/{team-slug}/repos/LegalShield/{repo} -X PUT -f permission=push
```

### 7. Create GitHub environments

Create each environment matching the reference repo's configuration:

**sandbox** (no protection rules):
```bash
gh api repos/LegalShield/{repo}/environments/sandbox -X PUT --input - <<< '{}'
```

**uat** and **production** (with required reviewers):
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
