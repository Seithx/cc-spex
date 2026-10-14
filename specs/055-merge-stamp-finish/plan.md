# Implementation Plan: Merge stamp into finish

**Branch**: `055-merge-stamp-finish` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/055-merge-stamp-finish/spec.md`

## Summary

Finish gains a Phase 0 that runs verify before anything else and stops on failure. A new deterministic script, `spex-verify-record.sh`, records a passing verify run against the walkthrough's content fingerprint and answers "is this code already verified?" for finish and for the pre-commit reminder hooks (which stop using the session-scoped TMPDIR marker). Verify gains an `--embedded` argument so finish and submit keep `.spex-state` and suppress the banner. The stamp command, its adapter mappings, the stale ship stage-8 entry, and all doc references are removed or corrected.

## Technical Context

**Language/Version**: POSIX sh (scripts, shared hooks), Python 3 (Claude pretool hook, fingerprint via `spex-runbook-status.py`), Markdown (commands, docs)

**Primary Dependencies**: `git`, `jq`, existing `spex-runbook-status.sh fingerprint`

**Storage**: One JSON file per worktree at `$(git rev-parse --git-path spex-verified.json)` (inside the git dir, so never tracked and never part of the fingerprinted content)

**Testing**: Shell test scripts under `tests/` (same harness style as `tests/test_runbook_status.sh`), wired into `make test-walkthrough`; `make sync-scripts-check`; `make validate`; `tests/test_marketplace_install.sh`

**Target Platform**: macOS and Linux shells used by Claude Code, Codex, and OpenCode harnesses

**Project Type**: Claude Code plugin with spec-kit extensions (commands, hooks, scripts)

**Performance Goals**: `check` completes within the hook's 5 s subprocess budget (one `git write-tree` on a temp index plus `ls-tree`)

**Constraints**: Constitution VII (state via scripts); extension composability (finish in core `spex` must work without `spex-gates`); scripts synced from `spex/scripts/` into extension `scripts/` dirs via `make sync-scripts`

**Scale/Scope**: ~20 files touched: 1 new script + test, 6 command files, 4 hook files, 2 adapter maps, 2 statusline copies, docs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|---|---|---|
| I. Spec-Guided Development | PASS | Spec 055 drives all changes; FRs trace to tasks. |
| II. Extension Architecture | PASS | Stamp removed from the spex-gates manifest; verify stays in spex-gates; finish stays in core spex. |
| III. Extension Composability | PASS | Finish detects spex-gates via the registry and skips verification with a note when absent (FR-008). Finish only invokes verify; it does not edit spex-gates files. |
| IV. Quality Gates | PASS | Strengthens gates: the direct-merge path now verifies. No gate is weakened; `--no-verify` is explicit and printed. |
| V. Naming Discipline | PASS | No new commands. New script follows the `spex-<area>-<noun>.sh` pattern. |
| VI. Skill Autonomy | PASS | Unattended finish never prompts during verification (FR-003). |
| VII. State as Scripts | PASS | The verification record is read and written only by `spex-verify-record.sh` (FR-009c); commands and hooks call it rather than inlining `jq`/`touch`. |

Post-design re-check: PASS (no new violations introduced by research or data model).

## Project Structure

### Documentation (this feature)

```text
specs/055-merge-stamp-finish/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── spex-verify-record.md
│   └── finish-verify-phase.md
└── tasks.md
```

### Source Code (repository root)

```text
spex/scripts/
├── spex-verify-record.sh                 # NEW: record/check/path/clear the verification record
├── spex-ship-statusline.sh               # CHANGED: drop "stamp" stage emoji case
└── hooks/
    ├── pretool-gate.py                   # CHANGED: STAGE_NAMES drop 8; reminder reads record; new text
    ├── context-hook.py                   # CHANGED: drop 'stamp' from known commands
    └── shared/
        ├── stage-gate.sh                 # CHANGED: drop 8) stamp
        ├── verify-gate.sh                # CHANGED: reminder reads record; new text
        └── context-hook.sh               # CHANGED: drop stamp from KNOWN_COMMANDS
spex/scripts/adapters/
├── claude/command-map.json               # CHANGED: drop suppress-prompts-stamp
└── codex/command-map.json                # CHANGED: drop suppress-prompts-stamp
spex/extensions/spex/
├── commands/speckit.spex.finish.md       # CHANGED: Phase 0 verify, --no-verify, FR-011a commit note
├── commands/speckit.spex.ship.md         # CHANGED: truthful last stage, finish description
├── commands/speckit.spex.submit.md       # CHANGED: invoke verify with --embedded
├── commands/speckit.spex.using-superpowers.md  # CHANGED: drop stamp, finish description
├── commands/speckit.spex.evolve.md       # CHANGED: stamp -> finish/verify
├── docs/help.md                          # CHANGED
└── scripts/                              # SYNCED: spex-verify-record.sh, spex-ship-statusline.sh
spex/extensions/spex-gates/
├── extension.yml                         # CHANGED: remove stamp entry
├── commands/speckit.spex-gates.stamp.md  # DELETED
├── commands/speckit.spex-gates.verify.md # CHANGED: --embedded, record instead of TMPDIR marker
└── scripts/                              # SYNCED: spex-verify-record.sh
spex/docs/help.md                         # CHANGED
spex/templates/skill-preamble/opencode-preamble.md  # CHANGED: drop stamp
README.md, CLAUDE.md                      # CHANGED
Makefile                                  # CHANGED: add script to SCRIPTS_spex and SCRIPTS_spex_gates; add test
tests/
├── test_verify_record.sh                 # NEW
├── test_verify_gate.sh                   # NEW: reminder hook reads the record
└── test_marketplace_install.sh           # CHANGED: no stamp expectation
```

**Structure Decision**: Single plugin repository. Canonical scripts live in `spex/scripts/` and are copied into extensions by `make sync-scripts`; hooks resolve `spex-verify-record.sh` relative to their own location (`spex/scripts/`), with a fallback to `.specify/extensions/spex-gates/scripts/` in the project.

## Complexity Tracking

No constitution violations to justify.
