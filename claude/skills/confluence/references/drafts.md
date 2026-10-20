# Drafts: listing, fetching, and deleting

## List drafts in a space (v1 only)

The v2 space-pages endpoint does not return drafts. Use v1:

```bash
SPACE_KEY="~61b7a02191c049006fa846ee"  # swap for target space key
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  "https://legalshield.atlassian.net/wiki/rest/api/content?spaceKey=$SPACE_KEY&status=draft&type=page&limit=50&expand=version,history,space"
```

Filter to a specific title by appending `&title=<url-encoded-title>`. The filter is exact-match.

```bash
TITLE_ENC=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$TITLE")
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  "https://legalshield.atlassian.net/wiki/rest/api/content?spaceKey=$SPACE_KEY&status=draft&type=page&title=$TITLE_ENC&limit=50"
```

## Fetch a single draft by ID (v2)

`GET /api/v2/pages/:id` returns 404 for drafts unless you pass `?status=draft`:

```bash
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  "https://legalshield.atlassian.net/wiki/api/v2/pages/$PAGE_ID?status=draft"
```

## Delete a draft (permanent)

Deleting a draft is permanent. Drafts have never been published, so they bypass the trash entirely. There is no restore.

Before deleting, confirm the ID, title, and `status=draft` with a GET (see section above). Never delete the page the caller wants to keep.

The v1 endpoint is the verified path:

```bash
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  -X DELETE "https://legalshield.atlassian.net/wiki/rest/api/content/$PAGE_ID?status=draft" \
  -w "%{http_code}\n"
# 204 = deleted permanently; re-fetching the ID returns 404
```

## Delete a current (published) page (soft-delete to trash)

For published pages, the v2 endpoint moves the page to trash:

```bash
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  -X DELETE "https://legalshield.atlassian.net/wiki/api/v2/pages/$PAGE_ID" -w "%{http_code}\n"
# 204 = moved to trash
```

To purge from trash permanently (cannot be undone):

```bash
curl -sS -H "Authorization: Basic $CONFLUENCE_AUTH_TOKEN" \
  -X DELETE "https://legalshield.atlassian.net/wiki/api/v2/pages/$PAGE_ID?purge=true" -w "%{http_code}\n"
```
