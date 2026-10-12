# Implementation Plan: Walkthrough as a Runbook

**Branch**: `054-walkthrough-runbook` | **Date**: 2026-10-11 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/054-walkthrough-runbook/spec.md`

## Summary

Rewrite `/speckit-spex-walkthrough` from scratch as a testability-gated, tutorial-style runbook. The agent judges whether anything can be tried by hand (one line and no file when not), writes `RUNBOOK.md` as one end-to-end journey where every step states why, the exact command, and what you should see, then runs a co-pilot session: per step the user runs the command from the clipboard or lets the agent run it with full transparency (command, real output, expected versus actual), or lets it "run the rest" until a mismatch. Light mode needs one approval for quick fixtures (processes, podman containers); full mode adds a review pause and tiered consent for slow and remote fixtures such as clusters. Ship drafts a runbook that can be run later from main. All deterministic work (status derivation with a squash-proof code fingerprint, step-format and secret checks, local fixture lifecycle, clipboard, detach-safe locations, preserving specs on worktree removal) moves into five new scripts; the three 053 helpers are removed. `finish`, `ship`, `verify`, and the status line read the new status.

## Technical Context

**Language/Version**: Markdown command files; Python 3 (stdlib only) with POSIX `sh` shims for parsing-heavy helpers; Bash with `jq` for process, container, and clipboard helpers.

**Primary Dependencies**: `specify` CLI, git, `jq`, `yq`, `rsync`; `podman` optional (quick container fixtures); clipboard tools optional (`pbcopy`, `wl-copy`, `xclip`, `xsel`); browser automation tool optional (agent-driven browser steps).

**Storage**: Files only: `RUNBOOK.md` with YAML frontmatter; self-ignoring scratch folder `specs/<feature>/.walkthrough/` with `fixtures.json` and logs; one key in `.specify/.spex-state`.

**Testing**: Bash test scripts under `tests/` in the style of `tests/test_spex_detach.sh` (temporary git repos, `assert_eq`); `make test-walkthrough`; `make sync-scripts-check`; `make validate`. Plus the human-judged real run in quickstart scenario 4.

**Target Platform**: Developer workstations (macOS primary, Linux) running Claude Code, Codex, or OpenCode with the spex plugin.

**Project Type**: Spec-kit plugin extensions (`spex`, `spex-gates`); no application `src/` tree.

**Performance Goals**: `show --no-git` under 0.5 s (status line; no git calls, single file read); full `show` with fingerprint under 3 s on this repository. Measured with `time` in T016.

**Constraints**: Never commits runbooks or scratch files in detach mode; never writes shared ignore files or detach-owned exclusions; never starts remote or paid fixtures without explicit consent; harness-neutral command vocabulary; no new mandatory runtime dependencies.

**Scale/Scope**: 1 command rewritten, 3 commands updated (finish, ship, verify), 1 script updated (status line), 5 new scripts (2 with shims), 3 scripts removed, 5 new test suites replacing 3, docs and manifest updates.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Spec-Guided Development**: PASS. Tracked feature with brainstorm, spec, clarifications, plan.
- **II. Extension Architecture**: PASS. Command stays `speckit.spex.walkthrough` in `spex`; scripts installed via the existing sync to extension `scripts/` dirs and referenced via `.specify/extensions/<own-ext>/scripts/`.
- **III. Extension Composability**: PASS after spec review fix. No writes to spex-detach files: detach state is only read via its `is-enabled` command; runbook relocation uses the self-ignoring scratch folder. `verify` (spex-gates) gets its own synced copy of the status script instead of reaching into `spex`.
- **IV. Quality Gates**: PASS. The walkthrough stays advisory and complements review and verify.
- **V. Naming Discipline**: PASS. Command name unchanged; new scripts follow the `spex-*` prefix; branch matches `NNN-feature-name`.
- **VI. Skill Autonomy**: PASS. The walkthrough owns runbook drafting and sessions; finish, ship, and verify only consume status or invoke the command.
- **VII. State as Scripts**: PASS. Status derivation, freshness, fixture state, step-format checks, detach location, and spec preservation are scripts; command markdown delegates.

Post-design re-check: PASS. Research R1 to R10 introduce no violations.

## Project Structure

### Documentation (this feature)

```text
specs/054-walkthrough-runbook/
├── plan.md              # This file
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   ├── scripts.md       # CLI contracts of the new scripts
│   └── command.md       # Command forms, phases, finish and ship integration
└── tasks.md             # /speckit-tasks output (not created here)
```

### Source Code (repository root)

```text
spex/
├── scripts/                                   # canonical sources
│   ├── spex-runbook-status.sh                 # NEW shim
│   ├── spex-runbook-status.py                 # NEW locate/init/step/steps/mode/show/list/not-testable/fingerprint
│   ├── spex-runbook-check.sh                  # NEW shim
│   ├── spex-runbook-check.py                  # NEW structure, placeholder, secret checks
│   ├── spex-runbook-fixture.sh                # NEW process/container/compose lifecycle + external records
│   ├── spex-runbook-clip.sh                   # NEW clipboard with fallback
│   ├── spex-finish-preserve-specs.sh          # NEW detach-mode copy back before worktree removal
│   ├── spex-ship-statusline.sh                # CHANGED: WT indicator from runbook status
│   ├── spex-walkthrough-workspace.sh          # REMOVED
│   ├── spex-walkthrough-coverage.py           # REMOVED
│   └── spex-walkthrough-lint.sh               # REMOVED
├── extensions/spex/
│   ├── commands/speckit.spex.walkthrough.md   # REWRITTEN
│   ├── commands/speckit.spex.finish.md        # CHANGED: gate via status, detach is-enabled, preserve specs
│   ├── commands/speckit.spex.ship.md          # CHANGED: draft at end, closing message
│   ├── extension.yml                          # CHANGED: description, argument hint
│   ├── docs/help.md                           # CHANGED
│   └── scripts/                               # synced copies
├── extensions/spex-gates/
│   ├── commands/speckit.spex-gates.verify.md  # CHANGED: reminder via status script
│   ├── commands/speckit.spex-gates.review-code.md  # CHANGED: next-step hint
│   └── scripts/                               # synced spex-runbook-status.{sh,py}
├── extensions/spex-deep-review/commands/speckit.spex-deep-review.run.md  # CHANGED: next-step hint
└── docs/help.md                               # CHANGED

tests/
├── test_runbook_status.sh          # NEW
├── test_runbook_check.sh           # NEW
├── test_runbook_fixture.sh         # NEW
├── test_runbook_clip.sh            # NEW
├── test_finish_preserve_specs.sh   # NEW
└── test_walkthrough_*.sh           # REMOVED (3 files)

Makefile        # SCRIPTS_spex and SCRIPTS_spex_gates lists, test-walkthrough target
README.md       # command table, workflow description
CHANGELOG.md    # entry for the rework
```

**Structure Decision**: Plugin layout as in feature 053. Canonical scripts in `spex/scripts/`, synced by `make sync-scripts`; `SCRIPTS_spex` gains the five new scripts plus shims and drops the three removed ones; `SCRIPTS_spex_gates` gains `spex-runbook-status.sh` and `.py` for `verify`. The `specs/**/.walkthrough/` rule in cc-spex's own `.gitignore` stays (harmless, redundant with the self-ignoring folder).

## Implementation Order

1. Scripts with tests first (TDD): status, check, fixture, clip, preserve.
2. Makefile lists and test target; `make sync-scripts`; remove old helpers and tests.
3. Rewrite the walkthrough command against the contracts.
4. Update finish, ship, verify, status line.
5. Docs, manifest, changelog.
6. Real run (quickstart scenario 4) on a small feature, judged by the user.

## Complexity Tracking

No constitution violations; table intentionally omitted.
