# Feature Specification: Create the Worktree Together with the Feature Branch

**Feature Branch**: `056-worktree-with-branch`

**Created**: 2026-10-16

**Status**: Draft

**Input**: User description: "https://github.com/rhuss/cc-spex/issues/57 (fix(worktrees): create the worktree together with the feature branch, not after specify)"

## Background

With the `spex-worktrees` extension enabled, the isolated worktree for a feature is created only after `/speckit-specify` finishes. Until then the feature branch is checked out in the main checkout and the spec is written there. The ship pipeline does the same, and creates the branch by hand in the main checkout when the `git` extension is missing.

While the main checkout sits on the feature branch, any other agent session working in the same repository commits onto the feature branch instead of the default branch. This happened on 2026-10-15 (agentmeter, spec 010): the main checkout stayed on the new feature branch for several minutes while a second session committed brainstorm files. The worktree's after-the-fact cleanup also commits every modified tracked file it finds (`git add -u`), which can sweep another session's uncommitted work onto the feature branch.

## Clarifications

### Session 2026-10-16

- Q: After `/speckit-specify` creates the worktree and writes the spec there, where should the current interactive session end up? → A: The session stays in the worktree. Follow-up commands run there in the same session, and the completion message also shows how to open a new session in the worktree.
- Q: When `/speckit-specify` starts while the main checkout is on a branch other than the default branch, which commit should the new feature branch start from? → A: Always the default branch's local tip, with a notice when the main checkout is on a different branch.
- Q: Should the init change (fail instead of warn when `spex-worktrees` is enabled without the `git` extension) be part of this feature or split out? → A: Keep it in this feature as the P3 story.
- Q: If the worktree cannot be created, should specify stop or fall back to working in the main checkout? → A: Stop with an error and a remedy, leaving everything unchanged. No fallback to the main checkout.

### Session 2026-10-16 (code review)

- Q: Should working-directory recovery after a harness reset also cover a direct `/speckit-specify`? → A: No. Reword the edge case: in-project worktrees keep the session's working directory, ship recovers through its state file, and external worktrees outside ship are not recovered automatically.

### Session 2026-10-16 (plan review)

- Q: Agents may dispatch `before_specify` hooks in file order, where the upstream `git` hook always comes first. How is a plain `/speckit-specify` protected? → A: Layered fix. The brainstorm handoff and ship run the worktree step themselves before specify. The spex methodology skill tells agents to dispatch hooks by priority. A late-mode repair restores the main checkout before the spec is written if the order was still wrong. FR-002 and SC-001 name this remaining window, and an upstream proposal asks spec-kit's templates to state the priority order.
- Q: Should the worktree step warn when specify already runs inside a worktree? → A: Warn in interactive runs, stay silent inside a worktree that ship or the brainstorm handoff just prepared on purpose.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Specify a feature without disturbing the main checkout (Priority: P1)

A developer with `spex-worktrees` enabled runs `/speckit-specify` (directly or through a brainstorm handoff). The feature branch and its worktree come into existence in the same step, before any spec content is written. The spec, the feature pointer and the flow state are written inside the worktree. The main checkout stays on the branch it was on from start to finish, and its uncommitted changes are left untouched.

**Why this priority**: This is the defect reported in the issue. Every other improvement depends on isolation starting at branch creation.

**Independent Test**: Record the main checkout's branch and `git status` output, run `/speckit-specify` on a sample feature, and compare. Meanwhile poll the main checkout's branch once per second. The branch never changes, the status output is identical, and the new spec exists only in the worktree.

**Acceptance Scenarios**:

1. **Given** the main checkout is on `main` with `spex-worktrees` enabled, **When** the developer runs `/speckit-specify`, **Then** the main checkout reports `main` as its branch at every moment of the run.
2. **Given** the same setup, **When** `/speckit-specify` completes, **Then** the new `spec.md`, `checklists/`, `.specify/feature.json` (pointing at the new spec directory) and `.specify/.spex-state` exist in the worktree and none of them were created or changed in the main checkout.
3. **Given** the main checkout has uncommitted modifications to tracked files, **When** `/speckit-specify` runs, **Then** those modifications remain uncommitted in the main checkout and do not appear in any commit on the feature branch.
4. **Given** the worktree has been created, **When** the `after_specify` hooks run (review-spec, optional commit, flow-state update), **Then** they act on the worktree's files and the worktree hook reports that isolation already exists instead of creating a second worktree.
5. **Given** `/speckit-specify` finishes interactively, **When** the completion message is shown, **Then** the session's working directory is the worktree, so `/speckit-clarify` or `/speckit-plan` can run next in the same session, and the message names the worktree path and shows how to open a new session there.

---

### User Story 2 - Concurrent session keeps committing to the default branch (Priority: P1)

A second agent session works in the main checkout of the same repository (for example, capturing brainstorm notes) while the first session runs `/speckit-specify` or `/speckit-spex-ship`. Every commit the second session makes lands on the default branch.

**Why this priority**: This is the concrete harm from the incident. It is the outcome users care about, and it validates User Story 1 under real concurrency.

**Independent Test**: Start a specify or ship run in one session. From a second shell in the main checkout, make a commit every few seconds until the first run has finished its specify stage. Every one of those commits is on the default branch and none is reachable only from the feature branch.

**Acceptance Scenarios**:

1. **Given** a ship pipeline is in its specify stage, **When** another session commits in the main checkout, **Then** the commit is on the default branch.
2. **Given** a ship pipeline has created its feature branch, **When** the pipeline continues to later stages, **Then** it runs entirely inside the worktree and never checks out a branch in the main checkout.

---

### User Story 3 - Ship pipeline uses the same one-step creation (Priority: P2)

A developer runs `/speckit-spex-ship` with `spex-worktrees` enabled. The pipeline gets its branch and worktree through the same combined step as `/speckit-specify`. It no longer creates a branch by hand in the main checkout, and it no longer relies on the `after_specify` hook to move work into a worktree after the fact. The ship state file lives in the worktree from the moment the worktree exists.

**Why this priority**: Ship is the most common path into specify for autonomous runs, and it currently has its own branch-creation fallback that bypasses isolation.

**Independent Test**: Run `/speckit-spex-ship` on a small brainstorm document and check the main checkout's branch and the location of the ship state file at the end of stage 0.

**Acceptance Scenarios**:

1. **Given** `spex-worktrees` is enabled, **When** ship stage 0 completes, **Then** the main checkout is on its original branch, the ship state file is in the worktree, and the pipeline's working directory is the worktree.
2. **Given** ship needs the feature branch name after specify, **When** it looks it up, **Then** it gets the name from the combined step's result or the state file, not from the main checkout's current branch.
3. **Given** a ship pipeline is active in a worktree, **When** the status line is rendered for a session in the main checkout, **Then** it shows no flow or ship progress for that feature.

---

### User Story 4 - Init refuses an unusable worktree setup (Priority: P3)

A developer runs `/spex:init` with `spex-worktrees` enabled but the spec-kit `git` extension cannot be enabled. Init stops with an error that names the problem and the fix, instead of printing a warning and continuing.

**Why this priority**: Listed as related work in the issue. Today the warning is easy to miss, and the result is the hand-made branch path that this feature removes.

**Independent Test**: In a scratch project, enable `spex-worktrees` and make the `git` extension unavailable, then run init and check the exit status and message.

**Acceptance Scenarios**:

1. **Given** `spex-worktrees` is enabled and the `git` extension is unavailable, **When** init runs, **Then** it exits with a non-success status and a message naming the missing `git` extension and how to fix it (enable `git` or disable `spex-worktrees`).
2. **Given** `spex-worktrees` is disabled, **When** the `git` extension is unavailable, **Then** init behaves as it does today.

---

### Edge Cases

- **Worktree creation fails** (path already exists, permission denied, disk full): specify stops before writing any spec content, the main checkout is unchanged, and no new branch is left behind. If the branch was created before the failure, it is removed again because it has no commits of its own.
- **Branch name already exists** (locally or checked out in another worktree): specify reports the conflict and stops. It does not check the branch out in the main checkout to resolve it.
- **Main checkout is not on the default branch** when specify starts: the new branch still starts from the default branch's local tip (FR-017). Specify mentions this in its output, naming the branch the main checkout is on. The main checkout stays on that branch.
- **Main checkout has a detached HEAD**: same as above. The new branch starts from the default branch's local tip, and the main checkout stays detached.
- **Default branch cannot be determined**: specify stops before creating anything and reports how to set it (for example, `git remote set-head origin --auto`).
- **Specify is started from inside an existing worktree**: nesting is not supported. The worktree step is skipped and the spec is written in the current worktree. Interactive runs print a warning. A worktree that was just prepared on purpose (by ship or the brainstorm handoff, before its branch exists) gets no warning.
- **Brainstorm document is uncommitted in the main checkout**: the content still reaches specify through the conversation and the ship argument. The file itself stays in the main checkout and is not copied or committed into the worktree.
- **`spex-worktrees` is disabled**: specify behaves exactly as it does today, including checking out the feature branch in the current checkout.
- **External `base_path`** (worktree outside the project): the combined step honors the configured location the same way the current `create` action does.
- **Session working directory**: after the combined step, the rest of the specify run (writing files, running hooks) happens in the worktree, and the session stays there afterwards (FR-013). With the default in-project location (`.claude/worktrees/`), the harness keeps the session's working directory, so no recovery is needed for a direct `/speckit-specify`. Inside a ship pipeline, the existing recovery script returns a reset session to the worktree through the ship state file. For external `base_path` worktrees outside ship, a reset is not recovered automatically; the `finalize` output names the worktree path to change into.
- **Flow state written before the branch exists**: the spex `before_specify` flow-state hook runs first today and writes `.specify/.spex-state` into the current checkout. With `spex-worktrees` enabled, that file must end up only in the worktree (FR-003). Either the hook runs after the worktree exists, or its output is moved there before the spec is written. The main checkout must hold no flow state for the feature at the end of the run.
- **Late-mode window**: the repair only takes over a feature branch that this run's branch hook just created (created within the last 10 minutes, name matching this run, no commits, no spec directory). Any other branch found in the main checkout is left alone and the step stops with an error, so another session's branch is never taken over.
- **Worktrees created by the old flow** keep working with `ensure`, `list`, `finish` and `cleanup`.
- **`ensure` fallback** (implementation starts on a feature branch checked out in the main checkout, for example a feature specified before this change or with `spex-worktrees` enabled afterwards): out of scope. It keeps today's behavior.
- **`ship --resume` and `ship --start-from <stage>` past stage 0**: no branch or worktree is created, so these keep today's behavior and continue wherever the existing feature lives.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When `spex-worktrees` is enabled, creating the feature branch and creating its worktree MUST happen as one step, before `/speckit-specify` writes any spec content.
- **FR-002**: When `spex-worktrees` is enabled, the main checkout's checked-out branch (or detached commit) MUST NOT change at any point during `/speckit-spex-ship`, during `/speckit-specify` started from a brainstorm handoff, or during a direct `/speckit-specify` whose hooks are dispatched in priority order. If an agent dispatches the `before_specify` hooks in file order instead, the main checkout MUST be restored to its previous ref before any spec content is written, and the run MUST print a notice naming the cause.
- **FR-003**: `spec.md`, the spec quality checklist, `.specify/feature.json` and `.specify/.spex-state` for the new feature MUST be written in the worktree, and MUST NOT be created or modified in the main checkout.
- **FR-004**: The combined step MUST NOT stage, commit, stash or otherwise modify uncommitted changes in the main checkout.
- **FR-005**: The combined step MUST copy the configuration the worktree needs (`.specify/`, `.claude/`, and in-repo symlink targets) as the current `create` action does, so that extensions, skills and hooks work in the worktree without running init there.
- **FR-006**: The feature branch name MUST follow the same numbering and naming rules as today (sequential or timestamp numbering, short name, `GIT_BRANCH_NAME` override).
- **FR-007**: The `after_specify` worktree hook MUST detect that the worktree for the current feature already exists and finish without creating, switching or committing anything.
- **FR-008**: All `after_specify` hooks (spec review, optional commit, flow-state update) MUST operate on the worktree's files.
- **FR-009**: `/speckit-spex-ship` MUST obtain its branch and worktree from the same combined step, MUST NOT create a branch in the main checkout by hand, and MUST keep its state file in the worktree once the worktree exists.
- **FR-010**: `/speckit-spex-ship` MUST determine the feature branch name without reading the main checkout's current branch.
- **FR-011**: If worktree creation fails, the system MUST stop before writing spec content, leave the main checkout unchanged, remove a branch it just created that has no commits of its own, and report the cause and a remedy. It MUST NOT fall back to creating the branch or writing the spec in the main checkout. In a ship pipeline, the failure pauses the pipeline as a blocker at every oversight level.
- **FR-012**: When `spex-worktrees` is disabled, `/speckit-specify` and `/speckit-spex-ship` MUST behave as they do today.
- **FR-013**: After `/speckit-specify` completes interactively, the session MUST remain in the worktree so follow-up commands run there without a restart. The completion message MUST name the worktree path and show how to open a new session in it.
- **FR-014**: `/spex:init` MUST fail with a non-success status and an actionable message when `spex-worktrees` is enabled and the `git` extension cannot be enabled.
- **FR-015**: The fix MUST NOT modify files that come from upstream spec-kit (the core specify command, the `git` extension's scripts or templates). Any change in behavior comes from spex extensions and scripts.
- **FR-016**: The README, `spex/docs/help.md` and the `spex-worktrees` command documentation MUST describe the new order (branch and worktree first, spec second).
- **FR-017**: When `spex-worktrees` is enabled, the new feature branch MUST start from the local tip of the default branch, whatever the main checkout has checked out. If the main checkout is on a different branch or a detached HEAD, specify MUST say so in its output.

### Key Entities

- **Main checkout**: the repository's primary working directory, where other sessions may be working. Its branch and uncommitted changes are owned by whoever works there.
- **Feature worktree**: a separate working directory for one feature branch, holding the spec, the feature pointer, the flow or ship state and, later, the implementation.
- **Feature pointer** (`.specify/feature.json`): names the active spec directory for the checkout it lives in.
- **Flow / ship state** (`.specify/.spex-state`): tracks workflow progress and drives the status line for the checkout it lives in.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 10 consecutive runs each of `/speckit-spex-ship` and brainstorm-handoff `/speckit-specify` with `spex-worktrees` enabled, the main checkout's HEAD reflog gains no new entries during any run, and its branch is the same before and after each run. For direct `/speckit-specify` runs where the agent ignored hook priority, the reflog gains at most the one switch and the one restore, both before the spec is written.
- **SC-002**: In a concurrency test where a second session commits in the main checkout every 5 seconds during a specify or ship stage 0 run, 100% of those commits land on the default branch.
- **SC-003**: After each run, the main checkout's `git status` output is identical to its output before the run (no new, staged, committed or removed files attributable to the run).
- **SC-004**: Zero manual steps are needed to get from `/speckit-specify` to a ready worktree (the workaround described in the issue is no longer needed).
- **SC-005**: With `spex-worktrees` disabled, existing behavior is unchanged: the existing test suite passes without modification to tests that cover the non-worktree path.

## Assumptions

- The spec-kit `git` extension's branch script can compute the next branch name without creating the branch (it supports a dry-run mode), so naming rules can be reused without changing upstream files.
- Per Constitution III, `spex-worktrees` MUST NOT disable, edit or reorder the `git` extension's hooks. The `git` extension's `before_specify` branch hook keeps running unchanged. The combined step therefore has to work with that hook (for example, by preparing the worktree first so that the unchanged hook creates the branch inside the worktree rather than in the main checkout). The plan chooses the mechanism. FR-002 and FR-015 are fixed constraints.
- The agent session can move its working directory into an in-project worktree (`.claude/worktrees/`) during a run, as ship already does today.
- Harness-neutral worktree lifecycle and a `.worktrees/` default location are out of scope; they are tracked in [#30](https://github.com/rhuss/cc-spex/issues/30).
- The default branch is determined as spex does today: the remote's HEAD, then a local `main` or `master`.
