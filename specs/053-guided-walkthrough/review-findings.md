# Deep Review Findings

**Date:** 2026-10-10
**Branch:** 053-guided-walkthrough
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** superpowers (after_implement → review-code → deep-review)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 6 | 6 | 0 |
| Minor | 6 | 6 | 0 |
| Notable | 2 | 2 | 0 |
| **Total** | **14** | **14** | **0** |

**Internal agents completed:** 5/5 (Correctness, Architecture, Security, Production Readiness, Test Quality). Goal Alignment skipped (no PR).
**External tools:** CodeRabbit completed (6 findings, all overlapping internal findings or noted below); Codex failed (usage limit reached); Copilot skipped (CLI not installed).

## Findings and resolutions

### Correctness
- **C1 (Notable→fixed):** `spex-walkthrough-coverage.py` skip gate — the `and total_scenarios == 0` clause was effectively dead (scenarios counted only within story spans), so a spec with acceptance scenarios not nested under a `### User Story N (Priority: Pn)` heading would be wrongly skipped (FR-006 gap). **Fixed:** added `_count_acceptance_scenarios()` that counts acceptance scenarios document-wide; `skip` is now genuinely `no stories AND no scenarios`. (Also reported by CodeRabbit.)
- **C2 (Notable→fixed):** `test_walkthrough_workspace.sh` success-path `OUT=$(...); RC=$?` under `set -euo pipefail` could never fail the exit-0 assertion. **Fixed:** wrapped in `set +e`/`set -e`. (Also Test-Quality T3.)

### Architecture
- **A1 (Important→fixed):** `extension.yml` `finish` entry description still read "Smoke test + squash..." (missed in the rename). **Fixed** to "Walkthrough + squash...".
- **A2 (Minor→fixed):** `finish.md` local vars `SMOKE_COMPLETED`/`SMOKE_COMMIT_HASH` inconsistent with verify.md. **Fixed:** renamed to `WALKTHROUGH_COMPLETED`/`WALKTHROUGH_COMMIT_HASH` (still reading the retained `.smoke_test_*` state keys).
- **A3 (Minor→fixed):** dead `SHIP_STATE_SCRIPT` assignment in finish.md Step 2. **Fixed:** removed.

### Production Readiness
- **P1 (Important→fixed):** skill parsed the workspace path with `awk '{print $2}'`, truncating paths containing spaces (common on macOS). **Fixed:** strip the `WORKSPACE_PATH ` prefix without whitespace-splitting; quote `"$WORKSPACE"` everywhere.
- **P2 (Important→fixed):** app PID held only in a shell var could not survive across fresh shells, and `lsof` may be absent, risking a leaked app process. **Fixed:** persist PID+port to `$WORKSPACE/.app.pid`; Step 7 reads it and escalates SIGTERM→SIGKILL, with a manual-stop notice fallback.
- **P3 (Minor→fixed):** report only written at Step 5, so an abnormal mid-loop exit left no report (SC-004 exposure). **Fixed:** skill now writes a skeleton `WALKTHROUGH.md` right after synthesis and finalizes it at the end.

### Test Quality
- **T1 (Important→fixed):** skip-gate boundary untested. **Fixed:** added "stories but no scenarios → skip false" and "standalone scenarios, no stories → skip false" cases.
- **T2 (Important→fixed):** suffixed FR ids (FR-011a) parsing/sort untested. **Fixed:** added a case asserting distinct coverage keys and `011 < 011a < 012` ordering.
- **T4 (Important→fixed):** resolve "most recent" never tested with >1 workspace. **Fixed:** added a two-workspace resolve assertion.
- **T5 (Minor→fixed):** lint `PLACEHOLDER` token, per-trigger FAIL-token output, and non-false-positive behavior untested. **Fixed:** added PLACEHOLDER, token-content assertions, and a near-miss (`<Foo>`, `<=`) negative case.
- **T6 (Minor→fixed):** workspace "spec dir not found" exit-2 branch untested. **Fixed:** added a case asserting exit 2 and that no `.walkthrough` dir is fabricated.

### External (CodeRabbit)
- CR findings on the coverage skip gate and finish-state handling overlapped C1/A2 and were fixed.
- **CR3/CR4 (addressed):** finish.md now documents that the walkthrough self-detects an unattended pipeline (writes a deferred report, returns) and that completion is recorded with HEAD after it returns.
- **CR1 (noted, not fixed):** the walkthrough reuses the retained `.smoke_test_completed` state key, so a pre-rename smoke-test record at the same commit could cause finish to skip re-running the walkthrough. Low impact because the walkthrough is advisory (FR-021a) — a stale skip never blocks. Renaming the state schema touches ship-state plumbing and is out of this feature's scope.
- **CR2 (noted, not fixed):** `spex-walkthrough-lint.sh` scans the whole report, not only command fields. This is per contract (scripts.md), and the lowercase-only angle-bracket rule limits false positives; structured per-field scanning is a future refinement.
- **CR6 (noted, not fixed):** coverage maps FRs referenced anywhere in a story span (narrative + scenarios), a deterministic approximation of FR-003's "exercised by a step"; the skill refines the mapping at runtime. Step-level static attribution is out of scope.

## Post-Fix Spec Coverage

No functional requirement was removed by the fix round (edits were a skip-gate helper, a docstring/variable rename, a dead-line removal, skill robustness additions, and test additions). All 27 FRs remain implemented; the test suite was strengthened. **All spec requirements verified after the fix round.**

## Test Suite Results

| Round | Test Command | Result |
|-------|-------------|--------|
| 1 | test_walkthrough_coverage.sh | 22/22 pass |
| 1 | test_walkthrough_workspace.sh | 14/14 pass |
| 1 | test_walkthrough_lint.sh | 13/13 pass |
| 1 | make test-generated-trees | pass |
| 1 | make sync-scripts-check | in sync |

## Gate

**PASS** after 1 fix round. 0 Critical, 0 Important remaining.
