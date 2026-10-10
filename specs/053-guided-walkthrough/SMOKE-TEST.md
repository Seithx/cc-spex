# Guided Demo Report

**Feature**: Guided Walkthrough (pair testing)
**Date**: 2026-10-10
**Spec**: spec.md
**Result**: User-skipped (0 passed, 6 skipped, 0 failed, 0 manual out of 6)

---

## Summary

The reviewer chose "Skip guided demo" at the readiness gate. No flows were
executed. This report is written so every run produces an artifact (SC-004).

The feature rewrites the smoke-test skill into a guided-walkthrough skill. Five
flows exercise fully-runnable deterministic deliverables (the three
`spex-walkthrough-*` scripts and their test suites, plus the command rename and
doc propagation). One flow (the new skill's interactive prompt behavior) is
manual because the new `/speckit-spex-walkthrough` skill is not installed as an
active skill in this session and cannot be driven live.

## Synthesized Flows (all skipped by user choice)

1. **Run-workspace lifecycle** (full) — Covers FR-007, FR-008, FR-009
   `spex-walkthrough-workspace.sh <spec-dir>` creates a persistent, gitignored
   run workspace, prints its path, never deletes, and resolves latest vs `--new`.
2. **Coverage + orphans + skip gate** (full) — Covers FR-003, FR-004, FR-006, FR-024
   `spex-walkthrough-coverage.py <spec> --json` emits stories in priority order,
   FR→story coverage, orphan FRs, and the skip signal.
3. **Placeholder lint gate** (full) — Covers FR-010, FR-025
   `spex-walkthrough-lint.sh <file-or-dir>` passes on clean text, exits 1 on a
   placeholder token such as `<scratch>`.
4. **Command rename + doc propagation** (full) — Covers FR-023, FR-005
   smoke-test renamed to walkthrough across command, help, README, manifest,
   changelog; the observable/internal keyword heuristic removed.
5. **Script test suites** (full) — Covers FR-024, FR-025
   `tests/test_walkthrough_{workspace,coverage,lint}.sh` pass.
6. **New walkthrough skill interactive behavior** (manual) — Covers FR-001, FR-002, FR-011–FR-022
   Requires running the installed `/speckit-spex-walkthrough` skill interactively.

## FR Coverage

| FR | Flow | Verdict |
|----|------|---------|
| FR-001 | Flow 6 | SKIP |
| FR-002 | Flow 6 | SKIP |
| FR-003 | Flow 2 | SKIP |
| FR-004 | Flow 2 | SKIP |
| FR-005 | Flow 4 | SKIP |
| FR-006 | Flow 2 | SKIP |
| FR-007 | Flow 1 | SKIP |
| FR-008 | Flow 1 | SKIP |
| FR-009 | Flow 1 | SKIP |
| FR-010 | Flow 3 | SKIP |
| FR-011 | Flow 6 | SKIP |
| FR-012 | Flow 6 | SKIP |
| FR-013 | Flow 6 | SKIP |
| FR-014 | Flow 6 | SKIP |
| FR-015 | Flow 6 | SKIP |
| FR-016 | Flow 6 | SKIP |
| FR-017 | Flow 6 | SKIP |
| FR-018 | Flow 6 | SKIP |
| FR-019 | Flow 6 | SKIP |
| FR-020 | Flow 6 | SKIP |
| FR-021 | Flow 6 | SKIP |
| FR-022 | Flow 6 | SKIP |
| FR-023 | Flow 4 | SKIP |
| FR-024 | Flow 2, Flow 5 | SKIP |
| FR-025 | Flow 3, Flow 5 | SKIP |
