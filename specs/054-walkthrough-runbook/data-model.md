# Data Model: Walkthrough as a Runbook

## Runbook (`RUNBOOK.md`)

Location: `specs/<feature>/RUNBOOK.md`, or `specs/<feature>/.walkthrough/RUNBOOK.md` in detach mode when the normal path is not ignored (research R4).

### Frontmatter (written only by `spex-runbook-status.py`)

| Key | Type | Meaning |
|-----|------|---------|
| `runbook_version` | int | Format version, `1` |
| `feature` | string | Spec directory name, e.g. `054-walkthrough-runbook` |
| `status` | enum | `drafted`, `in_progress`, `passed`, `failed` (derived, see below) |
| `mode` | enum | `light`, `full` |
| `steps_total` | int | Number of steps in the journey |
| `step_results` | csv | One entry per step: `pending`, `passed`, `failed`, `skipped` |
| `drafted_at` | sha | HEAD when drafted |
| `drafted_fingerprint` | hash | Code fingerprint when drafted (research R1) |
| `tested_at` | sha or empty | HEAD when the last step result was recorded |
| `tested_fingerprint` | hash or empty | Code fingerprint when the last step result was recorded |
| `updated` | date | `YYYY-MM-DD` of the last change |

### Human status line

Between `<!-- runbook-status -->` and `<!-- /runbook-status -->` directly below the H1, regenerated from frontmatter, e.g.:

```
> **Status:** passed · 6 of 6 steps (5 passed, 1 skipped) · Mode: light · Tested at 3f2a1c9 · 2026-10-11
```

### Body sections (written by the agent, structure enforced by `spex-runbook-check.py`)

1. `# Try it: <feature title>`
2. `## What you're testing`: overview and the journey's order (FR-004)
3. `## Test environment`: one entry per fixture with how it was set up, owner, teardown command (FR-009)
4. `## Steps`: `### Step N of M: <title> (US<k>)` blocks (FR-004a, FR-005)
5. `## Not covered here`: untestable parts with reasons (FR-003), omitted when empty
6. `## Coverage`: stories covered and not covered with reasons (FR-004a)
7. `## Results`: summary written at wrap-up

### Status derivation (FR-010a)

| Condition (evaluated in order) | status |
|---|---|
| all results `pending` and no step presented yet | `drafted` |
| any result `failed` | `failed` |
| any result `pending` | `in_progress` |
| every result `passed` or `skipped` | `passed` |

The "presented yet" fact is recorded by the first `step` call: once any result changes from `pending`, `drafted` is no longer possible.

## Step

| Field | Required | Notes |
|---|---|---|
| Heading `### Step N of M: <title> (US<k>)` | yes | Story tag per FR-004a |
| `**Why this step:**` | yes | Purpose in plain words |
| `**Needs:**` | no | Earlier steps or fixtures |
| `**Run:**` + fenced block, or `**Do:**` list | one of | `Do:` for browser or GUI steps |
| `**What you should see:**` | yes | Written before execution (FR-006) |
| `**If you see something else:**` | yes | Symptom to meaning |
| `**Result:**` | yes | Filled during the session (FR-024) |

Result content: verdict, who ran it (agent or user), expected-versus-actual comparison per observation, quoted output lines or log path, correction note if the step was fixed (FR-026).

## Fixture record (`.walkthrough/fixtures.json`)

```json
{
  "fixtures": [
    {
      "name": "postgres",
      "kind": "container",
      "tier": "quick",
      "owner": "agent",
      "id": "3c1f0a...",
      "pid": null,
      "log": ".walkthrough/fixtures/postgres.log",
      "started": "2026-10-11T08:00:00Z",
      "teardown": "podman stop 3c1f0a && podman rm 3c1f0a",
      "state": "running"
    }
  ]
}
```

| Field | Values |
|---|---|
| `kind` | `process`, `container`, `compose`, `external` |
| `tier` | `quick`, `slow`, `remote` |
| `owner` | `agent`, `user` |
| `state` | `running`, `stopped`, `kept`, `unknown` |

Only `process`, `container`, and `compose` fixtures are started and stopped by the script. `external` covers slow and remote fixtures set up by project tooling or the user; they carry a teardown command and are never stopped automatically (FR-019).

## Workflow state additions (`.specify/.spex-state`, when present)

| Key | Meaning |
|---|---|
| `walkthrough_not_testable_fingerprint` | Code fingerprint at which the walkthrough judged the feature not testable (FR-002, FR-033) |

The previous keys `smoke_test_completed`, `smoke_test_commit_hash`, `smoke_test_scenarios`, `smoke_test_total` are no longer read anywhere (FR-040).

## Status query result (`spex-runbook-status.py show`)

```json
{
  "exists": true,
  "path": "specs/054-walkthrough-runbook/RUNBOOK.md",
  "readable": true,
  "status": "in_progress",
  "mode": "light",
  "steps": {"total": 6, "passed": 2, "failed": 0, "skipped": 1, "pending": 3},
  "drafted_at": "ab030e0",
  "tested_at": "0bdb95c",
  "current": true,
  "changed_since_draft": false,
  "changed_files": [],
  "changed_files_note": null,
  "not_testable": false
}
```

`changed_files_note` is set (e.g. `"commit ab030e0 no longer exists (history rewritten); file list unavailable"`) when the fingerprints differ but the recorded commit cannot be diffed.

When `exists` is false and the state records a matching not-testable fingerprint, `status` is `not_testable`. When the frontmatter cannot be parsed, `readable` is false and `status` is `unreadable` (FR-033).
