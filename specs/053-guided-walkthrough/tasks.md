---
description: "Task list for guided-walkthrough (pair testing)"
---

# Tasks: Guided Walkthrough (pair testing)

**Input**: Design documents from `specs/053-guided-walkthrough/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/scripts.md, quickstart.md
**Tests**: Included — the spec requires a `tests/` suite (FR-024/FR-025, SC-003/SC-005) and the helper scripts are unit-testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- Paths are repository-root-relative (plugin repo; no `src/` tree).

---

## Phase 1: Setup (structural)

- [X] T001 Rename `spex/extensions/spex/commands/speckit.spex.smoke-test.md` → `speckit.spex.walkthrough.md` via `git mv` and update its command registration in `spex/extensions/spex/extension.yml`
- [X] T002 [P] Add `specs/**/.walkthrough/` to `.gitignore` (FR-008)
- [X] T003 [P] Add `spex-walkthrough-workspace.sh spex-walkthrough-coverage.py spex-walkthrough-lint.sh` to `SCRIPTS_spex` in `Makefile` so `make sync-scripts` copies them into `spex/extensions/spex/scripts/`

---

## Phase 2: Foundational (helper scripts — blocks all stories)

**⚠️ The deterministic scripts (Constitution VII) are prerequisites for every user story.**

### Tests first (TDD — write failing tests before implementation)

- [X] T004 [P] Write `tests/test_walkthrough_workspace.sh`: asserts a persistent timestamped workspace is created under `specs/<feature>/.walkthrough/`, path is printed as `WORKSPACE_PATH`, and nothing is deleted (FR-007, FR-008, FR-009)
- [X] T005 [P] Write `tests/test_walkthrough_coverage.sh`: asserts stories parsed in priority order, FR→scenario map, orphan FRs, and `skip:true` only when no stories and no scenarios (FR-003, FR-004, FR-006)
- [X] T006 [P] Write `tests/test_walkthrough_lint.sh`: asserts non-zero exit on a doc containing placeholder tokens (`<scratch>`, `TODO`, `/path/to/`) and zero on a clean doc (FR-010, FR-025)

### Implementation (make the tests pass)

- [X] T007 [P] Implement `spex/scripts/spex-walkthrough-workspace.sh` per contracts/scripts.md (create/resolve/print workspace; never delete) (FR-007, FR-008, FR-009)
- [X] T008 [P] Implement `spex/scripts/spex-walkthrough-coverage.py` per contracts/scripts.md (parse stories+FRs, coverage, orphans, skip gate; `--json`) (FR-003, FR-004, FR-006)
- [X] T009 [P] Implement `spex/scripts/spex-walkthrough-lint.sh` per contracts/scripts.md (placeholder scan, token-reporting exit codes) (FR-010, FR-025)
- [X] T010 Run `make sync-scripts` and confirm T004–T006 pass against the synced scripts

**Checkpoint**: deterministic foundation ready; skill can delegate to it.

---

## Phase 3: User Story 1 - Walk scenarios against a real environment (Priority: P1) 🎯 MVP

**Goal**: Agent-driven walkthrough that previews each command, runs it, opens the real artifact, and pauses for the reviewer.

**Independent Test**: Run `/speckit-spex-walkthrough` on a feature with user stories; confirm priority-ordered scenarios, command preview before each run, inline artifact, and a pause for verdict.

- [X] T011 [US1] Rewrite the Overview/concept of `spex/extensions/spex/commands/speckit.spex.walkthrough.md` as a guided pair-testing walkthrough (navigator/driver framing), preserving the three honesty HARD-GATEs
- [X] T012 [US1] Add the scenario-synthesis section that delegates to `spex-walkthrough-coverage.py` and presents scenarios in user-story priority order (FR-001, FR-002)
- [X] T013 [US1] Implement the walkthrough loop: preview exact command before running (FR-011), infer commands from acceptance criteria + repo conventions (FR-011a), run and open the artifact inline (FR-012), pause for verdict (FR-013)
- [X] T014 [US1] Wire environment setup: create the run workspace via `spex-walkthrough-workspace.sh` and reuse `/run` for app startup (FR-007, D4)

**Checkpoint**: MVP — a reviewer can walk a feature and judge from real artifacts.

---

## Phase 4: User Story 2 - Reproduce and inspect after the fact (Priority: P1)

**Goal**: Persistent workspace + runnable commands + report with artifact pointers.

**Independent Test**: After a run, copy a reported command and run it verbatim; it reproduces the artifact against the persisted workspace.

- [X] T015 [US2] Implement the report section writing `WALKTHROUGH.md` (scenario-anchored, real commands, artifact pointers, who-ran, verdicts, coverage) on every exit path (FR-019, FR-020, FR-021)
- [X] T016 [US2] Enforce persistence and no-placeholders: print the workspace path + cleanup command, and run `spex-walkthrough-lint.sh` before finalizing (FR-009, FR-010, FR-025; SC-001/003/006)
- [X] T017 [US2] Rename the report artifact `SMOKE-TEST.md` → `WALKTHROUGH.md` everywhere it is read/written

**Checkpoint**: every verdict is independently reproducible.

---

## Phase 5: User Story 3 - Agent drives, reviewer intervenes (Priority: P2)

**Goal**: B-default execution with C-style delegation and takeover.

**Independent Test**: A step needing unavailable infra is delegated with its exact command; the reviewer can take over any step.

- [X] T018 [US3] Implement delegation: when the agent cannot run a step (enumerated triggers in FR-014) present the exact command and wait for the reviewer's observation
- [X] T019 [US3] Implement reviewer takeover of any step and record execution mode (agent-ran / reviewer-ran) per step (FR-015, FR-017)
- [X] T020 [US3] Implement the fail → investigate → offer-fix → retry loop (max 2 retries), recording both outcomes (FR-018)

**Checkpoint**: honest handling of steps the agent cannot run.

---

## Phase 6: User Story 4 - Honest coverage without silent skips (Priority: P2)

**Goal**: Story-driven synthesis, orphan reporting, narrow skip gate; remove the old keyword auto-skip.

**Independent Test**: A spec with "internal-looking" FRs still walks them via their story; uncovered FRs appear as orphans; a spec with no stories/scenarios skips honestly with a report.

- [X] T021 [US4] Implement the skip gate (no stories AND no scenarios) via the coverage script, writing a skip report (FR-006)
- [X] T022 [US4] Surface orphan FRs in the report's coverage section (FR-004)
- [X] T023 [US4] Remove the old observable/internal keyword classification and auto-skip from the skill (FR-005)

**Checkpoint**: nothing is silently excluded.

---

## Phase 7: Polish & Cross-Cutting

- [X] T024 Implement advisory + always-interactive behavior and the unattended-pipeline skip-with-notice (scenarios recorded deferred, pipeline continues); update the Stage 8 reference in `spex/extensions/spex/commands/speckit.spex.ship.md` and the reference in `speckit.spex.finish.md` to the new command/report names (FR-021a, FR-022, FR-023)
- [X] T025 [P] Preserve the three honesty HARD-GATEs and the partial-evidence disclaimer in the rewritten skill (FR-016)
- [X] T026 [P] Update `README.md` and `spex/docs/help.md` for the rename and new description (FR-023)
- [X] T027 [P] Add a CHANGELOG entry documenting the `smoke-test` → `walkthrough` rename (FR-023)
- [X] T028 Run `make test-generated-trees`, the new `tests/test_walkthrough_*.sh`, and the quickstart.md validation; confirm all pass

---

## Dependencies & Execution Order

- **Setup (T001–T003)**: no dependencies; T002/T003 are [P].
- **Foundational (T004–T010)**: tests (T004–T006 [P]) before implementation (T007–T009 [P]); T010 after both. Blocks all stories.
- **US1 (T011–T014)**: after Foundational. T011 before T012/T013; T013 depends on coverage (T008); T014 depends on workspace (T007).
- **US2 (T015–T017)**: after US1 loop exists; T016 depends on lint (T009).
- **US3 (T018–T020)**: after US1 loop exists; independent of US2.
- **US4 (T021–T023)**: after coverage (T008); largely independent of US2/US3.
- **Polish (T024–T028)**: after the stories whose behavior they reference; T028 last.

### Parallel opportunities

- T002, T003 together.
- All three foundational tests (T004, T005, T006) together; then all three implementations (T007, T008, T009) together.
- Docs tasks T025, T026, T027 together.
- US3 (T018–T020) and US4 (T021–T023) can proceed in parallel once US1 exists.

---

## Implementation Strategy

- **MVP = Phases 1–4** (Setup + Foundational + US1 + US2): a reproducible, inspectable walkthrough. Validate before continuing.
- **Increment**: add US3 (drive/delegate/takeover), then US4 (honest coverage), then Polish (rename cross-refs, advisory/unattended, docs, full test run).

## Notes

- [P] = different files, no dependencies.
- Deterministic logic lives in the three scripts (Constitution VII); the skill delegates.
- The walkthrough is advisory — no change to spex-gates.
