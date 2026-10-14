# Data Model: Merge stamp into finish

## Verification record

File: `$(git rev-parse --git-path spex-verified.json)` (one per worktree). Written only by `spex-verify-record.sh record`; read only by `spex-verify-record.sh check`.

| Field | Type | Description |
|---|---|---|
| `version` | integer | Record format version, `1`. |
| `fingerprint` | string | SHA-256 content fingerprint from `spex-runbook-status.sh fingerprint` at record time. |
| `head` | string | Short HEAD commit at record time (informational only, not used for matching). |
| `feature` | string | Spec directory that was verified (e.g. `specs/055-merge-stamp-finish`), or empty. |
| `verified_at` | string | UTC ISO-8601 timestamp. |

### Rules

- **Match**: `check` reports verified when the file exists, parses, has `version: 1`, and its `fingerprint` equals the current fingerprint. When `check --feature <dir>` is given and the record has a non-empty `feature`, both must match too.
- **Write**: `record` overwrites the file atomically (temp file plus rename). A failed or interrupted verify never calls `record`.
- **Invalidation**: implicit. Any non-spec content change changes the fingerprint, so `check` reports `stale`. `clear` deletes the file.
- **Unreadable** (bad JSON, unknown version): `check` reports `unreadable` and exits 1; finish treats it as not verified.

### `check` states

| State | Exit | Meaning |
|---|---|---|
| `verified` | 0 | Record matches the current code. |
| `stale` | 1 | Record exists but the fingerprint (or feature) differs. |
| `missing` | 1 | No record file. |
| `unreadable` | 1 | Record cannot be parsed or has an unknown version. |
| (error) | 2 | Not a git repository, or usage error. |

## Finish run (transient)

| Variable | Source | Values |
|---|---|---|
| `SKIP_VERIFY` | `--no-verify` | true/false |
| `GATES_ENABLED` | registry check (R5) | true/false |
| `VERIFY_RESULT` | Phase 0 | `skipped-flag`, `skipped-no-gates`, `already-verified`, `passed`, `failed`, `no-spec`, `incomplete` |

Only `skipped-flag`, `skipped-no-gates`, `already-verified`, and `passed` let finish continue to the `before_finish` hooks and Phase 1.
