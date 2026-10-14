# Tasks: Merge stamp into finish

**Input**: Design documents from `specs/055-merge-stamp-finish/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included for the new script (shell test, project convention) and for the existing marketplace install test.

**Organization**: Tasks are grouped by user story so each story can be implemented and tested on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story the task belongs to (US1 to US4)

---

## Phase 1: Setup

- [X] T001 Register `spex-verify-record.sh` in `Makefile`: append it to `SCRIPTS_spex` and `SCRIPTS_spex_gates`, and add `@tests/test_verify_record.sh` to the `test-walkthrough` target

---

## Phase 2: Foundational (blocks all stories)

**Purpose**: The verification record script (FR-009c, FR-009d), used by verify, finish, and both reminder hooks.

- [X] T002 Write `tests/test_verify_record.sh` (executable, same harness style and `=== Results: N passed, M failed ===` footer as `tests/test_runbook_status.sh`) covering, in a temp git repo: `check` with no record is `missing`/exit 1; `record --feature specs/x` then `check` is `verified`/exit 0; committing the recorded content keeps `verified`; editing a file under `specs/` or `brainstorm/` keeps `verified`; editing a code file makes `stale`/exit 1; `check --feature specs/other` against a record for `specs/x` is `stale`; garbage JSON in the record is `unreadable`/exit 1; `path` is inside `git rev-parse --git-dir` (and inside `.git/worktrees/<name>/` for a linked worktree); writing the record does not change the fingerprint; `clear` removes it and prints `VERIFY_CLEARED`; unknown subcommand exits 2; outside a git repo `check` exits 2. Run it and confirm it fails
- [X] T003 Implement `spex/scripts/spex-verify-record.sh` (POSIX sh, `jq`) per `contracts/spex-verify-record.md` and `data-model.md`: subcommands `record [--feature D]`, `check [--feature D]`, `path`, `clear`; record file at `$(git rev-parse --git-path spex-verified.json)` resolved to an absolute path; fingerprint via `spex-runbook-status.sh fingerprint` resolved from the script's own directory; atomic write (temp file plus `mv`); JSON fields `version`, `fingerprint`, `head`, `feature`, `verified_at`; exit codes 0/1/2 as specified. Make it executable and run `tests/test_verify_record.sh` until it passes
- [X] T004 Run `make sync-scripts` so `spex/extensions/spex/scripts/` and `spex/extensions/spex-gates/scripts/` contain `spex-verify-record.sh`, then `make sync-scripts-check`

**Checkpoint**: `tests/test_verify_record.sh` passes; the script is present in both extensions.

---

## Phase 3: User Story 1 - Finish refuses to land unverified code (P1) MVP

**Goal**: Finish runs verify first and stops on failure (FR-001, FR-002, FR-003, FR-009, FR-009a, FR-009b, FR-016).

**Independent Test**: On a branch with a failing test, finish prints `Finish stopped: verification did not pass.` with the failing gate and leaves the branch unchanged; after fixing, it prints `Verification passed.` and reaches the walkthrough gate.

- [X] T005 [US1] In `spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md`: add an `## Arguments` section parsing `--embedded` and an optional spec path argument; in Spec Selection, when a spec path is given use it and set `FEATURE_DIR` to its directory (relative to the repo root, e.g. `specs/055-x`), otherwise use `check-prerequisites.sh` or the picker and set `FEATURE_DIR` from the chosen spec; in step 7 replace the `touch "${TMPDIR:-/tmp}/.claude-spex-verified-${SESSION_ID}"` marker with `"$RECORD" record --feature "$FEATURE_DIR"` where `RECORD=.specify/extensions/spex-gates/scripts/spex-verify-record.sh` (fallback `spex/scripts/spex-verify-record.sh`), so the recorded feature is exactly the spec dir that was verified; state that a failed or interrupted run never records; in step 8 skip the celebration banner and the `rm -f .specify/.spex-state` when `--embedded` is set; when no spec resolves and the run is unattended (ship guard autonomous), report `no spec` instead of showing the picker (interactive runs keep the picker)
- [X] T006 [US1] In `spex/extensions/spex/commands/speckit.spex.finish.md`: update the frontmatter `description` to "Verify + walkthrough + squash + merge/keep (land the code on main)" and `argument-hint` to `[--auto] [--no-verify] [--no-walkthrough] [--skip-archive]`; parse `--no-verify` into `SKIP_VERIFY`; retitle the command heading accordingly; insert `## Phase 0: Verification` before `## Pre-Execution Checks` (so `before_finish` hooks run after it) implementing the `contracts/finish-verify-phase.md` table rows for: resolve `FEATURE_DIR` once (state `spec_dir`, else `.specify/feature.json` `feature_directory`, else `specs/<branch>`) and reuse that same value in Phase 1 Step 2 instead of re-deriving it; treat `[ ! -f "$FEATURE_DIR/spec.md" ]` as the "no spec resolvable" row; invoke `/speckit-spex-gates-verify --embedded "$FEATURE_DIR/spec.md"` so verify records the same feature finish checks; gate PASS prints `Verification passed.`, gate FAIL prints the exact stop message with one line per failing gate and the evolve and `--no-verify` lines, `no spec` and `did not complete` stop messages; state that on any stop nothing is squashed, committed, or switched and `.spex-state` is untouched, and that unattended mode follows the same table without prompts
- [X] T007 [P] [US1] In `spex/extensions/spex/commands/speckit.spex.submit.md` Phase 1: invoke `/speckit-spex-gates-verify --embedded` instead of the bare command, noting that this keeps `.spex-state` for the later watch phase

**Checkpoint**: finish contains Phase 0 with the PASS/FAIL/no-spec/incomplete rows; verify supports `--embedded`.

---

## Phase 4: User Story 2 - No duplicate verification and explicit skip (P2)

**Goal**: A recorded pass for the current content skips re-verification; `--no-verify` skips explicitly; the reminder hooks use the same record (FR-004, FR-005, FR-006, FR-007, FR-011, FR-011a, FR-014).

**Independent Test**: `spex-verify-record.sh record` then a commit attempt shows no reminder; finish prints `Verification already passed for this code.`; a code edit brings the reminder back.

- [X] T008 [US2] In `spex/extensions/spex/commands/speckit.spex.finish.md` Phase 0: add the first two table rows ahead of the verify invocation: `--no-verify` prints `Verification skipped (--no-verify).`; `"$RECORD" check --feature "$FEATURE_DIR"` exit 0 prints `Verification already passed for this code.` (resolve `RECORD` from `.specify/extensions/spex/scripts/spex-verify-record.sh`, fallback `spex/scripts/spex-verify-record.sh`); in Phase 3 Step 1 (commit outstanding changes) and Step 6 (execute squash) add the FR-011a note that finish's own commits do not stop to confirm the pre-commit verification reminder when Phase 0 passed, found a recorded pass, or `--no-verify` was given (Step 5, where the user approves the squash message, is unchanged); state that `--no-verify` combines with `--no-walkthrough`, `--auto`, and `--skip-archive`
- [X] T009 [P] [US2] In `spex/scripts/hooks/pretool-gate.py` `check_verification_gate`: replace the `marker_path('spex-verified', session_id).exists()` check with a call to `spex-verify-record.sh check` (path `Path(__file__).resolve().parent.parent / 'spex-verify-record.sh'`, fallback `Path(cwd) / '.specify/extensions/spex-gates/scripts/spex-verify-record.sh'`, run with `cwd=cwd`, timeout 5 s; exit 0 means no reminder; missing script or error means reminder); change the reminder text to "spex verify reminder: No verification is recorded for the current code. Consider running /speckit-spex-gates-verify or /speckit-spex-finish first, or confirm with the user that they want to proceed without the final gate."
- [X] T010 [P] [US2] In `spex/scripts/hooks/shared/verify-gate.sh`: replace the `$TMPDIR/.claude-spex-verified-$SESSION_ID` check with `spex-verify-record.sh check` run in `$CWD` (path `$(dirname "$0")/../../spex-verify-record.sh`, fallback `$CWD/.specify/extensions/spex-gates/scripts/spex-verify-record.sh`; exit 0 means `allow`); update the header comment and the `context:` reminder text to the same wording as T009. Add `tests/test_verify_gate.sh` (register it in the `test-walkthrough` target in `Makefile`) that, in a temp git repo with a `.specify/` dir and a staged code file, runs `sh spex/scripts/hooks/shared/verify-gate.sh Bash "git commit -m x" sid <repo>`: without a record it prints the new `context:` reminder naming `/speckit-spex-gates-verify`; after `spex-verify-record.sh record` it prints `allow`; after a code edit it prints the reminder again; and each run completes in under 5 seconds. In the same test, pipe `{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"session_id":"sid","cwd":"<repo>"}` to `python3 spex/scripts/hooks/pretool-gate.py` with and without a record and assert the new reminder text appears only without one

**Checkpoint**: both hooks read the shared record; no code writes or reads the TMPDIR `spex-verified` marker (`rg -n "spex-verified" spex/` only matches `spex-verified.json` in the record script).

---

## Phase 5: User Story 3 - One clear name for each job (P2)

**Goal**: Stamp is gone everywhere; ship and docs describe the real flow (FR-010, FR-012, FR-013, FR-015).

**Independent Test**: `rg -n "spex-gates-stamp|gates\.stamp|suppress-prompts-stamp|/speckit-spex-stamp" spex/ README.md CLAUDE.md tests/` prints nothing; `tests/test_marketplace_install.sh` passes.

- [X] T011 [US3] Delete `spex/extensions/spex-gates/commands/speckit.spex-gates.stamp.md` and remove its `speckit.spex-gates.stamp` entry from `spex/extensions/spex-gates/extension.yml`
- [X] T012 [P] [US3] Remove the `suppress-prompts-stamp` entries from `spex/scripts/adapters/claude/command-map.json` and `spex/scripts/adapters/codex/command-map.json` (keep valid JSON; check `jq . <file>`)
- [X] T013 [P] [US3] Remove `stamp` from the known-command lists in `spex/scripts/hooks/context-hook.py` and `spex/scripts/hooks/shared/context-hook.sh` (`KNOWN_COMMANDS`), and from `spex/templates/skill-preamble/opencode-preamble.md` (plus any other preamble under `spex/templates/skill-preamble/` that lists it)
- [X] T014 [US3] Remove every index-8 entry from both ship stage maps so no lookup can hit a missing key: in `spex/scripts/hooks/pretool-gate.py` remove `8: "stamp"` from `STAGE_NAMES`, `8: "spex:verification-before-completion"` from `STAGE_SKILLS` (around line 174; `SKILL_TO_STAGE` is derived from it), and the `8:` brief from `_stage_brief` (around lines 264-271); in `spex/scripts/hooks/shared/stage-gate.sh` remove the `8)` cases in `stage_skill` (around line 52), `stage_name` (around line 68), `skill_to_stage` (around line 83), and the stage-8 brief case (around line 127). Then confirm with `python3 -c` that every key in `STAGE_SKILLS` exists in `STAGE_NAMES`
- [X] T015 [P] [US3] In `spex/scripts/spex-ship-statusline.sh` change the `stamp|finish)` case to `finish)`, then `make sync-scripts` to update `spex/extensions/spex/scripts/spex-ship-statusline.sh`
- [X] T016 [P] [US3] In `spex/extensions/spex/commands/speckit.spex.ship.md`: change the frontmatter description to "Autonomous full-cycle workflow: specify through review-code with configurable oversight levels, auto-fix, and optional PR creation"; fix the Overview chain (line ~26) to end at deep review and say verification runs in finish or submit; fix "After the final stage (verify)" (line ~225) to review-code; delete the line "Do NOT skip verify because all prior reviews passed" (line ~390; line ~389 already covers review-code); update every description of finish (completion option at line ~806, "Stop here" text, line ~838) to "Verify + walkthrough + squash + merge to main"
- [X] T017 [P] [US3] In `tests/test_marketplace_install.sh` remove the `spex-gates/commands/speckit.spex-gates.stamp.md` expectation (line ~224) and add a negative check that the stamp file is absent if the test has such a pattern; run the test
- [X] T018 [P] [US3] Update `README.md`: the Commands Reference row for `/speckit-spex-finish` (verify first, `--no-verify`), remove the `/speckit-spex-gates-stamp` row, add or keep a `/speckit-spex-gates-verify` row as "Verification only (finish runs it first)", fix the workflow text that says ship runs "through verification" (lines ~20, ~127, ~368; line ~127 also says "nine stages", which becomes eight ending at review-code), fix the "Merge directly" line, and change the migration table row `/spex:stamp` to map to `/speckit-spex-finish`
- [X] T019 [P] [US3] Update `spex/docs/help.md` and `spex/extensions/spex/docs/help.md`: replace `/speckit-spex-stamp` lines with `/speckit-spex-gates-verify  Verification only (finish runs it first)`, and describe `/speckit-spex-finish` as "Verify + walkthrough gate + squash + merge/keep", including `--no-verify`, at every place it is described (in `spex/docs/help.md` lines ~193, ~218, ~221, ~227 and the flowchart near line ~37; the matching lines in the extension copy)
- [X] T020 [P] [US3] Update `spex/extensions/spex/commands/speckit.spex.using-superpowers.md` (finish lines ~66 and ~84, remove the stamp line ~85, the "Use speckit-spex-finish" red flag stays) and `spex/extensions/spex/commands/speckit.spex.evolve.md` line ~26 (`speckit-spex-gates-stamp` becomes `speckit-spex-gates-verify`; line ~27 already lists finish)
- [X] T021 [P] [US3] Update the project `CLAUDE.md`: in the Project Structure comment change `(review-spec, review-code, review-plan, stamp)` to `(review-spec, review-code, review-plan, verify)` and in Extensions change the spex-gates line to drop stamp

**Checkpoint**: the US3 independent test passes.

---

## Phase 6: User Story 4 - Finish degrades gracefully without spex-gates (P3)

**Goal**: FR-008.

**Independent Test**: With `.extensions["spex-gates"].enabled` false in `.specify/extensions/.registry`, finish prints `Verification skipped: spex-gates is not enabled.` and continues.

- [X] T022 [US4] In `spex/extensions/spex/commands/speckit.spex.finish.md` Phase 0: add the registry row after the `--no-verify` row and before the record check: `jq -r '.extensions["spex-gates"].enabled // false' .specify/extensions/.registry` not `true` prints `Verification skipped: spex-gates is not enabled.` and continues

---

## Phase 7: Polish & Cross-Cutting

- [X] T023 Run `rg -n "stamp" spex/ README.md CLAUDE.md tests/ Makefile` and fix any remaining live reference to the stamp command (ignore unrelated words like "timestamp")
- [X] T024 Run `make test-walkthrough`, `make sync-scripts-check`, `tests/test_marketplace_install.sh`, `bash -n spex/scripts/hooks/shared/verify-gate.sh spex/scripts/hooks/shared/stage-gate.sh spex/scripts/hooks/shared/context-hook.sh`, `python3 -m py_compile spex/scripts/hooks/pretool-gate.py spex/scripts/hooks/context-hook.py`, and `make validate`; fix failures (note: `tests/test_marketplace_install.sh` was syntax-checked only, not executed, because it removes and reinstalls the live `spex@spex-plugin-development` plugin and marketplace in the user's Claude config)
- [X] T025 Walk through `specs/055-merge-stamp-finish/quickstart.md` sections 1 to 5 and confirm each expected outcome (note: the section 4 reminder regex expects backticks; the task-specified reminder text has none, so it was checked with a literal `rg "speckit-spex-gates-verify or /speckit-spex-finish"`; section 5 excludes the marketplace test, see T024)

---

## Dependencies & Execution Order

- **Setup (T001)** → **Foundational (T002 → T003 → T004)** → user stories.
- **US1 (T005, T006, T007)**: T005 and T006 are sequential in spirit (finish calls verify `--embedded`); T007 is independent.
- **US2 (T008 to T010)**: T008 edits finish.md after T006. T009 and T010 depend only on T003.
- **US3 (T011 to T021)**: independent of US1/US2 except T014 shares `pretool-gate.py` with T009 (do T009 first) and T015 needs `make sync-scripts`.
- **US4 (T022)**: edits finish.md after T008.
- **Polish (T023 to T025)**: last.

### Parallel opportunities

- T007, T009, T010 in parallel after T003.
- T012, T013, T015, T016, T017, T018, T019, T020, T021 in parallel (different files).

## Implementation Strategy

MVP is US1 (Phase 1 to 3): finish can no longer land unverified code. US2 removes duplicate runs and fixes the reminder; US3 removes the confusing name; US4 is a small guard. All stories ship together in this feature.
