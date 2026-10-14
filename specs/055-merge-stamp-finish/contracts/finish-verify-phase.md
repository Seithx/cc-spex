# Contract: finish Phase 0 (verification)

## Arguments

`/speckit-spex-finish [--auto] [--no-verify] [--no-walkthrough] [--skip-archive]`. All flags combine freely.

## Phase order

1. Ship Pipeline Guard (unchanged), argument parsing.
2. **Phase 0: Verification** (new).
3. `before_finish` extension hooks (moved after Phase 0).
4. Phase 1: Walkthrough gate (unchanged).
5. Phase 2 onward: context detection, squash, select action, execute, cleanup (unchanged except FR-011a commit note).

## Phase 0 decision table

Evaluated top to bottom; first match wins.

| Condition | Output (exact first line) | Result |
|---|---|---|
| `--no-verify` | `Verification skipped (--no-verify).` | continue |
| spex-gates not enabled in registry | `Verification skipped: spex-gates is not enabled.` | continue |
| `spex-verify-record.sh check --feature "$FEATURE_DIR"` exits 0 | `Verification already passed for this code.` | continue |
| `$FEATURE_DIR/spec.md` does not exist, unattended | `Finish stopped: no spec found for verification.` then `Run /speckit-spex-finish --no-verify to land without verification.` | stop |
| `$FEATURE_DIR/spec.md` does not exist, interactive | invoke `/speckit-spex-gates-verify --embedded` without a path (verify's normal selection); `NO_SPEC` uses the stop row above | per result rows |
| invoke `/speckit-spex-gates-verify --embedded "$FEATURE_DIR/spec.md"` (plus `--auto` when unattended); gate PASS | `Verification passed.` | continue |
| verify gate FAIL | see Stop message | stop |
| verify did not complete (error, interruption) | `Finish stopped: verification did not complete.` then the error, then the `--no-verify` line | stop |

Unattended mode (`AUTONOMOUS_MODE` true) uses the same table with no prompts; stop rows still stop.

## Stop message (gate FAIL)

```text
Finish stopped: verification did not pass.
  - <gate name>: <one-line reason>
  - <gate name>: <one-line reason>
Fix the issues and rerun /speckit-spex-finish, or reconcile the spec with /speckit-spex-evolve.
To land without verification: /speckit-spex-finish --no-verify
```

Gate names are those verify reports: `closeout`, `tests`, `code hygiene`, `spec compliance`, `spec drift`, `success criteria`.

On any stop: no squash, no commit, no branch switch, no worktree change, `.spex-state` untouched.

## Verify `--embedded`

When present, verify runs all gates and writes the record on pass, but skips step 8 (no banner, no `rm -f .specify/.spex-state`). Submit Phase 1 also invokes `/speckit-spex-gates-verify --embedded`.
