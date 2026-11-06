---
name: run-membership-details
description: Start, drive, and screenshot int-membership-details in the internal-membership-web repo, from any worktree on a spare port, logged in against DEV. Use in that repo when asked to run the app, screenshot or record a UI change, or capture PR evidence.
---

Runs a worktree's `int-membership-details` beside whatever already holds port 3110, behind a private Caddy TLS front, and drives it with `~/.claude/skills/run-membership-details/capture.mjs` (Playwright, resolved from the worktree). Each Bash call starts in the primary checkout and keeps no shell variables, so every command takes literal absolute paths: `<wt>` is the worktree, `<scratch>` your scratchpad.

## Prerequisites

Already set up on Joe's machine. Check them; report a gap instead of fixing it.

- `caddy` installed and its CA trusted (`<wt>/infra/README.md`, one-time setup).
- `test -e <wt>/apps/int-membership-details/.env.dev.local` (dev server) and `test -e <wt>/apps/int-membership-details/.env.local` (E2E login account). The local post-checkout hook symlinks both into new worktrees. Existence checks only; the files are never opened.
- `test -d <wt>/node_modules`, otherwise `pnpm -C <wt> install --frozen-lockfile`. The primary checkout often has an empty app `node_modules`, so everything resolves from the worktree.

## Launch

Port 3110 and Caddy's `:443` belong to the developer's own server, which may be running another worktree's code. Use spare ports.

1. Pick `PORT`: the first of 3111-3119 where `lsof -nP -iTCP:<port> -sTCP:LISTEN -t` prints nothing. Pick `PROXY` the same way from 8443-8449.
2. Start the dev server with Bash `run_in_background: true`, keeping the task ID:
   `cd <wt> && pnpm exec dotenv -o -e apps/int-membership-details/.env.dev.local -- pnpm --filter @internal-membership-web/int-membership-details exec next dev --hostname 127.0.0.1 -p <PORT> > <scratch>/next.log 2>&1`
3. Wait for it (macOS has no `timeout`):
   `for i in $(seq 1 90); do curl -sf -o /dev/null http://127.0.0.1:<PORT>/v1/health && echo up && break; sleep 2; done`
   `/v1/health` is a public route, so a 200 means the server is up.
4. Start the TLS front with Bash `run_in_background: true`, keeping the task ID:
   `caddy reverse-proxy --from https://membership-details-local.dev-legalshieldinternal.com:<PROXY> --to 127.0.0.1:<PORT> --internal-certs --disable-redirects > <scratch>/caddy.log 2>&1`
   Its admin endpoint is off, so it runs beside the developer's Caddy. Ready when
   `curl -s -o /dev/null -w '%{http_code}' --resolve membership-details-local.dev-legalshieldinternal.com:<PROXY>:127.0.0.1 https://membership-details-local.dev-legalshieldinternal.com:<PROXY>/v1/health` prints `200`.

## Test data

- Fresh DEV member: write `<scratch>/prov.mts` and run `node <scratch>/prov.mts`. It prints `{ identityId, email, firstName }`.
  ```ts
  import { provisionOtpMember } from "<wt>/apps/int-membership-details/e2e/support/provision.ts";
  console.log(JSON.stringify(await provisionOtpMember("US")));
  ```
  The member has a LegalShield plan, a PAY_PERIOD/12 subscription, a Yukon, OK address, no payment method, and shows PAST DUE. The provisioner refuses non-dev targets.
- Any other state (months past due, cancelled, a specific plan, dependents): the `internal-tools:member-factory` skill.
- The member page is `/members/<identityId>`.

## Drive

Write a scene module in `<scratch>`, then run the driver. The driver logs in with the E2E account, runs the scene once per theme, and prints `{ "files": [...] }`.

```js
// <scratch>/scene.mjs
export default async function scene({ page, args, ready, shot, record }) {
	await page.goto(`/members/${args.member}`);
	const card = page.getByTestId("billing-summary");
	await ready(card);
	await shot("billing-card-pay-period", card);
	await shot("member-page");
	await record("payments-dialog-open", async () => {
		await page.getByRole("button", { name: "Payments" }).click();
		await ready(page.getByRole("dialog"));
	});
	await shot("payments-dialog", page.getByRole("dialog"));
}
```

`node ~/.claude/skills/run-membership-details/capture.mjs --repo <wt> --proxy-port <PROXY> --scene <scratch>/scene.mjs --out ~/Documents/claude-screenshots/<TICKET> --prefix <TICKET> --arg member=<identityId>`

`--repo` decides which code runs and where Playwright resolves from; it defaults to the current directory. Verify the setup without launching anything: `node ~/.claude/skills/run-membership-details/capture.mjs --repo <wt> --check`.

| Scene helper | Behavior |
| --- | --- |
| `ready(locator)` | Waits until the locator is visible and no skeleton, spinner, or `aria-busy` remains inside it. Other panels on the page may keep skeletons up; they do not block `ready`. |
| `shot(name, locator?)` | Element shot, or the viewport when no locator. Saved once per theme as `<prefix>-<NN>-<name>-<theme>.png`. |
| `record(name, act)` | Records `act` to `<prefix>-<NN>-<name>.mp4` (H.264) in the first theme only. Runs `act` in every theme so later shots see the same state. |

Options: `--themes light,dark` (default), repeatable `--arg key=value` (passed to the scene as `args`).

## Stop

TaskStop both background tasks. Then `lsof -nP -iTCP:<PORT> -sTCP:LISTEN -t` and the same for `<PROXY>` must print nothing; a remaining listener on either port is yours (both ports were free when you started), so stop that PID.

## Gotchas

- **Portless URLs still reach your server inside the driver.** Chromium's `--host-resolver-rules` maps the hostname to `127.0.0.1:<PROXY>`, so the Okta cookies (bound to the hostname) are sent and app redirects to the portless host land on your server. Outside the driver (curl, a regular browser), the portless hostname reaches the developer's server on 3110.
- **Theme comes from `localStorage.theme`.** next-themes runs with `defaultTheme: "light"` and no system theme, so Playwright's `colorScheme` does nothing. The driver sets the key per theme.
- **No `fullPage` screenshots.** The shell scrolls inside a container, so a full-page capture renders the sticky header mid-page with a blank tail. Use element and viewport shots.
- **Dev overlays.** The driver hides the Next.js dev indicator (`nextjs-portal`) and the TanStack Query devtools button (`.tsqd-open-btn-container`). If either shows up in a capture, its selector changed.
- **First compile is slow.** `next dev` compiles a route on first hit, 10 to 30 seconds. `ready()` covers it.
- **Viewport shots need their own readiness.** `ready` only checks inside its locator, so before `shot("name")` with no locator, `ready` each region the shot must show (header, banner, cards). Otherwise the light and dark versions can catch different loading states.
