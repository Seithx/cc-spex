# Data Model: Guided Walkthrough

These are conceptual entities the skill and its scripts manipulate. There is no database; state is the filesystem (run workspace + report).

## Scenario

A user-story-derived journey.

| Field | Type | Notes |
|-------|------|-------|
| id | string | Sequential, priority-ordered (P1 first) |
| title | string | From the user story title |
| priority | enum | P1 / P2 / P3 ... from the story |
| source_story | string | User Story reference |
| steps | list<Step> | Ordered |
| fr_coverage | list<string> | FR-NNN ids exercised by this scenario |
| verdict | enum | pass / fail / skip / manual / deferred |
| notes | string | Reviewer notes (optional) |

Derivation: `spex-walkthrough-coverage.py` emits scenario skeletons (id, title, priority, source_story, fr_coverage) from the spec; the skill fills `steps` from Given/When/Then and records `verdict`/`notes` at runtime.

## Step

A single action within a scenario.

| Field | Type | Notes |
|-------|------|-------|
| intent | string | The Given/When/Then fragment this step realizes |
| command | string | Exact, runnable command (no placeholders, real workspace path) |
| execution_mode | enum | agent-ran / reviewer-ran (delegated or taken-over) |
| artifact | ref | File path, log excerpt, tree, or screenshot opened for inspection |
| expected | string | What the spec says should happen |
| actual | string | What was observed |
| partial_disclaimer | string? | Present when run without full infrastructure |

## RunWorkspace

The persistent directory holding everything a run created.

| Field | Type | Notes |
|-------|------|-------|
| path | string | `specs/<feature>/.walkthrough/<timestamp>/` (gitignored, never auto-deleted) |
| created_at | timestamp | Part of the path |
| cleanup_command | string | The exact `rm -rf <path>` printed in the report |

Managed by `spex-walkthrough-workspace.sh`.

## WalkthroughReport (`WALKTHROUGH.md`)

Scenario-anchored record written on every exit path.

| Field | Type | Notes |
|-------|------|-------|
| feature | string | From spec title |
| date | date | Run date |
| workspace_path | string | RunWorkspace.path |
| result_summary | string | N passed / M failed / K skipped / J manual / D deferred |
| scenarios | list<Scenario> | Full detail incl. steps, commands, artifacts, verdicts |
| story_coverage | table | User story → scenario(s) → verdict |
| fr_coverage | table | FR → covering scenario, or "orphan" |
| orphan_frs | list<string> | FRs exercised by no scenario |

Validated by `spex-walkthrough-lint.sh` (no placeholder tokens; every FR present as covered or orphan).

## State transitions (verdict)

```
(new) → pass | fail | skip | manual | deferred
fail → (investigate → fix → retry) → pass | fail   [max 2 retries, FR-018]
unattended pipeline → all scenarios = deferred      [FR-022]
```
