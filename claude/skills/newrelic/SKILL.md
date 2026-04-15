---
name: newrelic
description: Query New Relic for service health, error triage, and bug investigation across payment services and internal tooling. Read-only diagnostic skill — never makes deployments, rollbacks, or config changes.
argument-hint: "describe what to investigate"
model: sonnet
---

# New Relic Debugging & Observability

Read the knowledge files at `~/.claude/knowledge/newrelic/newrelic.md` and `~/.claude/knowledge/newrelic/references/app-registry.md` before proceeding.

**This skill is read-only/diagnostic.** It queries observability data but never makes deployments, rollbacks, or configuration changes.

Arguments: $ARGUMENTS

## My Teams

I work across two teams. When no specific app is mentioned, default to checking these teams' apps.

### OpSuccess (`nr.team:opsuccess`)
Payments, invoices, subscriptions, orders, provisioning, and the core atlas platform services. High-priority apps: `payment-methods-svc`, `paymentasaurus`, `payments-web`, `atlas-invoices-svc`, `atlas-provision-svc`, `purchases-service`, `subscriptions-service`.

### Internal Tools (`nr.team:tools`)
Internal-facing apps for member management and operations. High-priority apps: `member-search`, `internaltools-web`, `internal-resolutions-web`, `internal-resolutions-svc`.

### Dynamic Discovery

With ~40+ opsuccess apps and ~10+ tools apps, use tag-based discovery rather than hardcoded lists:

```bash
# Discover all prod apps for a team
newrelic entity search --domain APM --type APPLICATION --tag "nr.team:opsuccess"
newrelic entity search --domain APM --type APPLICATION --tag "nr.team:tools"
```

The full app-to-repo mapping is in the app registry reference file.

## Workflows

Select the appropriate workflow based on the user's request. Each workflow's detailed queries are in the knowledge file.

### 1. Service Health Check
Quick health snapshot for any application. Run error rate, throughput, and response time queries. Interpret thresholds: error rate >5% needs immediate investigation, P95 >2s for services or >5s for web apps indicates performance issues.

### 2. Error Triage & Prioritization
Produce a prioritized bug list. Start with high-priority apps from my teams, then expand. Apply prioritization criteria: team ownership > business impact > frequency > recency > trend > blast radius > environment.

### 3. Error Deep Dive
Investigate a specific error in detail. Get transaction context, stack traces, error timeline (when did it start?), and deployment correlation.

### 4. Journal Reader Diagnostics
Reader-specific health patterns for journal reader services. Check processing throughput for drops, reader errors, and slow processing. Look for `-reader` and `-rdr` suffix naming variants.

### 5. Frontend Error Analysis
For web applications: JavaScript errors, page performance, Ajax failures, and page load breakdowns.

### 6. Marketing Web Deep Dive
For marketing sites with custom monitoring layers. Query by error category, severity, service category. Analyze login funnels and checkout step tracking via PageAction events.

### 7. Cross-Service Error Tracing
Follow errors across service boundaries using distributed traces. Find trace IDs from erroring transactions, then look up those traces in downstream services. Map service names to repos using the app registry.

### 8. Checkout & Partner Purchase Monitoring
Monitor purchase health and partner checkout flows. Check purchase success rates via Browser AjaxRequest events. Partner context is visible in tracking pixel URLs, not pageUrl (NR Browser strips query params).

### 9. Bug Report Generation
After investigation, synthesize findings into a structured bug report using the template in the knowledge file. Save reports to `docs/projects/<project>/planning/` for ticket creation.

## Process

1. **Identify target** — Determine which app(s) to investigate from arguments or default to my teams' high-priority apps
2. **Verify app name** — Use `newrelic entity search` to confirm the correct NR app name with environment suffix
3. **Run appropriate workflow** — Execute queries from the knowledge file, substituting app names
4. **Interpret results** — Apply thresholds and prioritization criteria from the knowledge file
5. **Report findings** — Summarize with severity, frequency, trend, and affected transactions
6. **Generate artifacts** — Create bug reports or recommend next steps as appropriate

## Integration

- Use `/jira` to create bug tickets from generated reports
- Use `/debug` to investigate code paths after identifying the repo from stack traces
- Use `newrelic entity search --tag "nr.team:<team>"` to discover apps dynamically
