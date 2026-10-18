# Tasks: Codex Init from a Bundled Spex Source

**Input**: Design documents from `/specs/057-codex-bundled-init/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/cli.md, quickstart.md

**Tests**: Included (FR-015, quickstart.md).

**Organization**: User stories 2 and 3 (setup fixes) come before User Story 1 (Codex bootstrap), because the bootstrap runs the fixed setup workflow. User Story 4 is documentation.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup

- [X] T001 Add Makefile targets `test-codex-plugin` (runs `tests/test_cc_spex_codex_plugin.sh`) and `test-apply-extensions` (runs `tests/test_apply_extensions.sh`) in `Makefile`, and list both in `.PHONY`
- [X] T002 [P] Create the test harness `tests/test_apply_extensions.sh` (pattern of `tests/test_init_worktrees_git.sh`): `set -euo pipefail`, PASS/FAIL counters, `trap` cleanup of a `mktemp -d` project, and a stub `specify` on `PATH` backed by a jq-edited `.specify/extensions/.registry` that supports `extension enable <id>`, `extension disable <id>` and `extension list`, recording every call to a log file

---

## Phase 2: Foundational

- [X] T003 Add test cases to `tests/test_apply_extensions.sh` per `specs/057-codex-bundled-init/contracts/cli.md`: recommended set enables gates/worktrees/deep-review and disables teams/collab/detach; a selection naming `spex-detach` enables it; already-matching state makes zero enable/disable calls; output lines `Enabled:`/`Disabled:` name every change plus the summary line; `spex` and a non-spex `git` entry are never touched; an unselected extension that is not installed is ignored, a selected one that is not installed exits 1; selecting `spex-worktrees` enables a disabled `git` entry and never disables `git`; a failing `git` enable only warns and keeps exit 0; with `--before <snapshot>` only extensions whose state differs from the snapshot are reported; a failing `specify extension disable` exits 1 and names the extension; a selection containing `spex` is accepted and `spex` is left alone; empty or unknown selection exits 2
- [X] T004 Implement `spex/scripts/spex-apply-extensions.sh` (POSIX `sh`, `jq`) per the contract, and make the T003 cases pass with `make test-apply-extensions`

**Checkpoint**: One tested script enforces a resolved selection

---

## Phase 3: User Story 2 - Setup installs extensions from any local source location (Priority: P1)

**Goal**: The setup workflow installs every spex extension from a source under `/tmp`, macOS `$TMPDIR`, a plugin cache or a regular directory.

**Independent Test**: The new TMPDIR case in `tests/test_workflow_setup.sh` passes.

- [X] T005 [US2] In `spex/setup.yml`, replace the `DEV_FLAG` logic in all seven `install-ext-*` steps with `specify extension add "$EXT_PATH" --dev`, and remove the unconditional `specify extension disable "$EXT"` at the end of `install-ext-spex-detach`
- [X] T006 [US2] Add a case to `tests/test_workflow_setup.sh`, run twice (once with the copy under `/tmp`, once with `TMPDIR` set to a macOS-style path such as `<tmp>/var/folders/xx/T/`): copy `spex/` to `$(mktemp -d "${TMPDIR:-/tmp}/spex-src-XXXXXX")`, run setup with `SPEX_SOURCE` pointing at the copy and `extensions=recommended`, assert all 7 extensions are installed under `.specify/extensions/`, then delete the copy and assert the installed extensions and the generated command files still exist and resolve (no dangling symlinks into the deleted copy)

**Checkpoint**: [#58](https://github.com/rhuss/cc-spex/issues/58) defect 1 fixed

---

## Phase 4: User Story 3 - The extension selection is what ends up enabled (Priority: P1)

**Goal**: In every mode, and through both init paths, the enabled optional extensions equal the resolved selection, and the declaration matches.

**Independent Test**: The exact-selection cases in `tests/test_workflow_setup.sh` and `tests/test_init_worktrees_git.sh` pass.

### Tests

- [X] T007 [US3] Add cases to `tests/test_workflow_setup.sh` that read the enabled set from `.specify/extensions/.registry` after each run: `recommended` (gates, worktrees, deep-review on; teams, collab, detach off); `all` (all except detach on); explicit list `spex-teams` (teams and gates on, others off); refresh without input (same set as before, `spex.json` unchanged); a legacy declaration listing `spex-detach` while the registry has it disabled, refreshed without input (`spex-detach` stays disabled, is removed from `spex.json`, output says `Migrated:`); `all` followed by `recommended` (teams and collab off, the run's combined stdout and stderr (`2>&1`) contains `Disabled: spex-teams` and `Disabled: spex-collab`); and for each case that the declaration's optional extensions equal the enabled set
- [X] T008 [US3] Update `tests/test_init_worktrees_git.sh`: change the assertion for the old "specify extension disable spex-worktrees" guidance to the new FR-019 text and assert the old text is gone, and add cases for `spex-init.sh --refresh` with a valid `.specify/spex.json` (an extension enabled by hand outside the declaration is disabled again, and one in the declaration but disabled is enabled) a case with a declaration listing `spex-detach` while the registry has it disabled (`spex-detach` stays disabled, is removed from `spex.json`, output contains `Migrated:`), and without a declaration (a previously disabled extension stays disabled, unchanged behavior)

### Implementation

- [X] T009 [US3] Add a `--mode recommended|all|interactive` option (with `--reply <text>` for interactive) to `resolve` in `spex/scripts/spex-setup-profile.py` that maps the mode to the optional extension list per `contracts/cli.md` (Selection resolution table) and then applies the existing dependency normalization; add unit tests to `tests/test_setup_profile.py` for `recommended`, `all` (no `spex-detach`), interactive reply "all" (same as `all`), empty reply (same as `recommended`), a reply listing `spex-teams,spex-detach` (adds `spex-gates`, keeps `spex-detach`), and `--extensions spex` yielding exactly `["spex"]`; also add the `migrate-detach --root --before <snapshot>` subcommand per `contracts/cli.md` with unit tests: declaration lists `spex-detach` and the snapshot shows it disabled (removed, message printed), snapshot shows it enabled (unchanged), declaration without it (unchanged), no snapshot entry (unchanged), missing `--before` file (unchanged, exit 0)
- [X] T010 [US3] In `spex/setup.yml`: make `selected-extensions` call `spex-setup-profile.py resolve --mode ...` instead of its inline case statement; remove the disabling logic from `ext-interactive-fallback` and `ext-filter` and keep both steps as `printf ok` no-ops (the switch keeps its default case; the interactive prompt step stays); update the interactive prompt text so "all" means every extension except `spex-detach`, which must be named to be enabled; in `selected-extensions`, make `all` and interactive "all" resolve to `spex-gates,spex-worktrees,spex-deep-review,spex-teams,spex-collab`; add a `snapshot-registry` step before `resolve-request` that copies `.specify/extensions/.registry` (if present) to `.specify/extensions/.registry.before` and, when the `extensions` input is empty, `.specify/spex.json` exists and the snapshot file was created, runs `spex-setup-profile.py migrate-detach --root "$(pwd)" --before .specify/extensions/.registry.before` (so `resolve-request` and `extension-mode` read the migrated declaration), and an `apply-extensions` step right after `selected-extensions` that runs `"$SOURCE/scripts/spex-apply-extensions.sh" --before .specify/extensions/.registry.before "<selected>"` (omit `--before` when no snapshot exists), removes the snapshot, and fails the workflow on a non-zero exit
- [X] T011 [US3] In `spex/setup.yml` `enforce-git-extension`, replace the "specify extension disable spex-worktrees" line with guidance to re-run setup with a selection that leaves out `spex-worktrees` (FR-019)
- [X] T012 [US3] In `spex/scripts/spex-init.sh`: at the start of the no-flag init path, record whether `.specify/spex.json` exists and print `DECLARATION_EXISTED=true|false` before handing off to `setup.yml`; in `install_extensions`: when `.specify/spex.json` exists and `spex-setup-profile.py validate` accepts it, copy `.specify/extensions/.registry` (when it exists) to a temporary snapshot file before the remove/add loop; after reinstalling, run `spex-setup-profile.py migrate-detach --root "$PWD" --before <snapshot>` (only when the snapshot exists), then apply the declaration's `extensions` with `spex-apply-extensions.sh --before <snapshot>` (omit `--before` without a snapshot), and remove the snapshot file instead of restoring the snapshot (FR-004); when `.specify/spex.json` exists but fails validation, stop with the validator's message (as `setup.yml` does) instead of falling back; otherwise keep the current `prev_disabled` restore unchanged (FR-016); keep the git check after both paths, and apply the "previously disabled spex-worktrees counts as disabled" override (around line 506) only on the snapshot path, so a declaration that enables `spex-worktrees` still triggers the git check; update `worktrees_git_error` to the FR-019 text
- [X] T013 [US3] In `spex/skills/init/SKILL.md`: update the Step 1 git error guidance (FR-019); update the Step 1 refresh bullet (with a project declaration, a refresh re-applies it instead of preserving the current state); state the dependency rule for all three dependents (deep-review, teams, collab require gates); replace the manual `specify extension disable` instructions with running `spex-apply-extensions.sh` on the resolved selection; add the declaration write in the order resolve, apply, persist as in `contracts/cli.md` (always pass `--extensions "spex${csv:+,$csv}"` so an empty choice yields only `spex`): `spex-setup-profile.py resolve --root "$PWD" --extensions <spex,csv> --legacy-permissions <none|standard|yolo> [--harness claude only when Step 1 printed DECLARATION_EXISTED=false] | spex-setup-profile.py persist --root "$PWD"` (FR-022); script paths resolved from the plugin root as the skill already does for `spex-init.sh`
- [X] T014 [US3] Run `make sync-scripts` if any changed script is listed for an extension, then `make test-apply-extensions test-workflow-setup test-worktree test-setup-profile` until green

**Checkpoint**: [#58](https://github.com/rhuss/cc-spex/issues/58) defect 2 fixed for both init paths

---

## Phase 5: User Story 1 - Initialize a project from Codex without a network clone (Priority: P1)

**Goal**: `spex/` is the Codex plugin, and `$cc-spex-init` runs setup from the installed tree.

**Independent Test**: `make test-codex-plugin` passes.

### Tests

- [X] T015 [US1] Create `tests/test_cc_spex_codex_plugin.sh`: a stub `specify` that records its arguments and `SPEX_SOURCE`; a `git` wrapper that fails `clone`, `fetch` and `ls-remote` and passes other calls to the real git; a failing `curl`. Cases per `specs/057-codex-bundled-init/quickstart.md`: bundled source used in a non-repo project (`SPEX_SOURCE` equals the repo's `spex/`, stderr names `bundled`); no `cc-spex-init-*` directory under `$TMPDIR`; inputs without declaration (`integration=codex`, `extensions=recommended`, `security=safe`); with declaration and no overrides (only `integration=codex`); with declaration and `--extensions all` (`integration=codex` and `extensions=all`); `SPEX_SOURCE` precedence and invalid `SPEX_SOURCE` exits 1; `./spex` precedence inside a repo-like directory; broken bundled tree (copy of the script in a fake root without `setup.yml`) exits 1 naming the missing file without any fetch; working directory stays the project root; `--help` lists defaults; unknown option and unknown extension exit 2; version check `spex/.codex-plugin/plugin.json .version` equals the `version:` in `spex/setup.yml`'s workflow header and `spex/.claude-plugin/plugin.json .version`; SKILL.md mentions no slash-prefixed spex command; the Codex manifest's `skills` path is `./codex/skills/` and contains only `cc-spex-init`

### Implementation

- [X] T016 [US1] Create `spex/codex/skills/cc-spex-init/scripts/bootstrap.sh` per `contracts/cli.md`, starting from branch 050's version (`git show origin/050-cc-spex-plugin:plugins/cc-spex/skills/cc-spex-init/scripts/bootstrap.sh`): keep argument parsing, validation and `--help`; replace the source resolution with `SPEX_SOURCE`, then `./spex`, then the bundled root four levels above the script, validating `setup.yml` and `extensions/spex/extension.yml`; drop the `git` requirement, `mktemp` and `git clone`; pass `integration` always and `extensions`/`security` only when given or when `.specify/spex.json` is missing; print the source kind and effective inputs on stderr
- [X] T017 [P] [US1] Create `spex/codex/skills/cc-spex-init/SKILL.md` and `spex/codex/skills/cc-spex-init/agents/openai.yaml` from branch 050's versions, updated: run the bundled `scripts/bootstrap.sh` by its absolute path from the project root (never `cd`), no clone, defaults apply only without a project declaration, keep the reporting rules (`$` prefix, start a new Codex session, suggest `$speckit-spex-help`, no slash commands)
- [X] T018 [P] [US1] Create `spex/.codex-plugin/plugin.json`: `name` `cc-spex`, `version` equal to the release version in `spex/setup.yml` and `spex/.claude-plugin/plugin.json` (currently `6.1.0`), `skills` `./codex/skills/`, and the `interface` block from branch 050 with the long description saying the plugin bundles spex
- [X] T019 [US1] Create `.agents/plugins/marketplace.json` exactly as in `specs/057-codex-bundled-init/data-model.md` (marketplace `cc-spex`, plugin `cc-spex`, local source `./spex`); add the negation block (`!/.agents/`, `/.agents/*`, `!/.agents/plugins/`, `/.agents/plugins/*`, `!/.agents/plugins/marketplace.json`) to `.gitignore` after the second `**/.agents/` line
- [X] T020 [US1] In `tests/test_generated_trees.sh`, exempt exactly `.agents/plugins/marketplace.json` from the tracked-`.agents/` check, and add an assertion that another tracked `.agents/` file would still fail (for example by checking the filter on a sample list); add `git check-ignore` assertions that `.agents/plugins/marketplace.json` is not ignored while `.agents/plugins/other.json` and `.agents/skills/x/SKILL.md` are. Reuse the negation block and `awk` exemption from the local `050-cc-spex-plugin` branch (commit `2eb29c2`) where they fit
- [X] T021 [US1] Add a real-`specify` end-to-end case to `tests/test_workflow_setup.sh`: copy the plugin layout (`spex/`) to a temporary directory, put the network stubs from T015 first on `PATH` (fail `git clone/fetch/ls-remote` and `curl`, pass other `git` calls), run the copy's `codex/skills/cc-spex-init/scripts/bootstrap.sh` from a fresh git project, and assert setup completes, the recommended set is enabled, `.specify/spex.json` has `harness: codex`, and no `cc-spex-init-*` directory exists (SC-001)
- [X] T022 [US1] Run `make test-codex-plugin test-generated-trees test-workflow-setup` until green

**Checkpoint**: `$cc-spex-init` initializes from the bundled tree

---

## Phase 6: User Story 4 - Existing Codex installs move to the bundled plugin (Priority: P2)

**Goal**: Users with the thin plugin end up with one working `cc-spex` plugin.

**Independent Test**: Quickstart manual step 5.

- [X] T023 [US4] Add a "Codex" install section to `README.md` (near the Quick Start and Workflow-Based Setup sections): add the `cc-spex` marketplace from this repository, install `cc-spex`, run `$cc-spex-init` with its options and defaults, note that no clone or download happens; add a migration subsection: installs from a marketplace tracking `main` update the plugin; installs from a local path or the `050-cc-spex-plugin` branch remove the old marketplace and plugin and re-add the marketplace from `main`

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T024 In `Makefile` `release`, also set `.version` in `spex/.codex-plugin/plugin.json` with `jq` and add the file to the release `git add` list
- [X] T025 [P] In `README.md`, document exact selection semantics in "Workflow-Based Setup" (`all` excludes `spex-detach`; the declaration is applied on refresh; setup names every change) and in "Managing Extensions" (manual `specify extension` toggles of spex extensions are reset on the next refresh; change the selection by re-running setup with `extensions=...`); update the release section to list the Codex manifest; update the "seven bundled extensions" sentence if it no longer matches
- [X] T026 [P] Update `spex/docs/help.md` and `spex/extensions/spex/docs/help.md`: add the `$cc-spex-init` entry for Codex, and state that extension selections are exact
- [X] T027 [P] Update `.specify/memory/constitution.md` Plugin Architecture Constraints: `spex/` is both the Claude Code and the Codex plugin root, Codex skills live in `spex/codex/skills/`, and the release sets the Codex manifest version; bump the constitution patch version and date
- [X] T028 [P] Add Unreleased entries to `CHANGELOG.md`: Fixed ([#58](https://github.com/rhuss/cc-spex/issues/58) setup from temporary sources; selections leave unselected extensions enabled), Added (bundled Codex plugin, `$cc-spex-init` without clone), Changed (exact selection in every mode, `all` excludes `spex-detach`, `/spex:init` writes `.specify/spex.json`, refresh applies the declaration, new git-extension guidance)
- [X] T029 Run `make sync-scripts-check validate test-apply-extensions test-codex-plugin test-workflow-setup test-worktree test-generated-trees test-setup-profile test-ship-state test-statusline test-walkthrough test-codex-project` and fix any failure; confirm `git diff main -- .specify/ ':!.specify/memory/constitution.md'` is empty (no upstream spec-kit files changed). Do not run `make test-install` or `make install` (they touch the user's installed Claude plugin)

---

## Dependencies & Execution Order

- **Setup (T001, T002)**: no dependencies; T002 [P]
- **Foundational (T003, T004)**: after T002; blocks US3
- **US2 (T005, T006)**: after Setup; independent of the apply script
- **US3 (T007 to T014)**: after T004 and T005 (T010 edits the same file as T005); tests T007, T008 before T010 to T013; T009 (mapping in `spex-setup-profile.py`, with its unit tests) before T010
- **US1 (T015 to T022)**: after US2 and US3 (the bootstrap runs the fixed setup); T017, T018 [P]
- **US4 (T023)**: after US1
- **Polish (T024 to T029)**: after all stories; T025 to T028 [P]; T029 last

## Implementation Strategy

1. Apply script with tests (foundation for exact selection).
2. US2 and US3: both [#58](https://github.com/rhuss/cc-spex/issues/58) defects fixed and tested with the real `specify`.
3. US1: bundled Codex plugin and bootstrap.
4. US4 and polish: migration docs, release tooling, help, constitution, changelog, full test run.
