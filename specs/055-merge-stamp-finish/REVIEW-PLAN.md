# Plan Review: 055-merge-stamp-finish

**Date**: 2026-10-13
**Result**: PASS with findings (1 Critical, 3 Important, 5 Minor). No red flags. Every FR has at least one task.

## Coverage Matrix

| Requirement | Tasks |
|---|---|
| FR-001, FR-002, FR-003, FR-009, FR-009a, FR-016 | T006 |
| FR-004, FR-005, FR-011a | T008 (T006 parses flag) |
| FR-006, FR-009c, FR-009d | T002, T003, T004 |
| FR-007 | T005 |
| FR-008 | T022 |
| FR-009b | T005, T007 |
| FR-010 | T011, T012, T013, T017 |
| FR-011, FR-014 | T005, T009, T010 |
| FR-012 | T014, T015 |
| FR-013 | T016 |
| FR-015 | T013, T018, T019, T020, T021 |
| SC-001..SC-005 | T023, T024, T025 (quickstart) |

## Findings

1. **[Critical] T014 / FR-012**: T014 removes `STAGE_NAMES[8]` and `stage_name 8)` but only says "check `STAGE_SKILLS`/`skill_to_stage` for a stamp entry". Neither contains the string "stamp"; both map index 8 to `spex:verification-before-completion`. Leaving `STAGE_SKILLS[8]` makes `SKILL_TO_STAGE` resolve that skill to 8, and `pretool-gate.py` line ~226 then does `STAGE_NAMES[8]`, a KeyError. **Fix**: T014 must explicitly remove index 8 from `STAGE_SKILLS` (pretool-gate.py:174), the `8:` brief in `_stage_brief` (~264-271), and in stage-gate.sh `stage_skill 8)` (line 52), `skill_to_stage` (line 83), and the `8)` BRIEF case (line 127).
2. **[Important] T005/T006 / FR-005, SC-002**: Finish resolves `FEATURE_DIR` itself (state, feature.json, `specs/<branch>`), but verify resolves its own via `check-prerequisites.sh` and records that. If they differ, `check --feature` is always `stale` and finish re-verifies forever. **Fix**: T006 passes `$FEATURE_DIR/spec.md` as verify's spec argument. T005 makes verify derive `FEATURE_DIR` from the spec argument or picker selection before `record`.
3. **[Important] T006 / FR-009**: The "no spec resolvable" row has no concrete test, and the `specs/<branch>` fallback always yields a string. **Fix**: define the row as `[ ! -f "$FEATURE_DIR/spec.md" ]` after all fallbacks. Reuse that `FEATURE_DIR` in Phase 1 Step 2 instead of resolving it again.
4. **[Important] T018 / FR-013, FR-015**: README still says ship runs "through verification" (lines 20, 127, 368) and has "all nine stages" (line 127). "Fix workflow text" is too vague to catch these. **Fix**: list those lines explicitly and replace them with "eight stages ending at review-code; verification runs in finish or submit".
5. **[Minor] T005 / clarification Q2**: suppressing the spec picker whenever `--embedded` is set goes further than the spec, which stops without a picker only in unattended mode. **Fix**: suppress the picker only when `AUTONOMOUS_MODE`/`--auto`, or record this as an intentional choice.
6. **[Minor] T008 / FR-011a**: "add the FR-011a note to the squash step" could be read as skipping Step 5 (commit message approval). **Fix**: state that only the verification-reminder confirmation is skipped, and message approval stays.
7. **[Minor] T016**: rewording ship.md line 390 to "Do NOT skip review-code..." repeats line 389. **Fix**: delete line 390. Also list line 806 ("walk through, squash, and merge") among the finish descriptions.
8. **[Minor] T019, T020**: help.md has more finish descriptions at lines 218, 221, and 227. Evolve line 27 already lists finish. **Fix**: enumerate all of them, and change evolve line 26 to `speckit-spex-gates-verify` only.
9. **[Minor] T009/T010, Performance Goal** (see re-review below): no automated test for either reminder hook reading the record, and the 5 s budget is never measured. **Fix**: add cases to `tests/test_verify_record.sh` (or a hook test) that pipe a commit payload to both hooks with and without a record, and time `check`.

## Re-review (after fixes)

**Result**: PASS. Findings 1 to 8 are resolved, and finding 9 is resolved for `verify-gate.sh`. One Minor point is still open.

- 1: Resolved. T014 removes every index-8 entry in both files and adds a key-consistency check.
- 2, 3: Resolved. T005 derives `FEATURE_DIR` from the spec argument. T006 resolves it once (via `feature_directory`, which matches the `.specify/feature.json` key), uses `[ ! -f "$FEATURE_DIR/spec.md" ]` for the no-spec case, and passes `"$FEATURE_DIR/spec.md"` to verify. The contract matches.
- 4, 7, 8: Resolved. README, ship.md, help.md, and evolve lines are listed explicitly.
- 5, 6: Resolved. The picker is suppressed only in unattended runs, and Step 5 message approval is kept.
- 9: Partly resolved. `tests/test_verify_gate.sh` covers the shared hook and its timing. The argument order matches the `verify-gate.sh` usage (`<tool> <command> <session> <cwd>`).

### New / remaining

- **[Minor] T009**: the Claude `pretool-gate.py` reminder still has no automated test. **Fix**: add one case to `tests/test_verify_gate.sh` that pipes a `{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"<repo>"}` payload to `pretool-gate.py`, with and without a record.
