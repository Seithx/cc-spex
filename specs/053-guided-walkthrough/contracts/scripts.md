# Contracts: Helper Script CLIs

The three helper scripts mirror the `spex-closeout-gate.sh` convention: explicit args, machine-readable stdout tokens, documented exit codes. The skill markdown delegates to these (Constitution VII).

## spex-walkthrough-workspace.sh

Create or resolve the persistent run workspace.

```
Usage: spex-walkthrough-workspace.sh <spec-dir> [--new]
```

- `<spec-dir>`: feature spec directory (e.g. `specs/053-guided-walkthrough`).
- `--new`: force a fresh timestamped workspace; without it, resolve the most recent one if present.

**Stdout**: `WORKSPACE_PATH <absolute-path>`
**Behavior**: creates `specs/<feature>/.walkthrough/<timestamp>/`; never deletes anything.
**Exit codes**: 0 success; 2 usage error.

## spex-walkthrough-coverage.py

Parse the spec and emit synthesis inputs + coverage.

```
Usage: spex-walkthrough-coverage.py <spec-file> [--json]
```

**Stdout (`--json`)**:
```json
{
  "skip": false,
  "stories": [{"id": "US1", "title": "...", "priority": "P1", "scenarios": ["..."], "frs": ["FR-001"]}],
  "fr_coverage": {"FR-001": ["US1"]},
  "orphan_frs": ["FR-030"]
}
```

- `skip` is `true` only when there are no user stories AND no acceptance scenarios (FR-006).
- `orphan_frs` lists FRs mapped to no story-derived scenario (FR-004).

**Exit codes**: 0 success (including `skip: true`); 1 parse error; 2 usage error.

## spex-walkthrough-lint.sh

Fail if any presented/reported command contains a placeholder.

```
Usage: spex-walkthrough-lint.sh <file-or-dir>
```

- Scans the target (e.g. `WALKTHROUGH.md`) for placeholder tokens: `<...>` angle-bracket placeholders, `TODO`, `PLACEHOLDER`, `scratch` used as a path stand-in, `/path/to/`, `<store>`, etc.

**Stdout**: `WALKTHROUGH_LINT_PASS` or `WALKTHROUGH_LINT_FAIL token=<matched>` (one per finding).
**Exit codes**: 0 clean; 1 placeholder found; 2 usage error.

## Report format contract (`WALKTHROUGH.md`)

Required structure (validated by lint + review):

```markdown
# Walkthrough Report

**Feature**: <name>
**Date**: <YYYY-MM-DD>
**Workspace**: <absolute path>   (remove with: `rm -rf <path>`)
**Result**: N passed, M failed, K skipped, J manual, D deferred

## Scenario 1: <title> (P1, from US1)
**Verdict**: PASS
### Step 1: <intent>
- Command: `<exact runnable command>`
- Ran by: agent | reviewer
- Expected: <...>
- Actual: <...>
- Artifact: <path or excerpt>
...

## Coverage
### User stories
| Story | Scenario | Verdict |
### Functional requirements
| FR | Covered by | Verdict |
### Orphan FRs
- FR-030 (not covered by any scenario)
```
