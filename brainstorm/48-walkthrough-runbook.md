# Brainstorm: Walkthrough as a Runbook (rework of the Guided Walkthrough)

**Date:** 2026-10-11
**Status:** ready for spec
**Supersedes:** `47-guided-walkthrough-pair-testing.md` (shipped as 053-guided-walkthrough)
**Origin:** A real run of `/speckit-spex-walkthrough` on a container-build project produced steps like "Actual: Probed <image> (cache hit...), reported the delta..., wrote plan.yaml (16KB, 18 sections...)". The human could not tell what the feature does, what good output looks like, or what actually happened. The step template itself caused it: its `Actual:` field asks for a description of the artifact, and its `Artifact: <path or inline excerpt>` field accepts a bare path, so the prose rule "show the real output, do not narrate" lost to the template.

## Problem Framing

The walkthrough exists so a human can build trust in a feature an agent just built. The 053 version fails at that:

1. **Output is a summary card, not something a person can follow.** No explanation of what the feature or step is for, no statement of what good output looks like, no real output.
2. **It is not a tutorial.** The human often sees the feature for the first time during the walkthrough, but nothing teaches it.
3. **Setup is all or nothing.** It has no notion of cheap versus expensive test environments (a podman container versus a cloud cluster).
4. **The helper scripts serve the wrong model.** `spex-walkthrough-coverage.py` maps FRs to stories by FR-id mentions; on its own spec it reported all 27 FRs as orphans because stories never cite FR ids. Its skip gate (no stories and no scenarios) is not a testability decision.
5. **Completion is never recorded.** `finish`, `verify`, and the status line read `smoke_test_completed` from `.specify/.spex-state`, but nothing writes it, so `finish` can never see that a walkthrough ran.
6. **No way to run it later.** Ship cannot leave a walkthrough behind for the human to run after the pipeline ends.

## Decision

Green-field rewrite of the walkthrough command and its helpers. The command name stays `/speckit-spex-walkthrough`. All decisions below were approved in the brainstorm.

## Goal (user's words, condensed)

Give the user an easy to understand runbook for testing the feature, when it is testable. If it is not testable, say so and do nothing. The runbook walks the feature end to end so the user understands it. Every step is documented. Offer to start backends and fixtures that can be automated (from podman containers up to clusters); for everything else, instruct the user and offer to copy commands to the clipboard. Make it as user friendly as possible, so the runbook wins trust in the created feature.

## Section 1: Flow

### Testability check (always first)

Read spec, plan, quickstart, and the branch diff. Ask: is there something a person can do and then see the result of (run a command, call an API, open a page, use a skill, look at a generated file)?

- **Not testable:** one line with the reason (e.g. "Nothing to try by hand: this only refactors internal parsing, covered by unit tests"). No file is written. If flow or ship state exists, record "not testable" there so `finish` does not ask again in that run.
- **Partly testable:** the runbook covers the testable parts and lists the rest under "Not covered here" with a one-line reason each.
- **Testable:** continue.

### Two modes, chosen by the heaviest fixture needed

**Light mode** (no fixtures, or only quick local ones such as podman containers or a local process):

1. Write `RUNBOOK.md` in one go and show the steps in the chat.
2. One question approves the runbook and the quick fixtures together ("Start? This also starts the postgres container").
3. Steps one at a time (see Section 2).
4. Fixtures stop automatically, results go into the file, the status is recorded.

**Full mode** (any slow local fixture such as image builds or a local cluster, or any remote or paid fixture such as a cloud cluster):

1. Draft `RUNBOOK.md` and show it.
2. Separate review pause: the user answers "go", "change step 3", or "drop step 5", and changes go into the file before anything runs.
3. Environment setup with tiered consent (below).
4. Steps one at a time.
5. Wrap-up: results summary at the top of the file, teardown choice, status recorded.

**Upgrade:** if light mode discovers something heavy during setup (e.g. the container needs a 10 minute image build), stop, explain, and switch to full mode. Never downgrade mid-run.

**Resume (both modes):** results are written into the file step by step. If an unfinished runbook exists, rerunning the command offers to continue from the first unfinished step.

### Fixtures

- **Discovery:** infer what is needed from spec, plan, and quickstart. Look for setup paths in compose files, Makefile targets, scripts, README setup sections, CLIs on PATH, and skills or plugins in the session that provision infrastructure.
- **Reuse first:** check whether the environment already exists (a kubeconfig pointing at a live cluster, a running container) and offer to use it.
- **Tiers and consent:**
  - Quick and local (seconds, e.g. a podman container): offered with one yes.
  - Slow and local (minutes, e.g. image builds, a local kind cluster): state a time estimate, then ask.
  - Remote or paid (cloud cluster, cloud resources, anything using the user's accounts): never started on the agent's own initiative. State what will be created, rough duration, and that it may cost money; run the project's tooling only after an explicit yes, or hand the commands to the user.
- **Teardown:** quick local fixtures stop at the end of the session. Slow and remote fixtures stay up by default; the agent asks, and the teardown command is written into the runbook either way.
- **Test environment section** in the runbook lists every fixture: how it was set up, who started it, and how to tear it down.
- Scratch files (logs, test data, PID files, fixture list) go to `specs/<feature>/.walkthrough/` (already gitignored) and persist.

### Where things live

- `specs/<feature>/RUNBOOK.md`, committed with the other spec artifacts (except in detach mode, see Section 3).
- Session scratch in `specs/<feature>/.walkthrough/`.

## Section 2: What a step looks like

Every step in `RUNBOOK.md` has the same parts:

````markdown
### Step 2 of 6: Generate a build plan

**Why this step:** <what the feature does here and why it matters, in plain words>

**Needs:** <earlier steps or fixtures this depends on, and what happens without them>

**Run:**
```bash
<exact, complete, copyable command>
```

**What you should see:**
- <concrete observable 1>
- <concrete observable 2>

**If you see something else:**
- <symptom>: <what it means, what to do>

**Result:** (filled in during the session)
````

- "What you should see" is written before the command runs, so the user knows what good looks like.
- A missing prerequisite becomes its own step, found while drafting.
- Values only known at runtime are captured by a command (`ID=$(tool plan --json | jq -r .id)`), never written as placeholders.

### In the chat

The step text is shown, then a choice per step: `Run it myself (copied to clipboard)` / `You run it` / `Skip`.

- **User runs it:** the command goes to the clipboard; the user answers `Looks like that` or `Something else` (paste or describe).
- **Agent runs it:** the real output is shown, never a summary. Output up to about 40 lines is shown in full. Longer output is saved to `.walkthrough/step-N.log`, and the exact lines each "What you should see" bullet refers to are quoted verbatim with the log path. Each bullet is then marked seen or not seen.

### Result block

Verdict, who ran it, the quoted output lines or the user's observation, and a note if the step was corrected during the session (when real output differed from what the draft expected, the step is fixed in the file and the correction recorded).

## Section 3: Failures, status, and integration

### When a step does not match

The user chooses each time (no fixed retry limit):

- **Investigate:** read logs, code, and output, explain in plain words what probably went wrong.
- **Fix and retry:** only when a cause was found. Change the code, say what changed, rerun from that step, record fix and retry.
- **Record and continue:** step marked failed with the user's note.
- **Stop here:** runbook stays in progress and can be resumed.

### Status block (single source of truth)

```
Status: passed · 6 of 6 steps    (or: failed · in progress 3/6 · drafted)
Drafted at: <sha> · Tested at: <sha> · Mode: light · <date>
```

- "Current" means no code changed since the tested commit; changes under `specs/` do not count, so committing the runbook does not make it stale.
- Replaces the `smoke_test_*` keys in `.specify/.spex-state`.

### finish (advisory, never blocks)

| Runbook state | finish behavior |
|---|---|
| passed and current | "Walkthrough passed at <sha>", continue |
| passed, code changed since | list changed files, offer rerun or continue |
| in progress | offer resume |
| failed | show the failed step and note, offer continue anyway or stop |
| drafted | offer Run now or Later (stays drafted) |
| missing | run the command (testability check first); `--no-walkthrough` still skips |

### ship drafts, the user runs later

- At the end of the pipeline, ship always runs the command with `--draft`: testability check plus `RUNBOOK.md` with `Status: drafted`. No fixtures, no steps. This needs no consent, so it happens at every ask level.
- Ship's closing message points to it: "Runbook drafted: specs/054-foo/RUNBOOK.md (6 steps, light mode). Try it now or later with `/speckit-spex-walkthrough 054`." Not testable: one line.

### Command forms

| Call | Behavior |
|---|---|
| `/speckit-spex-walkthrough` | current branch's feature; run or resume an existing runbook, otherwise draft then run |
| `/speckit-spex-walkthrough --draft` | only write the runbook (used by ship) |
| `/speckit-spex-walkthrough 054` | run that feature's runbook from anywhere, including main after merge |
| on main, no argument | list drafted, in progress, and failed runbooks and let the user pick |

Running later: if code changed since the draft (ignoring `specs/`), show the changed files and offer to refresh the affected steps or run as is. The status block records the commit actually tested.

### Detach mode

- Detect with `spex-detach.sh is-enabled` (registry flag), not by checking whether the extension directory exists.
- `RUNBOOK.md` and `.walkthrough/` never enter git. After writing them, confirm with `git check-ignore`. If the configured exclude paths do not cover them, add them to `.git/info/exclude` (local, never committed) and tell the user. Never touch the tracked `.gitignore`.
- The status helper reads the file on disk, so finish, verify, and the status line behave the same.
- The finish archive step copies `RUNBOOK.md` along with the other spec artifacts.
- **Bug fix included:** with detach on, worktree setup copies the spec dir into the worktree, but nothing copies it back, so `finish` deletes all spec artifacts (including a drafted runbook) when it removes the worktree unless an archive path is configured. Before removing the worktree in detach mode, `finish` copies `specs/<feature>/` back to the main checkout, where it stays excluded.
- **Bug fix included:** finish's archive step uses the same faulty directory check; switch it to `is-enabled`.

### Secrets

Before quoting output into the runbook, redact anything that looks like a credential (tokens, passwords, keys) as `[redacted]`. Applies in both modes, since the file is committed in normal mode.

### Other consumers

- `verify` shows its reminder from the runbook status.
- The status line shows `WT ✓` or `WT 3/6` from the status block.

## Section 4: Scripts, removals, docs, testing

### New helpers (canonical in `spex/scripts/`, synced by `make sync-scripts`)

| Script | Job | Used by |
|---|---|---|
| `spex-runbook-status.sh <spec-dir>` | parse the status block, return JSON: status, steps done/total, drafted and tested commits, mode, whether code changed since (with changed files, ignoring `specs/`) | walkthrough, finish, verify, status line |
| `spex-runbook-fixture.sh` | `start` / `stop` / `status` for local processes and podman containers; `record` for remote fixtures with their teardown command; state in `.walkthrough/fixtures.json` | walkthrough |
| `spex-runbook-clip.sh` | copy a command via `pbcopy`, `wl-copy`, `xclip`, or `xsel`; distinct exit code when no clipboard exists | walkthrough |
| `spex-runbook-check.sh` | placeholders only inside fenced command blocks; credential-looking strings anywhere that were not redacted | walkthrough |

### Removed

- `spex-walkthrough-coverage.py`, `spex-walkthrough-workspace.sh`, `spex-walkthrough-lint.sh` (both copies) and their three tests.
- The `WALKTHROUGH.md` format and the `smoke_test_*` state reads in finish, verify, and the status line.
- Historical `SMOKE-TEST.md` and `WALKTHROUGH.md` files under `specs/` stay as history.

### Changed

- `speckit.spex.walkthrough.md`: rewritten from scratch with the command forms above.
- `speckit.spex.finish.md`: gate via status helper, drafted handling, `is-enabled` detach check, spec dir copy back before worktree removal in detach mode.
- `speckit.spex.ship.md`: draft at the end, closing message.
- `speckit.spex-gates.verify.md`, `spex-ship-statusline.sh`: read runbook status.
- `extension.yml`, `Makefile` (script lists, `test-walkthrough` target).
- Docs: README, both `help.md` files, the next-step hints in `review-code` and `deep-review`, CHANGELOG.

### Testing

- Script tests written first:
  - status: drafted, in progress, passed, failed; stale after a code change, not stale after a `specs/` only change (temporary git repo).
  - check: placeholder in a command block fails, the same text in prose passes, an unredacted token fails.
  - fixture: start and stop a short local process; podman container case skipped with a message when podman is not running; record a remote fixture.
  - clip: fake `pbcopy` on PATH; no-clipboard case.
- Real run: draft and run a light-mode runbook on a small real cc-spex feature and have the user judge whether it is understandable. Full mode is validated by the user on a project that needs a heavy fixture.

## Success Criteria

- A first-time viewer can read a runbook step and say what the feature does there and what good output looks like, before running anything.
- No step in a runbook shows a description of output in place of real output.
- A non-testable feature costs one line and no file.
- A runbook drafted by ship can be run after the merge from main.
- With detach enabled, no runbook or scratch file is ever committed, and a drafted runbook survives worktree removal.
- `finish` correctly recognizes a passed, current runbook and does not ask again.
