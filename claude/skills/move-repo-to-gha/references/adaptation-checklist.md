# Adaptation Points When Migrating Workflows

When copying workflows from a reference repo, these are the points that must be adapted per-repo. Specific files depend on the reference pattern in use.

## .NET service pattern (reference: products-answers-service)

### test.yml
- No repo-specific changes needed (generic dotnet test)

### build.yml
- No repo-specific changes needed (uses `github.event.repository.name` dynamically)

### pr.yml
- No repo-specific changes needed

### deploy.yml
- Health check URLs in `get-uat-commit` and `get-prod-commit` steps
- AI summary copilot prompt: application description, `git diff` source-directory paths, GitHub PR link base URL
- Source-directory names in feature-flag detection (e.g. `ProductsAnswersService/` vs `Products.Answers.Processors/ Products.Answers.Reader/`)

### pull-request-helpers.yml
- Bump `actions/checkout` to v6 if not already

## Web app pattern (reference: internal-events-web)

### ci.yml
- Source-directory names: `.csproj` paths, client app directory name
- `BuildClientApp` toggle and any frontend-specific build paths
- Secret references that assume a specific project name

### deploy.yml
- Health check URLs (if the app exposes a health endpoint)
- AI summary copilot prompt: application description, `git diff` paths, GitHub PR link base URL
- Environment set — `internal-events-web` has `production-2` in addition to sandbox/uat/production; copy whatever the reference actually has
- ECR registry reference usually stays the same; confirm it matches the target's AWS account

## Shared across both patterns

### Repo references
- Replace any `LegalShield/{reference-repo}` URL or path with `LegalShield/{target-repo}`

### Environment URL derivation

Derive UAT and production URLs from the dev URL by substituting only the env-prefix segment:
- `dev-` → `uat-` for UAT
- `dev-` → `` (empty) for production

The subdomain, optional `.api.` segment, and base TLD stay as-is. This works across every LegalShield domain family without needing a lookup.

### Known domain families in the org (reference only, non-exhaustive)

- `*.api.{env-prefix}legalshield.com` — canonical public API
- `*.api.{env-prefix}legalshieldinternal.com` — internal API
- `*.{env-prefix}legalshieldinternal.com` — internal, no `.api.` segment
- `*.api.{env-prefix}shield-service.com` — shield-service platform
- `*.reader.{env-prefix}shield-service.com` — reader services
- `*.{env-prefix}legalshieldproviders.com` — providers-facing
- `*.{env-prefix}legalshield.com` — public, no `.api.` segment

New families work automatically because the skill uses substitution, not a lookup.
