# Feature Specification: Codex Init from a Bundled Spex Source

**Feature Branch**: `057-codex-bundled-init`

**Created**: 2026-10-18

**Status**: Draft

**Input**: User description: "brainstorm/50-codex-bundled-init.md (issue https://github.com/rhuss/cc-spex/issues/58): fix the two setup defects and let `$cc-spex-init` initialize from a spex source bundled with the Codex plugin instead of cloning GitHub into a temporary directory"

## Background

A Codex user initializes spex in a project with `$cc-spex-init`. Today that skill comes from a thin Codex plugin built from an unmerged branch (`050-cc-spex-plugin`). The plugin contains only the init skill and a bootstrap script, not spex itself. In any project other than the cc-spex repository, the bootstrap clones the current GitHub `main` into a temporary directory, runs the spex setup workflow from there, and deletes the clone.

[#58](https://github.com/rhuss/cc-spex/issues/58) reports two defects in that path:

1. **The setup workflow cannot install extensions from a temporary source.** It installs local extensions in "development mode" only when the source is not under `/tmp` or `$TMPDIR`. Without development mode, the current `specify` CLI treats the path as a catalog name and fails ("not found in catalog"), so setup stops at its first extension.
2. **`recommended` (and `all`) do not enforce the selection.** All optional extensions are installed first. Only the interactive mode and an explicit list then disable the unselected ones, so `recommended` leaves `spex-teams` and `spex-collab` enabled although the persisted project declaration lists only the recommended set.

Behind both defects sits a structural issue. The plugin and the spex source it installs are versioned separately, and that source arrives over the network into a throwaway directory.

## Clarifications

### Session 2026-10-18 (brainstorm)

- Q: Where should `$cc-spex-init` get the spex source from? → A: Bundled with the Codex plugin. No clone.
- Q: How is it bundled? → A: The existing `spex/` directory, which is already the Claude Code plugin, also becomes the Codex plugin.
- Q: What happens with branch `050-cc-spex-plugin`? → A: Rebuilt on `main`. The branch is used only as a reference and deleted afterwards.
- Q: What does an extension selection mean for extensions outside it? → A: The selection is exact in every mode: selected extensions are enabled, all other optional extensions are disabled. A refresh without an explicit selection reuses the persisted one.

### Session 2026-10-18 (clarify)

- Q: When a project has a persisted declaration, which init path follows which rule on refresh? → A: The declaration is the single source of truth for both init paths (Claude `/spex:init` and the setup workflow). Only projects without a declaration keep the current registry-preserving refresh of `/spex:init`.
- Q: Do manual `specify extension enable/disable` toggles update the declaration? → A: No. spex cannot observe them. The documented way to change the selection is to re-run setup with an explicit selection, which updates the declaration. A refresh re-applies the declaration and reverts manual toggles of spex extensions.
- Q: Under which name is the bundled Codex plugin published? → A: Under the existing Codex identity `cc-spex` (marketplace `cc-spex`), so updating the plugin replaces the thin plugin instead of installing a second one.
- Q: Is the migration from the thin plugin automatic or manual? → A: A plugin update through the `cc-spex` marketplace replaces it. The documentation also lists manual steps for installs that came from elsewhere (for example a local marketplace path).

### Session 2026-10-18 (code review)

- Q: spec-kit's workflow `prompt` step cannot return the agent's reply. Where is the interactive extension and security choice collected? → A: In the agents: the Claude init skill (Step 2) and the Codex skill ask the user and pass an explicit list. `interactive` mode of the setup workflow itself applies `recommended` and `safe` and prints a notice.
- Q: How is the release version recorded for Codex, given the marketplace format has no version field? → A: The release sets the version in the Codex plugin manifest only; the marketplace entry carries no version.

### Session 2026-10-18 (plan review)

- Q: Which version does the Codex manifest carry? → A: The release version, the same as the setup workflow and the Claude Code plugin manifest (not the `-dev` `VERSION`). `make release` sets it.
- Q: How does `/spex:init` know whether a declaration existed before its own setup run? → A: `spex-init.sh` reports it (`DECLARATION_EXISTED=true|false`), and the skill writes `harness=claude` only when it was `false`.
- Q: How strict is selection enforcement? → A: Strict: selecting `spex-worktrees` also enables the `git` extension; changes are reported against the state before reinstalling; a selected extension that is not installed is an error.
- Q: How are declarations handled that list `spex-detach` only because the old `all` wrote it? → A: One-time migration: when a refresh applies a declaration that lists `spex-detach` while the registry (before reinstalling) shows it disabled, `spex-detach` is dropped from the declaration and the change is reported. It is enabled only when a user selects it again.
- Q: How are interactive mode and the real Codex run tested? → A: The mode-to-list mapping moves into `spex-setup-profile.py` and gets unit tests; one real-`specify` test runs the bootstrap from a copy of the plugin layout with network stubs.

### Session 2026-10-18 (spec review)

- Q: Should `$cc-spex-init` always pass its defaults (`recommended`, `safe`)? → A: No. The defaults apply only when the project has no declaration. With a declaration, `$cc-spex-init` passes no extension or security input unless the user gives an explicit override.
- Q: Does Claude `/spex:init` write the project declaration? → A: Yes. An interactive (non-refresh) `/spex:init` writes the resolved selection to `.specify/spex.json`, creating or updating it.
- Q: What does the offline guarantee cover? → A: Only the spex source: spex itself is never downloaded. Other setup steps (`specify init`, the spec-kit `git` extension) are not covered.
- Q: Does `all` enable `spex-detach`? → A: No. `spex-detach` stays opt-in; only an explicit list or the interactive choice enables it.
- Q: Which integration does `$cc-spex-init` use when a declaration exists? → A: Always `codex`. The declaration's `harness` becomes `codex`.
- Q: What does interactive `/spex:init` write besides the extensions? → A: On create: `harness=claude`, and `security` mapped from the permission choice (None to `safe`, Standard to `autonomous`, YOLO to `yolo`). On update: replace `extensions` and `security` with the new choices; `harness` stays as it is.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Initialize a project from Codex without a network clone (Priority: P1)

A Codex user with the cc-spex Codex plugin installed opens any project (not the cc-spex repository) and runs `$cc-spex-init` with the defaults. Spex initializes from the spex source the plugin was installed with. No repository is downloaded, no temporary checkout is created, and the installed extensions match the plugin's version.

**Why this priority**: This is the default Codex install path, and today it fails on macOS ([#58](https://github.com/rhuss/cc-spex/issues/58), defect 1). Removing the clone also removes the plugin/source version skew.

**Independent Test**: In a fresh git project with the plugin installed, put `git` and `curl` stubs first on `PATH` that fail `git clone`, `git fetch`, `git ls-remote` and every `curl` call, and pass all other `git` calls to the real binary. Run `$cc-spex-init`. Setup completes, the Codex plugin manifest version equals the bundled tree's release version (setup workflow version and Claude Code plugin manifest version), and no `cc-spex-init-*` directory appears in the temporary directory.

**Acceptance Scenarios**:

1. **Given** a fresh project and the Codex plugin installed, **When** the user runs `$cc-spex-init`, **Then** setup completes and every selected spex extension is installed and enabled.
2. **Given** network access to fetch spex is blocked, **When** the user runs `$cc-spex-init`, **Then** setup does not try to fetch spex (no clone, no download of spex). Other setup steps that may need the network (`specify init`, installing the spec-kit `git` extension) are not covered by this guarantee.
3. **Given** a successful init, **When** the user compares versions, **Then** the release version of the source that setup ran from (setup workflow version) equals the Codex plugin manifest version.
4. **Given** the cc-spex repository itself, or an explicitly configured local spex source, **When** the user runs `$cc-spex-init`, **Then** that local source is used instead of the bundled one, as today.

---

### User Story 2 - Setup installs extensions from any local source location (Priority: P1)

Anyone running the spex setup workflow from a local source tree gets the extensions installed regardless of where that tree lives, including under `/tmp`, under a macOS-style `$TMPDIR` such as `/var/folders/.../T/`, or inside a plugin cache.

**Why this priority**: This is [#58](https://github.com/rhuss/cc-spex/issues/58) defect 1. It blocks setup entirely for any temporary or cache location, independent of the bundling change.

**Independent Test**: Run the setup workflow from a copy of the spex source placed under `/tmp`, under a path shaped like macOS `$TMPDIR`, and under a regular directory. All three install every extension.

**Acceptance Scenarios**:

1. **Given** a spex source under `$TMPDIR`, **When** setup installs extensions, **Then** each extension installs successfully.
2. **Given** a successful install from a temporary source, **When** the temporary source is deleted afterwards, **Then** the project's installed extensions and generated commands keep working.

---

### User Story 3 - The extension selection is what ends up enabled (Priority: P1)

A user runs setup with `recommended`, `all`, an explicit list, or the interactive choice. Afterwards exactly the selected optional extensions are enabled, and the persisted project declaration matches the enabled set.

**Why this priority**: This is [#58](https://github.com/rhuss/cc-spex/issues/58) defect 2. Extensions the user did not choose register hooks and alter the workflow.

**Independent Test**: Run setup with each selection mode on a fresh project and compare the enabled extensions with the selection and with the persisted declaration.

**Acceptance Scenarios**:

1. **Given** `recommended`, **When** setup finishes, **Then** `spex-gates`, `spex-worktrees` and `spex-deep-review` are enabled and `spex-teams`, `spex-collab` and `spex-detach` are disabled.
2. **Given** `all`, **When** setup finishes, **Then** all optional extensions except `spex-detach` are enabled, and `spex-detach` is disabled.
3. **Given** an explicit list, **When** setup finishes, **Then** only the listed extensions (plus required dependencies, such as `spex-gates` for extensions that need it) are enabled.
4. **Given** an initialized project, **When** the user refreshes without an explicit selection, **Then** the persisted selection is applied again with the same exact result.
5. **Given** a project initialized with `all`, **When** the user re-runs setup with `recommended`, **Then** the extensions outside the recommended set are disabled.
6. **Given** the interactive choice in an agent (the Claude init skill or the Codex skill), **When** the user chooses "all", **Then** the result equals `all` mode (`spex-detach` stays disabled); choosing a list that names `spex-detach` enables it. **Given** the setup workflow run directly with `interactive`, **Then** it applies `recommended` and `safe` and says so.
7. **Given** a project initialized with `all` and `autonomous`, **When** the user re-runs `$cc-spex-init` without arguments, **Then** the same extensions stay enabled and the security setting stays `autonomous`.

---

### User Story 4 - Existing Codex installs move to the bundled plugin (Priority: P2)

A Codex user who installed the earlier thin plugin (`0.1.0+codex.*`) learns how to switch to the bundled plugin and ends up with a single, working `$cc-spex-init`.

**Why this priority**: Existing installs keep cloning GitHub `main` until they switch, and they keep hitting defect 1 if `main` regresses.

**Independent Test**: Follow the documented steps on a machine with the thin plugin installed. Afterwards Codex lists one cc-spex plugin and `$cc-spex-init` uses the bundled source.

**Acceptance Scenarios**:

1. **Given** the thin plugin is installed from a `cc-spex` marketplace that tracks this repository's default branch (`main`), **When** the user updates the plugin, **Then** Codex shows exactly one cc-spex plugin, at the bundled version.
2. **Given** the thin plugin came from another source (for example a local marketplace path, or a marketplace pointing at a local checkout of the `050-cc-spex-plugin` branch, the only place a Codex marketplace file was ever committed (locally, not pushed); such installs re-add the `cc-spex` marketplace from `main`, because updates through the old branch marketplace stop working once that branch is deleted), **When** the user follows the documented manual steps, **Then** Codex shows exactly one cc-spex plugin, at the bundled version.
3. **Given** the migration is done, **When** the user runs `$cc-spex-init`, **Then** no clone happens.

---

### Edge Cases

- **Plugin root cannot be resolved at runtime**: init stops with an error that names the problem and how to set an explicit local source. It does not fall back to cloning.
- **Bundled tree incomplete or corrupt** (setup workflow or an extension missing): init stops with an error naming the missing part.
- **Local source variable set to a non-spex directory**: init stops with an error, as today.
- **A selected extension depends on another** (for example `spex-deep-review` on `spex-gates`): the dependency is enabled too, and the persisted declaration reflects it.
- **Interactive mode with an empty answer, or the workflow's own `interactive` mode**: falls back to `recommended` (and `safe`) and is enforced exactly.
- **Extensions not shipped by spex** (for example the spec-kit `git` extension): never disabled by the selection.
- **Legacy `all` declarations**: earlier `all` runs wrote `spex-detach` into the declaration while leaving it disabled. On the first refresh that applies such a declaration, `spex-detach` is removed from the declaration (not enabled), and setup says so. Stealth mode is never switched on by this migration.
- **Manual toggles**: a spex extension enabled or disabled by hand with `specify extension` is reset to the declaration on the next refresh. Setup output names any extension whose state it changed, so the reset is visible.
- **Claude Code plugin unaffected**: adding the Codex manifest to `spex/` changes nothing for Claude Code installs or `/spex:init`.
- **Re-running init in an already initialized project**: re-installs from the bundled source and re-applies the selection without duplicating extensions.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The setup workflow MUST install every spex extension from a local source tree successfully, regardless of the tree's location (regular directory, `/tmp`, macOS `$TMPDIR`, plugin cache).
- **FR-002**: Extensions installed from a temporary source MUST keep working after that source is deleted.
- **FR-003**: After setup, the set of enabled optional spex extensions MUST equal the resolved selection for every selection mode: `recommended`, `all`, explicit list, interactive. The resolved selection adds required dependencies: `spex-deep-review`, `spex-teams` and `spex-collab` require `spex-gates`. The core `spex` extension is always enabled and is not part of the selection. `spex-detach` is opt-in: `all` does not include it, and neither does choosing "all" interactively (it resolves exactly like `all` mode). Only naming `spex-detach`, in an explicit list or the interactive choice made in an agent, enables it. The interactive choice is collected by the agents (the Claude init skill and the Codex skill) and passed to setup as an explicit list; the setup workflow's own `interactive` mode applies `recommended` and `safe` and prints a notice, because spec-kit's workflow prompt step cannot return a reply. When `spex-worktrees` is selected, the non-spex `git` extension is enabled (never disabled).
- **FR-004**: A refresh without an explicit selection MUST apply the selection persisted in the project declaration (`.specify/spex.json`) with the same exact semantics. This holds for both init paths: the setup workflow and Claude `/spex:init`.
- **FR-005**: The persisted project declaration and the enabled extension set MUST agree after every successful setup, through either init path.
- **FR-006**: Selection enforcement MUST NOT disable extensions that spex does not ship.
- **FR-007**: The spex plugin directory MUST also be installable as a Codex plugin that provides `$cc-spex-init`, with the plugin version equal to the spex release version (the setup workflow version and the Claude Code plugin manifest version).
- **FR-008**: `$cc-spex-init` MUST use the spex source installed with the Codex plugin. It MUST NOT clone or download spex, and MUST NOT create a temporary checkout.
- **FR-009**: `$cc-spex-init` MUST resolve the spex source in this order: `SPEX_SOURCE` (if set), then the current directory when it holds `spex/setup.yml` and `spex/extensions/spex` (the cc-spex repository), then the bundled plugin tree.
- **FR-010**: When the bundled source cannot be found or is incomplete, `$cc-spex-init` MUST stop with an actionable error and MUST NOT fall back to downloading.
- **FR-011**: `$cc-spex-init` MUST keep its overrides and reporting behavior. It MUST always pass `integration=codex`, so the declaration's `harness` becomes `codex`. Its other defaults (`extensions=recommended`, `security=safe`) MUST apply only when the project has no declaration. When a declaration exists, `$cc-spex-init` MUST NOT pass extension or security input unless the user gives an explicit override, so the declaration's selection and security are applied unchanged.
- **FR-012**: Adding the Codex plugin definition MUST NOT change Claude Code plugin behavior or `/spex:init`.
- **FR-013**: The repository MUST contain a committed Codex marketplace definition (`.agents/plugins/marketplace.json`, marketplace `cc-spex`) that exposes the plugin `cc-spex` with source `./spex`. The ignore rules MUST allow this file to be committed.
- **FR-014**: The documentation MUST describe the Codex install path, the migration from the thin plugin, and the exact selection semantics (README, help). The constitution's Plugin Architecture Constraints MUST record that `spex/` is both the Claude Code and the Codex plugin.
- **FR-015**: Tests MUST cover: setup from temporary and macOS-style `$TMPDIR` sources; exact selection for each mode, including a refresh and a switch from `all` to `recommended`; and Codex init from a bundled source without network access (with stubs first on `PATH` that fail `git clone`, `git fetch`, `git ls-remote` and `curl` and pass every other `git` call to the real binary, plus a check that no `cc-spex-init-*` directory is created).
- **FR-016**: For projects without a project declaration, Claude `/spex:init --refresh` MUST keep its current behavior of preserving the enabled/disabled state of already installed extensions.
- **FR-017**: The bundled Codex plugin MUST be published under the existing Codex identity `cc-spex` in the `cc-spex` marketplace, so a plugin update replaces the thin plugin.
- **FR-018**: Setup output MUST name every spex extension whose enabled state it changed.
- **FR-019**: Wherever spex tells the user how to resolve "spex-worktrees requires the git extension" (setup workflow, `/spex:init`, the init skill), the guidance MUST say to re-run setup with a selection that leaves out `spex-worktrees` (or to add the `git` extension), not to disable `spex-worktrees` by hand.
- **FR-020**: The release process MUST set the Codex plugin manifest to the same version as the Claude plugin and the setup workflow. The Codex marketplace entry carries no version (the Codex marketplace format has no version field).
- **FR-021**: The Codex plugin MUST expose only `cc-spex-init` to Codex. Skills meant for Claude Code (for example the `init` skill under `spex/skills/`) MUST NOT appear in Codex.
- **FR-022**: An interactive (non-refresh) Claude `/spex:init` MUST write a valid project declaration to `.specify/spex.json`. When the file is missing, it creates it with `harness=claude`, the resolved extension selection, and `security` mapped from the permission choice (None to `safe`, Standard to `autonomous`, YOLO to `yolo`). When the file exists, it replaces `extensions` and `security` with the new choices and leaves `harness` unchanged.
- **FR-023**: When a refresh applies a project declaration (no explicit selection) that lists `spex-detach`, and the extension registry before reinstalling shows `spex-detach` installed and disabled, spex MUST remove `spex-detach` from the declaration instead of enabling it, and MUST report the removal. This applies to both init paths.

### Key Entities

- **Spex source tree**: the `spex/` directory with the setup workflow, the extensions and the scripts. It is the Claude Code plugin, and with this feature also the Codex plugin.
- **Codex plugin**: the installed copy of the spex source tree in the Codex plugin cache, plus a Codex manifest and the `cc-spex-init` skill.
- **Extension selection**: the requested set of optional spex extensions (mode or list), resolved with dependencies.
- **Project declaration** (`.specify/spex.json`): the persisted harness, extension selection and security choice for a project.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `$cc-spex-init` with defaults succeeds on macOS and Linux in a fresh project on 3 of 3 attempts, and makes 0 attempts to fetch spex (verified with the stubs described in FR-015).
- **SC-002**: A setup run from a source under a macOS-style `$TMPDIR` path installs 7 of 7 spex extensions.
- **SC-003**: For each of the 4 selection modes, the enabled optional extensions after setup match the resolved selection exactly (0 extra, 0 missing).
- **SC-004**: After init, the release version of the source setup ran from (setup workflow version and Claude Code plugin manifest version) equals the Codex plugin manifest version.
- **SC-005**: Following the migration steps leaves exactly 1 cc-spex plugin in Codex.
- **SC-006**: Existing Claude Code installs and their test suites pass unchanged.

## Assumptions

- The Codex plugin manifest can point its skills at a subdirectory of the plugin, and a skill can determine its plugin's installed root at runtime. If not, the plan picks the closest supported layout that still bundles the same tree.
- Codex copies the whole plugin directory into its cache, including files Codex does not use (Claude-only manifests and hooks). These are inert for Codex.
- `specify extension add --dev` copies the extension into the project and links generated commands only to a cache inside the project. This makes development mode safe for temporary sources. Verified against `specify` 1.0.5.dev0; earlier versions accepted by the version check are not verified.
- The two init paths (Claude `/spex:init` via `spex-init.sh`, and the setup workflow) follow the same selection rule whenever a project declaration exists (FR-004, FR-016).
- The unmerged branch `050-cc-spex-plugin` is not merged. Its plugin skeleton and setup fix serve only as a reference, and the branch is deleted once this feature lands.
- Wider first-class Codex topics (pipeline semantics, hooks; brainstorm 42) are out of scope.
