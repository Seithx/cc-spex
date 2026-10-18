# Implementation Plan: Codex Init from a Bundled Spex Source

**Branch**: `057-codex-bundled-init` | **Date**: 2026-10-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/057-codex-bundled-init/spec.md`

## Summary

Make `spex/` a Codex plugin as well (`spex/.codex-plugin/plugin.json`, skills in `spex/codex/skills/`), so `$cc-spex-init` runs the setup workflow from the installed plugin tree instead of cloning GitHub into `$TMPDIR`. In the same change, fix both [#58](https://github.com/rhuss/cc-spex/issues/58) defects:

- `setup.yml` always installs local extensions with `--dev`.
- One new script, `spex-apply-extensions.sh`, makes the enabled extensions match the resolved selection in every mode and reports each change.

The Claude init paths (`spex-init.sh --refresh/--update`, the init skill) follow the project declaration when one exists, and interactive `/spex:init` writes it. The Codex marketplace file is committed, with the ignore and CI exemptions it needs. Release tooling, tests and docs follow.

## Technical Context

**Language/Version**: POSIX `sh` (bootstrap, apply script), Bash (tests), YAML (spec-kit workflow), JSON manifests, Markdown skills

**Primary Dependencies**: `specify` CLI (verified 1.0.5.dev0), `jq`, `python3` (`spex-setup-profile.py`), Codex CLI 0.163+ (manual checks only)

**Storage**: `.specify/spex.json`, `.specify/extensions/.registry`, Codex plugin cache

**Testing**: Bash test scripts with stubs on `PATH` (fake `specify`, failing `git` network subcommands, failing `curl`), plus the existing real-`specify` workflow test

**Target Platform**: macOS and Linux developer machines (Codex and Claude Code)

**Project Type**: Claude Code and Codex plugin, plus spec-kit extension bundle

**Performance Goals**: `$cc-spex-init` adds no network fetch of spex. Setup duration is otherwise unchanged.

**Constraints**:
- No changes to upstream spec-kit files.
- No network fetch of spex.
- Claude Code behavior unchanged (FR-012).
- The constitution's "extension installation via `--dev`" rule.

**Scale/Scope**:
- 2 new scripts (bootstrap, apply-extensions), 1 Codex manifest, 1 Codex skill, 1 marketplace file.
- Edits to `setup.yml`, `spex-init.sh`, the init skill, `.gitignore`, Makefile, 3 tests updated, 2 tests new, README, 2 help files, constitution, CHANGELOG.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Spec-Guided Development | Pass | Tracked feature from brainstorm 50 / [#58](https://github.com/rhuss/cc-spex/issues/58) |
| II. Extension Architecture | Pass | Extensions still installed with `specify extension add <path> --dev`; now unconditionally, which matches the constitution text exactly |
| III. Extension Composability | Pass | Selection enforcement touches only spex's own optional extensions, never `git` or other extensions (FR-006) |
| IV. Quality Gates | Pass | No gate changes |
| V. Naming Discipline | Pass | `specify` CLI, `$cc-spex-init` (existing Codex name), `spex-*` script names |
| VI. Skill Autonomy | Pass | `cc-spex-init` stays a single-purpose skill; the Claude init skill keeps its purpose |
| VII. State as Scripts | Pass (improves) | Selection enforcement moves from inline YAML and agent-run `specify extension disable` calls into `spex-apply-extensions.sh`; declaration writes go through `spex-setup-profile.py` |
| Plugin Architecture Constraints | Update | Add: `spex/` is both the Claude Code and the Codex plugin root; Codex skills live in `spex/codex/skills/` (FR-014) |

**Post-design re-check**: Pass. The bootstrap reads only files inside the plugin root or an explicit source. No cross-extension writes are introduced.

## Project Structure

### Documentation (this feature)

```text
specs/057-codex-bundled-init/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/cli.md
├── checklists/requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
spex/
├── .codex-plugin/plugin.json                    # NEW
├── codex/skills/cc-spex-init/                   # NEW (adapted from branch 050)
│   ├── SKILL.md
│   ├── agents/openai.yaml
│   └── scripts/bootstrap.sh
├── scripts/
│   ├── spex-apply-extensions.sh                 # NEW
│   ├── spex-setup-profile.py                    # resolve --mode/--reply, migrate-detach
│   └── spex-init.sh                             # declaration-aware refresh, git error text
├── setup.yml                                    # --dev always, one apply step, all excludes detach, git error text
└── skills/init/SKILL.md                         # apply + persist declaration, deps, git error text
.agents/plugins/marketplace.json                 # NEW (committed)
.gitignore                                       # negations for the marketplace file
Makefile                                         # release bumps Codex manifest; new test targets
tests/
├── test_cc_spex_codex_plugin.sh                 # NEW
├── test_apply_extensions.sh                     # NEW
├── test_workflow_setup.sh                       # TMPDIR source + exact selection cases
├── test_init_worktrees_git.sh                   # new error text; refresh with/without declaration
└── test_generated_trees.sh                      # exempt .agents/plugins/marketplace.json
README.md, spex/docs/help.md, spex/extensions/spex/docs/help.md, CHANGELOG.md
.specify/memory/constitution.md                  # Plugin Architecture Constraints
```

**Structure Decision**: Everything Codex needs lives inside `spex/`, the existing plugin root. New scripts go to `spex/scripts/` next to `spex-init.sh` and `spex-setup-profile.py`, which `setup.yml` already calls through `$SOURCE/scripts/`.

## Global Constraints

- Shared interface for every caller (`setup.yml`, `spex-init.sh`, the init skill): `spex-apply-extensions.sh <resolved csv>`, exit 0/1/2, change lines on stderr (see [contracts/cli.md](contracts/cli.md)).
- No caller disables or enables a spex extension any other way, except the unchanged registry-snapshot restore in `spex-init.sh install_extensions` for projects without a declaration (FR-016).
- No step may fetch spex over the network.
- Upstream spec-kit files under `.specify/` stay untouched (except the project-owned constitution).
- No em-dash or en-dash characters in docs.

## Design

### 1. Setup workflow (`spex/setup.yml`)

- **`install-ext-*`**: drop `DEV_FLAG` and always run `specify extension add "$EXT_PATH" --dev` (FR-001, FR-002). Remove the unconditional `spex-detach` disable after its install.
- **`select-extensions`**:
  - Keep the interactive prompt; its text says "all" means every extension except `spex-detach`, which must be named to be enabled.
  - Remove the per-mode disabling (`ext-interactive-fallback`, `ext-filter`) so that no step disables anything before the selection is resolved.
- **`selected-extensions`**: the mode-to-list mapping moves into `spex-setup-profile.py` (`resolve --mode recommended|all|interactive --reply <text>`), so it can be unit tested. `all` and interactive "all" resolve to the five extensions without `spex-detach`; an empty interactive reply resolves to `recommended`. Dependencies are added by the same `resolve` call.
- **New `snapshot-registry` step** between `validate-source` and `resolve-request`: copy the registry to `.specify/extensions/.registry.before` (when present) and, on a refresh without an `extensions` input, run `spex-setup-profile.py migrate-detach --root "$(pwd)" --before <snapshot>` (FR-023), so the following steps read the migrated declaration.
- **New `apply-extensions` step** right after `selected-extensions`: `"$SOURCE/scripts/spex-apply-extensions.sh" [--before .specify/extensions/.registry.before] "<selected>"`. It prints its change lines on stderr (FR-003, FR-018) and removes the snapshot afterwards.
- **`enforce-git-extension`**: new guidance text (FR-019): add the git extension, or re-run setup with a selection without `spex-worktrees`.

### 2. Apply script (`spex/scripts/spex-apply-extensions.sh`)

Contract in [contracts/cli.md](contracts/cli.md). It reads the registry with `jq` and changes state only through the `specify extension enable/disable` CLI. The fixed list of optional extensions is the single place the six names are spelled out for enforcement.

### 3. Claude init (`spex/scripts/spex-init.sh`, `spex/skills/init/SKILL.md`)

- **`install_extensions`**:
  - Snapshot the registry to a temporary file before reinstalling.
  - If `.specify/spex.json` validates, run `migrate-detach --before <snapshot>` (FR-023), then apply its `extensions` with `spex-apply-extensions.sh --before <snapshot>` (FR-004). An invalid declaration stops with the validator's message.
  - Otherwise keep the current registry snapshot restore unchanged (FR-016).
  - The git check runs after either path.
- **`worktrees_git_error`**: new text (FR-019).
- **Init skill**:
  - Step 1 error text (FR-019).
  - Step 2 dependency rule lists all three dependents (deep-review, teams, collab require gates).
  - After the choice, run `spex-apply-extensions.sh` and persist the declaration with `spex-setup-profile.py resolve ... | persist`, passing `--harness claude` only when `spex-init.sh` reported `DECLARATION_EXISTED=false` (its own setup run always writes a declaration) and `--legacy-permissions` from the permission choice (FR-022).
  - The skill no longer issues `specify extension disable` by hand.

### 4. Codex plugin and bootstrap

- **`spex/.codex-plugin/plugin.json`**: name `cc-spex`, version = the release version (as in `setup.yml` and the Claude manifest), `"skills": "./codex/skills/"`, and the interface block from branch 050 (description updated to "bundled").
- **`SKILL.md`**: takes branch 050's text, with these changes:
  - The skill runs the bundled `scripts/bootstrap.sh` by its absolute path from the project root.
  - No clone.
  - Defaults apply only without a declaration.
  - It keeps the reporting rules (the `$` prefix, new session, `$speckit-spex-help`).
- **`bootstrap.sh`**: implements the contract.
  - Source order: `SPEX_SOURCE`, then `./spex`, then the bundled root (`$(cd "$(dirname "$0")/../../../.." && pwd -P)`).
  - It validates the tree, passes `integration` always and `extensions`/`security` only when explicit or without a declaration, and never requires `git`.
  - It keeps branch 050's argument validation and help output.

### 5. Marketplace, ignore rules, CI

- `.agents/plugins/marketplace.json` as in [data-model.md](data-model.md) (FR-013).
- `.gitignore`: the negation block after the second `**/.agents/` (line 89).
- `tests/test_generated_trees.sh`: exempt exactly `.agents/plugins/marketplace.json`; every other tracked `.agents/` path still fails.

### 6. Release

`make release` also sets `.version` in `spex/.codex-plugin/plugin.json` and stages it. A test pins `spex/.codex-plugin/plugin.json .version` to the `setup.yml` workflow version and to `spex/.claude-plugin/plugin.json .version` (FR-020, SC-004). `spex/VERSION` (the `-dev` counter) is not compared.

### 7. Docs

- **README**:
  - A new "Codex" install section: marketplace add, install `cc-spex`, `$cc-spex-init` and its options, no clone.
  - Migration from the thin plugin: marketplace update, or remove and re-add from `main` for local-path and branch-050 installs.
  - Exact selection semantics in "Workflow-Based Setup" and "Managing Extensions" (manual toggles are reset on refresh; change the selection by re-running setup).
  - The release section lists the Codex manifest.
- **Both help files**: the `$cc-spex-init` entry, and the setup line saying selections are exact.
- **Constitution, Plugin Architecture Constraints**: a dual-harness plugin root bullet. Release bullet: Codex manifest version.
- **CHANGELOG**: Unreleased entries (Fixed: [#58](https://github.com/rhuss/cc-spex/issues/58) defects; Added: bundled Codex plugin; Changed: exact selection, init writes the declaration).

## Risks

| Risk | Mitigation |
|------|------------|
| Codex also scans the default `./skills/` and shows the Claude `init` skill | Manual quickstart step 2 checks it. If `init` shows up, FR-021 needs a layout change (moving the Claude skill out of the default path), which is recorded as a follow-up rather than done blind in this plan |
| Codex prefers `.claude-plugin/marketplace.json` over `.agents/plugins/marketplace.json` | Manual quickstart step 1 checks which marketplace appears. The `.agents` path is first in Codex's lookup list |
| Exact selection surprises users who toggled extensions by hand | Setup names every change (FR-018); README documents re-running setup to change the selection |
| Removing per-mode disabling changes interactive behavior | The apply step is the only enforcement; test_apply_extensions covers the resolved sets for all modes |

## Complexity Tracking

| Deviation | Why | Simpler alternative rejected because |
|-----------|-----|--------------------------------------|
| FR-020 asks for a version on the Codex marketplace entry; the Codex marketplace format has no version field (the installed version comes from the plugin manifest) | The manifest the entry points to carries the version, and a test pins it to the spex version | Adding an unknown field risks Codex rejecting the marketplace file |
