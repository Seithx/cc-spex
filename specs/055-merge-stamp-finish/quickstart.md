# Quickstart: Merge stamp into finish

## Prerequisites

- cc-spex checkout with this branch; `git`, `jq`, `python3`.
- Run from the repository root (or the feature worktree).

## 1. Record script works in isolation

```bash
tests/test_verify_record.sh
```

Expected: `=== Results: N passed, 0 failed ===`. Covers record/check/stale/missing/unreadable/clear, commit-after-record staying `verified`, spec-only edits staying `verified`, code edits turning `stale`, and the record path living in the git dir.

## 2. Manual record round trip

```bash
spex/scripts/spex-verify-record.sh check; echo "exit=$?"
spex/scripts/spex-verify-record.sh record --feature specs/055-merge-stamp-finish
spex/scripts/spex-verify-record.sh check --feature specs/055-merge-stamp-finish; echo "exit=$?"
spex/scripts/spex-verify-record.sh path
```

Expected: first `check` prints `"state": "missing"` (or `stale`) and `exit=1`; after `record`, `check` prints `"state": "verified"` and `exit=0`; `path` prints a path under `.git/`.

## 3. Stamp is gone

```bash
rg -n "spex-gates-stamp|gates\.stamp|suppress-prompts-stamp" spex/ README.md CLAUDE.md tests/
```

Expected: no output.

## 4. Stage map and reminder text

```bash
rg -n '"stamp"|8\) echo "stamp"|stamp\|finish' spex/scripts
rg -n "speckit-spex-gates-verify. or ./speckit-spex-finish" spex/scripts/hooks
```

Expected: first command no output; second shows the new reminder in `pretool-gate.py` and `shared/verify-gate.sh`.

## 5. Suite

```bash
make test-walkthrough && make sync-scripts-check && tests/test_marketplace_install.sh && make validate
```

Expected: all pass.

## 6. Finish behavior (manual, in a scratch feature branch)

1. Introduce a failing test, run `/speckit-spex-finish`: it prints `Finish stopped: verification did not pass.` with the failing gate, and the branch is unchanged.
2. Fix the test, run `/speckit-spex-finish`: `Verification passed.`, then the walkthrough gate.
3. Run `/speckit-spex-gates-verify`, then `/clear`, then `/speckit-spex-finish`: `Verification already passed for this code.`
4. Run `/speckit-spex-finish --no-verify`: `Verification skipped (--no-verify).`
5. (US2-AS2) After a recorded pass, edit a file under `src/` (or any non-spec path), run `/speckit-spex-finish`: no `already passed` line; verify runs again.
6. (US2-AS5) Run `/speckit-spex-finish --no-verify --no-walkthrough`: both `Verification skipped (--no-verify).` and `Walkthrough skipped (--no-walkthrough flag).` are printed.
7. (US1-AS3) With the failing test from step 1, run `/speckit-spex-finish --auto`: no prompt appears, it prints the `Finish stopped: verification did not pass.` block, and `git log`/`git status` are unchanged.
8. (US4-AS1) Set `.extensions["spex-gates"].enabled` to `false` in `.specify/extensions/.registry` (restore it afterwards), run `/speckit-spex-finish`: `Verification skipped: spex-gates is not enabled.`, then the walkthrough gate; finish's own commits do not stop on the verification reminder.
9. (FR-009, FR-009a) On a branch with no `specs/<branch>/spec.md`, run `/speckit-spex-finish --auto`: first line `Finish stopped: no spec found for verification.`, then `Run /speckit-spex-finish --no-verify to land without verification.`
10. (FR-009a, interrupted) Interrupt verify during finish (Esc while tests run): first line `Finish stopped: verification did not complete.`, the error on one line, then the `--no-verify` line.
11. (FR-009b) With a `.specify/.spex-state` file present, run `/speckit-spex-gates-verify --embedded`: no completion banner, and `.specify/.spex-state` still exists. Run `/speckit-spex-gates-verify` without the flag: banner shown and the state file is removed.
12. (FR-011a) After step 2 or 3, finish's `chore: final changes before finish` and squash commits proceed without a confirmation stop.
13. (Edge: re-check) After `Verification passed.`, edit a code file during the walkthrough: before staging, finish prints `Code changed after verification; verifying again.`
14. (Edge: default branch) On `main`, run `/speckit-spex-finish`: verification runs first (verify's spec picker in interactive mode), then `You are already on the default branch; no merge needed.`
