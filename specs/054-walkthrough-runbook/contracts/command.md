# Command Contract: /speckit-spex-walkthrough

## Invocation

| Form | Behavior |
|---|---|
| `/speckit-spex-walkthrough` | Feature from the current branch. Existing runbook: run or resume. None: testability check, draft, then run. |
| `/speckit-spex-walkthrough --draft` | Testability check and draft only. No fixtures, no steps. Used by ship. |
| `/speckit-spex-walkthrough --force [what to try]` | Skip a "not testable" verdict and draft anyway, covering the given hint. |
| `/speckit-spex-walkthrough <feature>` | `<feature>` is a number prefix (`054`) or a spec directory name. Runs that runbook from any branch. |
| on the default branch, no feature argument | Picker over `spex-runbook-status.sh list` entries with status drafted, in_progress, or failed. |

Flags combine: `<feature> --draft`, `<feature> --force`.

## Phases

1. **Resolve** feature and runbook (`locate`, `show`). Unattended detection: ship state with `status: running` and `ask: never`, or finish called with its auto option.
2. **Testability check** (skipped when a runbook exists or `--force`). Not testable: one line with reason and override hint, `not-testable`, stop.
3. **Draft**: write `RUNBOOK.md` body, `init`, `spex-runbook-check.sh` until clean. Mode from heaviest fixture.
4. **Approve**: light mode, one question covering runbook and quick fixtures. Full mode, review pause, then tiered consent per fixture.
5. **Environment**: reuse existing, `fixture start` for quick, consent flow for slow and remote, `fixture record` for external.
6. **Steps**: per step, choices: run it yourself (clipboard), let the agent run it (omitted with reason when not possible), run the rest, skip. Results via `step`.
7. **Wrap-up**: results summary, stop quick fixtures, keep-or-teardown for slow and remote, `spex-runbook-check.sh`, commit offer on the default branch (FR-030a).

Unattended: phases 1 to 3 only; never prompts.

## Output in chat for an agent-run step (FR-023, FR-023a, FR-024)

```
Running: <exact command>

<full output, or: Output: 212 lines, saved to specs/054-x/.walkthrough/step-3.log>

Expected vs actual:
  ✔ "Plan written to .sandcast/build/openshell/plan.yaml"
      → line 41: Plan written to .sandcast/build/openshell/plan.yaml
  ✘ "Components already in the base marked skip"
      → found: all 18 components marked install (lines 12 to 29)
```

## finish integration (FR-033, FR-033a)

| `show` status | Interactive | Unattended |
|---|---|---|
| `passed`, `current: true` | "Walkthrough passed at <sha>", continue | same |
| `passed`, `current: false` | list changed files, offer rerun or continue | continue, print status |
| `in_progress` | offer resume or continue | continue, print status |
| `failed` | show failed step, offer continue or stop | continue, print status |
| `drafted` | offer run now or later | continue, print status |
| `not_testable` | continue | continue |
| `unreadable` | report, offer rerun or continue | continue, print status |
| missing | run the walkthrough | run with `--draft` |

`--no-walkthrough` skips the gate in every case.

## ship integration (FR-032)

At the end of the pipeline, before the closing prompt: invoke the walkthrough with `--draft`. The closing message includes either `Runbook drafted: <path> (<n> steps, <mode> mode). Try it now or later with /speckit-spex-walkthrough <number>.` or the one-line not-testable verdict with the override hint.
