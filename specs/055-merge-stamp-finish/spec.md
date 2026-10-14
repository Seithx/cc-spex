# Feature Specification: Merge stamp into finish

**Feature Branch**: `055-merge-stamp-finish`

**Created**: 2026-10-13

**Status**: Draft

**Input**: Brainstorm `brainstorm/49-merge-stamp-finish.md`: finish becomes the single close-out command with verification as a blocking first phase; the redundant stamp command is removed; verify stays as the standalone check-only command.

## Background

Closing out a feature currently involves three overlapping commands:

- **verify** (spex-gates) performs the real checks: closeout gate, tests, code hygiene, spec compliance (100% required), drift, and success criteria.
- **stamp** (spex-gates) is a wrapper that only invokes verify.
- **finish** (core spex) runs the walkthrough gate, squashes, and merges, opens a PR, or keeps the branch. It never runs verify.

The documentation contradicts the behavior. Stamp says finish performs "verification + merge/PR/cleanup", and the methodology entry point says finish "verifies + merges/creates PR in one step". The pre-commit reminder points to stamp. Submit already runs verify before pushing, so today the PR path is verified while the direct-merge path is not. The ship pipeline description claims it runs "specify through verify", but its eight stages end at review-code, and a leftover ninth stage name ("stamp") remains in the stage-ordering hooks.

## Clarifications

### Session 2026-10-13

- Q: Should finish's verification phase run before or after the `before_finish` extension hooks (for example, the detach archive hook)? → A: Before them, so no hook acts on unverified code.
- Q: Which spec does finish verify when it runs on the default branch with no feature branch? → A: The spec verify resolves through its normal selection; when none resolves in unattended mode, stop with the `--no-verify` override (FR-009).
- Q: Should submit also skip verification when a pass is recorded for the current code? → A: No. Submit keeps always running verify in this feature; its passing run still writes the shared record.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Finish refuses to land unverified code (Priority: P1)

A developer finishes a feature with one command. Before anything is squashed or merged, finish runs the full verification. If verification fails, nothing is squashed or merged, and the developer is told which gates failed and how to resolve them.

**Why this priority**: This closes the actual defect: following the docs today lands code that was never verified.

**Independent Test**: On a feature branch with a deliberately failing test, run finish and confirm it stops before squash with the failing gate listed; fix the test, rerun finish, and confirm it proceeds to the walkthrough gate and squash.

**Acceptance Scenarios**:

1. **Given** a feature branch where verification passes, **When** the developer runs finish, **Then** finish reports that verification passed and continues to the walkthrough gate, squash, and the merge/PR/keep choice.
2. **Given** a feature branch where verification fails (any gate), **When** the developer runs finish, **Then** finish stops before the walkthrough gate and squash, lists each failing gate, and names the two ways out: fix and rerun finish, or reconcile the spec with `/speckit-spex-evolve`.
3. **Given** an unattended run (ship state running with ask level smart or never, or `--auto`), **When** verification fails, **Then** finish stops without prompting and reports the failure; it never continues to squash or merge.
4. **Given** a verification failure, **When** finish stops, **Then** the branch, its commits, and the working tree are unchanged.

---

### User Story 2 - No duplicate verification and explicit skip (Priority: P2)

A developer who just ran verify (or ran finish once, fixed an unrelated walkthrough issue, and reruns it) does not wait for the same checks twice on unchanged code. A developer who deliberately wants to land without verification can say so explicitly.

**Why this priority**: Verification runs the full test suite and compliance check; repeating it on unchanged code wastes minutes and discourages using finish.

**Independent Test**: Run verify on a feature branch, then run finish without changing code and confirm it reports the earlier pass instead of re-running; change a non-spec file and confirm finish re-runs verification; run finish with `--no-verify` and confirm verification is skipped with a visible note.

**Acceptance Scenarios**:

1. **Given** verification passed for the current code state, **When** finish runs, **Then** it prints that verification already passed for this code and does not re-run it.
2. **Given** verification passed earlier but code outside spec directories and brainstorm documents has changed since, **When** finish runs, **Then** it re-runs verification.
3. **Given** a recorded pass from an earlier session (for example, before `/clear`), **When** finish runs on unchanged code, **Then** the earlier pass is honored.
4. **Given** `--no-verify`, **When** finish runs, **Then** it skips verification, prints a one-line note that verification was skipped by request, and proceeds.
5. **Given** both `--no-verify` and `--no-walkthrough`, **When** finish runs, **Then** both phases are skipped, each with its own note.

---

### User Story 3 - One clear name for each job (Priority: P2)

A user reading the help, README, or command list sees exactly two close-out commands with distinct jobs: verify checks, finish checks and lands. The stamp command no longer exists, and every reminder, hook message, and doc points to verify or finish.

**Why this priority**: The confusion between three names is the user-facing problem that motivated the change.

**Independent Test**: Search the shipped commands, hooks, adapters, and docs for the stamp command and confirm no live references remain (historical specs, brainstorms, and the changelog excepted); trigger the pre-commit reminder and confirm it names verify or finish.

**Acceptance Scenarios**:

1. **Given** the installed extensions, **When** the user lists available commands, **Then** no stamp command is offered.
2. **Given** a commit attempted in a spex project without a recorded verification, **When** the reminder fires, **Then** it suggests `/speckit-spex-gates-verify` or `/speckit-spex-finish`.
3. **Given** the README migration table, **When** a user looks up the legacy `/spex:stamp`, **Then** it maps to `/speckit-spex-finish`.
4. **Given** the help and methodology docs, **When** a user reads how to close out a feature, **Then** the described behavior of finish matches what finish does (verify, walkthrough gate, squash, land).

---

### User Story 4 - Finish degrades gracefully without spex-gates (Priority: P3)

Finish is part of the core extension, while verify belongs to spex-gates, which can be disabled. A project without spex-gates can still use finish.

**Why this priority**: Required for extension composability, but affects only projects that opted out of quality gates.

**Independent Test**: Disable spex-gates, run finish, and confirm it prints a one-line note that verification is unavailable and continues to the walkthrough gate.

**Acceptance Scenarios**:

1. **Given** spex-gates is disabled or not installed, **When** finish runs, **Then** it prints one line stating verification was skipped because spex-gates is not enabled, and continues.

---

### Edge Cases

- **Finish on the default branch**: verification runs first against the spec verify resolves through its normal selection, then finish reports that there is nothing to merge and stops, as it does today. Running finish on the default branch therefore acts as a check-only run.
- **No spec resolvable for the branch**: verification cannot select a spec. Finish stops and reports that no spec was found, with the `--no-verify` override, rather than prompting for a spec in unattended mode.
- **Dirty working tree**: the recorded pass applies to content, not commits; uncommitted edits outside spec directories and brainstorm documents change the fingerprint, so a pass recorded before those edits is not honored, while committing already-verified content keeps it valid.
- **Verify interrupted or erroring** (not a clean pass or fail): treated as not passed; finish stops and reports the error.
- **Ship's "Merge directly" choice**: ship invokes finish, so the pipeline's direct-merge path now gets verification; ship's own stages are unchanged.

## Requirements *(mandatory)*

### Functional Requirements

**Finish verification phase**

- **FR-001**: Finish MUST run verification as its first phase, before its `before_finish` extension hooks, the walkthrough gate, squash, archive, or any merge, PR, or keep action.
- **FR-002**: When verification does not pass, finish MUST stop before any later phase, list each failing gate, and name both resolution paths: fix and rerun finish, or reconcile with `/speckit-spex-evolve`. It MUST NOT offer "continue anyway" in any mode.
- **FR-003**: In unattended mode (ship state running with ask level smart or never, or `--auto`), finish MUST NOT prompt during the verification phase; a failure still stops finish.
- **FR-004**: Finish MUST accept `--no-verify`, which skips the verification phase and prints a one-line note that it was skipped by request. `--no-walkthrough`, `--auto`, and `--skip-archive` MUST keep their current behavior and combine freely with `--no-verify`.
- **FR-005**: Finish MUST skip re-running verification when a pass is recorded for the current code state, printing that verification already passed for this code.
- **FR-006**: A recorded pass MUST be tied to the code state, not to the session: it survives `/clear` and new sessions, and it is invalidated when any file outside spec directories and brainstorm documents differs from the state that was verified (committed or uncommitted).
- **FR-007**: Every successful verify run (standalone or from finish) MUST record a pass for the code state it verified. A failed or interrupted run MUST NOT record a pass.
- **FR-008**: When spex-gates is not enabled (its entry in the extensions registry is missing or disabled), finish MUST skip verification with a one-line note naming the reason and continue.
- **FR-009**: When verification cannot resolve a spec for the current branch, finish MUST stop with a message that names `--no-verify` as the override.
- **FR-009a**: The stop message MUST have a fixed shape: a first line `Finish stopped: verification did not pass.`, `Finish stopped: no spec found for verification.`, or `Finish stopped: verification did not complete.` (interrupted or erroring run); then one line per failing gate by name, or the error; then the resolution lines naming `/speckit-spex-evolve` (failed gates only) and `/speckit-spex-finish --no-verify`.
- **FR-009b**: Verify MUST accept an `--embedded` argument, which finish and submit pass when they invoke it. With `--embedded`, verify MUST NOT remove `.specify/.spex-state` and MUST NOT show its completion banner; the caller keeps ownership of state cleanup. A standalone verify (no `--embedded`) keeps today's banner and cleanup.

**Verification record**

- **FR-009c**: The verification record MUST be read and written only through a deterministic script (Constitution VII). The code state it covers MUST be the same content fingerprint the walkthrough uses for currency (a hash of the working tree content excluding spec directories and brainstorm documents), so committing after verify, or finish's own commit of outstanding changes, does not invalidate it.
- **FR-009d**: The record MUST be stored per worktree, untracked, outside `.specify/.spex-state`, and outside the content its own fingerprint hashes (for example, inside the worktree's git directory), so writing it never invalidates it. It MUST survive `/speckit-spex-clear` and pipeline state cleanup.

**Stamp removal and naming**

- **FR-010**: The stamp command MUST be removed from the spex-gates extension: its command file, its manifest entry, the `suppress-prompts-stamp` mappings in both the Codex and Claude harness adapter command maps, the stamp entry in the context hook's known-command lists (both the Python and shell variants), and the marketplace install test's expectation of the stamp file (the test MUST instead pass without it).
- **FR-011**: The pre-commit verification reminder (both hook implementations) MUST name `/speckit-spex-gates-verify` and `/speckit-spex-finish`, MUST NOT mention stamp, and MUST read the shared verification record (FR-009c) instead of the session-scoped temporary marker. Verify MUST stop writing that session-scoped marker.
- **FR-011a**: Commits that finish makes itself (outstanding changes, squash) MUST proceed without a confirmation prompt when a pass is recorded for the code state or `--no-verify` was given.
- **FR-012**: The leftover ninth stage name ("stamp", index 8) MUST be removed from both copies of the ship stage map (the pre-tool gate and the shared stage-gate script), since ship has eight stages ending at review-code. Both copies of the ship status line MUST show no "stamp" stage.
- **FR-013**: Ship's description and body text MUST state its real last stage (review-code) and that verification runs in finish or submit. Every claim that ship's final stage is verify, or that ship runs "through verify", MUST be removed, and ship's description of finish MUST include verification.
- **FR-014**: The recorded verification pass that satisfies the pre-commit reminder MUST be the same record finish reads (FR-005, FR-006), so a pass from either command quiets the reminder for that code state.

**Documentation**

- **FR-015**: README (commands reference, workflow text, migration table with `/spex:stamp` mapped to `/speckit-spex-finish`), both help files (`spex/docs/help.md` and the extension's `docs/help.md`), the methodology entry point, the evolve command's references, the harness preambles, and the project CLAUDE.md extension descriptions MUST describe finish as verify, walkthrough gate, squash, and land, and MUST NOT reference stamp.
- **FR-016**: Finish's own description and argument hint MUST include the verification phase and `--no-verify`.

### Key Entities

- **Verification record**: Evidence that verify passed for a specific code state. Attributes: the content fingerprint it covers (FR-009c), the time, and the feature. Read by finish and by the pre-commit reminder; written only by a passing verify run (standalone, from finish, or from submit).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 0 paths through finish reach squash or merge after a failed verification, across interactive, `--auto`, and ship-invoked runs.
- **SC-002**: Running finish immediately after a passing verify on unchanged code re-runs 0 verification gates.
- **SC-003**: 0 live references to the stamp command remain in shipped commands, hooks, adapters, and user docs (historical specs, brainstorms, and the changelog excepted).
- **SC-004**: A user closing out a feature needs exactly 1 command (finish) to both verify and land it.
- **SC-005**: Every statement about finish in README, help, and the methodology entry point matches its actual phase order.

## Assumptions

- "Code state" uses the same rule as the walkthrough's currency check: changes inside spec directories and brainstorm documents do not invalidate a pass.
- What verify checks (its gates and compliance rules) is unchanged; only where it is invoked, how its pass is recorded, and its end-of-run cleanup when called from finish or submit change.
- Submit keeps always running verify before pushing (it does not read the record); its passing run writes the shared record, so a later finish on unchanged code skips re-verification.
- The ship pipeline keeps its eight stages; adding a verify stage to ship is out of scope.
- No deprecation alias for stamp: it is removed outright, and the README migration table is the pointer for users of the legacy name.
- The mechanical compliance gate (brainstorm #46) is out of scope.
