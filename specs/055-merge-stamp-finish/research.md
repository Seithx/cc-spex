# Research: Merge stamp into finish

## R1: What identifies "the code that was verified"?

- **Decision**: Reuse `spex-runbook-status.sh fingerprint`: a SHA-256 over `git ls-tree -r` of a temp-index `write-tree` of the working tree, excluding `specs/` and `brainstorm/`.
- **Rationale**: Content-based, so committing verified content or finish's own "commit outstanding changes" step keeps the pass valid (SC-002), while any non-spec edit invalidates it (FR-006). Already tested and shipped for walkthrough currency, so both features agree on what "current" means.
- **Alternatives considered**: HEAD commit hash (breaks on commit-after-verify); HEAD plus dirty-diff hash (complex, still breaks on commit); session marker (does not survive `/clear`, the current bug).

## R2: Where does the record live?

- **Decision**: `$(git rev-parse --git-path spex-verified.json)`.
- **Rationale**: Per worktree (`.git/worktrees/<name>/` for linked worktrees, `.git/` for the main checkout), never tracked, never part of the fingerprinted tree, untouched by `/speckit-spex-clear` and ship state cleanup (FR-009d).
- **Alternatives considered**: `.specify/.spex-verified` (inside fingerprinted content in projects that do not gitignore `.specify/`; would invalidate itself); inside `.spex-state` (deleted by verify/ship/finish cleanup); `$TMPDIR` (not per worktree, lost on reboot).

## R3: How does verify know it is embedded?

- **Decision**: An explicit `--embedded` argument parsed by verify. Finish and submit pass it. With it, verify skips step 8 (banner and `rm -f .specify/.spex-state`).
- **Rationale**: Deterministic and visible in the invocation; no hidden environment coupling. Standalone verify keeps current behavior.
- **Alternatives considered**: An env var (invisible in command text, harness-dependent); checking `.spex-state` mode (ship runs verify standalone in some flows and finish runs in flow mode, so the mode does not identify the caller).

## R4: How do hooks find the script?

- **Decision**: Claude pretool hook (`spex/scripts/hooks/pretool-gate.py`): `Path(__file__).resolve().parent.parent / 'spex-verify-record.sh'`. Shared `verify-gate.sh` (used by Codex and OpenCode adapters): `$(dirname "$0")/../../spex-verify-record.sh`, falling back to `$CWD/.specify/extensions/spex-gates/scripts/spex-verify-record.sh`. If no script is found or `check` fails, the reminder fires (fail closed, same as today without a marker).
- **Rationale**: Hooks ship inside the plugin next to `spex/scripts/`; adapter installs may only have the extension copy.
- **Alternatives considered**: Re-implementing the fingerprint in each hook (duplicates logic, violates VII).

## R5: How does finish detect spex-gates?

- **Decision**: `jq -r '.extensions["spex-gates"].enabled // false' .specify/extensions/.registry`, the same check ship already uses for spex-worktrees and spex-teams.
- **Rationale**: Consistent with existing commands; the registry is spec-kit's source of truth.
- **Alternatives considered**: Presence of `.specify/extensions/spex-gates/` (a disabled extension may keep its directory).

## R6: The stale ship stage 8

- **Decision**: Remove index 8 from both stage maps (`pretool-gate.py` STAGE_NAMES, `stage-gate.sh`) and the `stamp|finish` case in both statusline copies becomes `finish` only. `spex-ship-state.py` already defines 8 stages (`total_stages: 8`), so index 8 is never reached.
- **Rationale**: Dead mapping that perpetuates the stamp name; ship's stages end at review-code.

## R7: Finish's own commits and the reminder

- **Decision**: The reminder hook is non-blocking context. Finish instructs: when the record check passed in Phase 0 or `--no-verify` was given, proceed with its own commits without asking. With the record now content-keyed, Phase 0's pass also quiets the hook automatically, so the `--no-verify` case is the only one that sees the reminder.
