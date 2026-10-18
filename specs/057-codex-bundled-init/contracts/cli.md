# Contracts: Bootstrap and Extension Selection

## `spex/codex/skills/cc-spex-init/scripts/bootstrap.sh`

Run by the `cc-spex-init` Codex skill, with the working directory at the project root.

```
bootstrap.sh [--integration codex|claude|opencode|auto]
             [--extensions recommended|all|interactive|NAME,NAME]
             [--security safe|autonomous|yolo|interactive]
             [--help]
```

**Source resolution** (FR-009, first match wins):
1. `SPEX_SOURCE`, which must contain `setup.yml` and `extensions/spex`, otherwise exit 1.
2. `./spex` in the current directory, when it contains `setup.yml` and `extensions/spex` (the cc-spex repository).
3. The bundled plugin tree: four directories above the script. It must contain `setup.yml` and `extensions/spex/extension.yml`; otherwise the script exits 1 with an error naming the missing part and suggesting `SPEX_SOURCE` (FR-010).

The script never runs `git clone`, never downloads anything and never creates a temporary directory (FR-008). It no longer requires `git` on `PATH`.

**Inputs passed to `specify workflow run <source>/setup.yml --json`** (FR-011):

| Input | Passed when |
|-------|-------------|
| `integration` | Always. Value from `--integration`, default `codex` |
| `extensions` | `--extensions` was given, or `.specify/spex.json` is missing (then `recommended`) |
| `security` | `--security` was given, or `.specify/spex.json` is missing (then `safe`) |

The environment passes `SPEX_SOURCE=<resolved source>`.

**Exit codes**: 0 success, 1 missing prerequisite or invalid source, 2 usage error. The exit code of `specify workflow run` is passed through.

**Output**: one stderr line naming the source used (`bundled`, `SPEX_SOURCE`, or `repository`) and the effective inputs, then the workflow's output.

## `spex/scripts/spex-apply-extensions.sh`

Makes the enabled set of optional spex extensions match a resolved selection (FR-003, FR-006, FR-018). Used by `setup.yml`, `spex-init.sh` and the init skill.

```
spex-apply-extensions.sh [--before <registry-snapshot.json>] <comma-separated resolved selection>
```

- `--before`: a copy of `.specify/extensions/.registry` taken before the extensions were reinstalled. Changes are reported against it, so only real changes print. Without it, changes are reported against the current registry.

- The selection is the already resolved list (core `spex` and dependencies included), as printed by `spex-setup-profile.py resolve ... | jq -r '.extensions | join(",")'`.
- **Optional extensions**: `spex-gates`, `spex-worktrees`, `spex-deep-review`, `spex-teams`, `spex-collab`, `spex-detach`. For each installed one, the script runs `specify extension enable` when it is in the selection and `specify extension disable` when it is not. Nothing runs when the state already matches.
- **Never disabled**: `spex` (always enabled) and every extension spex does not ship (for example `git`).
- **`git` dependency**: when `spex-worktrees` is selected, the script enables the spec-kit `git` extension if it is installed but disabled. It never disables `git`. A failed `git` enable (or a missing `git` extension) only prints a warning on stderr and does not change the exit code: the git checks in `setup.yml` (`enforce-git-extension`) and `spex-init.sh` (`worktrees_git_error`) report that error with the FR-019 guidance.
- **Missing extension**: a selected extension that is not installed is an error (exit 1, named on stderr). Unselected extensions that are not installed are ignored.
- **Output** (stderr, so workflow steps that capture stdout keep it clean): one line per change, `Enabled: <ext>` or `Disabled: <ext>`, then `Extensions: <n> enabled, <m> disabled, <k> unchanged`. Stdout stays empty.
- **Exit codes**: 0 when every required change succeeded, 1 when an enable or disable failed or a selected extension is not installed (the extension is named), 2 for usage errors (empty selection, unknown names, unreadable `--before` file).

## Selection resolution (setup.yml `selected-extensions`)

| Mode / input | Resolved optional set |
|--------------|----------------------|
| `recommended` | gates, worktrees, deep-review |
| `all` | gates, worktrees, deep-review, teams, collab (no `spex-detach`) |
| interactive, reply "all" | same as `all` |
| interactive, empty reply | same as `recommended` |
| explicit list / interactive list | the list, plus `spex-gates` when deep-review, teams or collab is listed |
| refresh, no input | the declaration's `extensions` |

## Legacy `spex-detach` migration (`spex-setup-profile.py migrate-detach`)

```
spex-setup-profile.py migrate-detach --root "$PWD" --before <registry-snapshot.json>
```

- When `.specify/spex.json` lists `spex-detach` and the snapshot has `spex-detach` with `enabled: false`, the script rewrites the declaration without `spex-detach` (atomically, like `persist`) and prints `Migrated: removed spex-detach from .specify/spex.json (it was disabled; select it explicitly to enable it)` on stderr.
- Otherwise it changes nothing and prints nothing. A missing `--before` file (for example a fresh clone with a committed `spex.json` but no registry yet) also means no change and exit 0.
- Exit 0 in both cases, 1 when the declaration is invalid, 2 for usage errors.
- Callers run it only on a refresh without an explicit extension selection, before the declaration is read.

## Declaration written by `/spex:init` (FR-022)

```
RESOLVED=$(spex-setup-profile.py resolve --root "$PWD" --extensions "spex${csv:+,$csv}" \
  --legacy-permissions <none|standard|yolo> [--harness claude])
spex-apply-extensions.sh "$(printf '%s' "$RESOLVED" | jq -r '.extensions | join(",")')"
printf '%s' "$RESOLVED" | spex-setup-profile.py persist --root "$PWD"
```

Order: resolve, then apply, then persist. `--extensions` always starts with `spex`, so choosing no optional extension yields `["spex"]` instead of falling back to the stored selection (`resolve` keeps the stored value only when `--extensions` is empty).

`--harness claude` is passed only when `spex-init.sh` reported `DECLARATION_EXISTED=false` in Step 1 (its own setup run always writes a declaration, so the file's presence in Step 2 says nothing).
