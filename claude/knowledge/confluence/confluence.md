---
name: confluence
description: Knowledge reference for the /confluence skill. Confluence Cloud REST API patterns at legalshield.atlassian.net, including auth, page CRUD, search, storage format, and the LegalShield postmortem workflow.
---

# Confluence REST API Reference

All operations target **`https://legalshield.atlassian.net/wiki`**. Pages use the v2 API; CQL search still lives on the v1 endpoint.

## Auth

The token is pre-encoded base64 of `email:apitoken` and exported as `$CONFLUENCE_AUTH_TOKEN` from `~/.zshrc` (sourced from 1Password entry `op://PPLSI/Confluence - Base64/credential`). Use it directly in the `Authorization: Basic` header — do **not** call `base64` or `curl -u` on it.

```bash
if [ -z "$CONFLUENCE_AUTH_TOKEN" ]; then
  echo "ERROR: \$CONFLUENCE_AUTH_TOKEN not set. Run 'source ~/.zshrc' (and 'op signin' if needed)."
  return 1
fi

# Sanity check
curl -sS -o /dev/null -w "%{http_code}\n" \
  -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  "https://legalshield.atlassian.net/wiki/api/v2/spaces?limit=1"
# Expect 200. 401 = token bad, 403 = no Confluence access.
```

Why not `curl -u "$EMAIL:$TOKEN"`? Because our token is already encoded; passing it through `-u` would double-encode and break auth. The org's other skills use `-u` because they read the raw email + API token separately — we store the encoded form.

## Base URLs

| Use | URL |
|-----|-----|
| v2 (preferred) | `https://legalshield.atlassian.net/wiki/api/v2` |
| v1 (CQL search, some legacy ops) | `https://legalshield.atlassian.net/wiki/rest/api` |
| Page UI | `https://legalshield.atlassian.net/wiki/spaces/<KEY>/pages/<ID>` |

## Known spaces

| Key | Name | Space ID | Notes |
|-----|------|----------|-------|
| `~61b7a02191c049006fa846ee` | Joe Valdez (personal) | `2712174601` | **Default target for `create` when no other space is specified.** |
| `CP` | PIE-T Internal Tools | `851706832` | Release-notes hub. Releases parent page: `5353013302`. |
| `NPI` | Nothin' but NetWork | `3015671816` | Projects parent: `3549233181`. Postmortems parent: `3777331207`. |
| `PT` | Platform Team | — | Postmortem Summary 2025 page: `4119625778`. |
| `LL` | LegalShield | — | Atlas Accounts/Login docs, rollback/testing strategy. |
| `ES` | Engineering Services | — | Notification statuses and adjacent runbooks. |
| `DevOps` | DevOps | — | AWS access, Rancher K8s, Ansible standards. |
| `IdentityFO` | Identity FO | — | Identity team workspace. |

For unknown spaces, discover with:
```bash
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  "https://legalshield.atlassian.net/wiki/api/v2/spaces?limit=100" \
  | jq -r '.results[] | "\(.id)\t\(.key)\t\(.name)"' | column -t -s $'\t'
```

## Page operations

### Get a page

```bash
PAGE_ID=4463984714
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  "https://legalshield.atlassian.net/wiki/api/v2/pages/$PAGE_ID?body-format=storage" | jq
```

`body-format` options: `storage` (HTML-ish; default for round-tripping), `atlas_doc_format` (ADF JSON), `view` (rendered HTML — read-only).

### Find a page by title (CQL)

The v2 API can filter by exact title within a space:
```bash
TITLE="Refunds runbook"
SPACE_ID=851706832
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  "https://legalshield.atlassian.net/wiki/api/v2/spaces/$SPACE_ID/pages?title=$(jq -sRr @uri <<<"$TITLE")&status=current&limit=5" \
  | jq -r '.results[] | "\(.id)\t\(.title)"'
```

For fuzzy or cross-space search, use CQL on v1:
```bash
Q='title ~ "Refunds" AND space.key = "CP" AND type = "page"'
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  --data-urlencode "cql=$Q" --data-urlencode "limit=20" \
  -G "https://legalshield.atlassian.net/wiki/rest/api/content/search" \
  | jq -r '.results[] | "\(.id)\t\(.title)\t\(._links.webui)"'
```

### List children of a page

```bash
PARENT_ID=5353013302
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  "https://legalshield.atlassian.net/wiki/api/v2/pages/$PARENT_ID/children?limit=100" \
  | jq -r '.results[] | "\(.id)\t\(.title)"'
```

### Create a page

Always write the JSON body to a tempfile. Inline `-d '...'` with storage-format HTML containing single quotes, table markup, or macros will silently corrupt under shell expansion.

```bash
SPACE_ID=851706832
PARENT_ID=5353013302
TITLE="Refunds runbook"

cat > /tmp/conf_create.json <<JSON
{
  "spaceId": "$SPACE_ID",
  "status": "current",
  "title": "$TITLE",
  "parentId": "$PARENT_ID",
  "body": {
    "representation": "storage",
    "value": "<p>Owner: payments team.</p><h2>When to use this</h2><p>...</p>"
  }
}
JSON

RESP=$(curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST "https://legalshield.atlassian.net/wiki/api/v2/pages" \
  -d @/tmp/conf_create.json)

NEW_ID=$(echo "$RESP" | jq -r '.id')
WEBUI=$(echo "$RESP" | jq -r '._links.webui')
echo "Created: https://legalshield.atlassian.net/wiki$WEBUI  (id=$NEW_ID)"
```

If the title already exists at the same level you get a 409. Either reuse the existing page (search first) or pick a new title.

### Update a page (version dance)

You must submit `current_version + 1` or the request fails with 409. Title is required even if unchanged.

```bash
PAGE_ID=4463984714

CUR=$(curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  "https://legalshield.atlassian.net/wiki/api/v2/pages/$PAGE_ID?body-format=storage")
CUR_VER=$(echo "$CUR" | jq -r '.version.number')
CUR_TITLE=$(echo "$CUR" | jq -r '.title')
NEW_VER=$((CUR_VER + 1))

cat > /tmp/conf_update.json <<JSON
{
  "id": "$PAGE_ID",
  "status": "current",
  "title": "$CUR_TITLE",
  "body": {
    "representation": "storage",
    "value": "<p>Updated body.</p>"
  },
  "version": { "number": $NEW_VER, "message": "Edited via /confluence skill" }
}
JSON

curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -X PUT "https://legalshield.atlassian.net/wiki/api/v2/pages/$PAGE_ID" \
  -d @/tmp/conf_update.json | jq -r '"v\(.version.number) saved: \(._links.webui)"'
```

**Append vs replace.** Updates are full-body replacements. To append, fetch current body, concatenate, then PUT. For surgical edits use `sed`/`awk` on the fetched storage XML (it round-trips fine for plain HTML; be careful with `<ac:...>` macros which Confluence may rewrite slightly).

### Delete a page

Soft-delete (moves to trash):
```bash
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  -X DELETE "https://legalshield.atlassian.net/wiki/api/v2/pages/$PAGE_ID" -w "%{http_code}\n"
```

### Labels

```bash
# Read labels
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  "https://legalshield.atlassian.net/wiki/api/v2/pages/$PAGE_ID/labels" | jq -r '.results[].name'

# Add a label (v1 endpoint — v2 has no public label-write yet)
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST "https://legalshield.atlassian.net/wiki/rest/api/content/$PAGE_ID/label" \
  -d '[{"prefix":"global","name":"payments"}]'
```

### Comments

Footer comments only via v2:
```bash
cat > /tmp/conf_comment.json <<JSON
{ "pageId": "$PAGE_ID", "body": { "representation": "storage", "value": "<p>LGTM.</p>" } }
JSON
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST "https://legalshield.atlassian.net/wiki/api/v2/footer-comments" \
  -d @/tmp/conf_comment.json
```

### Attachments

The v1 endpoint is still required for uploads.
```bash
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  -H "X-Atlassian-Token: nocheck" \
  -F "file=@./diagram.png" \
  -F "comment=architecture diagram" \
  "https://legalshield.atlassian.net/wiki/rest/api/content/$PAGE_ID/child/attachment"
```

## Storage format primer

Storage format is HTML-with-macros. Confluence will normalise whitespace and reorder some attributes, so don't assert byte-equality on round-trips.

### Basics

```html
<h2>Section heading</h2>
<p>Paragraph with <strong>bold</strong>, <em>italic</em>, and <code>inline code</code>.</p>
<ul><li><p>Bullet item</p></li></ul>
<ol><li><p>Numbered item</p></li></ol>
<a href="https://example.com">External link</a>
```

### Code block

```html
<ac:structured-macro ac:name="code">
  <ac:parameter ac:name="language">bash</ac:parameter>
  <ac:plain-text-body><![CDATA[
echo hello
  ]]></ac:plain-text-body>
</ac:structured-macro>
```

### Info / Warning / Note panels

```html
<ac:structured-macro ac:name="info"><ac:rich-text-body><p>FYI message.</p></ac:rich-text-body></ac:structured-macro>
<ac:structured-macro ac:name="warning"><ac:rich-text-body><p>Heads up.</p></ac:rich-text-body></ac:structured-macro>
<ac:structured-macro ac:name="note"><ac:rich-text-body><p>Side note.</p></ac:rich-text-body></ac:structured-macro>
```

### Jira issue link (auto-renders as a chip with status)

```html
<ac:structured-macro ac:name="jira" ac:schema-version="1">
  <ac:parameter ac:name="key">OPSUC-2407</ac:parameter>
  <ac:parameter ac:name="serverId">c57f7d2a-6d1b-374e-8fc2-117016b9f620</ac:parameter>
  <ac:parameter ac:name="server">System Jira</ac:parameter>
</ac:structured-macro>
```

The `serverId` above is the LegalShield instance — keep as-is.

### Status pill

```html
<ac:structured-macro ac:name="status" ac:schema-version="1">
  <ac:parameter ac:name="title">P1</ac:parameter>
  <ac:parameter ac:name="colour">Yellow</ac:parameter>
</ac:structured-macro>
```

Colours: `Red`, `Yellow`, `Green`, `Blue`, `Grey` (default if omitted).

### Internal page link

```html
<ac:link><ri:page ri:space-key="CP" ri:content-title="Refunds runbook" /></ac:link>
```

### Tables

```html
<table>
  <tbody>
    <tr><th><p>Col A</p></th><th><p>Col B</p></th></tr>
    <tr><td><p>Cell</p></td><td><p>Cell</p></td></tr>
  </tbody>
</table>
```

## Gotchas

- **Token is already base64.** Don't `base64` it again. Don't use `curl -u`.
- **409 on update** = stale `version.number`. Re-fetch and retry.
- **409 on create** = duplicate title at the same parent. Search first, reuse if intent matches.
- **403 on space** = your account isn't in the space's group. Ask the space admin.
- **Storage XML must be well-formed.** Self-close `<br/>`, escape `&` as `&amp;`. The API will accept malformed input then render garbage — there's no parse-error response.
- **ADF vs storage.** `representation: "atlas_doc_format"` exists, but storage round-trips more reliably from shell. Stick with storage unless a macro demands ADF (rare for our content).
- **CQL search results lag indexing.** Pages created in the last ~30s may not appear in `cql=title~...`. Fall back to the v2 spaces-by-title query (it reads from the page store directly).

## Common workflows

### Find a page by title and open it

```bash
TITLE="Payment Diagrams"
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  --data-urlencode "cql=title=\"$TITLE\" AND type=page" \
  -G "https://legalshield.atlassian.net/wiki/rest/api/content/search" \
  | jq -r '.results[] | "https://legalshield.atlassian.net/wiki\(._links.webui)"'
```

### Create a child page from a markdown file

The cleanest path is: convert markdown → minimal storage HTML (the subset above is enough for runbooks/tech specs), wrap as a JSON payload via `jq`, POST.

```bash
MD_FILE=runbook.md
TITLE="Refunds runbook"
PARENT_ID=5353013302
SPACE_ID=851706832

# Use jq -Rs to read the file and embed safely as a JSON string
jq -n \
  --arg sid "$SPACE_ID" --arg pid "$PARENT_ID" --arg t "$TITLE" \
  --rawfile body "$MD_FILE" \
  '{spaceId:$sid, parentId:$pid, status:"current", title:$t, body:{representation:"storage", value:$body}}' \
  > /tmp/conf_create.json

curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST "https://legalshield.atlassian.net/wiki/api/v2/pages" \
  -d @/tmp/conf_create.json | jq '{id, webui:._links.webui}'
```

Caveat: if `runbook.md` contains raw markdown headings/bullets, Confluence will render them as literal text. Either run it through a markdown→HTML step (e.g. `pandoc -f gfm -t html`) before stuffing into `value`, or author directly in the storage subset above.

### Get the editor URL for a page (handy when handing off)

```bash
echo "https://legalshield.atlassian.net/wiki/spaces/<KEY>/pages/edit-v2/$PAGE_ID"
```

## Postmortem workflow

LegalShield postmortems live under `NPI > Postmortems` (parent `3777331207`) and get summarized on the `Postmortem Summary 2025` page in `PT` (`4119625778`).

### Inputs to gather

- **Title** — short incident summary (`"Checkout 500s during refund retry storm"`)
- **Owner** — engineer authoring the postmortem
- **Jira incident key** — `OPSUC-...` or `SC-...`
- **Priority** — `P0`, `P1`, or `P2+`
- **Affected services** — list
- **Executive summary** — 1–2 sentences
- **Date** — incident date, used on the summary page

### Step 1: Create the postmortem page

Build the storage body with the postmortem template — see [Postmortem template](#postmortem-storage-template) below — substituting only the priority macro you want to show (delete the other two).

```bash
TITLE="Checkout 500s during refund retry storm"
PARENT_ID=3777331207
SPACE_ID=3015671816

# After assembling /tmp/pm_body.html with the template:
jq -n --arg sid "$SPACE_ID" --arg pid "$PARENT_ID" --arg t "$TITLE" --rawfile body /tmp/pm_body.html \
  '{spaceId:$sid, parentId:$pid, status:"current", title:$t, body:{representation:"storage", value:$body}}' \
  > /tmp/pm_create.json

curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST "https://legalshield.atlassian.net/wiki/api/v2/pages" \
  -d @/tmp/pm_create.json | jq '{id, webui:._links.webui}'
```

### Step 2: Add a row to Postmortem Summary 2025

```bash
SUMMARY_ID=4119625778
CUR=$(curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  "https://legalshield.atlassian.net/wiki/api/v2/pages/$SUMMARY_ID?body-format=storage")
CUR_VER=$(echo "$CUR" | jq -r '.version.number')
CUR_TITLE=$(echo "$CUR" | jq -r '.title')
CUR_BODY=$(echo "$CUR" | jq -r '.body.storage.value')

NEW_ROW='<tr><td><p>'"$TITLE"'</p></td><td><p>May 11, 2026</p></td><td><p>BRIEF IMPACT</p></td><td><p><ac:link ac:card-appearance="inline"><ri:page ri:space-key="NPI" ri:content-title="'"$TITLE"'" /><ac:link-body>'"$TITLE"'</ac:link-body></ac:link></p></td></tr>'

# Insert NEW_ROW right after the first <tr>...</tr> (the header). Quick & dirty:
NEW_BODY=$(echo "$CUR_BODY" | python3 -c "
import sys, re
b = sys.stdin.read()
row = '''$NEW_ROW'''
# Insert after the first </tr> (header row close)
print(b.replace('</tr>', '</tr>' + row, 1))
")

jq -n --arg id "$SUMMARY_ID" --arg t "$CUR_TITLE" --argjson v $((CUR_VER+1)) --arg body "$NEW_BODY" \
  '{id:$id, status:"current", title:$t, body:{representation:"storage", value:$body}, version:{number:$v, message:"Add postmortem row"}}' \
  > /tmp/pm_summary_update.json

curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -X PUT "https://legalshield.atlassian.net/wiki/api/v2/pages/$SUMMARY_ID" \
  -d @/tmp/pm_summary_update.json | jq -r '"v\(.version.number) saved"'
```

### Postmortem storage template

Substitute the placeholders, then delete two of the three priority macros to keep only the one that applies.

```html
<h2>Postmortem summary</h2>
<table>
  <tbody>
    <tr><th><p><strong>Owner</strong></p></th><th><p>OWNER_NAME</p></th></tr>
    <tr><td><p><strong>Incident</strong></p></td><td><p><ac:structured-macro ac:name="jira" ac:schema-version="1"><ac:parameter ac:name="key">JIRA_KEY</ac:parameter><ac:parameter ac:name="serverId">c57f7d2a-6d1b-374e-8fc2-117016b9f620</ac:parameter><ac:parameter ac:name="server">System Jira</ac:parameter></ac:structured-macro></p></td></tr>
    <tr><td><p><strong>Priority</strong></p></td><td><p>
      <ac:structured-macro ac:name="status" ac:schema-version="1"><ac:parameter ac:name="title">P0</ac:parameter><ac:parameter ac:name="colour">Red</ac:parameter></ac:structured-macro>
      <ac:structured-macro ac:name="status" ac:schema-version="1"><ac:parameter ac:name="title">P1</ac:parameter><ac:parameter ac:name="colour">Yellow</ac:parameter></ac:structured-macro>
      <ac:structured-macro ac:name="status" ac:schema-version="1"><ac:parameter ac:name="title">P2+</ac:parameter></ac:structured-macro>
    </p></td></tr>
    <tr><td><p><strong>Affected services</strong></p></td><td><ul><li><p>SERVICE_NAME</p></li></ul></td></tr>
  </tbody>
</table>
<ac:structured-macro ac:name="note"><ac:rich-text-body><h2>Executive summary</h2><p>EXECUTIVE_SUMMARY</p></ac:rich-text-body></ac:structured-macro>
<h2>Postmortem report</h2>
<table>
  <tbody>
    <tr><th><p><strong>Instructions</strong></p></th><th><p><strong>Report</strong></p></th></tr>
    <tr><td><h3>Leadup</h3><p>Sequence of events that led to the incident.</p></td><td><ul><li><p></p></li></ul></td></tr>
    <tr><td><h3>Fault</h3><p>How the change failed.</p></td><td><ul><li><p></p></li></ul></td></tr>
    <tr><td><h3>Impact</h3><p>Internal and external user impact.</p></td><td><ul><li><p></p></li></ul></td></tr>
    <tr><td><h3>Detection</h3><p>When and how detected.</p></td><td><p></p></td></tr>
    <tr><td><h3>Response</h3><p>Who responded and what they did.</p></td><td><p></p></td></tr>
    <tr><td><h3>Recovery</h3><p>How impact was mitigated; resolution time.</p></td><td><p></p></td></tr>
    <tr><td><h3>Timeline (UTC)</h3><p>Minute-by-minute.</p></td><td><ul><li><p></p></li></ul></td></tr>
    <tr><td><h3>Five whys</h3><p>Walk down to root cause.</p></td><td><ul><li><p></p></li></ul></td></tr>
    <tr><td><h3>Blameless root cause</h3><p>Final cause without blame.</p></td><td><p></p></td></tr>
    <tr><td><h3>Lessons learned</h3></td><td><p></p></td></tr>
    <tr><td><h3>Follow-up tasks</h3><p>Jira keys for preventive work.</p></td><td><ul><li><p></p></li></ul></td></tr>
  </tbody>
</table>
```

## Response checklist

When the skill finishes any mutating operation, surface:

1. The page **ID**.
2. A clickable **URL** (`https://legalshield.atlassian.net/wiki<webui>`).
3. The **version number** after the change (so subsequent updates start from the right value).
4. Any **labels** added or removed.
