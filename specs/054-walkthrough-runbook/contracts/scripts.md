# Script Contracts

All scripts live canonically in `spex/scripts/` and are synced into extension `scripts/` directories by `make sync-scripts`. Commands call them via `.specify/extensions/<own-ext>/scripts/<name>`. All JSON goes to stdout; diagnostics go to stderr.

## spex-runbook-status.sh (shim) / spex-runbook-status.py

Synced to: `spex`, `spex-gates`.

| Subcommand | Arguments | Behavior | Exit |
|---|---|---|---|
| `locate` | `<spec-dir> [--create]` | Prints JSON `{"runbook": <path>, "scratch": <dir>, "detach": bool, "relocated": bool}`. With `--create`, creates the scratch folder with a `.gitignore` containing `*`. `relocated` is true when detach is on and the normal path is not git-ignored (research R4). | 0, 2 usage |
| `init` | `<runbook> --feature <name> --mode light\|full --steps <n>` | Adds or replaces frontmatter on an existing runbook file: status `drafted`, all results `pending`, `drafted_at` and `drafted_fingerprint` from the current tree, writes the status line. | 0, 1 file missing, 2 usage |
| `step` | `<runbook> <n> passed\|failed\|skipped\|pending` | Sets result `n` (1-based), sets `tested_at`, `tested_fingerprint`, `updated`, derives status (data-model table), rewrites the status line. Prints the new status JSON. | 0, 1 bad step number, 2 usage |
| `steps` | `<runbook> <n>` | Changes `steps_total` after review edits; extends with `pending` or truncates results. | 0, 2 usage |
| `mode` | `<runbook> light\|full` | Sets mode (upgrade from light to full; downgrade rejected with exit 1 when any result is not `pending`). | 0, 1, 2 |
| `show` | `<spec-dir\|runbook> [--no-git]` | Prints the status query JSON (data-model). `--no-git` skips fingerprint and diff work (used by the status line); `current` is then `null`. | 0 (also when missing: `exists: false`), 2 usage |
| `list` | `[<specs-root>]` (default `specs`) | Prints a JSON array of `show` results for every spec dir containing a runbook in either location. | 0 |
| `not-testable` | `<spec-dir>` | Writes `walkthrough_not_testable_fingerprint` into `.specify/.spex-state` if that file exists; no-op otherwise. | 0 |
| `fingerprint` | none | Prints the current code fingerprint (research R1). | 0, 1 not a git repo |

## spex-runbook-check.sh (shim) / spex-runbook-check.py

Synced to: `spex`.

`spex-runbook-check.sh <runbook>`

Checks (research R8):
- frontmatter present and parseable; `steps_total` equals the number of step headings
- each step has Why, What you should see, If you see something else, and Run with a fenced block or Do
- no placeholders inside fenced command blocks
- no unredacted credential-looking strings anywhere

Output: `RUNBOOK_CHECK_PASS` or one `RUNBOOK_CHECK_FAIL <kind> line=<n> <detail>` per finding, where kind is `frontmatter`, `structure`, `placeholder`, or `secret`. Exit 0 clean, 1 findings, 2 usage or file missing.

## spex-runbook-fixture.sh

Synced to: `spex`. Requires `jq`.

| Subcommand | Arguments | Behavior |
|---|---|---|
| `start` | `<scratch> --name <n> --kind process\|container\|compose [--file <compose-file>] -- <cmd...>` | Starts a quick local fixture, records it with tier `quick`, owner `agent`, log under `<scratch>/fixtures/<n>.log`, and a teardown command. Fails with exit 1 if the name exists and is running. For `container`, `<cmd>` must be a detached `podman run -d ...`; the printed ID is recorded. |
| `record` | `<scratch> --name <n> --tier slow\|remote\|quick --owner agent\|user --teardown <cmd> [--note <text>]` | Records an `external` fixture (not started by the script). |
| `stop` | `<scratch> (--name <n> \| --quick)` | Stops one fixture or all `quick` fixtures started by the script. Never stops `external` fixtures. Process: TERM, wait up to 5 s, KILL. Container: `podman stop` then `podman rm`. Compose: `podman compose -f <file> down`. |
| `keep` | `<scratch> --name <n>` | Marks a slow or remote fixture as kept at session end. |
| `status` | `<scratch>` | Prints `fixtures.json` with `state` refreshed (process alive via `kill -0`, container via `podman inspect`). |

Exit codes: 0 success, 1 operation failed (message on stderr), 2 usage, 4 container runtime unavailable.

## spex-runbook-clip.sh

Synced to: `spex`.

`printf '%s' "<command>" | spex-runbook-clip.sh`

Tries `pbcopy`, `wl-copy`, `xclip -selection clipboard`, `xsel --clipboard --input` in order. Prints `CLIP_OK tool=<name>` and exits 0, or prints `CLIP_UNAVAILABLE` and exits 3. Exit 2 when stdin is empty.

## spex-finish-preserve-specs.sh

Synced to: `spex`.

`spex-finish-preserve-specs.sh <worktree-path> <main-worktree> <feature-dir>`

If detach is enabled (checked in `<worktree-path>` with `spex-detach.sh is-enabled`) and `<worktree-path>/<feature-dir>` exists, copies it to `<main-worktree>/<feature-dir>` with `rsync -a` (no deletes), and prints `PRESERVED <feature-dir>`. Otherwise prints `PRESERVE_SKIPPED reason=<detach-off|no-spec-dir>`. Exit 0 in both cases, 1 if the copy failed, 2 usage.

## Removed

`spex-walkthrough-workspace.sh`, `spex-walkthrough-coverage.py`, `spex-walkthrough-lint.sh` (both copies) and `tests/test_walkthrough_{workspace,coverage,lint}.sh`.
