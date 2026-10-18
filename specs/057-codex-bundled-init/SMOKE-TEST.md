# Guided Demo Report

**Feature**: Codex Init from a Bundled Spex Source
**Date**: 2026-10-18
**Spec**: specs/057-codex-bundled-init/spec.md
**Result**: 4 passed, 0 skipped, 0 failed, 1 manual (out of 5)

---

## Triage Summary

| Tier | Count | Detail |
|------|-------|--------|
| full | 4 | Real `specify` 1.0.5.dev0 in fresh `/tmp/claude-501/sm57.*` projects |
| manual | 1 | Needs the Codex CLI plugin commands and the user's Codex installation |

User selection: Run what's ready

---

## Flow 1: Setup from a macOS `$TMPDIR` source

**Tier**: full | **Covers**: FR-001, FR-002, US2

**Execution**: copied `spex/` to `/var/folders/.../T//spex-src-XXXXXX`, ran `specify workflow run <copy>/setup.yml -i integration=claude -i extensions=recommended -i security=safe`, then deleted the copy.

```
setup rc=0  status=completed
installed: spex spex-collab spex-deep-review spex-detach spex-gates spex-teams spex-worktrees
enabled:   spex gates worktrees deep-review = true; teams collab detach = false
source deleted: yes; dangling symlinks: 0; speckit-spex-* skills: 28
```

### Verdict: PASS

---

## Flow 2: Exact extension selection

**Tier**: full | **Covers**: FR-003, FR-004, FR-005, FR-018

| Run | Enabled afterwards | Report | `spex.json` |
|-----|-------------------|--------|-------------|
| `all` | all except `spex-detach` | 0 changes (git warning, git added by the following check) | 6 extensions |
| `recommended` after `all` | gates, worktrees, deep-review | `Disabled: spex-teams`, `Disabled: spex-collab` | recommended |
| list `spex-teams` | teams, gates | `Disabled: spex-worktrees`, `Disabled: spex-deep-review`, `Enabled: spex-teams` | spex, gates, teams |
| refresh, no input | unchanged | 0 changes | byte-identical |

The `git` extension was enabled in both projects afterwards.

### Verdict: PASS

---

## Flow 3: Codex bootstrap from the bundled tree

**Tier**: full | **Covers**: FR-008 to FR-011, US1

**Execution**: copied `spex/` to a fake Codex cache path, put stubs first on `PATH` (fail `git clone/fetch/ls-remote` and `curl`), ran the copy's `codex/skills/cc-spex-init/scripts/bootstrap.sh` in a fresh project, then with `--extensions all --security autonomous`, then again without arguments.

```
manifest: cc-spex 6.1.0 skills=./codex/skills/ (only cc-spex-init)
run 1: Initializing Spex from bundled source .../codex-cache/cc-spex/6.1.0: integration=codex extensions=recommended security=safe
       spex.json {"harness":"codex","extensions":[spex,gates,worktrees,deep-review],"security":"safe"}
run 3: integration=codex extensions=(from .specify/spex.json) security=autonomous (from .specify/spex.json)
       spex.json keeps all (no detach) + autonomous
blocked network calls: 3 x curl (release check), 0 x git
new cc-spex-init-* temp dirs: 0
```

A pre-existing `$TMPDIR/cc-spex-init-*` directory from 2026-10-16 09:12 is a leftover of the old thin plugin, not created by this run.

### Verdict: PASS

---

## Flow 4: `spex-init.sh --refresh` follows the declaration

**Tier**: full | **Covers**: FR-004, FR-023

**Setup**: declaration listing all seven including `spex-detach`; `spex-collab` disabled by hand; `spex-detach` disabled.

```
refresh rc=3 (RESTART_REQUIRED, normal)
Migrated: removed spex-detach from .specify/spex.json (it was disabled; select it explicitly to enable it)
Enabled: spex-collab
after: spex-detach=false, removed from spex.json; .git/info/exclude spec lines: 0
```

### Verdict: PASS

---

## Flow 5: Real Codex install

**Tier**: manual | **Covers**: FR-013, FR-021, US4, SC-005

### Verdict: MANUAL

1. Push the branch (or merge), then `codex plugin marketplace add rhuss/cc-spex --ref main` and `codex plugin add cc-spex@cc-spex` (commands from the README; not yet run).
2. Confirm the Codex skill list shows `cc-spex-init` and not the Claude `init` skill.
3. On a machine with the old thin plugin: follow the README migration and confirm exactly one `cc-spex` plugin remains.
4. In a fresh project: `$cc-spex-init`; expect no `cc-spex-init-*` directory under `$TMPDIR` and `harness: codex` in `.specify/spex.json`.

---

## FR Coverage

| FR | Flow | Verdict |
|----|------|---------|
| FR-001, FR-002 | 1 | PASS |
| FR-003, FR-005, FR-018 | 2 | PASS |
| FR-004 | 2, 4 | PASS |
| FR-006 | 2 (git never disabled) | PASS |
| FR-008 to FR-011 | 3 | PASS |
| FR-023 | 4 | PASS |
| FR-007, FR-021 | 3 (manifest), 5 | PASS (layout) / MANUAL (Codex listing) |
| FR-013, US4 | 5 | MANUAL |
| FR-012, FR-014 to FR-017, FR-019, FR-020, FR-022 | automated test suites and code review | not demoed |
