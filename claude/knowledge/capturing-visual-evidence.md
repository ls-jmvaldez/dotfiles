---
name: capturing-visual-evidence
description: Captures screenshots, plus a short video when a still can't show it, of a UI change running in a worktree, and saves them locally for the user to drag into the PR.
---

# Capturing visual evidence

You capture **evidence** of one UI change: stills, plus a short video when a still cannot show the change. You run the change from its worktree, save files outside the repo, and return a **manifest**. The user uploads the files, because GitHub accepts PR media only through its web UI.

Inputs from your caller: worktree path, ticket key (or `pr<N>`), PR URL, the change's goal and manual test steps, and an optional `**Evidence:**` line from the plan. That line overrides your shot choices in Step 2.

## Guardrails

- **Env files.** Load them only through the app's own tooling (`dotenv`, `process.loadEnvFile`) inside the process that needs them. Check existence with `test -e`. Their values never reach your output: no `cat`, `grep`, `head`, `echo $VAR`, `env`, `printenv`, or logging of any value.
- **Processes.** Stop only what you started. A port someone else holds belongs to them; take another port.
- **Data.** DEV upstream and disposable test members only.
- **Files.** Evidence goes under `~/Documents/claude-screenshots/`; scratch files go in your scratchpad. The worktree ends exactly as you found it, and nothing gets committed.
- **Time box.** 20 minutes. Past that, clean up and report what blocked you.

## Step 1: Snapshot and find the recipe

1. Record `git -C <worktree> status --porcelain`. Step 5 restores to exactly this.
2. Find the run skill, first match wins: a personal `~/.claude/skills/run-<app>/SKILL.md` for the app this repo builds (here `run-membership-details`); then a `.claude/skills/run-*/SKILL.md` in the worktree or the primary checkout. Its description must cover launching the app. Read it and follow it verbatim for launch, auth, data, driving, and stop. Every app-specific detail lives there.
3. No run skill: invoke the built-in `run` skill for its fallback pattern, and add "no project run skill" to the manifest.

Done when you know the launch command, the ports you will use, how auth works, and where test data comes from.

## Step 2: Choose the shots

Write the shot list before launching anything. Name each shot by its subject: `billing-card-pay-period`, `payments-dialog-open`.

**Still or video.** Ask: can a reviewer confirm the change from one settled frame?

- Yes: stills. Text, labels, values, color, spacing, layout, a new static element, an empty or error state reachable by URL or data.
- No: a video of the interaction, plus a still of its end state. The change lives between two states joined by a user action: a dialog or menu opening, wizard steps, validation appearing on submit, a loading, optimistic, or toast state, an animation or transition, focus or keyboard behavior.
- A changed dialog whose opening is unchanged is a still of the open dialog. Video earns its place only when the motion is the change.

**Framing.**

- Stills: an element shot of the changed component, plus one viewport shot when its surroundings matter. Viewport 1440x900, stills at 2x device scale. Light and dark for every still.
- Video: light theme, one flow, under 30 seconds. Recording starts once the page is settled and stops about a second after the end state. H.264 `.mp4`, under 10MB.
- "After" state only. Captions follow the rules in Step 6.

Done when every item in the goal and manual test steps that a human would look at maps to a shot.

## Step 3: Capture

Launch, authenticate, seed data, and drive per the run skill. **Settled** means the target element is visible and no skeleton, spinner, or `aria-busy` remains; wait on that condition rather than a fixed delay.

Save to `~/Documents/claude-screenshots/<TICKET>/` as `<TICKET>-<NN>-<subject>-<theme>.png` and `<TICKET>-<NN>-<subject>.mp4`. `NN` is shot order, which becomes the drag order in the PR; the light and dark versions of one still share `NN`.

A run skill without a video converter: turn Playwright's VP8 `.webm` into H.264 with
`ffmpeg -y -loglevel error -i in.webm -c:v libx264 -pix_fmt yuv420p -crf 23 -preset slow -movflags +faststart -an out.mp4`

## Step 4: Verify

Open every PNG with Read and look at it. For each video, run `ffprobe` for duration and size, extract the middle and last frames into the scratchpad (`ffmpeg -ss <mid> -i in.mp4 -frames:v 1 mid.png`, `ffmpeg -sseof -0.5 -i in.mp4 -frames:v 1 last.png`), and open those. Retake any shot showing a login page, a skeleton, an error boundary, a blank region, the wrong theme, or something other than the changed component.

Done when every file shows the change, settled, in the theme its name claims.

## Step 5: Clean up

1. Stop each background task you started (TaskStop on its ID). Confirm its port has no listener; a listener still on a port that was free before you started is your orphan, so stop that PID.
2. Delete scratch files: scene scripts, `.webm` intermediates, extracted frames.
3. Compare `git -C <worktree> status --porcelain` with the Step 1 snapshot. Restore tracked files the capture changed (`git -C <worktree> restore <file>`) and delete untracked files it created.

Done when the status matches the snapshot and every process you started is gone.

## Step 6: Return the manifest

In shot order:

- the evidence folder's absolute path
- per file: absolute path and a one-line caption a reviewer reads above it (rules below)
- per `Before:` clause: its source, recorded in the manifest only, never in the caption
- planned shots you could not capture, with the reason
- confirmation that you opened every file and the worktree status matches the snapshot

### Captions

The main text describes only what the file shows: the component, the state, and the theme.

Add `Before: "<old output>"` only when the old visible output is proven by one of these, and name which in the manifest:

- the exact removed or changed lines in `git diff <base>...HEAD`, such as a removed string literal (source: diff line)
- an existing test assertion on the base branch (source: test)
- text the ticket or PR quotes as the bug, such as the ticket saying it renders "12 pay_periods" (source: ticket)

When the old output was computed (a formatter or template literal) and the diff does not show it literally, derive it by running the base-branch function with the same input: a vitest one-off, or `git show <base>:<file>` read alongside the actual inputs (source: base-branch run). Without that run, omit `Before:`.

Quote the old output exactly as it rendered, character for character. A paraphrase or an inference is a guess, and a guess is not proof.

When unsure, omit `Before:`. A caption without it is complete; a wrong one is a defect.
