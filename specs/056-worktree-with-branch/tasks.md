# Tasks: Create the Worktree Together with the Feature Branch

**Input**: Design documents from `/specs/056-worktree-with-branch/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/spex-worktree-cli.md, quickstart.md

**Tests**: Included. The quickstart defines an automated test script (`tests/test_worktree.sh`), and SC-001 to SC-003 are verified by it.

**Organization**: Tasks are grouped by user story. Story 2 (concurrent session) is a verification story on top of Story 1.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: User story from spec.md (US1 to US4)

---

## Phase 1: Setup

**Purpose**: Build wiring and test harness

- [X] T001 Add `spex-worktrees` to the script sync in `Makefile`: add `SCRIPTS_spex_worktrees := spex-worktree.sh`, append `spex-worktrees` to `EXTENSIONS`, add a `_print-scripts-spex-worktrees` helper target, add a `test-worktree` target running `tests/test_worktree.sh`, and list `test-worktree` in `.PHONY`
- [X] T002 [P] Create `tests/test_worktree.sh` harness (pattern of `tests/test_ship_state.sh`): `set -euo pipefail`, PASS/FAIL counters, `trap` cleanup, and a `make_repo` fixture that builds a temp repo with a `main` branch and one commit, `.specify/extensions/.registry` with `spex-worktrees` enabled, `.specify/extensions/spex-worktrees/worktree-config.yml`, a stub `.specify/extensions/git/scripts/bash/create-new-feature.sh` that prints `{"BRANCH_NAME":"057-<short-name>","FEATURE_NUM":"057"}` for `--dry-run --json` and does `git checkout -q -b` otherwise, a `.claude/settings.json`, and helper assertions (`assert_eq`, `assert_file`, `assert_no_file`, `main_head`, `main_reflog_top`, `main_status`)

---

## Phase 2: Foundational

**Purpose**: Script skeleton and shared helpers used by every subcommand

- [X] T003 Create `spex/scripts/spex-worktree.sh` (`#!/usr/bin/env bash`, `set -euo pipefail`) with subcommand dispatch (`prepare`, `finalize`, `adopt`), usage text, and exit codes 0/1/2 per `specs/056-worktree-with-branch/contracts/spex-worktree-cli.md`. Add shared helpers: `worktrees_enabled` (reads `.specify/extensions/.registry`), `resolve_default_branch` (origin/HEAD → `main` → `master`, else error with `git remote set-head origin --auto` hint), `read_base_path`, `compute_worktree_path <branch>` (inside-project `.claude/worktrees/<branch>` vs external `<base>/<repo>@<branch>`, including the existing "inside repo but not under .claude/worktrees" rejection), `in_linked_worktree`, `is_feature_branch <name>` (`^[0-9]{3}-` or timestamp form), `copy_config <path>` (rsync `.specify/` without `.git` and without per-session state files: `.spex-state`, `.pr-triage-state.json` and any other `.specify/.*-state*` file, `.claude/` without `worktrees/`, in-repo symlink targets as in today's manage Step 8), and `move_matching_state <path> [<late-branch>]` (moves `.specify/.spex-state` only when `mode==flow && running==specify`, `mode==ship && stage==specify`, or, in late mode, `mode==flow && feature_branch==<late-branch>`, because spec-kit drops hook args and the flow-state hook then writes plain `create` output)

**Checkpoint**: Script loads, prints usage, helpers are callable

---

## Phase 3: User Story 1 - Specify without disturbing the main checkout (Priority: P1) 🎯 MVP

**Goal**: `/speckit-specify` with `spex-worktrees` enabled creates the worktree before the branch, writes everything in the worktree, and leaves the main checkout's branch, reflog and status untouched.

**Independent Test**: `make test-worktree` passes the prepare/finalize/adopt cases from quickstart.md. Manually, `/speckit-specify` leaves `git reflog` and `git status` of the main checkout unchanged.

### Tests for User Story 1

- [X] T004 [US1] Add prepare test cases to `tests/test_worktree.sh`: early mode from clean main (HEAD, reflog top and porcelain status unchanged, worktree detached at main's tip with `.specify/` and `.claude/`), dirty main (changes stay uncommitted in main and absent from the worktree), main on `other` branch (NOTICE line, base is main's tip, main stays on `other`), main on a detached HEAD (NOTICE line, base is main's tip, main stays detached), late mode after `git checkout -b 057-x` in main (main back on `main`, worktree on `057-x`), late mode after `git checkout -b 057-x` while main was on `other` (main back on `other`, `057-x` reset to `main`'s tip before the worktree is attached), main on an old-flow feature branch `055-foo` with no commits but an uncommitted `specs/055-foo/` (`WORKTREE_PREPARED mode=early` with the FR-017 `NOTICE`, worktree based on `main`'s tip, main stays on `055-foo`, its uncommitted spec untouched), late-mode failure with the target path present (exit 1, main stays on its previous ref, the commit-less `057-x` is deleted), `--branch` naming an existing branch (exit 1, no worktree), inside a worktree on a non-feature branch, or on a feature branch with one commit beyond `main` (`WORKTREE_READY` with the nesting warning, nothing changed), inside a freshly prepared detached worktree (`WORKTREE_READY`, no warning), inside a prepared worktree after `git checkout -b 057-x` ran in it (`WORKTREE_READY`, no warning), target path exists (exit 1, no worktree, no branch, main unchanged), no resolvable default branch (exit 1, hint printed), extension disabled (`WORKTREE_SKIPPED`), external `base_path` (worktree at `<base>/<repo>@<branch>`), state moving (flow `running=specify` moved, ship `stage=plan` not moved, late mode with a flow state shaped like `spex-flow-state.sh create` output for the feature branch moved, and the worktree has no `.spex-state` when nothing matched), and a timing assertion that `prepare` finishes in under 5 seconds on the fixture
- [X] T005 [US1] Add finalize and adopt test cases to `tests/test_worktree.sh`: finalize keeps an existing valid `feature.json`, finalize with a timestamp-numbered spec directory, finalize with matching directory (`feature.json` and `.spex-state` `feature_branch`/`spec_dir` set), finalize with mismatching directory (worktree moved to `<base>/<branch>`, new path printed as `cd` line), finalize in main on a feature branch (delegates to adopt), adopt with an uncommitted tracked change in main (only the spec dir committed on the feature branch, the change stays uncommitted on `main`)

### Implementation for User Story 1

- [X] T006 [US1] Implement `prepare` early mode in `spex/scripts/spex-worktree.sh` (evaluation order: resolve the default branch first, then READY/SKIPPED checks, then late-mode detection from T007, then the early path below; inside a worktree, an unresolvable default branch means print the nesting warning and return READY instead of exit 1): parse `--short-name`, `--description`, `--branch` (and `GIT_BRANCH_NAME`), return `WORKTREE_READY` inside a linked worktree (plus `WARNING: already inside a worktree, nesting is not supported; using the current worktree` unless the worktree was just prepared on purpose: HEAD is detached (`git.feature` has not run yet), or HEAD is a feature-pattern branch with `git rev-list --count <default>..HEAD` equal to 0 and no `specs/<branch>/spec.md` yet (`git.feature` already ran inside it in file order)) and `WORKTREE_SKIPPED` when disabled, get the branch name from `create-new-feature.sh --dry-run --json` unless given, exit 1 if `git show-ref --verify --quiet refs/heads/<branch>` finds it already, print the FR-017 `NOTICE` when main is on another ref, `git worktree add --detach <path> <default>`, `copy_config`, `move_matching_state`, print `WORKTREE_PREPARED ... mode=early` and the final `cd <path>` line. On any failure after `worktree add`, remove the worktree (`git worktree remove --force`) and exit 1
- [X] T007 [US1] Implement `prepare` late mode in `spex/scripts/spex-worktree.sh`: detect per the contract before any dry run or branch-exists check, taking the branch name from the main checkout's current branch (no `specs/<branch>/` directory in the main checkout, feature-pattern branch, not default, not checked out elsewhere, tip equals `@{-1}` tip), `git checkout <@{-1}>` in main, `git branch -f <branch> <default-tip>` (safe because the branch has no commits; this keeps FR-017 when `git.feature` branched from another ref), `git worktree add <path> <branch>`, `copy_config`, `move_matching_state <path> <branch>`, print `NOTICE: hook order ...` and `WORKTREE_PREPARED ... mode=late`. A feature branch that fails late detection (own commits, or an existing `specs/<branch>/`) is not late: it takes the early path, so main stays on it and the new worktree starts from the default tip with the FR-017 `NOTICE`. On failure after main was restored: leave main on its previous ref, delete the commit-less feature branch (`git branch -D`), remove any partial worktree, and exit 1. Never check the feature branch out in main again (FR-011)
- [X] T008 [US1] Implement `finalize` in `spex/scripts/spex-worktree.sh`: inside a linked worktree on a feature branch, `git worktree move` when the directory name differs from the branch (from the main checkout's git dir), resolve the spec directory in this order and write `.specify/feature.json` only if it differs: the existing `feature.json` value when that directory holds a `spec.md`, then `specs/<branch>`, then the newest directory whose path matches the regex `^specs/([0-9]{3}|[0-9]{8}-[0-9]{6})-` and holds a `spec.md`, set `feature_branch` and `spec_dir` in `.specify/.spex-state` with `jq` if present, print `WORKTREE_FINALIZED` and the `cd` line. In the main checkout on a feature branch, delegate to `adopt`. Otherwise print `WORKTREE_SKIPPED`
- [X] T009 [US1] Implement `adopt` in `spex/scripts/spex-worktree.sh`: port today's `create` action from `spex/extensions/spex-worktrees/commands/speckit.spex-worktrees.manage.md` (Steps 2 to 8b), changing Step 5 to stage only the feature's spec directory (no `git add -u`, no `brainstorm/`, no `.specify/`), print `WORKTREE_CREATED path=... branch=...` and the `cd` line
- [X] T010 [P] [US1] In `spex/extensions/spex-worktrees/extension.yml`, add a `before_specify` hook (`command: speckit.spex-worktrees.manage`, `args: "prepare"`, `optional: false`, `priority: 1`, description naming action 'prepare'), and change the `after_specify` hook's `args` and description to action 'finalize'. Update the comment about dropped args
- [X] T011 [P] [US1] In `spex/extensions/spex/extension.yml`, change the `before_specify` flow-state hook's `priority` from 1 to 2 and add a comment that it must run after the spex-worktrees prepare hook
- [X] T012 [US1] Rewrite `spex/extensions/spex-worktrees/commands/speckit.spex-worktrees.manage.md`: update the Overview and Action Routing (no-arg `before_specify` hook → prepare, no-arg `after_specify` hook → finalize, `create` kept as an alias of `adopt`), add "Action: Prepare" (generate the short name once with the git extension's rules, run the script, `cd` into the printed path, reuse the same short name for `git.feature`, stop `/speckit-specify` on exit 1 with no fallback, and if `git.feature` later fails inside the prepared worktree, run `git worktree remove --force <path>`, `cd` back to the main checkout and stop) and "Action: Finalize" (run the script, `cd` to the printed path, keep the session in the worktree, show the completion box with the `cd <path> && claude` hint unless `.spex-state` has `status == running`). Update the `argument-hint` frontmatter to `[list|prepare|finalize|adopt|ensure|finish|cleanup]`. Replace the inline Create steps with a short "Action: Adopt" that delegates to `spex-worktree.sh adopt`, and make "Action: Ensure" Step 4 call adopt. Keep List, Finish and Cleanup unchanged
- [X] T013 [US1] In `spex/extensions/spex/commands/speckit.spex.brainstorm.md` "Transition: next steps", when the user chooses "Specify step-by-step" and `spex-worktrees` is enabled in `.specify/extensions/.registry`: run `.specify/extensions/spex-worktrees/scripts/spex-worktree.sh prepare --short-name <brainstorm basename without number prefix and extension> --description "<brainstorm title>"` from the main checkout, `cd` into the printed path, then invoke `/speckit-specify` there with the brainstorm content and the same short name. On exit 1, show the error and stop (no fallback). Add the same note to the worked example at the end of the file
- [X] T014 [P] [US1] In `spex/extensions/spex/commands/speckit.spex.using-superpowers.md`, add a short "Dispatching spec-kit hooks" rule: when a `/speckit-*` command lists hooks from `.specify/extensions.yml`, dispatch them sorted by `priority` ascending (missing priority = 10, ties keep file order), matching spec-kit's `HookExecutor`. Name the reason (spex-worktrees `prepare` at priority 1 must run before the `git` extension's branch hook)
- [X] T015 [US1] Run `make sync-scripts` to create `spex/extensions/spex-worktrees/scripts/spex-worktree.sh`, then `make test-worktree` until all US1 cases pass

**Checkpoint**: Direct `/speckit-specify` is isolated from the first hook on

---

## Phase 4: User Story 2 - Concurrent session keeps committing to the default branch (Priority: P1)

**Goal**: Commits made in the main checkout during a specify run land on the default branch.

**Independent Test**: The concurrency case in `tests/test_worktree.sh` passes.

- [X] T016 [US2] Add a concurrency case to `tests/test_worktree.sh`: start a background loop that commits to the main checkout every 0.2 s, run `prepare`, then the stub `create-new-feature.sh` inside the worktree, write a spec file there, run `finalize`, stop the loop, and assert that every loop commit is reachable from `main` and none is reachable from the feature branch only, and that main's branch never changed (check the loop's recorded `git rev-parse --abbrev-ref HEAD` outputs)

**Checkpoint**: SC-002 verified automatically

---

## Phase 5: User Story 3 - Ship pipeline uses the same one-step creation (Priority: P2)

**Goal**: Ship gets branch and worktree through `prepare` before stage 0, keeps its state in the worktree, and never creates a branch in the main checkout.

**Independent Test**: State-move and status-line test cases pass. Manually, ship stage 0 leaves the main checkout on its branch with no `.spex-state`.

- [X] T017 [US3] In `spex/extensions/spex/commands/speckit.spex.ship.md` Prerequisites, add a check: when `spex-worktrees` is enabled in `.specify/extensions/.registry` and `git` is not, stop with an error naming both fixes (enable `git` or disable `spex-worktrees`). Never create a branch by hand
- [X] T018 [US3] In `spex/extensions/spex/commands/speckit.spex.ship.md` Stage 0, keep step 1 (read the brainstorm content) first, because an uncommitted brainstorm file does not exist in the worktree. Then add a step before invoking `/speckit-specify`: when worktrees are enabled, run `.specify/extensions/spex-worktrees/scripts/spex-worktree.sh prepare --short-name <brainstorm basename without number prefix and extension> --description "<brainstorm title>"`, `cd` into the printed path, and re-export `SHIP_STATE_FILE` to the worktree's `.specify/.spex-state`. On exit 1, pause the pipeline as a blocker at every oversight level. Tell `/speckit-specify` to reuse the same short name for `git.feature`. Replace steps 4 and 5 (branch from `git branch --show-current` in main, fallback to manage create) with: run `spex-worktree.sh finalize`, `cd` to the printed path, re-export `SHIP_STATE_FILE` to `<printed path>/.specify/.spex-state` (finalize may have moved the worktree), and read `FEATURE_BRANCH` from inside the worktree. Update the "CRITICAL: Specify triggers after_specify hooks" note and the CWD recovery text
- [X] T019 [P] [US3] Add a case to `tests/test_ship_statusline.sh`: with the stdin JSON `.workspace.current_dir` set to a main checkout (and `SHIP_STATE_FILE` unset) that has no `.specify/.spex-state` and a worktree holding a running ship state, the status line rendered for the main checkout shows no pipeline progress
- [X] T020 [US3] Add a case to `tests/test_worktree.sh`: ship state with `stage=specify` in main is moved into the worktree by `prepare`, and the main checkout has no `.spex-state` afterwards

**Checkpoint**: Ship isolation does not depend on hook order

---

## Phase 6: User Story 4 - Init refuses an unusable worktree setup (Priority: P3)

**Goal**: `/spex:init` fails when `spex-worktrees` is enabled and the `git` extension cannot be enabled.

**Independent Test**: Quickstart manual step 6 (requires the `specify` CLI).

- [X] T021 [US4] In `spex/scripts/spex-init.sh` `install_extensions()`, replace the warning branch of the git dependency check: read `.extensions["spex-worktrees"].enabled` from `.specify/extensions/.registry`. When it is `true` and `specify extension enable git` fails (or `git` is still not enabled), print `ERROR: spex-worktrees requires the spec-kit git extension` plus the two fixes (`specify extension add git` / `specify extension enable git`, or `specify extension disable spex-worktrees`) to stderr and `exit 1`. Keep today's behavior when `spex-worktrees` is disabled
- [X] T022 [P] [US4] Update `spex/skills/init/SKILL.md`: describe that init now exits with an error in this case and that the skill must show the message and stop instead of continuing to the restart step

**Checkpoint**: Unsupported setup is rejected at init

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T023 [P] Update `README.md`: the `spex-worktrees` extension description (worktree created before the branch, main checkout never switched, hook-order note) and the ship "Worktree integration" section
- [X] T024 [P] Update `spex/docs/help.md`: the spex-worktrees block (specify now creates the worktree first and the session continues there) and the ship worktree line
- [X] T025 [P] Add an Unreleased entry to `CHANGELOG.md` describing the worktree-first flow, the late-mode repair, the narrowed legacy commit and the init failure, and noting that existing projects must run `/spex:init --refresh` to register the new `before_specify` hook (say the same in T023's README text)
- [X] T026 [P] Draft an upstream proposal for github/spec-kit in `specs/056-worktree-with-branch/upstream-proposal.md` (draft only, do not file it): the command templates' hook-dispatch instructions should tell agents to sort hooks by `priority` as `HookExecutor.get_hooks_for_event()` does. Include the observed file-order behavior, the affected templates (`specify`, `plan`, `tasks`, `implement`, `clarify` hook sections) and a suggested one-sentence template change
- [X] T027 Run `make sync-scripts-check validate` and every test target in the Makefile (`test-worktree`, `test-ship-state`, `test-statusline`, `test-workflow-setup`, `test-generated-trees`, `test-walkthrough`, `test-setup-profile`, `test-codex-project`) and fix any failure (SC-005). Check FR-015 with `git diff main -- .specify/ .claude/skills/speckit-specify .claude/skills/speckit-git-feature` returning no changes to upstream spec-kit files

---

## Dependencies & Execution Order

- **Setup (T001, T002)**: no dependencies. T002 can run in parallel with T001
- **Foundational (T003)**: after Setup. Blocks all story phases
- **US1 (T004 to T015)**: after T003. T004 and T005 (tests) come before T006 to T009. T010 and T011 are independent manifest edits [P]. T012 and T013 after T006 to T009 (they document and call the final interface). T014 is an independent methodology edit [P]. T015 last
- **US2 (T016)**: after US1 (needs prepare and finalize)
- **US3 (T017 to T020)**: after US1. T019 is independent [P]
- **US4 (T021, T022)**: independent of US1 to US3, only needs Setup
- **Polish (T023 to T027)**: after all stories. T027 last

## Parallel Example: User Story 1

```text
T010 spex/extensions/spex-worktrees/extension.yml   (before_specify hook)
T011 spex/extensions/spex/extension.yml             (flow-state priority)
```

These touch different files and can run alongside the script work in T006 to T009.

## Implementation Strategy

1. **MVP**: Setup, Foundational and US1. Direct `/speckit-specify` is isolated, which fixes the reported defect.
2. **Verify**: US2 adds the concurrency proof.
3. **Ship**: US3 moves ship to the same mechanism.
4. **Guard**: US4 closes the misconfiguration hole.
5. **Polish**: docs and changelog, then the full test run.
