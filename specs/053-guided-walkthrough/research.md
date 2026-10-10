# Research: Guided Walkthrough (pair testing)

All `NEEDS CLARIFICATION` items were resolved during `/speckit-specify` and `/speckit-clarify`. This document records the key technical decisions.

## D1: Run workspace location and gitignore

- **Decision**: Persistent workspace at `specs/<feature>/.walkthrough/<timestamp>/`. Add `specs/**/.walkthrough/` to `.gitignore`.
- **Rationale**: Keeping it under the feature dir makes the artifacts easy to find alongside the report and keeps every command's path short and real. A dedicated gitignore rule keeps it on disk but out of commits (FR-008). The existing `**/.specify/**` ignore does not cover `specs/`, so an explicit rule is needed.
- **Alternatives considered**: A top-level ignored dir (harder to associate with the feature); a temp dir under `$TMPDIR` (not persistent across reboots, harder for the reviewer to find). Rejected.

## D2: Deterministic parsing of stories and FRs

- **Decision**: A Python helper (`spex-walkthrough-coverage.py`) parses the spec for user stories (`### User Story N ... (Priority: Pn)`), their acceptance scenarios, and `**FR-NNN**` entries; emits scenario skeletons in priority order, the FR→scenario coverage map, orphan FRs, and the skip-gate signal (no stories AND no scenarios).
- **Rationale**: Constitution VII requires deterministic work in scripts. Python handles the multiline parsing more reliably than `grep`/`jq` pipelines. Mirrors the existing script-backed gate pattern (`spex-closeout-gate.sh`).
- **Alternatives considered**: Pure-bash `grep` extraction (brittle for multiline Given/When/Then); leaving synthesis to the agent prompt (violates VII, not reproducible). Rejected.

## D3: Script-vs-markdown split (Constitution VII)

- **Decision**: Three scripts own the deterministic parts: `spex-walkthrough-workspace.sh` (create/resolve/print workspace path; never delete), `spex-walkthrough-coverage.py` (synthesis inputs, coverage, orphans, skip gate), `spex-walkthrough-lint.sh` (scan presented/report commands for placeholder tokens, non-zero exit on any hit). The skill markdown orchestrates the human-in-the-loop walkthrough and delegates to these.
- **Rationale**: Makes SC-001/003/005 mechanically verifiable and keeps the skill prompt focused on the interactive flow.
- **Alternatives considered**: One monolithic script (less composable, harder to test); all in markdown (violates VII). Rejected.

## D4: App startup and browser steps

- **Decision**: Reuse the `/run` skill for app startup and Playwright MCP for browser steps when available; degrade to delegated manual steps (FR-014) when not.
- **Rationale**: Skill Autonomy (VI) — do not duplicate app-startup logic already in `/run`. Matches the current smoke-test behavior.
- **Alternatives considered**: Re-implement project-type detection in the walkthrough (duplication). Rejected.

## D5: No-placeholder enforcement

- **Decision**: `spex-walkthrough-lint.sh` scans the report (and the command set the skill is about to present) for placeholder tokens (`<...>`, `TODO`, `scratch`, `PLACEHOLDER`, etc.) and exits non-zero if any are found; the skill must resolve them before finalizing.
- **Rationale**: Turns FR-010 from prompt-hope into a checkable gate (SC-003), consistent with the "make it a script" review finding.
- **Alternatives considered**: Rely on agent discipline only (the original failure mode). Rejected.

## D6: Retention

- **Decision**: Keep all run workspaces until the reviewer removes them; the report prints the exact `rm -rf` command for the current run. No automatic pruning in v1.
- **Rationale**: Persistence is the whole point (US2); automatic deletion reintroduces the original complaint. Pruning can be added later if clutter becomes a problem.
- **Alternatives considered**: Keep last N; auto-delete on pass. Rejected for v1 (YAGNI, and deletion fights the goal).

## D7: Rename strategy

- **Decision**: Hard rename `speckit.spex.smoke-test.md` → `speckit.spex.walkthrough.md` and `SMOKE-TEST.md` → `WALKTHROUGH.md`; update every cross-reference (ship Stage 8, finish, help, README, manifest) in the same change; document in CHANGELOG. No backward-compatible alias.
- **Rationale**: Early in the 6.x line with few users (owner's call); the constitution requires cross-reference and documentation maintenance in the same change.
- **Alternatives considered**: Keep a deprecated alias command (extra surface to maintain for little benefit now). Rejected.
