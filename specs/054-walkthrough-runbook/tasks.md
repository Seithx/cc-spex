---
description: "Task list for 054-walkthrough-runbook"
---

# Tasks: Walkthrough as a Runbook

**Input**: Design documents from `specs/054-walkthrough-runbook/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/scripts.md, contracts/command.md, quickstart.md

**Tests**: Included. The brainstorm and plan require script tests written first (TDD): each script's test suite is written and seen failing before the script is implemented.

**Organization**: Tasks are grouped by user story. Scripts follow `contracts/scripts.md`; the command follows `contracts/command.md`; runbook structure follows `data-model.md`. Tests follow the style of `tests/test_spex_detach.sh` (temporary git repo, `assert_eq`, `assert_contains`, `Results: N passed, M failed`, non-zero exit on failure).

## Global Constraints

Every task inherits these (from spec.md, plan.md, and the constitution):

- Python helpers use the standard library only (no PyYAML); shell helpers are POSIX `sh` shims or Bash with `jq`.
- No new mandatory runtime dependencies beyond Python 3, git, `jq`, `yq`, `rsync`.
- Never modify the tracked `.gitignore` or `.git/info/exclude`; the only ignore file written is `specs/<feature>/.walkthrough/.gitignore` (FR-020, FR-038, Constitution III).
- Detach state is read only via `spex-detach.sh is-enabled`, never by checking the directory (FR-037).
- Containers use `podman` only.
- No remote or paid fixture is created without an explicit user yes (FR-018); no fixture starts without confirmation (FR-017).
- Command markdown uses harness-neutral wording and `{harness:interactive-choice}` markers; no agent-specific tool names (research R10).
- State and status are written only by scripts; command markdown never edits the runbook frontmatter or status line directly (Constitution VII).
- The walkthrough never blocks finish or ship.
- No em dash or en dash characters in any written file.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: User story from spec.md (US1 to US6)

---

## Phase 1: Setup

**Purpose**: Remove the 053 helpers and prepare build wiring.

- [X] T001 Delete `spex/scripts/spex-walkthrough-workspace.sh`, `spex/scripts/spex-walkthrough-coverage.py`, `spex/scripts/spex-walkthrough-lint.sh`, their copies in `spex/extensions/spex/scripts/`, and `tests/test_walkthrough_workspace.sh`, `tests/test_walkthrough_coverage.sh`, `tests/test_walkthrough_lint.sh` (FR-040)
- [X] T002 Update `Makefile`: in `SCRIPTS_spex` remove the three deleted helpers and add `spex-runbook-status.sh spex-runbook-status.py spex-runbook-check.sh spex-runbook-check.py spex-runbook-fixture.sh spex-runbook-clip.sh spex-finish-preserve-specs.sh`; in `SCRIPTS_spex_gates` add `spex-runbook-status.sh spex-runbook-status.py`; change the `test-walkthrough` target to run `tests/test_runbook_status.sh`, `tests/test_runbook_check.sh`, `tests/test_runbook_fixture.sh`, `tests/test_runbook_clip.sh`, `tests/test_finish_preserve_specs.sh` (each line prefixed with `@`)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The status and check scripts that every story depends on.

**CRITICAL**: No user story work starts until this phase is complete.

- [X] T003 [P] Write `tests/test_runbook_status.sh` covering: `fingerprint` is stable across a commit of the same content and across a squash (`git reset --soft` + commit); `fingerprint` ignores changes under `specs/` and `brainstorm/` but changes when a file under `spex/` changes or when an untracked non-ignored file appears; `locate --create` returns `specs/<f>/RUNBOOK.md` and creates `specs/<f>/.walkthrough/.gitignore` containing `*` so `git status --porcelain` shows nothing for the scratch folder; `init` writes frontmatter keys from data-model.md with status `drafted` and all results `pending`; `step` derivation per the data-model table (drafted, in_progress, failed wins over pending, passed with skips); `steps` extends and truncates; `mode light` after any non-pending result exits 1; `show` on a missing runbook returns `exists: false`; `show` returns `current: true` after a `specs/`-only change and `current: false` with `changed_files` after a code change; `show` reports `changed_since_draft: false` right after `init` and `true` after a code change even before any `step` call (FR-031), and still reports correctly after the drafted commit was squashed away (fingerprint comparison, `changed_files` empty with a note); `show` on broken frontmatter returns `readable: false` and `status: unreadable`; `show --no-git` returns `current: null`; the status line between the `<!-- runbook-status -->` markers is regenerated on every write. Run it and confirm it fails.
- [X] T004 [P] Write `tests/test_runbook_check.sh` covering: a complete runbook passes with `RUNBOOK_CHECK_PASS`; a step missing `**What you should see:**` fails with `RUNBOOK_CHECK_FAIL structure`; a step with `**Do:**` instead of `**Run:**` passes; `steps_total` not matching the number of `### Step N of M` headings fails with `frontmatter`; `<path>` inside a fenced command block fails with `placeholder`; the same `<path>` in prose passes; an unredacted `ghp_` token, an `AKIA` key, a JWT, and `password=` with a long value each fail with `secret`; `[redacted]` passes; missing file exits 2. Run it and confirm it fails.
- [X] T005 Implement `spex/scripts/spex-runbook-status.py` and POSIX shim `spex/scripts/spex-runbook-status.sh` (pattern of `spex/scripts/spex-ship-state.sh`) with subcommands `fingerprint`, `locate` (normal location only plus `--create`; detach relocation comes in US6), `init`, `step`, `steps`, `mode`, `show` per contracts/scripts.md, research R1 (temporary-index fingerprint excluding `specs/` and `brainstorm/`) and R2 (flat frontmatter, status line markers); stdlib only; make T003 pass
- [X] T006 Implement `spex/scripts/spex-runbook-check.py` and shim `spex/scripts/spex-runbook-check.sh` per contracts/scripts.md and research R8; make T004 pass
- [X] T007 Run `make sync-scripts` and `make sync-scripts-check`; confirm the new scripts appear in `spex/extensions/spex/scripts/` and the status script also in `spex/extensions/spex-gates/scripts/`

**Checkpoint**: Status and check scripts tested and synced.

---

## Phase 3: User Story 1 - Try a small feature with a light-mode runbook (Priority: P1) 🎯 MVP

**Goal**: A testable feature with no or quick fixtures gets a tutorial-style runbook, one setup question, and a transparent co-pilot session.

**Independent Test**: quickstart.md scenario 4.

### Tests for User Story 1

- [X] T008 [P] [US1] Write `tests/test_runbook_fixture.sh` covering: `start --kind process -- sleep 30` records the fixture with PID, log path, tier `quick`, owner `agent`, state `running`; starting the same name again exits 1; `status` refreshes state via `kill -0`; `stop --name` ends the process (TERM, then KILL after 5 s) and marks it `stopped`; `stop --quick` stops all quick fixtures; a container case using `podman run -d docker.io/library/alpine:3.20 sleep 30` that is skipped with a printed note when `podman info` fails, otherwise checks start, `status`, and `stop` (container removed); exit 4 when `--kind container` is used without podman. Run it and confirm it fails.
- [X] T009 [P] [US1] Write `tests/test_runbook_clip.sh` covering: with a fake `pbcopy` first on `PATH` that writes stdin to a temp file, the script prints `CLIP_OK tool=pbcopy` and the file holds the exact command; with `PATH` limited so none of the four tools exist, it prints `CLIP_UNAVAILABLE` and exits 3; empty stdin exits 2. Run it and confirm it fails.

### Implementation for User Story 1

- [X] T010 [P] [US1] Implement `spex/scripts/spex-runbook-fixture.sh` subcommands `start` (kinds `process`, `container`, `compose`), `stop`, `status` per contracts/scripts.md and research R6, state in `<scratch>/fixtures.json` via `jq`, logs in `<scratch>/fixtures/`; make T008 pass
- [X] T011 [P] [US1] Implement `spex/scripts/spex-runbook-clip.sh` per contracts/scripts.md and research R7; make T009 pass
- [X] T012 [US1] Rewrite `spex/extensions/spex/commands/speckit.spex.walkthrough.md` from scratch: frontmatter description and argument hint for the command forms in contracts/command.md; overview of purpose (trust through trying the feature); feature resolution via `spex-runbook-status.sh locate --create` and `show`; drafting rules: one end-to-end journey in real-user order, steps tagged `(US<k>)`, sections and step anatomy exactly as data-model.md (Why this step, Needs, Run with fenced block or Do, What you should see written before running, If you see something else, Result), prerequisites become their own steps, runtime values captured by commands, `## Coverage` and `## Not covered here` sections (FR-003 to FR-008, FR-004a); after writing, call `spex-runbook-status.sh init` and loop `spex-runbook-check.sh` until clean
- [X] T013 [US1] In `spex/extensions/spex/commands/speckit.spex.walkthrough.md`, add light mode: mode selection by heaviest fixture (FR-011), fixture discovery sources and reuse-first check (FR-015, FR-016), one `{harness:interactive-choice}` question approving runbook and quick fixtures together (FR-012, FR-017), quick fixtures via `spex-runbook-fixture.sh start` (podman for containers); the `## Test environment` section written from `spex-runbook-fixture.sh status` with how each fixture was set up, who started it, and its teardown command (FR-009); when `start` exits 4 (container runtime unavailable), report it with the command to start the runtime and offer to skip or hand over the affected steps; when the user declines a fixture, mark every step that needs it skipped with the reason via `spex-runbook-status.sh step <n> skipped` and note it in the step's Result
- [X] T014 [US1] In `spex/extensions/spex/commands/speckit.spex.walkthrough.md`, add the step session: per-step choices "run it yourself" (pipe the exact command to `spex-runbook-clip.sh`, fall back to showing it on exit 3), "let the agent run it" (omitted with the reason for browser steps without a browser automation tool, other GUI, interactive terminal programs, user-only credentials, actions outside the sandbox), "run the rest", "skip" (FR-021, FR-022, FR-024a); agent-run transparency: print the exact command before running, real output in full up to about 40 lines else saved to `<scratch>/step-N.log` with verbatim relevant lines, expected-versus-actual comparison per observation in the format of contracts/command.md (FR-023, FR-023a, FR-024); browser steps driven by a connected browser automation tool with screenshots (FR-021a); "run the rest" stops at the first mismatch, user-only step, or consent point
- [X] T015 [US1] In `spex/extensions/spex/commands/speckit.spex.walkthrough.md`, add mismatch handling (investigate, fix and retry only with an identified cause, record and continue, stop; no retry limit; FR-025), draft corrections recorded in the step (FR-026), recording each result with `spex-runbook-status.sh step` immediately (FR-027), credential redaction to `[redacted]` before writing output to the runbook (FR-028), and wrap-up: `## Results` summary, `spex-runbook-fixture.sh stop --quick`, final `spex-runbook-check.sh`, and the closing summary in the chat
- [X] T016 [US1] Run `make sync-scripts`, `make test-walkthrough`, and `make validate`; fix failures. Measure on this repository with a sample runbook: `time spex/scripts/spex-runbook-status.sh show --no-git <spec-dir>` must finish under 0.5 s and `time spex/scripts/spex-runbook-status.sh show <spec-dir>` under 3 s; optimize `spex-runbook-status.py` if not

**Checkpoint**: Light-mode walkthrough works end to end (MVP).

---

## Phase 4: User Story 2 - Nothing to try costs one line (Priority: P1)

**Goal**: Honest exit for non-testable features, with an override.

**Independent Test**: quickstart.md scenario 5.

- [X] T017 [US2] Extend `tests/test_runbook_status.sh` with: `not-testable` writes `walkthrough_not_testable_fingerprint` into an existing `.specify/.spex-state` and is a no-op without it; `show` on a spec dir without runbook reports `status: not_testable` when the recorded fingerprint matches the current one and `exists: false` with no `not_testable` after a code change. Run it and confirm the new cases fail.
- [X] T018 [US2] Implement `not-testable` and the `not_testable` reporting in `show` in `spex/scripts/spex-runbook-status.py`; make T017 pass
- [X] T019 [US2] In `spex/extensions/spex/commands/speckit.spex.walkthrough.md`, add the testability check before any file is written (FR-001): sources (spec, plan, quickstart, branch diff), the three outcomes, the one-line verdict format including the override hint, `spex-runbook-status.sh not-testable`, no runbook or scratch files on this path (FR-002), partly testable handling (FR-003), and `--force [what to try]` skipping the verdict and covering the hint (FR-002a)

**Checkpoint**: US1 and US2 together form the complete P1 scope.

---

## Phase 5: User Story 3 - Run a runbook drafted by ship, later (Priority: P2)

**Goal**: Ship leaves a drafted runbook that can be run from main after the merge.

**Independent Test**: quickstart.md scenario 6.

- [X] T020 [US3] Extend `tests/test_runbook_status.sh` with `list`: returns runbooks from several spec dirs (normal and `.walkthrough/` locations) with their status; empty array when none. Run it and confirm the new cases fail.
- [X] T021 [US3] Implement `list` in `spex/scripts/spex-runbook-status.py`; make T020 pass
- [X] T022 [US3] In `spex/extensions/spex/commands/speckit.spex.walkthrough.md`, add the command forms of contracts/command.md: `--draft` (phases 1 to 3 only, no prompts, no fixtures), feature identifier as number prefix or directory name (FR-029), picker on the default branch over `list` entries with status drafted, in_progress, or failed (FR-030), changed-since-draft check via `show` with refresh-affected-steps or run-as-is (FR-031), unattended detection (ship state `status: running` with `ask: never`) limiting to drafting, and the end-of-session commit offer on the default branch with a prepared `docs(<number>): walkthrough results` message, never pushing, not offered on feature branches or in detach mode (FR-030a)
- [X] T023 [US3] Update `spex/extensions/spex/commands/speckit.spex.ship.md`: replace the "Do NOT check for walkthrough scenarios..." paragraph with an instruction to invoke `/speckit-spex-walkthrough --draft` at the end of the pipeline at every ask level, before the post-pipeline prompt, and to include the drafted runbook line or the one-line not-testable verdict with override hint in the closing message (FR-032)

**Checkpoint**: Drafts survive the pipeline and are runnable later (detach-mode survival comes with US6).

---

## Phase 6: User Story 4 - Full mode for heavy environments (Priority: P2)

**Goal**: Review pause, tiered consent, external fixture records, teardown choice, resume.

**Independent Test**: on a feature needing a cluster, the review pause, consent with time and cost, reuse, fixture list, keep-or-teardown, and resume behave as in spec User Story 4.

- [X] T024 [US4] Extend `tests/test_runbook_fixture.sh` with: `record` adds an `external` fixture with tier, owner, teardown, and note; `stop --quick` never touches external fixtures; `keep` marks a fixture `kept`; `status` keeps external fixtures at state `unknown` unless kept. Run it and confirm the new cases fail.
- [X] T025 [US4] Implement `record` and `keep` in `spex/scripts/spex-runbook-fixture.sh`; make T024 pass
- [X] T026 [US4] In `spex/extensions/spex/commands/speckit.spex.walkthrough.md`, add full mode: review pause before anything runs with change and drop handling plus `spex-runbook-status.sh steps` after edits (FR-013); tiered consent: slow local with time estimate, remote or paid with what, duration, and possible cost stated and an explicit yes or hand-over of commands (FR-017, FR-018); `fixture record` for external fixtures; the `## Test environment` section kept in sync with `fixtures.json` (FR-009); at wrap-up keep-or-teardown for slow and remote with keep as default and teardown commands recorded (FR-019); upgrade from light to full via `spex-runbook-status.sh mode full` when setup turns out heavy, never downgrading (FR-014)
- [X] T027 [US4] In `spex/extensions/spex/commands/speckit.spex.walkthrough.md`, add resume: when `show` reports `in_progress`, offer continuing from the first pending step, offer restarting stopped quick fixtures, and check kept fixtures for availability before reuse (FR-027)

**Checkpoint**: Heavy-environment features are supported with explicit consent.

---

## Phase 7: User Story 5 - Finish and other commands use the result (Priority: P2)

**Goal**: finish, verify, and the status line read the runbook status; finish asks only when there is something to decide.

**Independent Test**: quickstart.md scenario 7.

- [X] T028 [US5] Rewrite Phase 1 of `spex/extensions/spex/commands/speckit.spex.finish.md` ("Walkthrough Gate"): replace the `smoke_test_*` state reads with `.specify/extensions/spex/scripts/spex-runbook-status.sh show <feature-dir>`; implement the interactive and unattended columns of the finish table in contracts/command.md (FR-033, FR-033a), including `not_testable` and `unreadable`; keep `--no-walkthrough`; remove the paragraph about retained `.smoke_test_*` keys
- [X] T029 [P] [US5] Update Step 0a of `spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md`: derive the reminder from `.specify/extensions/spex-gates/scripts/spex-runbook-status.sh show <feature-dir>` (remind when no runbook exists, or the runbook is not `passed`, and the feature is not `not_testable`); remove the `smoke_test_completed` read (FR-035)
- [X] T030 [P] [US5] Update `spex/scripts/spex-ship-statusline.sh`: replace the smoke-test indicator block with a `WT` indicator from `spex-runbook-status.sh show --no-git` on the state's `spec_dir` (passed `WT ✓` green, failed `WT ✗`, in_progress `WT <done>/<total>` yellow, drafted `WT ◌` dim, hidden when no runbook); resolve the status script next to the statusline script (FR-035)
- [X] T031 [US5] Run `make sync-scripts` and `make sync-scripts-check`; run `bash -n spex/scripts/spex-ship-statusline.sh`

**Checkpoint**: finish recognizes a passed walkthrough and stops asking.

---

## Phase 8: User Story 6 - Detach mode never stores runbooks in git (Priority: P2)

**Goal**: Correct detach detection, relocation when needed, and spec preservation on worktree removal.

**Independent Test**: quickstart.md scenario 8.

- [X] T032 [P] [US6] Extend `tests/test_runbook_status.sh` with `locate` in a repo with a stub `.specify/extensions/spex-detach/scripts/spex-detach.sh` that exits 0 or 1 for `is-enabled`: detach off returns `detach: false`, `relocated: false`; detach on with `specs/` in `.git/info/exclude` returns the normal path; detach on without the exclusion returns `specs/<f>/.walkthrough/RUNBOOK.md` and `relocated: true`; the detach directory without the script returns `detach: false`; `show` and `list` find relocated runbooks. Run it and confirm the new cases fail.
- [X] T033 [P] [US6] Write `tests/test_finish_preserve_specs.sh` covering: with the detach stub reporting enabled, the feature dir is copied from a worktree to the main checkout (existing files updated, extra files in main kept) and `PRESERVED` is printed; with detach disabled `PRESERVE_SKIPPED reason=detach-off` and nothing copied; missing feature dir prints `PRESERVE_SKIPPED reason=no-spec-dir`; missing arguments exit 2. Run it and confirm it fails.
- [X] T034 [US6] Implement detach detection (`is-enabled` via `.specify/extensions/spex-detach/scripts/spex-detach.sh`, missing script means disabled) and relocation via `git check-ignore` in `locate`, and the second location in `show` and `list`, in `spex/scripts/spex-runbook-status.py` (FR-037, FR-038); make T032 pass
- [X] T035 [US6] Implement `spex/scripts/spex-finish-preserve-specs.sh` per contracts/scripts.md and research R9; make T033 pass
- [X] T036 [US6] Update `spex/extensions/spex/commands/speckit.spex.finish.md`: replace `[ -d ".specify/extensions/spex-detach" ]` in Step 1.5 with the `is-enabled` check (FR-037); call `.specify/extensions/spex/scripts/spex-finish-preserve-specs.sh "$WORKTREE_PATH" "$MAIN_WORKTREE" "$FEATURE_DIR"` before every `git worktree remove` in Option A and in the Option B worktree cleanup (FR-039)
- [X] T037 [US6] In `spex/extensions/spex/commands/speckit.spex.walkthrough.md`, state that the runbook path always comes from `locate`, that a relocated runbook is announced to the user with the reason, and that the walkthrough never edits `.gitignore` or `.git/info/exclude` (FR-038)
- [X] T038 [US6] Run `make sync-scripts`, `make sync-scripts-check`, and `make test-walkthrough`

**Checkpoint**: All user stories complete.

---

## Phase 9: Polish & Cross-Cutting Concerns

- [X] T039 [P] Update `spex/extensions/spex/extension.yml`: `speckit.spex.walkthrough` description to describe the runbook (testability check, tutorial-style steps, co-pilot session, draft for later)
- [X] T040 [P] Update `README.md`: the `/speckit-spex-walkthrough` and `/speckit-spex-finish` rows of the Commands Reference table and any workflow text mentioning `WALKTHROUGH.md` (FR-041)
- [X] T041 [P] Update `spex/docs/help.md` and `spex/extensions/spex/docs/help.md`: walkthrough entry (forms `--draft`, `--force`, `<feature>`; `RUNBOOK.md`; light and full mode), finish gate description, ship drafting a runbook (FR-041)
- [X] T042 [P] Update the next-step hints in `spex/extensions/spex-gates/commands/speckit.spex-gates.review-code.md` and `spex/extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md` to "try the feature with a runbook" wording (FR-041)
- [X] T043 [P] Add an Unreleased entry to `CHANGELOG.md` describing the rework, the removed helpers, the `RUNBOOK.md` artifact replacing `WALKTHROUGH.md`, and the two fixed bugs (completion never recorded; detach-mode spec loss on worktree removal) (FR-041)
- [X] T044 Run `rg -n 'smoke_test_|WALKTHROUGH\.md|spex-walkthrough-(workspace|coverage|lint)' spex/ README.md Makefile` and remove remaining references outside `spex/docs/sync-reports/` and CHANGELOG history (FR-040)
- [X] T045 Run `make test-walkthrough`, `make sync-scripts-check`, `make validate`, and `make test-generated-trees`; fix failures
- [X] T046 Run quickstart.md scenarios 2, 3, and 5 locally and record results in the session; prepare scenario 4 (light-mode real run) for the user to judge

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none
- **Foundational (Phase 2)**: after Setup; blocks all stories
- **US1 (Phase 3)**: after Foundational
- **US2 (Phase 4)**: after Foundational; edits the same command file as US1, so sequence after T015
- **US3 (Phase 5)**: after US1 (command file); T020 and T021 can start right after Foundational
- **US4 (Phase 6)**: after US1 (command file and fixture script)
- **US5 (Phase 7)**: after Foundational; independent of the command file, so it can run in parallel with US1 to US4
- **US6 (Phase 8)**: T032 to T035 after Foundational; T036 after T028 (same finish file); T037 after US1
- **Polish (Phase 9)**: after all stories

### Within Each Story

- Tests written and seen failing before the implementation that makes them pass
- Script changes before command markdown that relies on them
- `make sync-scripts` after script changes

### Parallel Opportunities

- T003 and T004 (different test files)
- T008, T009, T010, T011 (fixture and clip are independent scripts)
- US5 tasks T029 and T030 alongside US1 work
- US6 script tasks T032 to T035 alongside US3 and US4 command work
- Polish T039 to T043

## Parallel Example: User Story 1

```text
Task: "Write tests/test_runbook_fixture.sh" (T008)
Task: "Write tests/test_runbook_clip.sh" (T009)
then
Task: "Implement spex/scripts/spex-runbook-fixture.sh" (T010)
Task: "Implement spex/scripts/spex-runbook-clip.sh" (T011)
```

## Implementation Strategy

### MVP First

1. Phases 1 and 2 (setup, status and check scripts)
2. Phase 3 (US1): light-mode runbook session
3. Phase 4 (US2): honest not-testable exit
4. Stop and validate with quickstart scenarios 4 and 5: this is the user-visible core and the answer to the original complaint

### Incremental Delivery

5. US5 (finish integration) so the result is recognized
6. US3 (ship draft, run later)
7. US6 (detach safety) before anyone uses it in a detach project
8. US4 (full mode)
9. Polish, then the user-judged real run
