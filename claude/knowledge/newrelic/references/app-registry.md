# App Registry

NR app name to GitHub repo mapping for my teams. Only production (`[PD1]`) instances listed — other environments follow the same base name with `[SB]`, `[UT]`, `[PD]`, `[PD2]` suffixes.

## OpSuccess Team (`nr.team:opsuccess`)

### High Priority — Payments & Revenue

| NR App Name | Repository | Description |
|---|---|---|
| `payment-methods-svc` | `atlas-payment-methods-service` | Payment method CRUD |
| `paymentasaurus` | `paymentasaurus` | Payment processing engine |
| `payments-web` | `atlas-payments-web` | Payments UI |
| `atlas-invoices-svc` | `atlas-invoices-service` | Invoicing service |
| `atlas-invoices-web` | `atlas-invoices-web` | Invoices UI |
| `atlas-invoices-rdr` | `atlas-invoices-reader` | Invoices journal reader |
| `atlas-payment-method-rdr` | `atlas-payment-methods-reader` | Payment methods journal reader |
| `atlas-provision-svc` | `atlas-provision-service` | Provisioning service |
| `atlas-provision-rdr` | `atlas-provision-reader` | Provisioning journal reader |
| `atlas-transactions-svc` | `atlas-transactions-service` | Transactions service |
| `atlas-transactions-rdr` | ? | Transactions journal reader |
| `atlas-taxcalculation-svc` | `atlas-taxcalculation-service` | Tax calculation |
| `atlas-taxcalculation-rdr` | `atlas-taxcalculation-reader` | Tax calculation journal reader |

### Platform Services

| NR App Name | Repository | Description |
|---|---|---|
| `applications-svc` | `atlas-applications-service` | Applications service |
| `atlas-addresses-svc` | `atlas-addresses-service` | Address management |
| `aggregator-svc` | `atlas-aggregator-service` | Data aggregation |
| `atlas-queries-svc` | `atlas-queries-service` | Query service |
| `atlas-reporting-service` | `atlas-reporting-service` | Reporting |
| `atlas-share-svc` | `atlas-share-service` | Share service |
| `atlas-iseries-svc` | `atlas-classic-iseries-service` | iSeries integration |
| `atls-clasic-auto-cmts-svc` | `atlas-classic-auto-comments-service` | Auto comments |
| `alerts-service` | `atlas-alerts-service` | Alerts |
| `alerts-rdr` | `atlas-alerts-journal-reader-service` | Alerts journal reader |

### Readers & Migration

| NR App Name | Repository | Description |
|---|---|---|
| `atlas-associates-reader` | `atlas-associates-reader` | Associates reader |
| `atlas-benefits-rdr` | `atlas-products-benefits-reader` | Benefits reader |
| `atlas-cohorts-reader` | `atlas-cohorts-reader` | Cohorts reader |
| `atlas-groups-rdr` | `atlas-groups-reader` | Groups reader |
| `atlas-merges-rdr` | `atlas-merges-reader` | Merges reader |
| `atlas-notifications-rdr` | `atlas-notifications-reader` | Notifications reader |
| `atlas-products-rdr` | `atlas-products-products-reader` | Products reader |
| `atlas-profiles-rdr` | `atlas-profiles-reader` | Profiles reader |
| `backend-entitlements-rdr` | `atlas-entitlements-reader` | Entitlements reader |
| `migr-payment-methods-svc` | `atlas-migration-payment-methods-service` | Payment methods migration |
| `migr-payment-methods-rdr` | `atlas-migration-payment-methods-reader` | Payment methods migration reader |
| `atlas-migration-adm-svc` | `atlas-migration-group-admins-service` | Group admins migration |
| `atlas-migration-adm-rdr` | `atlas-migration-group-admins-reader` | Group admins migration reader |
| `atls-migrt-gps-srvc-rpts` | `atlas-migration-groups-servicing-reports` | Groups servicing reports migration |
| `atls-migr-gps-srv-rpt-rd` | `atlas-migration-groups-servicing-reports-reader` | Groups servicing reports migration reader |

## Internal Tools Team (`nr.team:tools`)

| NR App Name | Repository | Description |
|---|---|---|
| `member-search` | `core-apps-member-search` | Member search — **highest priority** |
| `internaltools-web` | `atlas-internal-tools-web` | Internal tools portal |
| `internal-resolutions-web` | `internal-resolutions-web` | Resolutions UI |
| `internal-resolutions-svc` | `internal-resolutions-service` | Resolutions service |
| `internal-resolutions-rdr` | `internal-resolutions-journal-reader-service` | Resolutions journal reader |
| `internal-events-web` | `internal-events-web` | Events UI |
| `internal-history-web` | `internal-history-web` | History UI (Node.js) |
| `internal-intakes-web` | `internal-intakes-web` | Intakes UI |
| `internal-notes-svc` | `internal-notes-service` | Notes service |
| `internal-offers-web` | `internal-offers-web` | Offers UI |
| `internal-profile-web` | `internal-profile-web` | Profile UI |

## Cross-Team Revenue Dependencies

Apps outside my teams that affect shared purchase/payment paths — escalate errors here:

| NR App Name | Team | Description |
|---|---|---|
| `purchases-service` | ? | Order processing |
| `subscriptions-service` | ? | Subscription management |
| `finalcheckout` | growth | Checkout V3 |
| `checkout-us` | growth | US checkout (legacy) |

## Default NRQL Filters

```sql
-- OpSuccess high-priority (payments & revenue)
appName IN ('payment-methods-svc [PD1]', 'paymentasaurus [PD1]', 'payments-web [PD1]', 'atlas-invoices-svc [PD1]', 'atlas-provision-svc [PD1]', 'atlas-transactions-svc [PD1]')

-- OpSuccess all prod (use LIKE for broad scan)
appName LIKE '%[PD]%' AND tags.nr.team = 'opsuccess'
-- OR use: newrelic entity search --domain APM --type APPLICATION --tag "nr.team:opsuccess"

-- Internal Tools high-priority
appName IN ('member-search [PD1]', 'internaltools-web [PD1]', 'internal-resolutions-web [PD1]', 'internal-resolutions-svc [PD1]')

-- Internal Tools all prod
appName LIKE '%[PD]%' AND tags.nr.team = 'tools'

-- All my teams combined (high-priority only)
appName IN ('payment-methods-svc [PD1]', 'paymentasaurus [PD1]', 'payments-web [PD1]', 'atlas-invoices-svc [PD1]', 'member-search [PD1]', 'internaltools-web [PD1]')
```

## Quick Health Checks

```bash
# OpSuccess payments health
newrelic nrql query --query "SELECT percentage(count(*), WHERE error IS true) AS 'Error Rate', rate(count(*), 1 minute) AS 'RPM', average(duration) AS 'Avg Duration', percentile(duration, 95) AS 'P95' FROM Transaction WHERE appName IN ('payment-methods-svc [PD1]', 'paymentasaurus [PD1]', 'payments-web [PD1]', 'atlas-invoices-svc [PD1]', 'atlas-provision-svc [PD1]', 'atlas-transactions-svc [PD1]') SINCE 1 hour ago FACET appName"

# Internal Tools health
newrelic nrql query --query "SELECT percentage(count(*), WHERE error IS true) AS 'Error Rate', rate(count(*), 1 minute) AS 'RPM', average(duration) AS 'Avg Duration', percentile(duration, 95) AS 'P95' FROM Transaction WHERE appName IN ('member-search [PD1]', 'internaltools-web [PD1]', 'internal-resolutions-web [PD1]', 'internal-resolutions-svc [PD1]') SINCE 1 hour ago FACET appName"

# OpSuccess errors (last 24h)
newrelic nrql query --query "SELECT count(*) AS 'Count', latest(timestamp) AS 'Last Seen' FROM TransactionError WHERE appName IN ('payment-methods-svc [PD1]', 'paymentasaurus [PD1]', 'payments-web [PD1]', 'atlas-invoices-svc [PD1]', 'atlas-provision-svc [PD1]', 'atlas-transactions-svc [PD1]') SINCE 24 hours ago FACET appName, error.class, error.message LIMIT 20"

# Internal Tools errors (last 24h)
newrelic nrql query --query "SELECT count(*) AS 'Count', latest(timestamp) AS 'Last Seen' FROM TransactionError WHERE appName IN ('member-search [PD1]', 'internaltools-web [PD1]', 'internal-resolutions-web [PD1]', 'internal-resolutions-svc [PD1]') SINCE 24 hours ago FACET appName, error.class, error.message LIMIT 20"
```

## Discovery

When you encounter an app not in this registry, discover it:

```bash
# By name
newrelic entity search --name "<partial-name>" --domain APM --type APPLICATION

# By team tag
newrelic entity search --domain APM --type APPLICATION --tag "nr.team:<team>"
```

The `gh_repo` tag on the entity maps to the GitHub repository name under the LegalShield org.
