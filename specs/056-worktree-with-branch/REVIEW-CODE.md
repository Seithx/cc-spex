# Code Review: Create the Worktree Together with the Feature Branch

**Spec:** specs/056-worktree-with-branch/spec.md
**Contract:** specs/056-worktree-with-branch/contracts/spex-worktree-cli.md
**Date:** 2026-10-16
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 97%**

- Functional Requirements: 17/17 (100%)
- Edge Cases: 14/14 (100%): the cwd-recovery edge case was reworded by the user's decision (FINDING-25)
- Success Criteria (script-verifiable parts of SC-001 to SC-005): 5/5
- Spec-declared constants: none (no `## Constants` section)

## Detailed Review

### Functional Requirements

| Req | Implementation | Status |
|-----|---------------|--------|
| FR-001 branch and worktree in one step before spec content | `spex-worktree.sh prepare` as `before_specify` hook (priority 1), run directly by ship Stage 0 and the brainstorm handoff | Compliant |
| FR-002 main checkout never switches; late repair with notice | early mode touches nothing; late mode restores `@{-1}` and prints `NOTICE: hook order ...`, now only for this run's freshly created branch | Compliant |
| FR-003 spec, checklist, feature.json, state only in worktree | session `cd`, `move_matching_state`, finalize | Compliant |
| FR-004 no stage/commit/stash in main | early mode; `copy_config` restores tracked config; adopt commits only `<spec_dir>` | Compliant |
| FR-005 copy configuration | `copy_config` (`.specify/`, `.claude/`, in-repo symlink targets) | Compliant |
| FR-006 naming rules | git extension `--dry-run`, timestamp mode, `GIT_BRANCH_NAME`/`--branch` | Compliant |
| FR-007 after_specify detects existing worktree, no side effects | `finalize` (idempotence and no-change test) | Compliant |
| FR-008 after_specify hooks act on worktree files | session stays in the worktree | Compliant |
| FR-009 ship uses the combined step, no hand-made branch | ship.md Stage 0 steps 2 to 5, Worktree Prerequisite | Compliant |
| FR-010 ship reads the branch from the worktree | ship.md step 5 plus in-worktree guard | Compliant |
| FR-011 failure stops, rolls back, no fallback, ship blocker | script rollback paths; manage.md Step 4; ship pause | Compliant |
| FR-012 disabled extension unchanged | `WORKTREE_SKIPPED` evaluated first; ship dirty-check kept | Compliant |
| FR-013 session stays, completion message | manage.md Finalize Step 3 | Compliant |
| FR-014 init fails without git | `install_extensions` (exit 1), setup.yml step, SKILL.md | Compliant |
| FR-015 no upstream file changes | diff touches nothing under `.specify/` | Compliant |
| FR-016 docs | README, `spex/docs/help.md`, `spex/extensions/spex/docs/help.md` (fixed in review), manage.md | Compliant |
| FR-017 start from default-branch tip, notice | early mode `--detach <tip>`, late `git branch -f`, `NOTICE:` | Compliant |

### Edge Cases

All edge cases are handled by the script or the command docs and covered by tests where testable, except one:

- **Session working directory recovery** (Deviation, minor): the spec says the existing recovery mechanism returns a reset session to the worktree. `spex-worktree-cwd.sh` does so for ship (`SHIP_STATE_FILE`), but not for an interactive `/speckit-specify`, where the main checkout stays on the default branch. See Deep Review FINDING-25.

### Extra Features (Not in Spec)

- Prepare marker and content manifest in each worktree's git dir (`spex-prepared`, `spex-finalized`, `spex-prepared-files`), added during review so finalize only moves or removes worktrees prepare created. Supports FR-007 and FR-011; documented in the contract.
- finalize repair from the main checkout (`WORKTREE_ADOPTED` with `NOTICE:`) when git.feature ran there after prepare. Supports FR-002 recovery.
- Late mode refuses fresh branches of another run or with commits. Strengthens FR-002.
- `base_path` and branch-name validation. Hardening, no spec impact.
- Init now keeps disabled extensions disabled across refresh. Needed for FR-014 scenario 2.

Spec evolution candidates: mention the 10-minute late-mode window and the refusal cases under Edge Cases; settle the cwd-recovery wording (FINDING-25).

## Deep Review Report

**Gate: FAIL** (after fix round 3). 1 Important finding remains, and it needs a design or requirement decision rather than a code fix.

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 6 | 6 | 0 | completed |
| Architecture & Idioms | 12 | 5 | 1 Important + 6 Minor | completed |
| Security | 4 | 4 | 0 | completed |
| Production Readiness | 7 | 5 | 1 Minor (+1 spec-accepted) | completed |
| Test Quality | 8 | 4 | 4 Minor | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| Re-review round 2 | 6 | 5 | 1 Minor | completed |
| Re-review round 3 | 4 | 3 | 1 Notable | completed |
| CodeRabbit (external) | 0 | 0 | 0 | completed |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 8 | 7 | 0 (1 false positive dismissed) | completed |
| Test Suite (regression) | 0 | 0 | 0 | passed every round |

MVP: Architecture & Idioms (12 findings)

Severity totals after merging duplicates:

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 1 | 1 | 0 |
| Important | 24 | 23 | 0 |
| Minor | 16 | 4 | 12 |
| Notable | 2 | - | 2 |

Key fixes applied:
1. Late-mode failure no longer force-removes an existing worktree at the target path (Critical; correctness, security).
2. Late mode only takes over this run's freshly created branch; other fresh branches or ones with commits stop with an error.
3. `base_path` and branch-name validation; no free text spliced into agent shell commands.
4. Prepare marker plus content manifest: finalize moves only worktrees prepare created, and the main-checkout repair removes a prepared worktree only when nothing would be lost.
5. `copy_config` keeps tracked config at the worktree's commit; adopt resets a staged `feature.json`.
6. Init keeps disabled extensions disabled across refresh (FR-014 scenario 2) with a new stubbed-CLI test.
7. Agent docs: `GIT_BRANCH_NAME` pass-through, state-preserving rollback, explicit finalize status handling and an in-worktree guard in ship.
8. Extension copy of help.md updated (FR-016).
9. 130 new test assertions (119 in test_worktree.sh, 11 in the new init test) for rollback paths, FR-007 idempotence, late-mode safety and the init refusal.

Remaining findings: none Critical or Important.
- FINDING-25 (Important) resolved by spec evolution: the user chose to reword the cwd-recovery edge case (in-project worktrees keep the session CWD; ship recovers through its state file; external worktrees outside ship are not recovered automatically). The 10-minute late-mode window was added to the Edge Cases at the same time.

Post-fix spec coverage: 17/17 requirements verified ✓

Notable observations: 2 captured to brainstorm/idea-inbox.md

Details: specs/056-worktree-with-branch/review-findings.md
