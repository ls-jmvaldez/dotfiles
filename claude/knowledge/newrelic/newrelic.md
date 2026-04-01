# New Relic Query Reference

Comprehensive NRQL query catalog, NerdGraph recipes, and diagnostic reference for the `/newrelic` skill.

## Environment Naming Conventions

All NR application names include an environment suffix. Always filter by environment in queries.

| Pattern | Environment | NRQL Filter |
|---------|-------------|-------------|
| `[SB]` | Sandbox/Dev | `appName LIKE '%[SB]%'` |
| `[UT]` | UAT | `appName LIKE '%[UT]%'` |
| `[PD]` | Production (combined) | `appName LIKE '%[PD]%'` |
| `[PD1]` | Production instance 1 | `appName LIKE '%[PD1]%'` |
| `[PD2]` | Production instance 2 | `appName LIKE '%[PD2]%'` |

**Notes:**
- Most services have `[PD1]` and sometimes `[PD2]` instances, plus `[PD]` as a combined view
- For production queries, use `appName LIKE '%[PD]%'` to capture `[PD]`, `[PD1]`, and `[PD2]`
- Some app names include a language suffix like `(.NET)` or `(Node.js)`

## CLI Quick Reference

```bash
# Verify CLI auth
newrelic profile list

# Test NRQL query
newrelic nrql query --query "SELECT count(*) FROM Transaction SINCE 1 minute ago"

# Entity discovery
newrelic entity search --name "<partial-name>" --domain APM --type APPLICATION
```

---

## NRQL Query Catalog

### Health Check Queries

```bash
# Error rate + throughput + response times
newrelic nrql query --query "SELECT percentage(count(*), WHERE error IS true) AS 'Error Rate', rate(count(*), 1 minute) AS 'RPM', average(duration) AS 'Avg Duration', percentile(duration, 95) AS 'P95' FROM Transaction WHERE appName = '<APP_NAME>' SINCE 1 hour ago"

# Top errors by class and message
newrelic nrql query --query "SELECT count(*) FROM TransactionError WHERE appName = '<APP_NAME>' SINCE 1 hour ago FACET error.class, error.message LIMIT 10"

# Multi-app health (use with team app list)
newrelic nrql query --query "SELECT percentage(count(*), WHERE error IS true) AS 'Error Rate', rate(count(*), 1 minute) AS 'RPM', average(duration) AS 'Avg Duration', percentile(duration, 95) AS 'P95' FROM Transaction WHERE appName IN (<APP_LIST>) SINCE 1 hour ago FACET appName"

# Recent deployments (may affect health)
newrelic nrql query --query "SELECT * FROM NrAuditEvent WHERE description LIKE '%<APP_NAME>%' SINCE 7 days ago LIMIT 5"
```

### Error Triage Queries

```bash
# Errors with context — single app
newrelic nrql query --query "SELECT count(*) AS 'Count', uniqueCount(request.uri) AS 'Endpoints', latest(timestamp) AS 'Last Seen' FROM TransactionError WHERE appName = '<APP_NAME>' SINCE 24 hours ago FACET error.class, error.message LIMIT 20"

# Errors with context — multiple apps
newrelic nrql query --query "SELECT count(*) AS 'Count', uniqueCount(request.uri) AS 'Endpoints', latest(timestamp) AS 'Last Seen' FROM TransactionError WHERE appName IN (<APP_LIST>) SINCE 24 hours ago FACET error.class, error.message, appName LIMIT 20"

# All prod errors (broad scan)
newrelic nrql query --query "SELECT count(*) AS 'Count', uniqueCount(request.uri) AS 'Endpoints', latest(timestamp) AS 'Last Seen' FROM TransactionError WHERE appName LIKE '%[PD]%' SINCE 24 hours ago FACET error.class, error.message, appName LIMIT 20"

# Error trend (is it getting worse?)
newrelic nrql query --query "SELECT count(*) FROM TransactionError WHERE appName = '<APP_NAME>' AND error.class = '<CLASS>' SINCE 7 days ago TIMESERIES 1 day"
```

### Error Deep Dive Queries

```bash
# Error details with transaction context
newrelic nrql query --query "SELECT timestamp, error.class, error.message, transactionName, request.uri, request.method, host FROM TransactionError WHERE appName = '<APP_NAME>' AND error.class = '<CLASS>' SINCE 24 hours ago LIMIT 20"

# When did this error start?
newrelic nrql query --query "SELECT count(*) FROM TransactionError WHERE appName = '<APP_NAME>' AND error.class = '<CLASS>' SINCE 30 days ago TIMESERIES 1 day"

# Stack traces
newrelic nrql query --query "SELECT error.class, error.message, error.stack FROM TransactionError WHERE appName = '<APP_NAME>' AND error.class = '<CLASS>' SINCE 24 hours ago LIMIT 5"

# Deployment correlation
newrelic nrql query --query "SELECT * FROM NrAuditEvent WHERE description LIKE '%<APP_NAME>%' SINCE 7 days ago"
```

### Journal Reader Queries

```bash
# Reader processing throughput (look for drops)
newrelic nrql query --query "SELECT rate(count(*), 1 minute) FROM Transaction WHERE appName LIKE '%reader%[PD]%' SINCE 1 hour ago FACET appName TIMESERIES"

# Also check -rdr suffix apps
newrelic nrql query --query "SELECT rate(count(*), 1 minute) FROM Transaction WHERE appName LIKE '%-rdr%[PD]%' SINCE 1 hour ago FACET appName TIMESERIES"

# Reader errors
newrelic nrql query --query "SELECT count(*) FROM TransactionError WHERE appName LIKE '%reader%[PD]%' OR appName LIKE '%-rdr%[PD]%' SINCE 24 hours ago FACET appName, error.class, error.message LIMIT 20"

# Slow processing (potential lag indicator)
newrelic nrql query --query "SELECT average(duration), max(duration), percentile(duration, 99) FROM Transaction WHERE appName = '<READER_APP>' SINCE 1 hour ago FACET name"
```

**Reader-specific error patterns:**
- **Quarantine entries** — `ProcessJournalEntry` failures: check idempotency or downstream service health
- **Connection errors** — PostgreSQL or downstream SDK timeouts: check database health or upstream service
- **Deserialization errors** — Schema changes in upstream journal: check recent deployments on the producing service
- **Throughput drops to zero** — Reader may be stuck or pod crashed: check pod health

### Frontend Queries

```bash
# JavaScript errors
newrelic nrql query --query "SELECT count(*) FROM JavaScriptError WHERE appName = '<APP_NAME>' SINCE 24 hours ago FACET errorMessage, errorClass, pageUrl LIMIT 20"

# Page performance
newrelic nrql query --query "SELECT average(duration), percentile(duration, 95), average(domProcessingDuration) FROM PageView WHERE appName = '<APP_NAME>' SINCE 1 hour ago FACET pageUrl LIMIT 10"

# Ajax errors (failed API calls from browser)
newrelic nrql query --query "SELECT count(*) FROM AjaxRequest WHERE appName = '<APP_NAME>' AND httpResponseCode >= 400 SINCE 24 hours ago FACET requestUrl, httpResponseCode LIMIT 20"

# Page load breakdown
newrelic nrql query --query "SELECT average(backendDuration), average(domProcessingDuration), average(pageRenderingDuration) FROM PageView WHERE appName = '<APP_NAME>' SINCE 1 hour ago"
```

### Marketing Web Queries

For sites with custom monitoring layers (structured error categories, severity levels, service categorization).

```bash
# Errors by domain category
newrelic nrql query --query "SELECT count(*) FROM JavaScriptError WHERE appName = '<APP_NAME>' SINCE 24 hours ago FACET errorCategory LIMIT 20"

# Critical severity errors only
newrelic nrql query --query "SELECT count(*) FROM JavaScriptError WHERE appName = '<APP_NAME>' AND errorSeverity = 'critical' SINCE 24 hours ago FACET errorMessage LIMIT 20"

# Errors by backend service being called
newrelic nrql query --query "SELECT count(*) FROM JavaScriptError WHERE appName = '<APP_NAME>' SINCE 24 hours ago FACET serviceCategory LIMIT 20"

# Checkout step funnel
newrelic nrql query --query "SELECT count(*) FROM PageAction WHERE appName = '<APP_NAME>' AND actionName = 'view_step' SINCE 24 hours ago FACET step"

# Login funnel
newrelic nrql query --query "SELECT count(*) FROM PageAction WHERE appName = '<APP_NAME>' AND actionName LIKE 'integrated_login_%' SINCE 24 hours ago FACET actionName"

# Login failures with details
newrelic nrql query --query "SELECT count(*) FROM PageAction WHERE appName = '<APP_NAME>' AND actionName = 'integrated_login_failure' SINCE 24 hours ago FACET statusCode, errorMessage"

# Login success rate by user type
newrelic nrql query --query "SELECT percentage(count(*), WHERE actionName = 'integrated_login_success') AS 'Success Rate' FROM PageAction WHERE appName = '<APP_NAME>' AND actionName IN ('integrated_login_attempt', 'integrated_login_success', 'integrated_login_failure') SINCE 24 hours ago FACET loginEmailType"

# Errors correlated with checkout step
newrelic nrql query --query "SELECT count(*) FROM JavaScriptError WHERE appName = '<APP_NAME>' AND step IS NOT NULL SINCE 24 hours ago FACET step, errorCategory"

# Error trend by category over time
newrelic nrql query --query "SELECT count(*) FROM JavaScriptError WHERE appName = '<APP_NAME>' SINCE 7 days ago FACET errorCategory TIMESERIES 1 day"

# Errors for a specific user
newrelic nrql query --query "SELECT count(*) FROM JavaScriptError WHERE appName = '<APP_NAME>' AND userId = '<USER_ID>' SINCE 7 days ago FACET errorMessage"
```

**Key custom attributes on JavaScriptError:**
- `errorCategory` — domain classification (checkout, payment, cart, api, network, auth, etc.)
- `errorSeverity` — `critical` / `error` / `warning` / `info` / `debug`
- `serviceCategory` — which backend service failed (purchase, order, payment-method, identity, etc.)
- `correlationId` — unique error ID for cross-system tracking
- `appVersion`, `environment`, `path`, `step`, `component`, `form`

**Key PageAction events:**
- `view_step` — checkout step with `step` attribute
- `integrated_login_*` — login funnel with `loginEmailType`, `statusCode`, `duration`

### Cross-Service Tracing Queries

```bash
# Find distributed traces with errors
newrelic nrql query --query "SELECT * FROM Span WHERE error IS true AND service.name = '<SERVICE>' SINCE 1 hour ago LIMIT 10"

# Find trace IDs from erroring transactions
newrelic nrql query --query "SELECT traceId, error.class, error.message, transactionName FROM TransactionError WHERE appName = '<APP_NAME>' SINCE 1 hour ago LIMIT 10"

# Look up traces in downstream services
newrelic nrql query --query "SELECT appName, error.class, error.message, transactionName FROM TransactionError WHERE traceId = '<TRACE_ID>' SINCE 1 hour ago"
```

**Approach for cross-service tracing:**
1. Query trace IDs from the originating service with errors
2. For each trace ID, query downstream services to find the full error chain
3. Map service names to repos using the app registry

### Checkout & Purchase Monitoring Queries

```bash
# Purchase success rate (Browser ajax)
newrelic nrql query --query "SELECT count(*) FROM AjaxRequest WHERE appName LIKE '<CHECKOUT_APP>%[PD]%' AND requestUrl LIKE '%purchase%' SINCE 1 hour ago FACET httpResponseCode"

# Partner sessions (detected via tracking pixels in AjaxRequest)
newrelic nrql query --query "SELECT count(*) FROM AjaxRequest WHERE appName LIKE '<CHECKOUT_APP>%[PD]%' AND requestUrl LIKE '%<PARTNER>%' SINCE 1 hour ago FACET requestUrl LIMIT 20"

# Verify a specific order completed
newrelic nrql query --query "SELECT count(*) FROM AjaxRequest WHERE appName LIKE '<CHECKOUT_APP>%[PD]%' AND requestUrl LIKE '%purchase%' AND requestUrl LIKE '%<ORDER_ID_PREFIX>%' SINCE 1 hour ago FACET httpResponseCode"
```

**Key insight:** NR Browser strips query params from `pageUrl`, so partner context is only visible in tracking pixel URLs captured in `AjaxRequest` events.

---

## NerdGraph Recipes

For data the CLI can't access directly, use NerdGraph via curl. Requires `NEW_RELIC_API_KEY` and `NEW_RELIC_ACCOUNT_ID` env vars (extract from `newrelic profile list` if needed).

### Error Groups

```bash
curl -s https://api.newrelic.com/graphql \
  -H "Content-Type: application/json" \
  -H "API-Key: $NEW_RELIC_API_KEY" \
  -d '{
    "query": "{ actor { account(id: '$NEW_RELIC_ACCOUNT_ID') { nrql(query: \"SELECT count(*) FROM TransactionError WHERE appName LIKE '"'"'%[PD]%'"'"' SINCE 24 hours ago FACET error.class, appName LIMIT 50\") { results } } } }"
  }'
```

### Entity Relationships (Service Dependencies)

```bash
curl -s https://api.newrelic.com/graphql \
  -H "Content-Type: application/json" \
  -H "API-Key: $NEW_RELIC_API_KEY" \
  -d '{
    "query": "{ actor { entitySearch(query: \"name = '"'"'<APP_NAME>'"'"' AND domain = '"'"'APM'"'"'\") { results { entities { name relationships { source { entity { name } } target { entity { name } } type } } } } } }"
  }'
```

### Alert Conditions and Violations

```bash
curl -s https://api.newrelic.com/graphql \
  -H "Content-Type: application/json" \
  -H "API-Key: $NEW_RELIC_API_KEY" \
  -d '{
    "query": "{ actor { account(id: '$NEW_RELIC_ACCOUNT_ID') { nrql(query: \"SELECT count(*) FROM NrAiIncident WHERE priority = '"'"'critical'"'"' SINCE 24 hours ago FACET conditionName, entity.name LIMIT 20\") { results } } } }"
  }'
```

---

## Interpretation Guide

### Health Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| Error rate | > 2% | > 5% |
| P95 response (services) | > 1s | > 2s |
| P95 response (web apps) | > 3s | > 5s |
| RPM drop | > 30% below baseline | > 50% below baseline |

### Prioritization Criteria

Apply in order when triaging multiple errors:

1. **Team ownership** — Team-owned apps (from overlay) triaged first
2. **Business impact** — Purchase/checkout/payment flow errors are always HIGH
3. **Frequency** — Higher count = higher priority
4. **Recency** — Newly appearing > long-standing
5. **Trend** — Increasing > stable > decreasing
6. **Blast radius** — Multiple endpoints affected > single
7. **Environment** — Production > UAT > Sandbox

---

## Bug Report Template

```markdown
## Bug Report: [Error Class] in [App Name]

**Severity:** [Critical/High/Medium/Low]
**Environment:** [Production/UAT/Sandbox]
**First Seen:** [date]  |  **Frequency:** [X/hour]  |  **Trend:** [increasing/decreasing/stable]

### Error Details
- **Error Class:** `ExceptionType`
- **Message:** `error message`
- **Affected Transactions:** list of endpoints
- **Stack Trace:** (key frames)

### Repository
- **Repo:** `org/repo-name`
- **Likely File(s):** (inferred from stack trace namespaces/class names)

### Investigation Guidance
- Look at: [specific files/classes from stack trace]
- Possibly related to: [deployment, config change, upstream service]
- Similar patterns: [if found in other services]

### Suggested Fix Priority
[Rationale based on frequency, trend, blast radius]
```

---

## Troubleshooting

### Auth Failures
- Verify CLI profile: `newrelic profile list`
- Ensure API key is a **Personal API Key** (starts with `NRAK-`), not a license key
- For NerdGraph curl, ensure `NEW_RELIC_API_KEY` env var is set

### Empty Results
- Check app name is correct: `newrelic entity search --name "<partial>"` to discover
- Include environment suffix: `appName = 'myapp [PD1]'` not just `'myapp'`
- Some apps have language suffixes: `accountsv2 [PD1] (.NET)`
- Check time range: default `SINCE 1 hour ago` may miss infrequent errors

### Environment Filtering
- `WHERE appName LIKE '%[PD]%'` matches `[PD]`, `[PD1]`, and `[PD2]`
- For a specific instance only: `WHERE appName LIKE '%[PD1]%' AND appName NOT LIKE '%[PD]%'`
- Reader names vary: some use `-rdr`, others use `-reader` suffix

### NerdGraph Query Errors
- Escape single quotes carefully in nested queries
- Max NRQL result set is typically 2000 rows

---

## Quick Reference

| Task | Approach |
|------|----------|
| Find an app | `newrelic entity search --name "<name>" --domain APM` |
| Health check | NRQL: Transaction error rate + throughput |
| Top errors (prod) | NRQL: TransactionError FACET error.class WHERE `%[PD]%` |
| Stack trace | NRQL: error.stack from TransactionError |
| Reader health | NRQL: Transaction WHERE appName LIKE `%reader%` or `%-rdr%` |
| JS errors | NRQL: JavaScriptError FACET errorMessage |
| Purchase health | NRQL: AjaxRequest WHERE requestUrl LIKE `%purchase%` FACET httpResponseCode |
| Marketing by category | NRQL: JavaScriptError FACET errorCategory |
| Login funnel | NRQL: PageAction WHERE actionName LIKE `integrated_login_%` |
| Checkout steps | NRQL: PageAction WHERE actionName = `view_step` FACET step |
| Page performance | NRQL: PageView FACET pageUrl |
| Ajax failures | NRQL: AjaxRequest WHERE httpResponseCode >= 400 |
| Deployment check | NRQL: NrAuditEvent WHERE description LIKE `%<APP>%` |
| Distributed trace | NRQL: Span WHERE error IS true |
| Alert violations | NerdGraph: NrAiIncident |
| Bug report | Synthesize from deep dive findings using template above |
