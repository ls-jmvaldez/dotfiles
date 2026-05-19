---
name: release-notes-onboard
description: Onboard a LegalShield repo to the Confluence release-notes automation. Creates the per-repo Confluence parent page, sets repo secrets/vars, copies the scripts/release-notes scaffold and the GitHub Actions workflow from the reference repo, adapts repo-specific values, and opens a PR.
---

Wires up an internal LegalShield repo so that every `deploy/prod/*` GitHub Release auto-publishes a stakeholder-friendly Confluence page in the **PIE-T Internal Tools** space under the **Releases** hub.

This skill is scoped to the `LegalShield` org and assumes the target repo:
- Already deploys to production via GitHub Actions
- Tags prod releases as `deploy/prod/YYYY-MM-DD-<short-sha>`
- Publishes a GitHub Release on each prod deploy (or you're about to add that)

The reference repo is `LegalShield/internal-membership-web`. Read source files from there directly; do not paste templates into prompts.

## Inputs the skill collects

The user may pre-supply any of these. Prompt for what's missing.

- **Audience line**: Who reads these notes? Default `Customer Care, Internal Tools`. Examples: `Care leads, Product`, `Sales Ops`.
- **Health endpoint URL**: e.g. `https://<service>.legalshieldinternal.com/v1/health`. Discover from existing workflow files in the target repo if possible (search for `/v1/health` or `legalshieldinternal.com`).
- **Atlassian token source**: defaults to `op://PPLSI/Jira - Base64/credential` (a base64-encoded `email:atlassian-token`). The user may have a Confluence-specific entry at `op://PPLSI/Confluence - Base64/credential` — try that first, fall back to Jira-Base64.

The **target repo** is auto-detected from the current directory (`gh repo view --json nameWithOwner`).

## Constants (do not prompt for these)

- Confluence space key: `CP`
- Confluence space ID: `851706832`
- "Releases" hub page ID: `5353013302`
- Reference repo: `LegalShield/internal-membership-web`

## Step 0: Detect target repo

```bash
TARGET_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "$TARGET_REPO"
```

Refuse if the org is not `LegalShield`. Refuse if the repo is the reference itself.

Detect a short repo name (without org) for use in the Confluence child-page title:
```bash
REPO_SHORT="${TARGET_REPO#LegalShield/}"
```

## Step 1: Prerequisite checks

Run all four. Halt with a clear error if any fail.

```bash
# 1. gh authenticated
gh auth status >/dev/null 2>&1 || { echo "✗ run 'gh auth login'"; exit 1; }

# 2. 1Password CLI signed in (op read works)
op read 'op://PPLSI/Jira - Base64/credential' >/dev/null 2>&1 \
  || { echo "✗ run 'op signin' in this terminal"; exit 1; }

# 3. Repo has at least one deploy/prod/* tag (else there's nothing to backfill against)
git fetch --tags origin 2>/dev/null
LATEST_TAG=$(git tag --list 'deploy/prod/*' --sort=-creatordate | head -1)
[ -n "$LATEST_TAG" ] || echo "⚠ no deploy/prod/* tags found yet; the workflow will activate on the first one"

# 4. Repo doesn't already have the workflow installed
test ! -f .github/workflows/confluence-release-notes.yml \
  || { echo "✗ .github/workflows/confluence-release-notes.yml already exists"; exit 1; }
```

## Step 2: Resolve Atlassian token

```bash
TOKEN="$(op read 'op://PPLSI/Confluence - Base64/credential' 2>/dev/null)"
[ -z "$TOKEN" ] && TOKEN="$(op read 'op://PPLSI/Jira - Base64/credential' 2>/dev/null)"
[ -z "$TOKEN" ] && { echo "✗ no Atlassian token in 1Password"; exit 1; }
```

Sanity-check Confluence access:
```bash
HTTP=$(curl -sS -o /dev/null -w "%{http_code}" \
  -H "Authorization: Basic $TOKEN" \
  "https://legalshield.atlassian.net/wiki/api/v2/spaces?keys=CP")
[ "$HTTP" = "200" ] || { echo "✗ Confluence auth failed ($HTTP)"; exit 1; }
```

## Step 3: Create the per-repo Confluence child page

Idempotent. If a page with the same title already exists under the Releases hub, reuse it.

Title format: `<repo-short>` (e.g. `internal-membership-web`, `atlas-accounts-web`). Plain repo name, no decoration — releases for that repo will nest as grandchildren.

```bash
TITLE="$REPO_SHORT"
EXISTING=$(curl -sS -H "Authorization: Basic $TOKEN" \
  "https://legalshield.atlassian.net/wiki/api/v2/spaces/851706832/pages?title=$(printf '%s' "$TITLE" | jq -sRr @uri)&status=current&limit=1")
PARENT_ID=$(echo "$EXISTING" | jq -r '.results[0].id // empty')

if [ -z "$PARENT_ID" ]; then
  BODY_TEXT="<p>Release notes for the <code>$REPO_SHORT</code> app. Each child page corresponds to one production release.</p><p><strong>Repo:</strong> <a href=\"https://github.com/$TARGET_REPO\">github.com/$TARGET_REPO</a></p>"
  PAYLOAD=$(jq -n --arg sid "851706832" --arg pid "5353013302" --arg t "$TITLE" --arg b "$BODY_TEXT" \
    '{spaceId: $sid, parentId: $pid, status: "current", title: $t, body: {representation: "storage", value: $b}}')
  PARENT_ID=$(curl -sS -H "Authorization: Basic $TOKEN" \
    -X POST 'https://legalshield.atlassian.net/wiki/api/v2/pages' \
    -H 'Content-Type: application/json' -d "$PAYLOAD" | jq -r '.id')
fi
echo "Parent page ID: $PARENT_ID"
```

## Step 4: Set GH secrets and variables on the target repo

```bash
gh secret set ATLASSIAN_BASIC_AUTH -R "$TARGET_REPO" -b "$TOKEN"
gh variable set CONFLUENCE_SPACE_ID -R "$TARGET_REPO" -b "851706832"
gh variable set CONFLUENCE_PARENT_ID -R "$TARGET_REPO" -b "$PARENT_ID"
```

## Step 5: Pull scripts/release-notes from the reference repo

Use `gh api` to fetch each file's content. Do NOT clone the reference repo.

Files to copy (exact paths, identical content):
- `scripts/release-notes/generate.mjs`
- `scripts/release-notes/README.md`
- `scripts/release-notes/lib/confluence.mjs`
- `scripts/release-notes/lib/gh.mjs`
- `scripts/release-notes/lib/git.mjs`
- `scripts/release-notes/lib/jira.mjs`
- `scripts/release-notes/lib/parsePr.mjs`
- `scripts/release-notes/lib/polish.mjs`
- `scripts/release-notes/lib/render.mjs`
- `scripts/release-notes/lib/template.mjs`

Fetch pattern:
```bash
mkdir -p scripts/release-notes/lib
for path in scripts/release-notes/generate.mjs scripts/release-notes/README.md \
            scripts/release-notes/lib/confluence.mjs scripts/release-notes/lib/gh.mjs \
            scripts/release-notes/lib/git.mjs scripts/release-notes/lib/jira.mjs \
            scripts/release-notes/lib/parsePr.mjs scripts/release-notes/lib/polish.mjs \
            scripts/release-notes/lib/render.mjs scripts/release-notes/lib/template.mjs; do
  gh api "repos/LegalShield/internal-membership-web/contents/$path" \
    --jq '.content' | base64 -d > "$path"
done
```

## Step 6: Adapt repo-specific values

Five constants are hardcoded to `internal-membership-web` in the reference. Edit them in the copied files.

**`scripts/release-notes/lib/gh.mjs`** — line near top:
```js
const REPO = "LegalShield/internal-membership-web";
```
Replace with `const REPO = "<TARGET_REPO>";`.

**`scripts/release-notes/generate.mjs`** — line near top:
```js
const REPO = "LegalShield/internal-membership-web";
```
Replace with `const REPO = "<TARGET_REPO>";`.

**`scripts/release-notes/lib/template.mjs`** — three constants:
```js
const REPO_URL = "https://github.com/LegalShield/internal-membership-web";
const HEALTH_URL = "https://membership-details.legalshieldinternal.com/v1/health";
const DEFAULT_AUDIENCE = "Customer Care, Internal Tools";
```
Replace with the user's inputs (target repo URL, health URL, audience).

**`scripts/release-notes/lib/template.mjs`** — `releasePageTitle` function:
```js
export const releasePageTitle = ({ releaseDate, releaseShortSha }) =>
  `internal-membership-web ${releaseDate} (${releaseShortSha})`;
```
Replace `internal-membership-web` with `<REPO_SHORT>`.

**`scripts/release-notes/README.md`** — adapt the local-dev usage example to use the new repo name. Optional but worth doing.

## Step 7: Copy the workflow file

```bash
mkdir -p .github/workflows
gh api repos/LegalShield/internal-membership-web/contents/.github/workflows/confluence-release-notes.yml \
  --jq '.content' | base64 -d > .github/workflows/confluence-release-notes.yml
```

The workflow as-shipped reads space/parent IDs from repo variables, so no edits are needed.

## Step 8: Add the PR template (only if missing)

```bash
if [ ! -f .github/pull_request_template.md ]; then
  gh api repos/LegalShield/internal-membership-web/contents/.github/pull_request_template.md \
    --jq '.content' | base64 -d > .github/pull_request_template.md
fi
```

If the repo already has a PR template, don't clobber it. Mention to the user that they may want to align it with the Contributor persona format used by the reference for best LLM-polish output.

## Step 9: Verify and open a PR

Run the target repo's verification suite (typically `pnpm -w format:check && pnpm -r typecheck && pnpm -r lint` for TypeScript repos, `dotnet build` for .NET, etc.). Adapt to the target's stack.

Create a feature branch, commit, push, open a PR. Use the same conventional-commit format as the reference:
```
feat(ci): publish confluence release notes on prod deploy
```

PR body should follow the Contributor persona (lead with why, manual test steps, links section).

## Step 10: Optional — backfill the existing latest release

If `LATEST_TAG` was set in step 1, offer to dispatch the workflow with `--backfill` against that tag once the PR merges. Do not run `--backfill` for second and subsequent prod releases — only the first one for a repo.

```bash
gh workflow run "Publish Confluence release notes" -R "$TARGET_REPO" \
  -f tag="$LATEST_TAG" -f backfill=true
```

## Failure modes

- **Atlassian 403 on space `CP`**: user's account lacks Confluence access. Tell them to ask their admin for `Confluence User` group membership or for the org's `releases@pplsi.com` service account.
- **Title collision creating per-repo parent**: in step 3, if `$REPO_SHORT` already exists somewhere in space CP, the search returns it and we reuse it. If the existing page is under a different parent, surface this to the user before proceeding.
- **No `models: read` permission in CI**: workflow will run but polish will be silently skipped. Verify the workflow file has `permissions: { contents: read, models: read }`.

## Confirmation checklist before declaring done

- [ ] Confluence parent page visible at `https://legalshield.atlassian.net/wiki/spaces/CP/pages/<PARENT_ID>`
- [ ] Repo secret `ATLASSIAN_BASIC_AUTH` present (`gh secret list -R "$TARGET_REPO"`)
- [ ] Repo variables `CONFLUENCE_SPACE_ID`, `CONFLUENCE_PARENT_ID` present (`gh variable list -R "$TARGET_REPO"`)
- [ ] PR open against `main`
- [ ] CI passing on the PR
