---
name: jira
description: Creates and manages Jira issues via REST API. Use when creating stories, subtasks, epics, searching issues, or bulk ticket creation.
---

# Jira REST API Skill

Manage Jira issues using `curl` against the Jira REST API v3.

## Writing Style

When composing issue descriptions (stories, subtasks, epics, comments), follow `~/.claude/knowledge/writer.md` using **The Engineer** persona. Key rules:

- **No em dashes.** Use commas, parentheses, colons, or split into two sentences.
- **No AI tells:** "It's worth noting," "this powerful feature," "let's explore/delve into," "at its core."
- **No corporate speak:** "Leverage," "utilize," "best-in-class," "seamless." Just say the thing.
- **Lead with the point.** State what's wrong or what needs to change, then support it.
- **Be concrete.** Specific file paths, function names, error behaviors. Not "improve error handling."
- **Short paragraphs.** 3-4 sentences max.
- **No emojis** unless the user requests them.

For the full style guide, read `~/.claude/knowledge/writer.md`.

## Ticket Authoring Guidelines

### Scope each story by file ownership

Each story should own specific files exclusively. No two stories should touch the same file. This enables parallel development with zero merge conflicts and makes ownership unambiguous.

One story = one PR. If a story requires more than one PR to review comfortably, it's too big.

### Don't spoon-feed implementation

State the problem and what needs to change at a high level. Do not include:

- Numbered implementation steps ("1. Open the file, 2. Find the function, 3. Replace...")
- Line number ranges ("lines 80-233 of ContactEditDialogs.tsx")
- Code blocks showing what to write
- Exact file paths for new files the engineer will create

The engineer decides how to implement it. The ticket defines what and why.

### Bake testing into each subtask

Each subtask's acceptance criteria should include testing for that subtask's work. Do not create a standalone "write tests" subtask at the end.
Testing disconnected from the work it validates is easy to skip and hard to scope.

### Reference tickets by Jira key

Use the actual Jira key (e.g., `COREAPP1-3279`), not informal names like "Story 0" or "the shared foundations story." Jira auto-links keys in descriptions.
Informal names don't, and they break when someone reads the ticket out of context.

### Subtask summary format

Prefix subtask summaries with `N.M:` using a colon separator:

- `1.1: Phone update route validation` (correct)
- `1.1 — Phone update route validation` (wrong)

### Prefix story summaries under shared epics

When multiple apps or modules share an epic, prefix each story summary with the app or module name. This makes stories identifiable on boards and in search results without opening them.

Example: `int-membership-details: Shared Foundations`

### Do not assign tickets by default

Omit the `assignee` field when creating issues unless the user explicitly requests assignment.

### Label AI-created tickets

Every issue created by or with AI assistance MUST include the labels `AI` and `AI_Created`. These labels are already established in COREAPP1 and should be applied to all projects. Add them to the `labels` array in the issue creation payload alongside any other labels.

### Inherit CAPEX from the parent epic

CAPEX classification cascades down the hierarchy. Before creating a story under an epic (or a subtask under a story), read the parent's `customfield_11317` value and propagate it to the new issue. Finance reporting depends on every child of a CAPEX epic also being marked CAPEX, and missing values get caught in audit later.

```bash
# Read the epic's CAPEX value, then create the story with it set
EPIC_KEY="COREAPP1-3116"
CAPEX=$(curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  "https://legalshield.atlassian.net/rest/api/3/issue/${EPIC_KEY}?fields=customfield_11317" \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
v = d.get('fields', {}).get('customfield_11317')
print(v[0]['value'] if v else '')")

# CAPEX is now 'YES', 'NO', or '' (unset)
```

If the epic's CAPEX value is unset, create the story without the field rather than guessing. Surface the gap to the user so they can decide.

For subtasks, read CAPEX from the parent story (which already inherited from the epic) and propagate it the same way.

### Workflow: plan one story at a time

Present the story summary and subtask list to the user for review before creating anything via the API. Wait for explicit approval. Corrections before creation are cheap. Rework after creation is not.

Before writing a story's description, read the actual source files that story will touch. Do not rely on memory, prior context, or assumptions about what the code looks like.

---

## Authentication

All requests require a base64-encoded `email:api-token` string for authentication.

**Standard headers for every request:**

```bash
-H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
-H "Content-Type: application/json"
```

### Token Format

The token is a base64 encoding of `your-email@example.com:your-jira-api-token`. Generate one manually:

```bash
echo -n "you@example.com:YOUR_JIRA_API_TOKEN" | base64
```

Create a Jira API token at: https://id.atlassian.com/manage-profile/security/api-tokens

### Setup: 1Password CLI via shell profile

Export the token in your shell profile so it's available to Claude Code's Bash tool (which inherits the parent shell environment).

```bash
# In .zshrc or .bashrc
export JIRA_AUTH_TOKEN="$(op read 'op://PPLSI/Jira - Base64/credential')"
```

This resolves the 1Password secret once when you open a terminal. You must have an active `op` session (`eval $(op signin)` if needed). The token is then available for the entire shell session.

**Before any Jira operation**, verify the token is set:

```bash
if [ -z "$JIRA_AUTH_TOKEN" ]; then
  echo "ERROR: JIRA_AUTH_TOKEN not set."
  echo "Run 'eval \$(op signin)' and open a new terminal, or re-source your shell profile."
  exit 1
fi
```

### Customizing the 1Password reference

The `op read` reference above points to a specific 1Password vault and item. To use your own:

1. Store your base64-encoded Jira token in 1Password
2. Update the `op read` path in your shell profile to match: `op://YourVault/YourItem/credential`

## Instance Configuration

All projects below share the same Jira instance and custom field IDs.

| Setting         | Value                               | Notes                                    |
| --------------- | ----------------------------------- | ---------------------------------------- |
| Jira URL        | `https://legalshield.atlassian.net` | Shared across all teams                  |
| Default Project | `COREAPP1`                          | Fallback when `$JIRA_PROJECT` is not set |

### Selecting the Active Project

When no project is explicitly specified, resolve the active project in this order:

1. **Command flag** — `/jira --opsuc ...` sets the project for that request
2. **`$JIRA_PROJECT` env var** — if set, use this project key for the session
3. **Fallback** — use the Default Project from the table above

Switch teams without editing config or restarting:

```bash
# Via command flag (per-request, highest priority)
/jira --opsuc create a story called "Fix payment bug"

# Via env var at launch (session-wide)
JIRA_PROJECT=OPSUC claude
```

Before any Jira operation, resolve the active project:

```bash
PROJECT="${JIRA_PROJECT:-COREAPP1}"
```

Then use `$PROJECT` in API calls instead of hardcoding the project key.

### Field IDs (instance-wide)

These custom field IDs are the same across all projects on this Jira instance:

| Field                | ID                  | Notes                                             |
| -------------------- | ------------------- | ------------------------------------------------- |
| Epic Link            | `customfield_10118` | Set to epic key (e.g. `COREAPP1-3116`)            |
| Parent               | `parent`            | Set to `{"key": "EPIC_KEY"}` — also links to epic |
| Sprint               | `customfield_10122` | Set to sprint ID (integer)                        |
| Story Point Estimate | `customfield_11240` | Numeric                                           |
| Fibonacci Points     | `customfield_11348` | Numeric (alternative)                             |
| Epic Name            | `customfield_10120` | Only for creating epics                           |
| Issue is CAPEX?      | `customfield_11317` | Array of option. Allowed: `YES`, `NO`. Set as `[{"value": "YES"}]` |

---

## Project Profiles

When the user mentions a project by key or team name, use the matching profile below. If no project is specified, default to COREAPP1.

### COREAPP1 — Internal Tools (default)

| Setting       | Value                           |
| ------------- | ------------------------------- |
| Project Key   | `COREAPP1`                      |
| Board ID      | `544`                           |
| Board Type    | Scrum                           |
| Active Sprint | `9142` (COREAPP1 2026 Sprint 5) |

**Available issue types:**

| Type            | ID      | Subtask? |
| --------------- | ------- | -------- |
| Epic            | `10004` | No       |
| Story           | `10000` | No       |
| Sub-task        | `10002` | Yes      |
| Bug             | `10003` | No       |
| Task (Non Dev)  | `10001` | No       |
| Task (Dev Work) | `10559` | No       |
| Spike           | `10300` | No       |
| Refactor        | `10501` | No       |
| Technical Debt  | `10557` | No       |

**Key sprints:**

| Sprint ID | Name                   | State  |
| --------- | ---------------------- | ------ |
| `9142`    | COREAPP1 2026 Sprint 5 | Active |
| `5033`    | People App Bucket      | Future |
| `4176`    | Ready for Sprint       | Future |

---

### OPSUC — Gold Diggers

| Setting       | Value                     |
| ------------- | ------------------------- |
| Project Key   | `OPSUC`                   |
| Board ID      | `673`                     |
| Board Type    | Scrum                     |
| Active Sprint | `7840` (GD 2026 Sprint 5) |

**Available issue types:**

| Type     | ID      | Subtask? |
| -------- | ------- | -------- |
| Epic     | `10004` | No       |
| Story    | `10000` | No       |
| Sub-task | `10002` | Yes      |
| Bug      | `10003` | No       |
| Task     | `10576` | No       |
| Outcome  | `10566` | No       |
| Theme    | `10401` | No       |

**Key sprints:**

| Sprint ID | Name             | State  |
| --------- | ---------------- | ------ |
| `7840`    | GD 2026 Sprint 5 | Active |
| `7841`    | GD 2026 Sprint 6 | Future |
| `7842`    | GD 2026 Sprint 7 | Future |

**Note:** OPSUC uses `Task` (ID `10576`) instead of COREAPP1's `Task (Non Dev)` / `Task (Dev Work)` split. The Story, Sub-task, Bug, and Epic IDs are the same across both projects.

---

### Adding a New Project Profile

To add a profile for another project, run the discovery queries below and add a new section following the pattern above.

```bash
# Find your account ID
curl -s -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  "https://legalshield.atlassian.net/rest/api/3/myself" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'Account ID: {d[\"accountId\"]}')"

# List projects you can access
curl -s -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  "https://legalshield.atlassian.net/rest/api/3/project/search?maxResults=50" | python3 -c "
import json,sys
for p in json.load(sys.stdin).get('values',[]): print(f'{p[\"key\"]:12s} {p[\"name\"]}')"

# Find boards for a project
curl -s -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  "https://legalshield.atlassian.net/rest/agile/1.0/board?projectKeyOrId=PROJECT_KEY" | python3 -c "
import json,sys
for b in json.load(sys.stdin).get('values',[]): print(f'Board {b[\"id\"]}: {b[\"name\"]} ({b[\"type\"]})')"

# Find issue type IDs for a project
curl -s -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  "https://legalshield.atlassian.net/rest/api/3/issue/createmeta/PROJECT_KEY/issuetypes" | python3 -c "
import json,sys
data = json.load(sys.stdin)
for it in data.get('issueTypes', data.get('values', [])):
    print(f'ID: {it[\"id\"]:6s}  Name: {it[\"name\"]:20s}  Subtask: {it.get(\"subtask\", False)}')"

# Find sprints for a board
curl -s -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  "https://legalshield.atlassian.net/rest/agile/1.0/board/BOARD_ID/sprint?state=active,future&maxResults=10" | python3 -c "
import json,sys
for s in json.load(sys.stdin).get('values',[]): print(f'Sprint {s[\"id\"]}: {s[\"name\"]} ({s[\"state\"]})')"

# Find custom field IDs (run once — these are instance-wide)
curl -s -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  "https://legalshield.atlassian.net/rest/api/3/field" | python3 -c "
import json,sys
for f in json.load(sys.stdin):
    n = f.get('name','').lower()
    if any(k in n for k in ['epic','sprint','story point','parent']):
        print(f'{f[\"id\"]:30s} {f[\"name\"]}')"
```

## API Base URL

```
https://legalshield.atlassian.net/rest/api/3
```

For agile endpoints (boards, sprints):

```
https://legalshield.atlassian.net/rest/agile/1.0
```

---

## Operations

### 1. Verify Connection

```bash
curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  "https://legalshield.atlassian.net/rest/api/3/myself" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(f\"Connected as: {d['displayName']} ({d['emailAddress']})  ID: {d['accountId']}\")
"
```

### 2. Search Issues (JQL)

**IMPORTANT:** The `/rest/api/3/search` endpoint is deprecated. Use `/rest/api/3/search/jql` with POST.

```bash
curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST \
  "https://legalshield.atlassian.net/rest/api/3/search/jql" \
  -d '{
    "jql": "project = COREAPP1 AND issuetype = Story ORDER BY created DESC",
    "maxResults": 20,
    "fields": ["summary", "status", "assignee", "priority", "customfield_10118"]
  }'
```

Common JQL patterns:

- Stories under an epic: `project = COREAPP1 AND issuetype = Story AND "Epic Link" = COREAPP1-3116`
- Subtasks of a story: `parent = COREAPP1-XXXX`
- My open issues: `project = COREAPP1 AND assignee = currentUser() AND status != Done`
- Text search: `project = COREAPP1 AND summary ~ "membership"`

### 3. Create Story (under an Epic)

Stories are linked to epics via BOTH `customfield_10118` (Epic Link) AND `parent` (hierarchy). Inherit `customfield_11317` (Issue is CAPEX?) from the epic — see the authoring guidelines above.

```bash
curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST \
  "https://legalshield.atlassian.net/rest/api/3/issue" \
  -d '{
    "fields": {
      "project": {"key": "COREAPP1"},
      "issuetype": {"id": "10000"},
      "summary": "Story title here",
      "description": {
        "version": 1,
        "type": "doc",
        "content": [
          {
            "type": "paragraph",
            "content": [{"type": "text", "text": "Story description here."}]
          }
        ]
      },
      "customfield_10118": "COREAPP1-3116",
      "parent": {"key": "COREAPP1-3116"},
      "customfield_11240": 5,
      "customfield_11317": [{"value": "YES"}]
    }
  }'
```

**Response** contains `{"id": "...", "key": "COREAPP1-XXXX", "self": "..."}`.

### 4. Create Sub-task (under a Story)

Sub-tasks use `parent` to link to their parent Story. Do NOT set `customfield_10118` on sub-tasks. Inherit `customfield_11317` (Issue is CAPEX?) from the parent story.

```bash
curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST \
  "https://legalshield.atlassian.net/rest/api/3/issue" \
  -d '{
    "fields": {
      "project": {"key": "COREAPP1"},
      "issuetype": {"id": "10002"},
      "summary": "Subtask title here",
      "description": {
        "version": 1,
        "type": "doc",
        "content": [
          {
            "type": "paragraph",
            "content": [{"type": "text", "text": "Subtask description."}]
          }
        ]
      },
      "parent": {"key": "COREAPP1-XXXX"},
      "customfield_11317": [{"value": "YES"}]
    }
  }'
```

### 5. Create Epic

```bash
curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST \
  "https://legalshield.atlassian.net/rest/api/3/issue" \
  -d '{
    "fields": {
      "project": {"key": "COREAPP1"},
      "issuetype": {"id": "10004"},
      "summary": "Epic title",
      "customfield_10120": "Epic Name for Board",
      "description": {
        "version": 1,
        "type": "doc",
        "content": [
          {
            "type": "paragraph",
            "content": [{"type": "text", "text": "Epic description."}]
          }
        ]
      }
    }
  }'
```

### 6. Update Issue

```bash
curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -X PUT \
  "https://legalshield.atlassian.net/rest/api/3/issue/COREAPP1-XXXX" \
  -d '{
    "fields": {
      "summary": "Updated title",
      "customfield_11240": 8
    }
  }'
```

### 7. Get Issue Details

```bash
curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  "https://legalshield.atlassian.net/rest/api/3/issue/COREAPP1-XXXX?fields=summary,status,assignee,parent,subtasks,customfield_10118,customfield_11240"
```

### 8. Transition Issue (Change Status)

First, get available transitions:

```bash
curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  "https://legalshield.atlassian.net/rest/api/3/issue/COREAPP1-XXXX/transitions"
```

Then transition:

```bash
curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST \
  "https://legalshield.atlassian.net/rest/api/3/issue/COREAPP1-XXXX/transitions" \
  -d '{"transition": {"id": "TRANSITION_ID"}}'
```

### 9. Add to Sprint

```bash
curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST \
  "https://legalshield.atlassian.net/rest/agile/1.0/sprint/SPRINT_ID/issue" \
  -d '{"issues": ["COREAPP1-XXXX", "COREAPP1-YYYY"]}'
```

Known sprint IDs:

- `9142` — COREAPP1 2026 Sprint 5 (active)
- `5033` — People App Bucket (future/backlog)
- `4176` — Ready for Sprint (future)

### 10. List Sprints

```bash
curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  "https://legalshield.atlassian.net/rest/agile/1.0/board/544/sprint?state=active,future&maxResults=10"
```

### 11. Delete Issue

```bash
curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -X DELETE \
  "https://legalshield.atlassian.net/rest/api/3/issue/COREAPP1-XXXX"
```

Add `?deleteSubtasks=true` to also delete subtasks of the issue.

### 12. Add Comment

```bash
curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST \
  "https://legalshield.atlassian.net/rest/api/3/issue/COREAPP1-XXXX/comment" \
  -d '{
    "body": {
      "version": 1,
      "type": "doc",
      "content": [
        {
          "type": "paragraph",
          "content": [{"type": "text", "text": "Comment text here."}]
        }
      ]
    }
  }'
```

### 13. Add Labels

```bash
curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -X PUT \
  "https://legalshield.atlassian.net/rest/api/3/issue/COREAPP1-XXXX" \
  -d '{"fields": {"labels": ["int-membership-details", "tech-debt"]}}'
```

---

## Rich Description Format (Atlassian Document Format v1)

Jira v3 uses ADF (Atlassian Document Format) for description and comment bodies. Key node types:

### Headings

```json
{
  "type": "heading",
  "attrs": { "level": 3 },
  "content": [{ "type": "text", "text": "Section Title" }]
}
```

### Bold / Italic / Code

```json
{"type": "text", "text": "bold text", "marks": [{"type": "strong"}]}
{"type": "text", "text": "italic text", "marks": [{"type": "em"}]}
{"type": "text", "text": "inline code", "marks": [{"type": "code"}]}
```

### Bullet List

```json
{
  "type": "bulletList",
  "content": [
    {
      "type": "listItem",
      "content": [
        {
          "type": "paragraph",
          "content": [{ "type": "text", "text": "Item one" }]
        }
      ]
    },
    {
      "type": "listItem",
      "content": [
        {
          "type": "paragraph",
          "content": [{ "type": "text", "text": "Item two" }]
        }
      ]
    }
  ]
}
```

### Ordered List

```json
{
  "type": "orderedList",
  "content": [
    {
      "type": "listItem",
      "content": [
        {
          "type": "paragraph",
          "content": [{ "type": "text", "text": "Step one" }]
        }
      ]
    }
  ]
}
```

### Code Block

```json
{
  "type": "codeBlock",
  "attrs": { "language": "typescript" },
  "content": [{ "type": "text", "text": "const x = 1;" }]
}
```

### Horizontal Rule

```json
{ "type": "rule" }
```

### Panel (Info / Warning / Note)

```json
{
  "type": "panel",
  "attrs": { "panelType": "info" },
  "content": [
    {
      "type": "paragraph",
      "content": [{ "type": "text", "text": "Info panel text" }]
    }
  ]
}
```

Panel types: `info`, `note`, `warning`, `success`, `error`

### Full Example: Rich Story Description

```json
{
  "version": 1,
  "type": "doc",
  "content": [
    {
      "type": "heading",
      "attrs": { "level": 3 },
      "content": [{ "type": "text", "text": "Overview" }]
    },
    {
      "type": "paragraph",
      "content": [{ "type": "text", "text": "Description of the work." }]
    },
    {
      "type": "heading",
      "attrs": { "level": 3 },
      "content": [{ "type": "text", "text": "Acceptance Criteria" }]
    },
    {
      "type": "bulletList",
      "content": [
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [{ "type": "text", "text": "Criterion one" }]
            }
          ]
        },
        {
          "type": "listItem",
          "content": [
            {
              "type": "paragraph",
              "content": [{ "type": "text", "text": "Criterion two" }]
            }
          ]
        }
      ]
    },
    {
      "type": "heading",
      "attrs": { "level": 3 },
      "content": [{ "type": "text", "text": "Implementation Notes" }]
    },
    {
      "type": "codeBlock",
      "attrs": { "language": "typescript" },
      "content": [{ "type": "text", "text": "// code snippet here" }]
    }
  ]
}
```

---

## Bulk Creation Workflow

When creating multiple stories with subtasks (e.g., sprint planning):

1. **Create stories first** — collect the returned keys
2. **Create subtasks** — use the parent story key in `parent.key`
3. **Add to sprint** — batch all issue keys into one sprint request

```bash
# Step 1: Create a story, capture the key
STORY_KEY=$(curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST \
  "https://legalshield.atlassian.net/rest/api/3/issue" \
  -d '{ ... }' | python3 -c "import json,sys; print(json.load(sys.stdin)['key'])")

echo "Created: $STORY_KEY"

# Step 2: Create subtasks under that story
curl -s \
  -H "Authorization: Basic ${JIRA_AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST \
  "https://legalshield.atlassian.net/rest/api/3/issue" \
  -d "{
    \"fields\": {
      \"project\": {\"key\": \"COREAPP1\"},
      \"issuetype\": {\"id\": \"10002\"},
      \"summary\": \"Subtask title\",
      \"parent\": {\"key\": \"$STORY_KEY\"},
      ...
    }
  }"
```

---

## Error Handling

Common HTTP status codes:

- `200/201` — Success
- `400` — Bad request (check field names, required fields)
- `401` — Auth failed (token expired or malformed)
- `403` — Permission denied (no access to project)
- `404` — Issue/project not found
- `429` — Rate limited (back off and retry)

Always check response for errors:

```bash
response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" ...)
http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
body=$(echo "$response" | sed '/HTTP_STATUS:/d')

if [ "$http_status" != "201" ]; then
  echo "ERROR ($http_status): $body"
fi
```

---

## Quick Reference

| Action        | Method | Endpoint                              |
| ------------- | ------ | ------------------------------------- | --- |
| Search        | POST   | `/rest/api/3/search/jql`              |
| Create issue  | POST   | `/rest/api/3/issue`                   |
| Get issue     | GET    | `/rest/api/3/issue/{key}`             |
| Update issue  | PUT    | `/rest/api/3/issue/{key}`             |
| Delete issue  | DELETE | `/rest/api/3/issue/{key}`             |
| Transitions   | GET    | `/rest/api/3/issue/{key}/transitions` | :   |
| Do transition | POST   | `/rest/api/3/issue/{key}/transitions` |
| Add comment   | POST   | `/rest/api/3/issue/{key}/comment`     |
| Add to sprint | POST   | `/rest/agile/1.0/sprint/{id}/issue`   |
| List sprints  | GET    | `/rest/agile/1.0/board/544/sprint`    |
| My info       | GET    | `/rest/api/3/myself`                  |
