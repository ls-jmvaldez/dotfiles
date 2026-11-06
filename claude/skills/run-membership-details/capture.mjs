import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, rmSync, statSync } from "node:fs";
import { createRequire } from "node:module";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";

const HOST = "membership-details-local.dev-legalshieldinternal.com";
const LOGIN_ORIGIN = "https://login.dev-legalshieldinternal.com";
const VIEWPORT = { width: 1440, height: 900 };
const GITHUB_FREE_PLAN_VIDEO_LIMIT = 10 * 1024 * 1024;
const LOADING_INDICATORS =
  '[class*="animate-pulse"],[role="progressbar"],[aria-busy="true"]';
const DEV_OVERLAYS_HIDDEN =
  "nextjs-portal, .tsqd-open-btn-container { display: none !important; }";

const { values } = parseArgs({
  options: {
    repo: { type: "string", default: process.cwd() },
    "proxy-port": { type: "string", default: "8443" },
    scene: { type: "string" },
    out: { type: "string" },
    prefix: { type: "string" },
    themes: { type: "string", default: "light,dark" },
    arg: { type: "string", multiple: true, default: [] },
    check: { type: "boolean", default: false },
    help: { type: "boolean", default: false },
  },
});
if (values.help) {
  console.log(`usage: node capture.mjs --repo <worktree> --scene <file> --out <dir> --prefix <name>
       [--proxy-port 8443] [--themes light,dark] [--arg key=value]...
       node capture.mjs --repo <worktree> --check

--repo defaults to the current directory. --check resolves Playwright from the repo and
confirms the env file exists (never opened), then exits 0 without launching anything.`);
  process.exit(0);
}
if (!values.check)
  for (const required of ["scene", "out", "prefix"]) {
    if (!values[required]) {
      console.error(`missing --${required}`);
      process.exit(2);
    }
  }

const appDir = join(resolve(values.repo), "apps/int-membership-details");
if (!existsSync(join(appDir, "package.json"))) {
  console.error(
    `${appDir} not found; pass --repo <internal-membership-web worktree>`,
  );
  process.exit(2);
}
// Resolve from the target worktree: this file lives in ~/.claude/skills, so bare imports would not find it.
const { chromium, request } = createRequire(join(appDir, "package.json"))(
  "@playwright/test",
);

if (values.check) {
  const envFile = join(appDir, ".env.local");
  if (!existsSync(envFile)) {
    console.error(`missing ${envFile}`);
    process.exit(1);
  }
  console.log(
    `ok: playwright resolved from ${appDir}; ${typeof chromium.launch}; .env.local present`,
  );
  process.exit(0);
}

// Values stay inside this process; nothing here prints them.
process.loadEnvFile(join(appDir, ".env.local"));

const args = Object.fromEntries(
  values.arg.map((pair) => pair.split(/=(.*)/s).slice(0, 2)),
);
const { default: scene } = await import(
  pathToFileURL(resolve(values.scene)).href
);
mkdirSync(values.out, { recursive: true });

const storageState = await login();
const browser = await chromium.launch({
  channel: "chromium",
  // Okta cookies are bound to HOST, so the browser must keep using it while reaching our port.
  args: [`--host-resolver-rules=MAP ${HOST} 127.0.0.1:${values["proxy-port"]}`],
});
const written = [];

try {
  for (const [themeIndex, theme] of values.themes.split(",").entries()) {
    const context = await browser.newContext({
      baseURL: `https://${HOST}`,
      storageState,
      viewport: VIEWPORT,
      deviceScaleFactor: 2,
      ignoreHTTPSErrors: true,
    });
    // next-themes ignores prefers-color-scheme here (defaultTheme "light", no system theme).
    await context.addInitScript(
      ([themeName, css]) => {
        localStorage.setItem("theme", themeName);
        document.addEventListener("DOMContentLoaded", () => {
          const style = document.createElement("style");
          style.textContent = css;
          document.head.append(style);
        });
      },
      [theme, DEV_OVERLAYS_HIDDEN],
    );
    const page = await context.newPage();
    let shotNumber = 0;
    const fileFor = (name, suffix) =>
      join(
        values.out,
        `${values.prefix}-${String(++shotNumber).padStart(2, "0")}-${name}${suffix}`,
      );

    const ready = async (locator) => {
      await locator.waitFor({ state: "visible", timeout: 60_000 });
      // Scoped to the target: other panels on the page can keep skeletons up indefinitely.
      const handle = await locator.elementHandle();
      await page.waitForFunction(
        ([el, sel]) => !el.matches(sel) && !el.querySelector(sel),
        [handle, LOADING_INDICATORS],
        { timeout: 30_000 },
      );
    };

    const shot = async (name, locator) => {
      const path = fileFor(name, `-${theme}.png`);
      const options = { path, animations: "disabled" };
      await (locator ? locator.screenshot(options) : page.screenshot(options));
      written.push(path);
    };

    const record = async (name, act) => {
      const path = fileFor(name, ".mp4");
      // One video per flow; later themes still run act so their stills see the same page state.
      if (themeIndex > 0) return act();
      const webm = path.replace(/\.mp4$/, ".webm");
      await page.screencast.start({ path: webm, size: VIEWPORT });
      await page.screencast.showActions();
      await act();
      await page.waitForTimeout(1000);
      await page.screencast.stop();
      // Playwright writes VP8; GitHub recommends H.264 for playback in every browser.
      execFileSync("ffmpeg", [
        "-y",
        "-loglevel",
        "error",
        "-i",
        webm,
        "-c:v",
        "libx264",
        "-pix_fmt",
        "yuv420p",
        "-crf",
        "23",
        "-preset",
        "slow",
        "-movflags",
        "+faststart",
        "-an",
        path,
      ]);
      rmSync(webm);
      if (statSync(path).size > GITHUB_FREE_PLAN_VIDEO_LIMIT) {
        throw new Error(`${path} is over 10MB; shorten the recorded flow`);
      }
      written.push(path);
    };

    await scene({ page, theme, args, ready, shot, record });
    await context.close();
  }
} finally {
  await browser.close();
}

console.log(JSON.stringify({ files: written }, null, 2));

// Mirrors packages/core/config/e2e-config/src/global-setup.ts. That file can't be imported here:
// its relative .js imports don't resolve under Node's type stripping.
async function login() {
  const api = await request.newContext({ ignoreHTTPSErrors: true });
  try {
    const start = await api.get(
      `${LOGIN_ORIGIN}/v1/oauth/okta?app=membership-details-local&path=/&source=dev-legalshieldinternal.com`,
    );
    const authorizeUrl = new URL(start.url());
    const authn = await (
      await api.post(`${authorizeUrl.origin}/api/v1/authn`, {
        data: {
          username: process.env.E2E_USER_EMAIL,
          password: process.env.E2E_USER_PASSWORD,
        },
      })
    ).json();
    if (authn.status !== "SUCCESS") {
      throw new Error(
        `Okta authentication failed: ${authn.errorSummary ?? authn.status}`,
      );
    }
    authorizeUrl.searchParams.set("sessionToken", authn.sessionToken);
    // The callback sets the cookies; the final hop to the app can fail locally and doesn't matter.
    await api.get(authorizeUrl.toString(), { timeout: 10_000 }).catch(() => {});
    return await api.storageState();
  } finally {
    await api.dispose();
  }
}
