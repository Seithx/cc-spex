---
description: "Guided Walkthrough (pair testing): story-anchored, agent-driven walkthrough against a real environment with runnable, reproducible evidence"
---

# Guided Walkthrough (speckit-spex-walkthrough)

## Overview

Pair-test a completed feature with the reviewer. You (the agent) are the **navigator**: you synthesize scenarios from the spec's user stories, set up a real environment, and for each step you preview the exact command, run it, open the real artifact it produced, and pause. The reviewer is the **driver-of-record**: they judge each step from evidence they can see and reproduce, and they can take over any step at will.

The whole point is to put a human in contact with real, running behavior and catch the class of gaps that unit tests and code review structurally cannot. That only works if every verdict is backed by an artifact the reviewer can inspect and a command they can re-run verbatim. So this skill never narrates a summary in place of real output, and never presents a command the reviewer cannot copy and run.

Scenarios come from the spec's **user stories** (in priority order), with each story's Given/When/Then acceptance scenarios as the backbone. Functional requirements are mapped onto the steps that exercise them; requirements no scenario touches are reported as **orphans**, never dropped. The walkthrough is **advisory**: a FAIL is recorded but never hard-blocks `finish` or `ship` (FR-021a).

Results are persisted as `WALKTHROUGH.md` in the spec directory, written on every exit path.

### Deterministic helpers (Constitution VII)

The deterministic work lives in three scripts; this skill delegates to them and never re-implements their logic inline:

- `spex-walkthrough-workspace.sh <spec-dir> [--new]` — create/resolve the persistent run workspace; prints `WORKSPACE_PATH <abs>`; never deletes (FR-007/008/009).
- `spex-walkthrough-coverage.py <spec-file> --json` — user stories in priority order, their scenarios, FR→story coverage, orphan FRs, and the skip gate (FR-003/004/006).
- `spex-walkthrough-lint.sh <file-or-dir>` — fail if any presented/reported command contains a placeholder token (FR-010/025).

Resolve each script from the extension's installed `scripts/` dir, falling back to the canonical repo path:

```bash
WS_SCRIPT=".specify/extensions/spex/scripts/spex-walkthrough-workspace.sh"
COV_SCRIPT=".specify/extensions/spex/scripts/spex-walkthrough-coverage.py"
LINT_SCRIPT=".specify/extensions/spex/scripts/spex-walkthrough-lint.sh"
[ -f "$WS_SCRIPT" ]  || WS_SCRIPT="spex/scripts/spex-walkthrough-workspace.sh"
[ -f "$COV_SCRIPT" ] || COV_SCRIPT="spex/scripts/spex-walkthrough-coverage.py"
[ -f "$LINT_SCRIPT" ] || LINT_SCRIPT="spex/scripts/spex-walkthrough-lint.sh"
```

<HARD-GATE>
## No Simulated Tests

You MUST NOT simulate, fake, or hand-reproduce what the system under test would do. Every step must exercise the actual system (run the real command, call the real API, invoke the real skill). If a step cannot be genuinely executed by either party, record it honestly as **skipped** or **manual** with real reasoning, never as a pass. If a step runs without full infrastructure, present the real proxy evidence (dry-run output, request payloads, logs) with an explicit **partial-evidence disclaimer** stating what it does and does not prove (FR-016).

A simulated step that edits files to mimic system output is worse than no step. It creates false confidence.
</HARD-GATE>

<HARD-GATE>
## Always Interactive

The walkthrough is ALWAYS interactive and ALWAYS requires a human, regardless of the pipeline's `--ask` level (FR-022). No `--ask never` can auto-pass a step. When no human is available (an unattended pipeline), you do not fake the walkthrough: you skip it with a clear "manual walkthrough required" notice, record every scenario as **deferred**, write the report, and let the pipeline continue (see Unattended Pipeline below). You never block indefinitely or fail the stage.
</HARD-GATE>

<HARD-GATE>
## Mandatory Report

You MUST write `WALKTHROUGH.md` and output the results report on EVERY exit path, including honest skips, early exits, and unattended pipeline runs (FR-021, SC-004). A walkthrough whose results a human never sees is worthless.
</HARD-GATE>

## Prerequisites

### Spec resolution

```bash
PREREQS=$(.specify/scripts/bash/check-prerequisites.sh --json --paths-only 2>/dev/null)
FEATURE_DIR=$(echo "$PREREQS" | jq -r '.FEATURE_DIR')
SPEC_FILE="$FEATURE_DIR/spec.md"
```

If the spec cannot be resolved, report the error and exit (no report needed; there is no feature to walk).

### Pipeline and attendance detection

```bash
PIPELINE_MODE=false
ASK="always"
if [ -f ".specify/.spex-state" ]; then
  STATUS=$(jq -r '.status // empty' .specify/.spex-state 2>/dev/null)
  ASK=$(jq -r '.ask // "always"' .specify/.spex-state 2>/dev/null)
  [ "$STATUS" = "running" ] && PIPELINE_MODE=true
fi
# Unattended = running inside a pipeline with no human to answer (ask never).
UNATTENDED=false
if [ "$PIPELINE_MODE" = true ] && [ "$ASK" = "never" ]; then
  UNATTENDED=true
fi
```

In pipeline mode, complete the walkthrough and return without a "Shall I proceed?" prompt. Never suppress the results report.

## Step 1: Synthesize scenarios from user stories (FR-001, FR-002, FR-005)

Run the coverage helper and read its JSON. Do NOT classify requirements as "observable" vs "internal-only" and do NOT auto-skip on that basis — that keyword heuristic is removed (FR-005).

```bash
COVERAGE=$(python3 -I "$COV_SCRIPT" "$SPEC_FILE" --json)
SKIP=$(echo "$COVERAGE" | jq -r '.skip')
```

The JSON gives you, in user-story priority order:

- `stories[]`: `{id, title, priority, scenarios[], frs[]}`
- `fr_coverage`: `{FR-NNN: [US...]}`
- `orphan_frs`: FRs no story-derived scenario exercises (FR-004)

Build one walkthrough scenario per user story, **in the order the script returns them** (P1 first). For each, turn the story's Given/When/Then acceptance scenarios into steps (FR-002):

- **Given** → environment setup for the scenario
- **When** → the driven action(s)
- **Then** → the inspection and the reviewer's judgment

### Honest skip gate (FR-006)

If `SKIP` is `true` (no user stories AND no acceptance scenarios), there is genuinely nothing to walk. Write a skip report (Step 6) recording the reason and the orphan FRs, display it, and exit. In pipeline mode, return so the pipeline proceeds.

## Step 2: Set up the real environment (FR-007, D4)

Create the persistent run workspace and keep its path for every command and the report:

```bash
WS_OUT=$(bash "$WS_SCRIPT" "$FEATURE_DIR" --new)
# Strip the "WORKSPACE_PATH " prefix only — do NOT split on whitespace, so a
# workspace path that contains spaces (common on macOS, e.g. ~/My Project/...)
# is preserved intact.
WS_LINE=$(printf '%s\n' "$WS_OUT" | grep '^WORKSPACE_PATH ')
WORKSPACE=${WS_LINE#WORKSPACE_PATH }
echo "Run workspace: $WORKSPACE"
```

`$WORKSPACE` is a real, gitignored directory that persists after the run. Use it for every file a step creates, so every command you present carries a concrete path (no placeholders). Always wrap it in double quotes (`"$WORKSPACE"`) in every command.

Immediately write a skeleton report so an abnormal exit still leaves a truthful record (FR-021, SC-004):

```bash
# After Step 1 synthesis + workspace creation, write WALKTHROUGH.md with every
# synthesized scenario marked INCOMPLETE and the full Coverage section populated
# from the Step 1 JSON. Each scenario verdict overwrites its INCOMPLETE marker as
# the loop progresses, and Step 5 finalizes the report.
```

For app startup and browser steps, **reuse the `/run` skill** when available (do not re-implement project-type detection). When it is not available, degrade to delegated manual steps (Step 4). If you start an app, **persist its PID and port to the workspace** so cleanup (Step 7) works even though each command runs in a fresh shell:

```bash
# After the app is up, record PID and port in the run workspace:
printf '%s %s\n' "$APP_PID" "$APP_PORT" > "$WORKSPACE/.app.pid"
# If /run does not surface a PID, discover it by the port the app listens on:
#   APP_PID=$(lsof -ti :"$APP_PORT" 2>/dev/null)
# If neither a PID nor lsof is available, tell the reviewer the exact process/port
# to stop manually rather than silently skipping cleanup.
```

**Stale process on a known port**: before starting an app, if a process already holds the port, ask before killing it (it may be unrelated work) rather than assuming it is yours.

## Step 3: The walkthrough loop (FR-011, FR-011a, FR-012, FR-013)

For each scenario (priority order), announce it, then for each step:

1. **Infer the concrete command** from the step's acceptance criteria (Given/When/Then) plus the repository's conventions — entry points, README, Makefile, and the `/run` skill when available (FR-011a). There is no author-declared command list; the command preview is the safeguard against mis-inference.

2. **Preview the exact command before running it** (FR-011). Show it verbatim, with the real `$WORKSPACE` path and concrete arguments — never a placeholder like `<scratch>`, `<path>`, or `/path/to/`:

   ```
   ### Step N: <intent from Given/When/Then>
   About to run:
       <exact runnable command>
   ```

3. **Run it yourself** (default), then **open the resulting artifact inline** (FR-012): file contents, a log excerpt, a directory tree, or a screenshot. Show the real output, do not narrate a summary of it.

4. **State expected vs actual**, quoting the spec's requirement or acceptance scenario for "expected":

   ```
   - Command: `<exact runnable command>`
   - Ran by: agent
   - Expected: <from spec>
   - Actual: <what the artifact shows>
   - Artifact: <path or inline excerpt>
   ```

   For a step run without full infrastructure, add a **partial-evidence disclaimer** (FR-016): what the proxy evidence proves and what it cannot.

5. **Pause and wait for the reviewer's judgment before the next step** (FR-013). Present a verdict choice (your evidence-based recommendation first):
   - **Pass** — behavior matches
   - **Fail** — does not match (triggers the retry loop, Step 3b)
   - **Skip** — cannot verify now
   - **Run manually** — reviewer will drive it

When all steps of a scenario are judged, record the **scenario verdict** (pass / fail / skip / manual / deferred) with optional per-step notes, and record **who ran each step** (agent or reviewer) (FR-017).

### Step 3a: Delegation and takeover (FR-014, FR-015)

**Delegate** a step to the reviewer — present the exact command and wait for their observation — when you cannot run it yourself. Delegation triggers include at least:

- infrastructure you cannot provision
- interactive terminal (TUI) programs
- required external credentials
- GUI / visual judgment
- any action outside the execution sandbox

**Takeover**: the reviewer may claim any step at any time. When they do, yield, show the command, and wait for their result. Record the step's execution mode as reviewer-ran in both cases.

Never fake a delegated step's result. If neither party can run it, record it as skip/manual with honest reasoning (No Simulated Tests gate).

### Step 3b: Fail → investigate → fix → retry (FR-018)

When a step's verdict is **fail**:

1. Offer to investigate (analyze the artifact, compare expected vs actual, read the relevant source/logs/config).
2. If a cause is found, offer to apply a fix.
3. After a fix, offer to retry the step from scratch with fresh evidence.
4. Record both the initial failure and the retry outcome.
5. **At most 2 retries per scenario.** After two unsuccessful retries, record the failure and move on.

A FAIL is advisory: it is recorded, it does not hard-block `finish`/`ship` (FR-021a). The reviewer decides whether to fix or proceed knowingly.

## Step 4: Unattended pipeline (FR-022)

If `UNATTENDED` is true (pipeline with `ask never`, no human present):

- Do NOT run the interactive loop.
- Print a clear **"manual walkthrough required"** notice.
- Record every synthesized scenario with verdict **deferred**.
- Write `WALKTHROUGH.md` (Step 5) and display it.
- Return so the pipeline continues. Do not block, do not fail the stage.

## Step 5: Write the report (FR-019, FR-020, FR-021)

Write `$FEATURE_DIR/WALKTHROUGH.md`, scenario-anchored and ordered by user-story priority. Overwrite any previous report (each run is a fresh validation). Required structure:

```markdown
# Walkthrough Report

**Feature**: <name from spec title>
**Date**: <YYYY-MM-DD>
**Workspace**: <absolute workspace path>   (remove with: `rm -rf <absolute workspace path>`)
**Result**: N passed, M failed, K skipped, J manual, D deferred

## Scenario 1: <title> (P1, from US1)
**Verdict**: PASS
### Step 1: <intent>
- Command: `<exact runnable command>`
- Ran by: agent | reviewer
- Expected: <...>
- Actual: <...>
- Artifact: <path or excerpt>
<partial-evidence disclaimer, if any>
...

## Coverage
### User stories
| Story | Scenario | Verdict |
| US1 | Scenario 1 | PASS |
### Functional requirements
| FR | Covered by | Verdict |
| FR-001 | Scenario 1 | PASS |
### Orphan FRs
- FR-030 (not covered by any scenario)
```

Every FR from the spec MUST appear here either as covered (with its scenario) or as an orphan — none silently absent (FR-020, SC-005). Pull `fr_coverage` and `orphan_frs` from the Step 1 JSON.

### Enforce persistence and no placeholders (FR-009, FR-010, FR-025)

Before finalizing:

1. Print the workspace path and the exact cleanup command (`rm -rf <absolute workspace path>`). Do NOT auto-delete the workspace; only stop any app process you started (Step 7).
2. Run the lint gate over the report and fail-closed on any placeholder:

   ```bash
   bash "$LINT_SCRIPT" "$FEATURE_DIR/WALKTHROUGH.md"
   ```

   If it prints `WALKTHROUGH_LINT_FAIL`, a presented/reported command still has a placeholder. Resolve it to the concrete value actually used and rewrite the report before finishing (SC-003).

## Step 6: Skip report

For the honest-skip gate (Step 1, `skip: true`) or an unattended run, write the same `WALKTHROUGH.md` with:

- **Result**: Skipped (no user stories and no acceptance scenarios) — or — Deferred (unattended pipeline, manual walkthrough required)
- Each scenario (if any) listed with verdict SKIP or DEFERRED and the reason
- The Coverage section still listing every FR as covered-or-orphan

This satisfies SC-004 (a report on every exit) and still runs the lint gate.

## Step 7: Cleanup (processes only — never the workspace)

**Applies at ANY exit point**, not just success.

- If you started an app process, stop it. Read the persisted PID/port (independent of in-memory shell state) and escalate SIGTERM → wait up to 5s → SIGKILL:

  ```bash
  if [ -f "$WORKSPACE/.app.pid" ]; then
    read -r APP_PID APP_PORT < "$WORKSPACE/.app.pid"
    kill -TERM "$APP_PID" 2>/dev/null
    sleep 5
    kill -0 "$APP_PID" 2>/dev/null && kill -KILL "$APP_PID" 2>/dev/null
    rm -f "$WORKSPACE/.app.pid"
  fi
  ```

  Report the outcome. If no PID file exists and `lsof` is unavailable, tell the reviewer which process/port to stop manually rather than silently skipping.
- If the reviewer started the app manually, do NOT stop it.
- **Never delete the run workspace or its artifacts** (FR-009). It persists for reproduction; the report prints the cleanup command for the reviewer to run when they choose.

## Step 8: Results display (MANDATORY on every exit)

After cleanup, always print the results to the console (including pipeline and unattended mode):

```
═══════════════════════════════════════════════════════
WALKTHROUGH RESULTS
═══════════════════════════════════════════════════════

Feature: <name>
Date: <YYYY-MM-DD>
Status: <COMPLETE | SKIPPED | DEFERRED (unattended) | INCOMPLETE (early exit)>
Workspace: <absolute path>   (remove with: rm -rf <absolute path>)

Scenarios:
  1. <verdict> <title> [P1, US1]   steps: agent-ran X, reviewer-ran Y
     <one-line evidence pointer>
  ...

Coverage: <C> FRs covered, <O> orphan(s): FR-030, ...
Summary: N passed, M failed, K skipped, J manual, D deferred
Full report: <path to WALKTHROUGH.md>

═══════════════════════════════════════════════════════
```

In pipeline mode, still suppress "Shall I proceed?" and next-step suggestions, but NEVER suppress this report.

## Integration

**Invoked by:**
- Users directly via `/speckit-spex-walkthrough`
- The finish command via `/speckit-spex-finish` (the walkthrough gate)
- The ship pipeline via `/speckit-spex-ship` (which routes the walkthrough through finish)

**Invokes:**
- `.specify/scripts/bash/check-prerequisites.sh` (spec resolution)
- `spex-walkthrough-workspace.sh`, `spex-walkthrough-coverage.py`, `spex-walkthrough-lint.sh` (deterministic helpers)
- Optionally: the `/run` skill (app startup) and Playwright MCP (browser steps)
