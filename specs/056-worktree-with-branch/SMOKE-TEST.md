# Guided Demo Report

**Feature**: Create the Worktree Together with the Feature Branch
**Date**: 2026-10-16
**Spec**: specs/056-worktree-with-branch/spec.md
**Result**: 4 passed, 0 skipped, 0 failed, 2 manual (out of 6)

---

## Triage Summary

| Tier | Count | Detail |
|------|-------|--------|
| full | 4 | Real `spex-worktree.sh` and the real upstream git extension script in scratch repos under `/tmp` |
| partial | 0 | |
| setup_offered | 0 | |
| manual | 2 | Need an installed plugin and a fresh agent session, or the real `specify` CLI in a scratch project |

User selection: Run what's ready

---

## Flow 1: `prepare` creates the worktree first and leaves main untouched

**Tier**: full
**Covers**: FR-001, FR-002, FR-004, FR-005, FR-006, FR-017

### Setup
Scratch project with a `main` commit, an uncommitted change to `README.md`, the real `.specify/extensions/git` scripts, and `spex-worktree.sh` from the extension.

### Evidence
**Execution**: `spex-worktree.sh prepare --short-name hello-cmd`, then the real `create-new-feature.sh` inside the worktree, then `prepare` again with the main checkout on branch `other`.
**Output**:
```
--- BEFORE: branch=main reflog-top=6ea9ad9 status=[ M README.md ]
WORKTREE_PREPARED path=.../.claude/worktrees/002-hello-cmd branch=002-hello-cmd base=main mode=early
--- AFTER: branch=main reflog-top=6ea9ad9 status=[ M README.md ]
.../.claude/worktrees/002-hello-cmd 6ea9ad9 (detached HEAD)
{"BRANCH_NAME":"002-hello-cmd","FEATURE_NUM":"002"}      # git.feature inside the worktree
worktree branch: 002-hello-cmd
main branch:     main, reflog-top 6ea9ad9
NOTICE: main checkout is on 'other', new branch starts from 'main'
new worktree base: 6ea9ad9; main checkout still on: other
```

### Verdict: PASS

**Verify yourself**:
1. Build a scratch project with the real git extension and run `spex-worktree.sh prepare --short-name t`.
2. Compare `git branch --show-current`, `git reflog -1` and `git status --porcelain` in the main checkout before and after.

---

## Flow 2: A concurrent session's commits land on `main`

**Tier**: full
**Covers**: User Story 2, FR-002, FR-003, FR-007

### Setup
Background loop committing to the main checkout every 0.3 s and recording the main checkout's branch after each commit.

### Evidence
**Execution**: prepare, then the real `create-new-feature.sh` in the worktree, then write `specs/002-hello-cmd/spec.md`, then `finalize`.
**Output**:
```
WORKTREE_PREPARED ... mode=early
{"BRANCH_NAME":"002-hello-cmd","FEATURE_NUM":"002"}
WORKTREE_FINALIZED ... branch=002-hello-cmd
{ "feature_directory": "specs/002-hello-cmd" }
--- loop observed main checkout branch values:   12 main
concurrent commits on main: 12; concurrent commits only on feature branch: 0
main checkout .spex-state present: no; spec in main checkout: no
```

### Verdict: PASS

**Verify yourself**:
1. Run a commit loop in the main checkout (see quickstart.md) while running the sequence above.
2. `git log main --grep=concurrent` shows all loop commits; `git log main..<feature> --grep=concurrent` shows none.

---

## Flow 3: Late-mode repair and failures without fallback

**Tier**: full
**Covers**: FR-002 (late window), FR-011, edge case "branch name already exists"

### Evidence
**Execution**: real `create-new-feature.sh` in the main checkout (file-order hook dispatch), then `prepare`; `prepare` with an occupied target path; `prepare --branch` naming an existing branch.
**Output**:
```
main checkout now on: 002-hello-cmd
WORKTREE_PREPARED ... branch=002-hello-cmd base=main mode=late
NOTICE: hook order: git.feature ran before the worktree step; main checkout was restored to 'main'
main checkout after: main; worktree: .../002-hello-cmd [002-hello-cmd]

ERROR: target path already exists: .../.claude/worktrees/003-blocked
exit=1
main on: main; branch 003-blocked exists: no; precious.txt intact: keep

ERROR: branch '002-hello-cmd' already exists
exit=1
```

### Verdict: PASS

**Verify yourself**:
1. In a scratch project, run the git extension's `create-new-feature.sh` in the main checkout, then `spex-worktree.sh prepare`.
2. Check that the main checkout is back on `main` and the branch is attached to the new worktree.

---

## Flow 4: Docs and agent instructions describe the new order

**Tier**: full
**Covers**: FR-001, FR-007, FR-009, FR-013, FR-014, FR-016

### Evidence
**Execution**: inspected manifests, README, help.md, ship and brainstorm commands, the methodology skill, init and CHANGELOG on the branch.
**Output**:
```
spex-worktrees hooks: before_specify args=prepare priority=1; after_specify args=finalize; before_implement args=ensure
spex flow-state before_specify priority: 2
README / help.md: worktree first, main never switches, session stays, run /spex:init --refresh after upgrading
ship.md:497 and brainstorm.md:181: spex-worktree.sh prepare before /speckit-specify
using-superpowers.md:70: dispatch hooks sorted by priority, not file order
spex-init.sh:537 and setup.yml:384: ERROR: spex-worktrees requires the spec-kit git extension
CHANGELOG: entries for #57, the narrowed legacy commit, the init refusal
```

### Verdict: PASS

---

## Flow 5: Real agent session (direct specify and brainstorm handoff)

**Tier**: manual
**Covers**: FR-008, FR-009, FR-010, FR-013, SC-001

### Verdict: MANUAL

**Steps**:
1. Install the plugin from this branch (`make install` from the merged main) and run `/spex:init --refresh` in a test project with `spex-worktrees` enabled.
2. In a second terminal, run the commit loop from quickstart.md in the main checkout.
3. Run `/speckit-spex-brainstorm`, pick "Specify step-by-step". Expect: the main checkout's reflog gains no entries, the loop prints `main` every time, the session ends in `.claude/worktrees/<NNN-...>`.
4. Run a direct `/speckit-specify`. Expect the same, or, if the agent dispatched hooks in file order, one switch plus one restore before the spec is written and a `NOTICE` line.
5. Run `/speckit-spex-ship` on a small brainstorm and check the same at the end of stage 0.

---

## Flow 6: Init refuses spex-worktrees without the git extension

**Tier**: manual
**Covers**: FR-014 (User Story 4)

### Verdict: MANUAL

**Steps** (run in a dedicated scratch directory; check `pwd` first):
1. `mkdir /tmp/init-check && cd /tmp/init-check && git init` and initialize spex there.
2. Enable `spex-worktrees`, then `specify extension remove git`.
3. Run `/spex:init --refresh`. Expect a non-zero exit and `ERROR: spex-worktrees requires the spec-kit git extension` with both fixes.
4. Disable `spex-worktrees` and rerun: init succeeds as before.

The automated init test (`tests/test_init_worktrees_git.sh`, stubbed CLI) covers this path; the manual run confirms it with the real CLI.

---

## FR Coverage

| FR | Flow | Verdict | Classification |
|----|------|---------|----------------|
| FR-001 | Flow 1, 4 | PASS | observable |
| FR-002 | Flow 1, 2, 3 | PASS | observable |
| FR-003 | Flow 2 | PASS | observable |
| FR-004 | Flow 1 | PASS | observable |
| FR-005 | Flow 1 | PASS | observable |
| FR-006 | Flow 1 | PASS | observable |
| FR-007 | Flow 2, 4 | PASS | observable |
| FR-008 | Flow 5 | MANUAL | observable |
| FR-009 | Flow 4, 5 | PASS (docs) / MANUAL (agent) | observable |
| FR-010 | Flow 5 | MANUAL | observable |
| FR-011 | Flow 3 | PASS | observable |
| FR-012 | - | - | covered by `make test-worktree` (disabled extension) |
| FR-013 | Flow 4, 5 | PASS (docs) / MANUAL (agent) | observable |
| FR-014 | Flow 4, 6 | PASS (code) / MANUAL (real CLI) | observable |
| FR-015 | - | - | verified by `git diff main -- .specify/` (no upstream changes) |
| FR-016 | Flow 4 | PASS | observable |
| FR-017 | Flow 1 | PASS | observable |
