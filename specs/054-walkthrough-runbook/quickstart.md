# Quickstart: Validating Walkthrough as a Runbook

Prerequisites: run from the repository root on branch `054-walkthrough-runbook`; `python3`, `jq`, `git` available; `podman` running for scenario 4 (otherwise it is skipped).

## 1. Script test suites

```bash
make test-walkthrough
```

Expected: each suite (`test_runbook_status.sh`, `test_runbook_check.sh`, `test_runbook_fixture.sh`, `test_runbook_clip.sh`, `test_finish_preserve_specs.sh`) prints `Results: N passed, 0 failed`. The fixture suite prints a skip note for the container case when podman is not running. Contracts: [contracts/scripts.md](contracts/scripts.md).

## 2. Status derivation and freshness

```bash
spex/scripts/spex-runbook-status.sh show specs/054-walkthrough-runbook
```

Expected before any runbook exists: `{"exists": false, ...}`. The test suite covers the derivation table in [data-model.md](data-model.md) and that a change only under `specs/` keeps `current: true` while a change under `spex/` sets it to `false`.

## 3. Runbook check catches the 053 failure mode

Create a runbook whose step has only a command and a one-line summary (no "What you should see" section), then:

```bash
spex/scripts/spex-runbook-check.sh /tmp/terse-runbook.md
```

Expected: exit 1 with `RUNBOOK_CHECK_FAIL structure ...` naming the missing section.

## 4. Light-mode session on a real feature (manual, human-judged)

In a project with a small testable feature (command-line effect, optionally one podman container), run `/speckit-spex-walkthrough`. Verify:
- one setup question before the first step (SC-004)
- each step shows why, the exact command, and what you should see before running (SC-001)
- an agent-run step shows the command, the real output, and an expected-versus-actual comparison (SC-002)
- choosing "run it yourself" puts the command on the clipboard
- at the end, the container is stopped and `RUNBOOK.md` has a `passed` or `failed` status
- you can explain what the feature does after reading the runbook (SC-005)

## 5. Not testable

On a feature that only refactors internals, run `/speckit-spex-walkthrough`. Expected: one line with reason and override hint; `git status` shows no new files (SC-003). Then run `/speckit-spex-walkthrough --force` and confirm a runbook is drafted.

## 6. Ship draft, run later from main

Run the draft-only form on a testable feature, merge it, then on the default branch run `/speckit-spex-walkthrough` without arguments. Expected: picker lists the drafted runbook; choosing it runs the session; at the end you are asked once whether to commit the updated runbook (SC-007, FR-030a).

## 7. finish recognizes a passed walkthrough

After scenario 4 passes, run `/speckit-spex-finish`. Expected: "Walkthrough passed at <sha>" and no walkthrough question (SC-008). Change a file under `spex/`, run finish again: the changed file is listed and rerun or continue is offered.

## 8. Detach mode

In a test repository with spex-detach enabled and a feature worktree: draft a runbook, run finish with merge. Expected: `git log --all --stat` shows no `RUNBOOK.md` or `.walkthrough/` files (SC-006); the runbook exists in the main checkout after the worktree is removed (SC-007). Also confirm that with the detach directory present but the extension disabled, `spex-runbook-status.sh locate` reports `"detach": false`.
