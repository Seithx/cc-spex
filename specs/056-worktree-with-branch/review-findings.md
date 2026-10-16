# Deep Review Findings

**Date:** 2026-10-16
**Branch:** 056-worktree-with-branch
**Rounds:** 3
**Gate Outcome:** FAIL (1 Important finding remains; it needs a design or requirement decision, not a code fix)
**Invocation:** quality-gate (ship pipeline, ask=smart)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 1 | 1 | 0 |
| Important | 24 | 22 | 1 |
| Minor | 16 | 4 | 12 |
| Notable | 2 | - | 2 |
| **Total** | **43** | **27** | **15** |

One further Important finding (FINDING-12, hook order) was partly fixed and the rest is accepted by the spec (Clarifications, FR-002, SC-001). It is not counted as remaining.

**Agents completed:** 5/5 internal (Goal Alignment skipped: no PR) + 2 re-review agents + CodeRabbit + Codex
**Agents failed:** none. Copilot skipped (disabled in config).

Fix commits: `7c3eb80` (round 1), `4acfc35` (round 2), `9fd0334` (round 3).

## Findings

### FINDING-1
- **Severity:** Critical
- **File:** spex/scripts/spex-worktree.sh (`prepare_late` / `late_fail`)
- **Source:** correctness (also security), reproduced by both
- **Resolution:** fixed (round 1)

**What is wrong:** In late mode, "target path already exists" called `late_fail`, which ran `git worktree remove --force` on the existing path. A registered worktree there (for example one an aborted early prepare left behind) was deleted together with its untracked files.

**Why this matters:** Silent data loss of another worktree, contradicting FR-011's "nothing left behind" intent.

**How it was resolved:** `late_fail` only removes a worktree this invocation created (`created` flag set after `git worktree add`). Regression test: "late-mode failure never removes an existing worktree at the target path".

### FINDING-2
- **Severity:** Important
- **File:** spex/scripts/spex-worktree.sh (`compute_worktree_path`)
- **Source:** security, codex
- **Resolution:** fixed (round 1)

**What is wrong:** `base_path` values such as `.claude/worktrees/../../src` passed the textual allow-list and created a worktree inside the repository; shell metacharacters reached the `cd <path>` line the agent runs.

**How it was resolved:** `validate_base_path` rejects characters outside `[A-Za-z0-9._/@+-]` and `.`/`..` components below `.claude/worktrees`; branch names get the same character check. External base paths are still resolved with `pwd -P` and checked. Tests cover both cases.

### FINDING-3
- **Severity:** Important
- **File:** ship.md, brainstorm.md, manage.md (prepare call sites)
- **Source:** security
- **Resolution:** fixed (round 1)

**What is wrong:** Agents were told to splice the brainstorm title into `--description "<title>"`; backticks or `$(...)` in it would run.

**How it was resolved:** Call sites pass only `--short-name '<short-name>'` in single quotes and are told never to splice free text; `--description` is optional in the script and contract.

### FINDING-4
- **Severity:** Important
- **File:** spex/scripts/spex-worktree.sh (`detect_late_branch`)
- **Source:** correctness, architecture, production readiness (all reproduced)
- **Resolution:** fixed (round 1, extended round 2)

**What is wrong:** Any commit-less feature-pattern branch in the main checkout was taken over as "just created by git.feature", ignoring the requested name. A concurrent session's fresh branch was hijacked and the main checkout switched under it (FR-002), and ship/brainstorm callers could trigger it too.

**How it was resolved:** A candidate must have been created within 10 minutes (reflog) and must match `--branch`/`GIT_BRANCH_NAME` or end with `-<short-name>`. A fresh non-matching branch, or a matching one with commits, stops with an `ERROR:` and changes nothing; stale branches take the early path. Exact non-pattern `--branch` names are accepted (round 2). Five tests cover the cases.

### FINDING-5
- **Severity:** Important
- **File:** spex/scripts/spex-worktree.sh (`cmd_finalize`)
- **Source:** correctness
- **Resolution:** fixed (round 1, refined round 2)

**What is wrong:** finalize ran `git worktree move` on any linked worktree whose path differed from the computed one, including user or harness worktrees.

**How it was resolved:** prepare writes a `spex-prepared` marker into each worktree's own git dir (renamed to `spex-finalized` by finalize). Only marked worktrees are moved, and the target path is only computed for them.

### FINDING-6
- **Severity:** Important
- **File:** spex/scripts/spex-worktree.sh (finalize from the main checkout)
- **Source:** correctness, production readiness
- **Resolution:** fixed (rounds 1 to 3)

**What is wrong:** `prepared-worktree-exists` was a dead end when git.feature had run in the main checkout after prepare (the listed worktree was detached), and the heuristic listing also matched merged old-flow worktrees and other sessions' worktrees.

**How it was resolved:** The listing uses the prepare marker. When a prepared worktree for exactly this branch exists and holds nothing but what prepare put there, finalize hands the state back, removes it and adopts (`WORKTREE_ADOPTED` plus a `NOTICE:`). Other cases still return `prepared-worktree-exists` and change nothing. Old-flow worktrees no longer block adopt.

### FINDING-7
- **Severity:** Important
- **File:** spex/scripts/spex-init.sh (`install_extensions`)
- **Source:** correctness, production readiness
- **Resolution:** fixed (round 1)

**What is wrong:** remove + add re-registers every bundled extension as enabled, so the new git gate fired on `--refresh`/`--update` even for users who had disabled spex-worktrees (FR-014 scenario 2), and the advertised remedy did not stick.

**How it was resolved:** Disabled extensions are recorded before the loop and disabled again afterwards; the gate ignores a previously disabled spex-worktrees. New `tests/test_init_worktrees_git.sh` (stubbed `specify`) covers both FR-014 scenarios.

### FINDING-8
- **Severity:** Important
- **File:** manage.md Step 4, ship.md, brainstorm.md
- **Source:** correctness, architecture (security reported a Minor variant)
- **Resolution:** fixed (round 1)

**What is wrong:** The rollback after a failed `speckit.git.feature` force-removed the worktree that held the only copy of the moved ship/flow state, and ship and brainstorm had no rollback at all.

**How it was resolved:** Step 4 copies the state back and re-points `SHIP_STATE_FILE` before removing the worktree; ship and brainstorm reference Step 4.

### FINDING-9
- **Severity:** Important
- **File:** ship.md Stage 0 step 4, spex-worktree.sh finalize
- **Source:** architecture, production readiness
- **Resolution:** fixed (round 1)

**What is wrong:** Ship always ran `cd` on the last line (absent for `SKIPPED`), had no branch for `SKIPPED`/`ADOPTED`, and a prepared worktree still detached after specify was reported as harmless `not-on-a-feature-branch`.

**How it was resolved:** finalize fails (exit 1) in a marked worktree without a branch. Ship handles every status explicitly and verifies it is in a linked worktree on a branch before advancing, pausing as a blocker otherwise.

### FINDING-10
- **Severity:** Important
- **File:** manage.md, ship.md, brainstorm.md
- **Source:** architecture
- **Resolution:** fixed (round 1)

**What is wrong:** The branch computed by prepare was only advisory; git.feature recomputed it, which always drifts in timestamp mode and forced a live `git worktree move`.

**How it was resolved:** Callers run `speckit.git.feature` with `GIT_BRANCH_NAME` set to the `branch=` value from `WORKTREE_PREPARED`. The finalize move stays as a fallback.

### FINDING-11
- **Severity:** Important
- **File:** spex/extensions/spex/docs/help.md
- **Source:** architecture
- **Resolution:** fixed (round 1)

**What is wrong:** The help copy that `/speckit-spex-help` reads first still described the old order (FR-016).

**How it was resolved:** Both worktree passages updated to match `spex/docs/help.md`.

### FINDING-12
- **Severity:** Important
- **File:** spex/scripts/spex-worktree.sh, generated `.specify/extensions.yml`
- **Source:** production readiness
- **Resolution:** partly fixed (round 1); remainder accepted by the spec

**What is wrong:** The generated specify skill dispatches hooks in file order, so late mode may be the common path; a concurrent commit in the gap made prepare silently take the early path and leave the main checkout on the feature branch.

**How it was resolved:** The silent fall-through is gone: a fresh matching branch with commits now stops with an `ERROR:`. Rewriting `.specify/extensions.yml` into priority order was not done: Constitution III and FR-015 forbid reordering the git extension's hooks, and the spec's Clarifications explicitly accept the remaining window (FR-002, SC-001, upstream proposal).

### FINDING-13
- **Severity:** Important
- **File:** spex/scripts/spex-worktree.sh (`copy_config`)
- **Source:** production readiness
- **Resolution:** fixed (round 1)

**What is wrong:** rsync overwrote tracked `.specify/`/`.claude/` files in the new worktree with the main checkout's working copies, carrying uncommitted edits (possibly another session's) into the feature branch.

**How it was resolved:** Tracked files under both directories are restored to the worktree's commit after the copy. Test: "prepare keeps tracked config at the worktree's commit".

### FINDING-14
- **Severity:** Important
- **File:** spex/scripts/spex-worktree.sh (`cmd_finalize`)
- **Source:** codex
- **Resolution:** fixed (round 1)

**What is wrong:** A valid exact branch such as `feature/login` (via `--branch`/`GIT_BRANCH_NAME`) was skipped by finalize because it did not match the numeric pattern.

**How it was resolved:** Marked worktrees are finalized whatever the branch name. Test added.

### FINDING-15
- **Severity:** Important
- **File:** spex/scripts/spex-worktree.sh (`adopt_impl`)
- **Source:** codex
- **Resolution:** fixed (round 1)

**What is wrong:** A staged tracked `feature.json` pointer was not reset before switching the main checkout back.

**How it was resolved:** Compares against `HEAD` and resets index and working tree. Test added.

### FINDING-16 to FINDING-19
- **Severity:** Important
- **File:** tests/
- **Source:** test quality
- **Resolution:** fixed (round 1)

FR-014 had no test (now `tests/test_init_worktrees_git.sh`, wired into `make test-worktree`); FR-011 rollback paths were never triggered (rsync-failure tests for early and late mode); the "feature branch with commits is never late" rule was untested; finalize's FR-007 "no side effects" and idempotence were not asserted. All four now have tests with repository-state assertions.

### FINDING-20 and FINDING-21
- **Severity:** Important
- **File:** spex/scripts/spex-worktree.sh (`finalize_from_main`)
- **Source:** round 2 re-review, codex
- **Resolution:** fixed (round 2)

The repair's cleanliness check rejected prepare's own copies (so it rarely ran), and when both the worktree and the main checkout held a state it deleted the prepared run's only copy. A flow state for this branch that the hooks wrote in the main checkout is now backed up to `.spex-state.bak-<branch>`; any other state stops the repair.

### FINDING-22 to FINDING-24
- **Severity:** Important
- **File:** spex/scripts/spex-worktree.sh (`prepared_worktree_unused`)
- **Source:** round 3 re-review, codex
- **Resolution:** fixed (round 3)

The round 2 check missed ignored files and collapsed untracked directories, accepted a running flow state of another feature, and a timestamp-based variant missed files copied in with old mtimes. prepare now writes a content manifest (`spex-prepared-files`) of every untracked file it copied; the repair removes the worktree only when all untracked files (ignored included) still match it, symlinks match the main checkout, there are no tracked changes and no spec content, and it fails closed when the worktree cannot be read. A last Codex claim that `git ls-files --others` omits ignored files was checked and is false (dismissed).

### FINDING-25 (resolved by spec evolution)
- **Severity:** Important
- **File:** spex/scripts/spex-worktree-cwd.sh (unchanged), spec Edge Cases
- **Source:** architecture
- **Resolution:** resolved by spec evolution (user decision 2026-10-16): the Edge Cases entry now states that in-project worktrees keep the session CWD, ship recovers through its state file, and external worktrees outside ship are not recovered automatically

**What is wrong:** The spec says that after a harness cwd reset "the existing recovery mechanism returns it to the worktree". That script only works with `SHIP_STATE_FILE` (ship) or an old-flow feature branch checked out in the main checkout. In an interactive `/speckit-specify` with the new flow, the main checkout stays on the default branch, so nothing points back to the worktree.

**What is needed:** Either evolve the spec (in-project worktrees are documented not to see resets, and finalize's `prepared-worktree-exists` guidance covers the specify window), or extend recovery with a per-session pointer (for example an exported flow-state path or the prepare marker). This is a design choice, so it was not auto-fixed.

## Remaining Minor Findings

- Duplicate "spex-worktrees requires git" checks and texts in spex-init.sh, setup.yml, ship.md and the script (architecture).
- Ship/brainstorm pre-check `enabled // false` while the script treats a missing `enabled` as enabled (architecture).
- `prepared_on_purpose` still uses a heuristic next to the marker (architecture, partly addressed).
- `ensure`, `list`, `cleanup` and the cwd script only accept `NNN-` branches and build paths inline (architecture).
- `WORKTREE_CREATED` vs `WORKTREE_ADOPTED` for the same adopt outcome (architecture).
- `feature.json` normalization repeated three times (architecture).
- rsync is a hard dependency without an init check; python3/yq absence is silent (production readiness).
- No late-mode test from a detached HEAD (test quality; the dirty-tree late test was added).
- No test for the in-repo symlink-target copy (test quality).
- The new statusline test passes on empty output (test quality).
- `origin/HEAD` default-branch resolution and SKIPPED-first ordering untested (test quality).
- A stale `spex-prepared` marker from an abandoned run keeps blocking the adopt fallback (round 2 re-review).

## Notable Observations

### NOTABLE-1
- **File:** spex/scripts/spex-worktree.sh (`finalize_from_main`, `adopt_impl`)
- **Source:** round 3 re-review
- **Description:** The main-checkout repair and adopt only handle feature-pattern branches, while late mode and finalize now accept exact custom names.
- **Rationale:** A custom `--branch` plus a cwd reset ends with `not-on-a-feature-branch` and no hint about the prepared worktree.

### NOTABLE-2
- **File:** generated `.specify/extensions.yml`, upstream spec-kit templates
- **Source:** production readiness
- **Description:** The hook-order window can only close for good when spec-kit dispatches hooks by priority.
- **Rationale:** Tracked by `specs/056-worktree-with-branch/upstream-proposal.md`; worth following up once upstream answers.

## Post-Fix Spec Coverage

The fix loop replaced `list_prepared_worktrees` and rewrote parts of `finalize`; every functional requirement is still implemented.

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001 one step before spec content | `prepare` (before_specify hook priority 1, ship and brainstorm) | ✓ |
| FR-002 main checkout never switches | early mode; late mode restores, now only for this run's branch | ✓ |
| FR-003 spec, pointer, state in worktree | `move_matching_state`, finalize | ✓ |
| FR-004 no staging of main changes | early mode, tracked config restore, adopt `commit -- <spec_dir>` | ✓ |
| FR-005 copy configuration | `copy_config` | ✓ |
| FR-006 naming rules | git extension dry run, `GIT_BRANCH_NAME` | ✓ |
| FR-007 finalize without side effects | `cmd_finalize` (idempotence test) | ✓ |
| FR-008 after_specify hooks on worktree | session `cd`, finalize | ✓ |
| FR-009, FR-010 ship | ship.md Stage 0 | ✓ |
| FR-011 failure handling | rollback paths, tests | ✓ |
| FR-012 disabled extension | `WORKTREE_SKIPPED` first | ✓ |
| FR-013 session stays in worktree | manage.md completion box | ✓ |
| FR-014 init refusal | `install_extensions`, setup.yml, init test | ✓ |
| FR-015 no upstream edits | no files under `.specify/` changed | ✓ |
| FR-016 docs | README, both help.md copies, manage.md | ✓ |
| FR-017 default-branch tip + notice | early mode, late `branch -f` | ✓ |

All spec requirements verified after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make test-worktree test-ship-state test-statusline test-workflow-setup sync-scripts-check | 0 | 0 | passed (167 worktree tests) |
| 1 | same (plus new init test) | 0 | 0 | passed (257 + 11) |
| 2 | same | 0 | 0 | passed (276 + 11) |
| 3 | same | 0 | 0 | passed (286 + 11) |

Test suite passed in all fix rounds.
