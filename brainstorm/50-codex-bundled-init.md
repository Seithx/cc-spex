# Brainstorm: Codex Init from a Bundled Spex Source

**Date:** 2026-10-18
**Status:** active
**Issue:** https://github.com/rhuss/cc-spex/issues/58

## Problem Framing

Running `$cc-spex-init` from Codex fails on macOS, and when it does get through, it leaves the wrong extensions enabled ([#58](https://github.com/rhuss/cc-spex/issues/58)).

How the Codex init works today:

- `$cc-spex-init` comes from the Codex plugin `cc-spex@cc-spex` (cache version `0.1.0+codex.20260726163220`). It was built from the branch `050-cc-spex-plugin`, which was never merged into `main` and is now 40 commits behind.
- The plugin is thin. It ships only the init skill and `bootstrap.sh`, not the extensions.
- `bootstrap.sh` looks for a spex source tree in this order:
  1. `$SPEX_SOURCE`;
  2. `./spex/setup.yml`, which exists only inside the cc-spex repo;
  3. otherwise it shallow-clones the current GitHub `main` into `$TMPDIR/cc-spex-init-XXXX`, runs `specify workflow run` on that `setup.yml`, and deletes the clone.
- The clone is not pinned. A 07-26 plugin runs today's `setup.yml`.

Two defects on `main` follow from this:

1. **The install step drops `--dev` for temp sources.** `setup.yml` omits `--dev` when the source is under `/tmp` or `$TMPDIR`, which is exactly where the bootstrap clone lives. Current `specify extension add <path>` without `--dev` looks the path up in the catalog and fails with "not found in catalog".
   - The exception has no purpose any more. With `--dev`, specify copies the extension into `.specify/extensions/<id>` and links commands to `.specify/extensions/.cache`, so deleting the temp directory breaks nothing.
   - Branch `050` already fixed this (always `--dev`), but the fix never reached `main`.
2. **`recommended` and `all` don't enforce the selection.** Both are no-ops in `setup.yml`. Only the interactive path and an explicit list disable unselected extensions. Because every optional extension is installed first, `recommended` leaves `spex-teams` and `spex-collab` enabled, even though `.specify/spex.json` records the recommended list correctly.

Behind both defects sits a structural problem: the plugin and the source it installs are versioned separately, and the source arrives over the network into a temp directory.

## Approaches Considered

### A: `spex/` is also the Codex plugin

Add `spex/.codex-plugin/plugin.json` next to the existing `spex/.claude-plugin/`. The Codex skills live in a Codex-specific subdirectory, and the Codex marketplace points at `spex/`. Codex installs the whole tree into its plugin cache, and the bootstrap uses that installed tree as the spex source.

- Pros:
  - The same model as the Claude plugin.
  - Nothing is duplicated, and every release ships the matching extensions.
  - No network clone or temp directory, so bug 1 cannot recur through the bootstrap.
- Cons:
  - The Codex cache also contains Claude-only files (hooks, `.claude-plugin`). Harmless, but unneeded.
  - Needs confirmation that a Codex manifest can point `skills` at a subdirectory, and that the skill can find its plugin root at runtime.

### B: Generated bundle under `plugins/cc-spex/`

`make codex-plugin` copies the needed parts of `spex/` into the Codex plugin directory, and the copy is committed. A check like `sync-scripts-check` keeps it current.

- Pros: the Codex plugin contains only what Codex needs.
- Cons: two copies of the same tree, large diffs, and a sync step that can be forgotten. This is the same class of drift as the renamed git-extension script.

### C: Version-pinned release tarball

The thin plugin downloads the spex tarball of its own version from the GitHub release.

- Pros: a small plugin, pinned to a version.
- Cons: still needs the network and a temp directory, and every release needs an upload.

## Decision

**Approach A.** `spex/` becomes the Codex plugin as well, and `$cc-spex-init` initializes from the installed plugin tree. The work is rebuilt on `main`. Branch `050-cc-spex-plugin` serves only as a reference (its `--dev` fix and plugin skeleton) and is deleted afterwards. Both [#58](https://github.com/rhuss/cc-spex/issues/58) defects are fixed in the same change.

## Key Requirements

1. **Always `--dev`:** `setup.yml` installs local spex extensions with `--dev` regardless of where the source lives. The `/tmp` / `$TMPDIR` exception is removed.
2. **Exact extension selection:** in every mode (`recommended`, `all`, explicit list, interactive), the enabled optional extensions afterwards match the selection exactly, and all others are disabled. `.specify/spex.json` and the registry agree.
3. **Refresh reuses the persisted selection:** a refresh without `--extensions` applies the list persisted in `.specify/spex.json`.
4. **Codex plugin from `spex/`:** a `spex/.codex-plugin/plugin.json` with the `cc-spex-init` skill in a Codex-specific skills directory. The Codex marketplace exposes `spex/`, and the plugin version equals the spex version.
5. **No clone:** `$cc-spex-init` uses the installed plugin tree as the spex source, with no `git clone` and no temp directory. `$SPEX_SOURCE` and an in-repo `./spex/` stay supported for development.
6. **Migration:** existing Codex installs of the thin `0.1.0+codex.*` plugin get documented steps to switch to the new plugin (or are replaced cleanly by a marketplace update).
7. **Docs and tests:** README, help, and Codex install instructions describe the new path. Tests cover a non-repo project init from the plugin tree, macOS-style `$TMPDIR` paths, and the exact selection for each mode.

## Open Questions

- Can a Codex plugin manifest point `skills` at a subdirectory such as `codex/skills/`, and how does the skill or `bootstrap.sh` resolve its plugin root at runtime?
- Should a manual `specify extension enable/disable` also update `.specify/spex.json`, so the next refresh does not undo it?
- How does "selection is exact" interact with today's `spex-init.sh` change that keeps manually disabled extensions disabled across a refresh? The two init paths (Claude `/spex:init` via `spex-init.sh`, and the `setup.yml` workflow) should follow one rule.
- Do Claude-only files in the Codex cache (`hooks.json`, `.claude-plugin/`) cause any Codex-side warnings?
