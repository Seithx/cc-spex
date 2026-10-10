# Quickstart: Validating the Guided Walkthrough

This guide proves the `speckit-spex-walkthrough` skill works end to end. Run it after implementation.

## Prerequisites

- spex plugin installed from the dev marketplace (`make install`).
- A feature with a spec that has at least two user stories with Given/When/Then acceptance scenarios (the CFP sample or any `specs/NNN-*/spec.md` qualifies).

## Scenario A: Helper scripts (deterministic parts)

```bash
# Coverage synthesis from stories + FRs
python3 -I spex/scripts/spex-walkthrough-coverage.py specs/053-guided-walkthrough/spec.md --json

# Workspace creation (persistent, printed path)
spex/scripts/spex-walkthrough-workspace.sh specs/053-guided-walkthrough --new

# Placeholder lint (should FAIL on a doc containing <scratch>)
spex/scripts/spex-walkthrough-lint.sh specs/053-guided-walkthrough/WALKTHROUGH.md
```

Expected: coverage JSON lists stories in priority order with `orphan_frs`; workspace command prints `WORKSPACE_PATH <path>` and the directory exists; lint exits non-zero when a placeholder is present, zero when clean. See [contracts/scripts.md](./contracts/scripts.md).

## Scenario B: Full walkthrough (interactive)

```bash
/speckit-spex-walkthrough
```

Expected (maps to acceptance scenarios in [spec.md](./spec.md)):

- Scenarios are presented in user-story priority order (US1 / FR-001).
- For each step the exact command is shown **before** it runs; after running, the real artifact is opened inline, not narrated (US1 / FR-011, FR-012).
- The run workspace path is printed and still exists after the run; every command uses that real path with no placeholders (US2 / FR-007..010, SC-001/003/006).
- A step the agent cannot run is delegated with its exact command; the reviewer can take over any step (US3 / FR-014/015).
- `WALKTHROUGH.md` is written with scenarios, commands, artifacts, verdicts, and coverage (incl. orphan FRs) (US4 / FR-019/020).

## Scenario C: Honest skip + unattended pipeline

```bash
# A spec with no user stories and no acceptance scenarios
/speckit-spex-walkthrough      # expect: honest skip, report still written (FR-006)

# Inside an unattended ship (--ask never, no human)
/speckit-spex-ship --ask never # expect: walkthrough skipped with "manual walkthrough required",
                               # scenarios recorded deferred, pipeline continues (FR-022)
```

## Success check

Cross-reference the run against [spec.md](./spec.md) Success Criteria SC-001..SC-007. The key proofs: every reported command runs verbatim (SC-001), every PASS is independently reproducible (SC-002), zero placeholders (SC-003), a report exists on every exit (SC-004), every FR is covered-or-orphan (SC-005), the workspace persists (SC-006), and no step passes without real evidence (SC-007).
