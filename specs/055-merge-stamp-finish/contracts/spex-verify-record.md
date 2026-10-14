# Contract: `spex-verify-record.sh`

POSIX sh. Requires `git` and `jq`. Resolves `spex-runbook-status.sh` from its own directory. Runs against the git repository of the current working directory.

## Subcommands

### `record [--feature <spec-dir>]`

Writes the verification record for the current content fingerprint (see [data-model.md](../data-model.md)).

- stdout: `VERIFY_RECORDED fingerprint=<sha> feature=<dir>`
- exit 0 on success; 2 when not in a git repository or the fingerprint cannot be computed.

### `check [--feature <spec-dir>]`

- stdout: one JSON object: `{"state": "verified|stale|missing|unreadable", "fingerprint": "<current>", "recorded": "<recorded or null>", "verified_at": "<ts or null>", "feature": "<dir or null>"}`
- exit 0 when `state` is `verified`; 1 for `stale`, `missing`, `unreadable`; 2 on error (not a git repository, usage).

### `path`

- stdout: absolute path of the record file. exit 0; 2 when not in a git repository.

### `clear`

- Removes the record file if present. stdout: `VERIFY_CLEARED`. exit 0.

### Usage errors

Unknown subcommand or missing option value: usage text on stderr, exit 2.

## Callers

| Caller | Call | Effect |
|---|---|---|
| verify (step 7, on pass) | `record --feature "$FEATURE_DIR"` | Replaces the TMPDIR marker `touch`. |
| finish Phase 0 | `check --feature "$FEATURE_DIR"` | exit 0: print "Verification already passed for this code." and skip verify. |
| `pretool-gate.py` reminder | `check` | exit 0: no reminder. |
| `verify-gate.sh` reminder | `check` | exit 0: `allow`. |
