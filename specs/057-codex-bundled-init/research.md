# Research: Codex Init from a Bundled Spex Source

## R1: Can `spex/` be a Codex plugin, with its skills in a subdirectory?

**Decision**: Yes. Add `spex/.codex-plugin/plugin.json` with `"skills": "./codex/skills/"` and put the skill at `spex/codex/skills/cc-spex-init/`.

**Evidence** (Codex CLI 0.163.0 binary strings):
- Manifest paths "must start with `./` relative to plugin root" and must not resolve outside the plugin root. `./codex/skills/` qualifies.
- Codex looks for `.codex-plugin/plugin.json`, then `.claude-plugin/plugin.json`, then `.cursor-plugin/plugin.json`. The Codex manifest is used first.
- There is a precedent: cc-review's `review/` directory carries both `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` and is installed by both harnesses.

**Why a subdirectory**: `spex/skills/init/SKILL.md` is the Claude `/spex:init` skill. Pointing Codex at `./skills/` would expose it in Codex (FR-021).

**Residual risk**: It is not proven whether Codex also scans a default `./skills/` directory in addition to the manifest path. The manual quickstart check lists the skills after an install, and if `init` appears, the plan falls back to moving the Claude skill (see Risks in plan.md).

**Alternatives rejected**: generated bundle under `plugins/cc-spex/` (duplication and drift) and release tarball (network and temp dir again). Both are documented in brainstorm 50.

## R2: How does the bootstrap find the plugin root at runtime?

**Decision**: Derive it from the script's own path. `bootstrap.sh` lives at `<root>/codex/skills/cc-spex-init/scripts/bootstrap.sh`, so the root is four levels up. The script then checks that `<root>/setup.yml` and `<root>/extensions/spex/extension.yml` exist.

**Evidence**: Codex has `PLUGIN_ROOT` / `CLAUDE_PLUGIN_ROOT` only for hooks and MCP servers, not for skills. For skills, Codex expands the `SKILL.md` path to an absolute path and tells the model to resolve relative references from that directory. The SKILL.md therefore tells the agent to run the bundled script by its absolute path while staying in the project root, and the script finds everything else relative to itself.

## R3: Is Codex's plugin cache a full copy of the plugin directory?

**Decision**: Yes. The installed tree is the spex source.

**Evidence**: `~/.codex/plugins/cache/cc-review-plugin-development/cc-review/1.2.0` has a file list identical to cc-review's `review/` source directory, including `.claude/`, `.claude-plugin/` and all other subdirectories. Claude-only files in `spex/` (`hooks.json`, `.claude-plugin/`, `.claude/`) are copied too. They are inert for Codex: Codex's default hooks path is `hooks/hooks.json` (no such directory in `spex/`), and `spex/` has no top-level `commands/` that Codex could migrate into skills.

## R4: Is `--dev` safe for temporary sources?

**Decision**: Always pass `--dev`, regardless of the source location.

**Evidence**:
- In `specify` 1.0.5.dev0, `extension add --dev` calls `install_from_directory(..., link_commands=True)`. That copies the extension into `.specify/extensions/<id>` and links generated commands to `.specify/extensions/.cache`, which is inside the project.
- Without `--dev`, a path argument is looked up as a catalog name and fails ("not found in catalog").
- Branch `050-cc-spex-plugin` already made this change but was never merged.
- The temp-path exception has no remaining purpose.

## R5: Where does the selection get enforced today, and why does it drift?

**Findings** (`spex/setup.yml`):
- All seven extensions are installed, then `spex-detach` is always disabled (line 223).
- `recommended` and `all` are no-op switch cases (241-248).
- Interactive "all" or an empty reply disables nothing (271-274).
- An explicit or declaration-sourced list disables the unselected extensions (308-351), but nothing ever re-enables a listed one. If an earlier run had disabled it, it stays off.
- `selected-extensions` (353-370) maps `all` and interactive "all" to a list that includes `spex-detach`. So the persisted declaration says `spex-detach` while the registry says disabled.

**Decision**: Replace all per-mode enforcement with one script, `spex/scripts/spex-apply-extensions.sh` (Constitution VII), called once after `selected-extensions` has resolved the final list.
- It enables what is selected, disables what is not, and reports every change (FR-018).
- `all` and interactive "all" resolve to the six-extension set without `spex-detach`.
- `spex-detach` is installed like the others and then handled by the same rule (disabled unless selected), which replaces line 223.

## R6: Which values does `$cc-spex-init` pass to setup?

**Decision**:
- It always passes `-i integration=codex`.
- It passes `-i extensions=...` and `-i security=...` only when the user gave them explicitly, or when `.specify/spex.json` is missing (then `recommended` and `safe`).
- With a declaration and no overrides, setup's `extension-mode` and `security-mode` steps read the declaration (their inputs default to empty).
- `persist-request` takes the harness from `resolve-request`, so `integration=codex` records `harness: codex` (FR-011).

## R7: How do the Claude init paths follow the declaration?

**Findings**:
- `/spex:init` without flags delegates to `setup.yml` with no inputs (`spex-init.sh` 742-744), so it already reads the declaration.
- `--refresh` and `--update` call `install_extensions` directly, which preserves previously disabled extensions from the registry (439-497) and never reads `.specify/spex.json`.
- The init skill's Step 2 disables unselected extensions by hand and never writes the declaration.

**Decision**:
- **FR-004**: when `.specify/spex.json` exists, `install_extensions` applies the declaration's extensions through `spex-apply-extensions.sh` instead of the registry snapshot.
- **FR-016**: when it does not exist, the registry snapshot behavior stays exactly as it is.
- **FR-022**: the init skill's Step 2 applies its choice through `spex-apply-extensions.sh` and persists it with `spex-setup-profile.py resolve ... | persist`. It passes `--harness claude` only when the file is missing, and `--legacy-permissions none|standard|yolo` for the permission choice.

## R8: Where does the Codex marketplace file live, and how do we commit it?

**Decision**: `.agents/plugins/marketplace.json` with marketplace `cc-spex`, plugin `cc-spex` and local source `./spex`. This is the first file Codex looks for.

**Constraints found**:
- `.gitignore` ignores `**/.agents/` at line 74 and again at line 89. The negations (`!/.agents/`, `/.agents/*`, `!/.agents/plugins/`, `/.agents/plugins/*`, `!/.agents/plugins/marketplace.json`) must come after line 89.
- `tests/test_generated_trees.sh` (the only CI job) fails on any tracked `.agents/` path. Its filter needs an exact exemption for `.agents/plugins/marketplace.json`.
- Codex also reads `.claude-plugin/marketplace.json` (the existing `spex-plugin-development` marketplace). The `.agents` file is found first, and the manual check confirms that only `cc-spex` appears.

## R9: Versioning and release

**Decision** (updated in plan review: release version, not `VERSION`):
- `spex/.codex-plugin/plugin.json` carries the release version, the same value as the `setup.yml` workflow `version` and `spex/.claude-plugin/plugin.json` (currently `6.1.0`). `make release` sets all three. `spex/VERSION` carries the next `-dev` version between releases and is not compared.
- `make release` sets that `version` next to the Claude manifests.
- The Codex marketplace entry has no `version` field in Codex's format (the committed 050 entry has none, and the installed version comes from the plugin manifest), so the entry stays version-free. FR-020 is met through the manifest it points to (see the plan's Complexity Tracking).
- A test asserts that `spex/.codex-plugin/plugin.json .version` equals the `setup.yml` workflow version and `spex/.claude-plugin/plugin.json .version` (SC-004). Like the Claude plugin, Codex sees a new version only at a release.

## R10: Testing without network access to fetch spex

**Decision**: Use the stub-on-`PATH` pattern from `tests/test_init_worktrees_git.sh`.
- A `git` wrapper fails `clone`, `fetch` and `ls-remote` and passes every other call to the real binary.
- A `curl` stub fails every call.
- A fake `specify` records its arguments for bootstrap tests. The real `specify` is used for the setup workflow tests in `tests/test_workflow_setup.sh`, which already create throwaway projects.
