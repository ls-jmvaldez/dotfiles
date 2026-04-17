# Adaptation Points When Migrating Workflows

When copying workflows from a reference repo, these are the points that must be adapted per-repo:

## test.yml
- No repo-specific changes needed (generic dotnet test)

## build.yml
- No repo-specific changes needed (uses `github.event.repository.name` dynamically)

## pr.yml
- No repo-specific changes needed

## deploy.yml
These require adaptation:

### Health endpoint URLs
- UAT: `https://<service-subdomain>.api.uat-legalshield.com/v1/health`
- Production: `https://<service-subdomain>.api.legalshield.com/v1/health`
- Pattern: replace domain prefix, keep `/v1/health` path

### AI summary copilot prompts
- Application description (e.g. "a .NET API service" vs "a .NET journal reader/processor service")
- `git diff` paths for feature flag detection (e.g. `ProductsAnswersService/` vs `Products.Answers.Processors/ Products.Answers.Reader/`)
- GitHub PR link base URL (e.g. `LegalShield/products-answers-service/pull/` vs `LegalShield/products-answers-journal-reader-service/pull/`)

### Environment URL patterns
- dev: `*.api.dev-legalshield.com`
- sandbox: `*.api.sandbox-legalshield.com`
- UAT: `*.api.uat-legalshield.com`
- Production: `*.api.legalshield.com`

## pull-request-helpers.yml
- Bump `actions/checkout` to v6 if not already
