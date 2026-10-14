# Code Review: Merge stamp into finish

**Spec:** specs/055-merge-stamp-finish/spec.md
**Date:** 2026-10-13
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 100%** (initially 95%: one FR-013 deviation, fixed in commit 18c81d6)

- Functional Requirements: 21/21 (100%)
- Error Handling: 4/4 (100%) (gate failure, no spec, incomplete verify, record unavailable)
- Edge Cases: 5/5 (100%)
- Non-Functional (SC-001 to SC-005): 5/5 (100%)
- Spec-declared constants: none (no `## Constants` section)

## Detailed Review

### Functional Requirements

| Req | Implementation | Status |
|-----|---------------|--------|
| FR-001 verification first | finish.md Phase 0, before Pre-Execution hooks | Compliant |
| FR-002 stop on failure, both paths, no continue | finish.md gate-failure stop message, "On any stop row" | Compliant |
| FR-003 unattended no prompt | finish.md `--auto` sets AUTONOMOUS_MODE, passes `--auto` to verify | Compliant |
| FR-004 `--no-verify` + other flags | finish.md argument parsing, table row 1 | Compliant |
| FR-005 skip on recorded pass | finish.md table row 3 (`check --feature`) | Compliant |
| FR-006 tied to code state | spex-verify-record.sh + runbook fingerprint (excludes specs/, brainstorm/) | Compliant |
| FR-007 only passing runs record | verify.md step 7 (`begin`/`record`, no record on fail) | Compliant |
| FR-008 no spex-gates | finish.md row 2 (registry check) | Compliant |
| FR-009 / FR-009a stop shapes | finish.md rows 4, 7, 8 and stop message block | Compliant |
| FR-009b `--embedded` | verify.md Arguments + step 8 skip; finish/submit pass it | Compliant |
| FR-009c deterministic script, walkthrough fingerprint | spex-verify-record.sh calls `spex-runbook-status.sh fingerprint` | Compliant |
| FR-009d git dir, untracked, survives clear | `git rev-parse --git-path spex-verified.json` | Compliant |
| FR-010 stamp removed | command file, manifest, both adapter maps, both context hooks, marketplace test | Compliant |
| FR-011 reminder text + shared record | pretool-gate.py, shared/verify-gate.sh; session marker no longer written | Compliant |
| FR-011a finish commits without confirm | finish.md Phase 3 Step 1 and Step 6 | Compliant |
| FR-012 stage 8 removed, status line | pretool-gate.py, stage-gate.sh, both statusline copies | Compliant |
| FR-013 ship text | ship.md description/overview; **deviation found**: extension.yml and agents-md templates still said "specify through verify". Fixed in 18c81d6 | Compliant (after fix) |
| FR-014 same record | both hooks run `spex-verify-record.sh check` | Compliant |
| FR-015 docs | README, both help files, using-superpowers, evolve, preambles, CLAUDE.md | Compliant |
| FR-016 finish description/hint | finish.md frontmatter | Compliant |

### Extra Features (Not in Spec)

- `spex-verify-record.sh begin` / `record --expect` (start-state check), and the finish Phase 3 re-check. These were added during the deep review so that a pass can never cover code that changed after the gates ran. They strengthen FR-007 and US1 and do not change the spec's observable behavior. Spec evolution candidate: mention the re-check in FR-001 or the Edge Cases.
- The fingerprint is seeded from the real index (a performance change with identical semantics).

## Deep Review Report

**Gate: PASS** (after fix round 3, final re-review clean)

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 6 | 4 | 0 (+1 Notable) | completed |
| Architecture & Idioms | 12 | 7 | 3 Minor (+2 Notable) | completed |
| Security | 3 | 0 | 1 Minor (+2 Notable) | completed |
| Production Readiness | 7 | 3 | 2 Minor (+2 Notable) | completed |
| Test Quality | 8 | 6 | 1 Minor (+1 Notable) | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| CodeRabbit (external) | 2 | 1 | 0 (1 dismissed) | completed (initial); re-review runs failed (WebSocket closed) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 0 | 0 | 0 | failed (usage limit) |
| Re-review rounds 1-3 | 16 | 12 | 3 Minor | completed |
| Test Suite (regression) | 0 | 0 | 0 | passed every round |

By severity: Critical 0/0/0; Important 9 found, 8 fixed, 0 remaining (1 dismissed as contradicting FR-006); Minor 34 found, 24 fixed, 10 remaining; Notable 8 (captured to brainstorm/idea-inbox.md).

MVP: Architecture & Idioms (12 findings)

Key fixes applied:
1. Verify records only when the code still matches the state stored by `begin` at the start of the run (correctness).
2. Finish re-checks the record before staging, since hooks or the walkthrough may change code (CodeRabbit, correctness).
3. Fingerprint performance: a seeded temp index, gated on a plain index so the semantics are identical (production, re-review).
4. Hook timeout: process-group SIGTERM, a drain wait, then SIGKILL, with no leaked temp index (production, re-review).
5. `fingerprint` from a subdirectory hashed nothing; fixed with `ls-tree --full-tree` (found by a new test).
6. Doc accuracy: ship stage order and count, help "Stage 8", README `after_implement` (architecture).
7. Tests: 30+ new assertions, including mutation-checked seeded-index equality and timeout cleanup (test quality).

Remaining findings: Minor only (see review-findings.md, "Remaining Findings").

Post-fix spec coverage: 21/21 requirements verified.

Details: review-findings.md

## Conclusion

The implementation complies with the spec at 100%. Deep review passes with no Critical or Important findings remaining. `make test-walkthrough`, `make sync-scripts-check`, and `make validate` all pass.
