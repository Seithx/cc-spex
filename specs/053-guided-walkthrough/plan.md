# Implementation Plan: Guided Walkthrough (pair testing)

**Branch**: `053-guided-walkthrough` | **Date**: 2026-10-10 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/053-guided-walkthrough/spec.md`

## Summary

Replace the `speckit-spex-smoke-test` "Guided Demo" with `speckit-spex-walkthrough`: a user-story-anchored, agent-driven pair-testing walkthrough. The agent synthesizes scenarios from the spec's user stories (priority order), sets up a persistent real environment, and for each step previews the exact command, runs it (or delegates when it cannot), opens the resulting artifact inline, and pauses for the reviewer's verdict. Deterministic concerns (workspace lifecycle, story/FR coverage and orphan computation, skip-gate detection, no-placeholder enforcement) move into dedicated scripts per Constitution VII; the skill markdown delegates to them. The walkthrough is advisory (never hard-blocks finish/ship) and produces `WALKTHROUGH.md` on every exit path.

## Technical Context

**Language/Version**: Bash (POSIX-compatible) + Markdown skill files + Python 3 for parsing-heavy helpers; `jq` and `yq` for JSON/YAML.

**Primary Dependencies**: `specify` CLI (spec-kit), `jq`, `yq`, git; optional `/run` skill and Playwright MCP for app/browser steps.

**Storage**: Filesystem only. Persistent run workspace under `specs/<feature>/.walkthrough/<timestamp>/`; report at `specs/<feature>/WALKTHROUGH.md`.

**Testing**: Bash test scripts under `tests/` (same style as `tests/test_spex_detach.sh`), plus the existing `make test-generated-trees` discipline. New helper scripts are unit-testable in isolation.

**Target Platform**: Developer workstation running Claude Code / Codex / OpenCode via the spex plugin.

**Project Type**: Spec-kit plugin extension (the `spex` extension). Not an application; no `src/` tree.

**Performance Goals**: N/A (interactive, human-paced).

**Constraints**: Honesty gates preserved (no simulated tests, always interactive, mandatory report). No new runtime dependencies beyond `jq`/`yq`/`git` already required. Must work across Claude Code, Codex, and OpenCode (harness-neutral command vocabulary).

**Scale/Scope**: One renamed/rewritten skill, ~3 new helper scripts, manifest + doc + gitignore updates, and a test suite. Single extension (`spex`).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Spec-Guided Development**: PASS. Tracked feature with spec/plan/tasks.
- **II. Extension Architecture**: PASS. The command stays in the `spex` extension as `speckit.spex.walkthrough`; helper scripts installed alongside via the existing sync mechanism.
- **III. Extension Composability**: PASS. No changes to other extensions' files. Ship (`spex`) and finish (`spex`) already own their references; updating them is within the same extension. spex-gates is untouched (walkthrough is advisory, not a gate).
- **IV. Quality Gates**: PASS. Walkthrough is explicitly advisory (FR-021a), complementing—not duplicating—the review/verify gates.
- **V. Naming Discipline**: PASS. `speckit-spex-walkthrough` follows the `/speckit-*` + `spex` convention. Rename is documented in CHANGELOG and all cross-references updated (Constitution Development Workflow requirement).
- **VI. Skill Autonomy**: PASS. Single purpose (pair-testing walkthrough); delegates deterministic work to scripts; reuses `/run` rather than duplicating app-startup logic.
- **VII. State as Scripts**: PASS by design. Workspace lifecycle, coverage/orphan computation, skip-gate detection, and no-placeholder linting are implemented as scripts (FR-024/FR-025), not inline markdown bash.

No violations. Complexity Tracking table not required.

## Project Structure

### Documentation (this feature)

```text
specs/053-guided-walkthrough/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output (script CLIs + report format)
└── tasks.md             # /speckit-tasks output (not created here)
```

### Source Code (repository root)

```text
spex/
├── extensions/spex/
│   ├── commands/
│   │   ├── speckit.spex.walkthrough.md      # RENAMED from speckit.spex.smoke-test.md, rewritten
│   │   ├── speckit.spex.ship.md             # Stage 8 reference updated
│   │   └── speckit.spex.finish.md           # reference updated
│   ├── extension.yml                        # command registration updated
│   └── scripts/                             # synced copies of the new helpers
└── scripts/
    ├── spex-walkthrough-workspace.sh        # NEW: create/resolve persistent run workspace (FR-007/008/009)
    ├── spex-walkthrough-coverage.py         # NEW: parse stories+FRs, compute coverage, orphans, skip-gate (FR-003/004/006)
    └── spex-walkthrough-lint.sh             # NEW: no-placeholder scan over report/commands (FR-010/025)

tests/
├── test_walkthrough_coverage.sh             # synthesis-from-stories, orphan FRs, skip gate
├── test_walkthrough_workspace.sh            # persistence, no auto-delete, printed path
└── test_walkthrough_lint.sh                 # placeholder detection fails as required

.gitignore                                   # add specs/**/.walkthrough/
README.md, spex/docs/help.md                 # rename + description updates
CHANGELOG.md                                 # rename note
Makefile                                     # SCRIPTS_spex += new helpers (sync-scripts)
```

**Structure Decision**: This is a plugin extension, not an app, so the default `src/` tree does not apply. Canonical scripts live in `spex/scripts/` and are synced into `spex/extensions/spex/scripts/` via `make sync-scripts` (the `SCRIPTS_spex` list gains the three new helpers). The skill markdown delegates to these scripts per Constitution VII. The rename touches the command file, its generated skill dir (handled by init/sync), and all cross-references (ship, finish, help, README, manifest).

## Complexity Tracking

No constitution violations; table intentionally omitted.
