# Brainstorm: Guided Walkthrough (pair testing, replaces the Guided Demo smoke test)

**Date:** 2026-10-09
**Status:** ready for spec
**Origin:** The `speckit-spex-smoke-test` "Guided Demo" output is a narrated prose summary of flows with no runnable verification. A real run presented "Flow 1 of 7... Actual: folder tree plus config.md with..." and a single `verify yourself` command containing a `<scratch>` placeholder, so the human could not reproduce or inspect anything and could not seriously judge pass/fail.

## Problem Framing

The smoke test exists to catch the class of gaps that unit tests and DeepReview structurally cannot: things a human only notices by actually driving the software. The current skill defeats that purpose:

1. **Agent runs everything autonomously, then narrates.** Evidence is prose ("Actual: two bios saved with counts 325 and 761"), not artifacts the human can open.
2. **`verify yourself` commands are not runnable.** They contain placeholders (`--store <scratch>`) instead of the real paths the run used, and the scratch workspace is not persisted, so there is nothing to inspect after the fact.
3. **What gets tested is FR-keyword-driven.** Step 2 classifies each FR as observable/internal by keyword and auto-skips the internal ones, then groups observable FRs into flows. The auto-skip hides exactly the areas where human-only gaps live, and FR-shaped flows do not read like the user journeys a human would actually walk.

The result is a verdict the human must trust rather than verify.

## Decision

Full reframe (Approach "3b" from the brainstorm). Rebrand the skill to a **Guided Walkthrough / pair-testing** exercise, anchored on user stories, driven by the agent with the human inspecting at every checkpoint, against a persistent real environment. All decisions below are approved.

## What the skill becomes

The agent is the navigator, the human is the driver-of-record. Together they walk real user-story scenarios against a real, persistent environment. The agent sets up the environment, shows the exact command before running it, runs it, opens the resulting artifact for the human to read, and pauses for judgment. When the agent cannot run a step it hands the human the exact command; the human can take over any step.

### Naming (approved)

Rename the skill from `speckit-spex-smoke-test` ("Guided Demo") to **`speckit-spex-walkthrough`** ("Guided Walkthrough / Pair Testing"). A clean break is acceptable this early after 6.0.0 with few users. Rename blast radius:

- Command file `spex/extensions/spex/commands/speckit.spex.smoke-test.md` -> `speckit.spex.walkthrough.md`, and the generated skill dir
- Report artifact `SMOKE-TEST.md` -> `WALKTHROUGH.md`
- References in `speckit.spex.ship.md` (Stage 8), `speckit.spex.finish.md`, `help.md`, `README.md`, extension manifest
- CHANGELOG note documenting the rename for existing users

### Section B: Scenario synthesis (replaces current Step 2)

- **Primary input is User Stories**, walked in priority order (P1 first). Each story's **Independent Test** line and **Given/When/Then acceptance scenarios** become the scenario backbone: Given -> setup steps, When -> actions the pair drives, Then -> what they inspect and judge.
- **FRs become coverage tags, not the unit of synthesis.** After scenarios are built from stories, map FR-NNN onto the steps that exercise them so the report still shows FR coverage.
- **Drop the observable/internal auto-skip entirely.** Replace it with a narrow honest gate: skip only when the spec has no user stories and no acceptance scenarios at all (nothing to walk).
- **Orphan check:** any FR not touched by a story-derived scenario is reported as "not covered by a walkthrough scenario" rather than silently dropped.

### Section C: Environment and persistence

- Each run creates a **persistent, named workspace** at a printed path under the feature dir, gitignored but kept on disk, e.g. `specs/<feature>/.walkthrough/<timestamp>/`.
- **Nothing is auto-deleted.** Every command shown uses that real path; no `<scratch>` placeholders, ever. App *processes* started during the run are stopped at the end; *files/artifacts* persist. The report prints the workspace path and the single command to remove it when done.

### Section D: The walkthrough loop (B default, C intervention)

Per scenario, ordered steps derived from Given/When/Then. For each step:

1. **Preview (always):** the agent prints the exact command it is about to run, before running it.
2. **Default (B):** the agent runs it, opens the artifact inline (`cat` the file, `tail` the log, show the tree, screenshot via Playwright), states expected vs actual, and pauses for the human's read.
3. **Manual delegation (C):** when the agent cannot run a step (missing infra it cannot provision, interactive TUI, external credentials, GUI/visual judgment, anything outside the sandbox) it hands the human the exact command and waits for their observation.
4. **Takeover (C):** on any step the human can say "I'll drive this one" and the agent waits.
5. **Verdict** captured per scenario (with optional per-step notes). On fail: the existing investigate -> offer fix -> retry loop (max 2 retries) carries over.

### Section E: Report (`WALKTHROUGH.md`)

Scenario-anchored, user-story order. Per scenario: the steps, the real copy-pasteable commands against the persistent workspace, artifact pointers (file paths, log excerpts), expected vs actual, who ran each step (agent/human), tier, verdict plus notes. Top of file records the workspace path. Coverage section: user-story coverage + FR tags + orphan FRs.

### Section F: Integration and honesty gates

- Keep all three HARD-GATEs: always-interactive, no-simulated-tests, mandatory-report.
- Update ship Stage 8 and finish references to the new command name.
- The walkthrough is inherently human-in-the-loop, so even under `--ask never` it still blocks for a human (same stance as today). Note explicitly in the spec that a truly unattended pipeline cannot pair-test and will pause.

## Key Requirements (draft)

- Scenario synthesis anchored on User Stories (priority-ordered) with Given/When/Then backbone; FRs mapped as coverage tags; orphan FRs reported.
- Auto-skip removed; replaced by the "no stories and no scenarios" gate.
- Persistent, printed, gitignored run workspace; no placeholder paths anywhere; process cleanup without artifact deletion.
- Walkthrough loop: command preview before every run; B default with inline artifact opening; C manual delegation and per-step takeover; per-scenario verdicts; fail/fix/retry loop preserved.
- `WALKTHROUGH.md` report with real commands, artifact pointers, who-ran, tiers, and coverage.
- Rename across command file, skill dir, report artifact, ship/finish/help/README/manifest references, with a CHANGELOG note.
- Honesty HARD-GATEs preserved; pipeline still pauses for the human.
- Tests in `tests/` covering synthesis-from-stories, the no-stories skip gate, orphan-FR reporting, and persistence/no-placeholder guarantees.

## Open Questions

- Workspace location: `specs/<feature>/.walkthrough/<timestamp>/` vs a top-level ignored dir. Does the gitignore already cover it, or add a rule?
- Per-step verdicts vs per-scenario only: is scenario-level enough, or do some steps need their own pass/fail?
- How should the agent decide a step is "can't run" vs "should delegate for judgment" (the C triggers) in a way that is deterministic enough to be reliable?
- Retention policy: keep the last N run workspaces, or all until manually cleaned?
- Should the pipeline (ship Stage 8) skip the walkthrough with a clear "manual walkthrough required" note when no human is present, rather than blocking?
