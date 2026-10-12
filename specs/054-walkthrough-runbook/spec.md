# Feature Specification: Walkthrough as a Runbook

**Feature Branch**: `054-walkthrough-runbook`

**Created**: 2026-10-11

**Status**: Draft

**Input**: User description: "Rework the walkthrough command from scratch: give the user an easy to understand runbook for testing the feature when it is testable (say so and do nothing when it is not), teach the feature end to end with every step documented, offer to start backends and fixtures that can be automated (from podman containers up to clusters), instruct the user and offer clipboard copies for everything else, let ship draft a runbook that can be run later in co-pilot mode, and never store runbooks in git when detach mode is enabled." Design source: `brainstorm/48-walkthrough-runbook.md`.

## Clarifications

### Session 2026-10-11 (brainstorm)

- Q: Who runs the feature steps during a session? → A: The user chooses per step: run it themselves (command copied to clipboard) or let the agent run it.
- Q: What form does the runbook take? → A: A readable `RUNBOOK.md` in the spec directory that can be followed later without the agent, plus a guided session that records results into the same file.
- Q: How is the session structured? → A: The whole runbook is written before anything runs.
- Q: Does every feature get the full procedure? → A: No. Light mode for no fixtures or quick local ones (podman containers, local processes); full mode only when a slow local or a remote/paid fixture is needed.
- Q: Are the existing walkthrough helper scripts kept? → A: No. Green-field rewrite; only the ideas of a persistent gitignored scratch folder and a placeholder check survive.
- Q: How are runbooks handled in detach mode? → A: They are never committed; they stay on disk and survive worktree removal.
- Q: Can a runbook be run after ship finished? → A: Yes. Ship always drafts one; the user runs it later, also from main after the merge.

### Session 2026-10-11

- Q: When a step needs a browser, should the agent drive it when a browser automation tool is available, or always hand it to the user? → A: The agent drives the browser when a browser automation tool is connected (screenshots as evidence); otherwise the step is the user's.
- Q: Can the user let the agent run the remaining steps in one go instead of confirming each? → A: Yes, via a "run the rest" choice that stops at the first mismatch, the first user-only step, or any fixture needing consent; every step stays fully transparent: the exact command before it runs, the real output, and each expected observation compared against the actual output.
- Q: When a runbook is run on the default branch after the merge, should the walkthrough commit the updated runbook? → A: Ask once at the end of the session whether to commit it, with a prepared message; never push.
- Q: How can the user get a runbook when the agent judged the feature not testable? → A: The one-line verdict names the override (a force option, or describing what to try); forcing drafts a runbook anyway, using the user's hint if given.
- Q: Should a runbook follow one end-to-end journey or one section per user story? → A: One end-to-end journey in the order a real user would go; each step tagged with the user story it exercises; a coverage line at the end lists covered and uncovered stories with reasons.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Try a small feature with a light-mode runbook (Priority: P1)

A developer finished a feature that is testable with no fixtures or only quick local ones. They start the walkthrough. The agent explains in one block what the feature does, writes a runbook where every step says why it matters, what to run, and what good output looks like, then asks one question that approves both the runbook and any quick fixtures. The developer walks the steps one at a time, choosing per step whether to run the command themselves (it is already on the clipboard) or let the agent run it and show the real output. At the end, fixtures stop, results are in the runbook, and the developer understands and trusts the feature.

**Why this priority**: This is the common case and the core value: a first-time viewer understands the feature and judges it from real output.

**Independent Test**: Run the walkthrough on a small feature with a command-line effect and, optionally, one container fixture. Confirm the runbook format, the single approval question, per-step choice, real output, recorded results, and fixture cleanup.

**Acceptance Scenarios**:

1. **Given** a testable feature needing no slow or remote fixtures, **When** the walkthrough starts, **Then** it writes a runbook with a feature overview and steps, each having a purpose, prerequisites, an exact command, expected observations, and hints for unexpected results, and asks a single question that approves the runbook and the quick fixtures together.
2. **Given** a step is reached, **When** the user chooses to run it themselves, **Then** the exact command is placed on the clipboard (or shown if no clipboard is available) and the user is asked whether the output matched the expected observations.
3. **Given** a step is reached, **When** the user lets the agent run it, **Then** the agent shows the real output (in full when short; otherwise saved to a log with the exact relevant lines quoted) and marks each expected observation as seen or not seen.
4. **Given** a step does not match, **When** the user is asked how to proceed, **Then** they can choose investigate, fix and retry (only when a cause was found), record and continue, or stop here.
5. **Given** all steps are judged, **When** the session ends, **Then** quick fixtures are stopped, the runbook carries a results summary and a status, and the result is recorded where finish reads it.

---

### User Story 2 - Nothing to try costs one line (Priority: P1)

A developer finished a feature with no user-observable effect (for example an internal refactor covered by unit tests). The walkthrough says so in one line with the reason and does nothing else.

**Why this priority**: Without an honest exit, the walkthrough produces noise that erodes trust in it.

**Independent Test**: Run the walkthrough on a feature whose only change is internal. Confirm a single message with a reason and no file created.

**Acceptance Scenarios**:

1. **Given** a feature with nothing a person can trigger and observe, **When** the walkthrough starts, **Then** it prints one line stating that nothing can be tried by hand, why, and how to override the verdict, and creates no runbook or scratch files.
2. **Given** a feature where only some parts are testable, **When** the runbook is written, **Then** it covers the testable parts and lists each untestable part under "Not covered here" with a one-line reason.
3. **Given** the user disagrees with a "not testable" verdict, **When** they use the force option or describe what they want to try, **Then** a runbook is drafted anyway and covers what they described.

---

### User Story 3 - Run a runbook drafted by ship, later (Priority: P2)

The autonomous ship pipeline ends with a drafted runbook. Hours later, possibly after the feature was merged, the developer runs it in co-pilot mode from the main branch.

**Why this priority**: Ship runs unattended, so the human check has to happen afterwards. Without a drafted runbook, the human starts from nothing.

**Independent Test**: Run ship (or the draft-only form) on a testable feature, merge it, then start the walkthrough for that feature from main. Confirm the drafted runbook is found, any code changes since the draft are reported, and the session runs.

**Acceptance Scenarios**:

1. **Given** ship reaches the end of its pipeline, **When** the feature is testable, **Then** ship drafts a runbook without starting fixtures or running steps, and its closing message names the runbook and the command to run it later.
2. **Given** a drafted runbook exists for a merged feature, **When** the user starts the walkthrough naming that feature from main, **Then** the runbook is loaded and run.
3. **Given** the user is on main and names no feature, **When** the walkthrough starts, **Then** it lists runbooks that are drafted, in progress, or failed and lets the user pick one.
4. **Given** code changed since the runbook was drafted, **When** the user starts it, **Then** the changed files are shown and the user can refresh the affected steps or run as is.

---

### User Story 4 - Full mode for heavy environments (Priority: P2)

A feature needs a slow local fixture (an image build, a local cluster) or a remote or paid one (a cloud cluster). The walkthrough reviews the runbook with the user before anything runs, asks for consent per fixture tier with time and cost information, reuses environments that already exist, records every fixture with its teardown, and lets the user resume after interruptions.

**Why this priority**: Heavy environments are where an unasked action costs the most (time, money, accounts), and where an interrupted session is most likely.

**Independent Test**: Run the walkthrough on a feature that needs a cluster. Confirm the review pause, the tiered consent, reuse of an existing cluster, the fixture list, the keep-or-teardown choice, and resume after stopping midway.

**Acceptance Scenarios**:

1. **Given** a feature needs a slow or remote fixture, **When** the runbook is drafted, **Then** the user reviews it and can change or drop steps before anything runs.
2. **Given** a required environment already exists, **When** setup starts, **Then** the agent offers to reuse it instead of creating a new one.
3. **Given** a remote or paid fixture is needed, **When** setup reaches it, **Then** the agent states what will be created, the rough duration, and possible cost, and creates nothing without an explicit yes (or hands the commands to the user).
4. **Given** the session ends, **When** slow or remote fixtures are running, **Then** the user chooses keep or tear down (keep by default), and the teardown command is recorded in the runbook either way.
5. **Given** a session stopped midway, **When** the user starts the walkthrough again, **Then** it offers to continue from the first unfinished step.
6. **Given** light mode discovers that setup is slow, **When** this happens, **Then** the agent stops, explains, and switches to full mode.

---

### User Story 5 - Finish and other commands use the result (Priority: P2)

When the developer runs finish, it knows whether a walkthrough passed for the current code and only asks when there is something to decide. Verify and the status line show the same state.

**Why this priority**: Today finish can never tell that a walkthrough ran and asks every time, which trains users to skip it.

**Independent Test**: Complete a walkthrough, then run finish and confirm it does not ask. Change code, run finish, confirm it reports the change and offers a rerun.

**Acceptance Scenarios**:

1. **Given** a passed runbook and no code changes since the tested commit (changes under the spec directory excluded), **When** finish runs, **Then** it reports the pass and asks no walkthrough question.
2. **Given** a passed runbook and code changed since, **When** finish runs, **Then** it lists the changed files and offers rerun or continue.
3. **Given** an in-progress, failed, or drafted runbook, **When** finish runs, **Then** it offers resume, continue-anyway-or-stop, or run-now-or-later respectively, and never blocks.
4. **Given** no runbook, **When** finish runs, **Then** it starts the walkthrough (testability check first), and the existing skip flag still bypasses it.

---

### User Story 6 - Detach mode never stores runbooks in git (Priority: P2)

In a project using detach (stealth) mode, spec artifacts must never reach the project repository. Runbooks and scratch files stay on disk only, and survive the cleanup of a worktree.

**Why this priority**: Leaking spec-driven artifacts into an upstream repository breaks the purpose of detach mode; losing a drafted runbook breaks User Story 3.

**Independent Test**: Enable detach mode, draft and run a runbook in a worktree, finish and remove the worktree. Confirm nothing was committed and the runbook is present in the main checkout.

**Acceptance Scenarios**:

1. **Given** detach mode is enabled, **When** a runbook or scratch file is written, **Then** git ignores it; if the configured exclusions do not cover the runbook's normal location, the runbook is stored inside the self-ignoring scratch folder instead and the user is told, and no shared ignore or exclusion file is modified.
2. **Given** detach mode is enabled and the feature was built in a worktree, **When** finish removes the worktree, **Then** the feature's spec directory, including the runbook, is copied back to the main checkout first.
3. **Given** the detach extension directory exists but the extension is disabled, **When** finish or the walkthrough checks detach mode, **Then** detach mode is treated as off.

---

### Edge Cases

- No clipboard tool is available: the command is shown for manual copying and the session continues.
- The container runtime is not running: the quick fixture is reported as unavailable with the command to start it; the affected steps can be skipped or delegated.
- The user declines a fixture: steps that need it are marked skipped with the reason.
- Agent-run output is very long: the full output goes to a log file; the relevant lines are quoted verbatim with the log path.
- Output contains credentials: they are replaced with `[redacted]` before anything is written to the runbook.
- A step needs a value produced by an earlier step: the runbook captures it with a command instead of a placeholder.
- Real output differs from the draft's expectation because the draft was wrong (not the feature): the step is corrected in the file and the correction recorded.
- The pipeline is unattended: the runbook is drafted only; nothing is started.
- The archive path for detach mode is not configured: the copy back to the main checkout still preserves the runbook.
- Several features have drafted runbooks on main: the picker lists all of them with status.

## Requirements *(mandatory)*

### Functional Requirements

#### Testability

- **FR-001**: Before writing anything, the walkthrough MUST decide whether the feature has anything a person can trigger and observe (command, API call, page, skill, generated file), using the spec, plan, quickstart, and the changes on the branch.
- **FR-002**: When nothing is testable, the walkthrough MUST print one line with the reason and how to override it, MUST NOT create a runbook or scratch files, and MUST record "not testable" in workflow state when such state exists. The same override hint MUST appear when finish or ship report the verdict.
- **FR-002a**: The walkthrough MUST support a force option that skips the "not testable" verdict and drafts a runbook anyway; when the user describes what they want to try, the draft MUST cover it.
- **FR-003**: When only part of the feature is testable, the runbook MUST list each untestable part under "Not covered here" with a one-line reason.

#### Runbook content

- **FR-004**: The runbook MUST start with a plain-language overview of what the feature does and the order in which the steps exercise it.
- **FR-004a**: Steps MUST form one end-to-end journey in the order a real user would go, not one section per user story. Each step MUST be tagged with the user story it exercises, and the runbook MUST end with a coverage line listing the user stories covered and those not covered, each uncovered story with a one-line reason.
- **FR-005**: Every step MUST contain: why the step matters, what it needs (earlier steps or fixtures), the exact command, what the user should see, and what to do if they see something else.
- **FR-006**: Expected observations MUST be written before the step is executed.
- **FR-007**: Commands MUST be complete and copyable without edits; values known only at runtime MUST be obtained by a command, never by a placeholder.
- **FR-008**: Prerequisites discovered while drafting MUST become their own steps.
- **FR-009**: The runbook MUST contain a test environment section listing every fixture, how it was set up, who started it, and how to tear it down.
- **FR-010**: The runbook MUST carry a status block at the top stating status (drafted, in progress, passed, failed), steps completed out of total, the counts of passed, failed, and skipped steps, the commit it was drafted at, the commit it was tested at, the mode, and the date.
- **FR-010a**: Overall status MUST be derived from step results: failed if any step was recorded as failed; passed if no step failed and every step was passed or skipped; in progress while any step has no result; drafted before the first step was presented.

#### Modes

- **FR-011**: The walkthrough MUST use light mode when the feature needs no fixtures or only quick local ones, and full mode when it needs any slow local or remote/paid fixture.
- **FR-012**: In light mode, a single confirmation MUST approve the runbook and the quick fixtures together.
- **FR-013**: In full mode, the user MUST be able to review and change the runbook before anything runs.
- **FR-014**: If light mode discovers a slow or remote fixture during setup, the walkthrough MUST stop, explain, and switch to full mode; it MUST NOT switch from full to light during a run.

#### Fixtures

- **FR-015**: The walkthrough MUST identify needed fixtures from the spec, plan, and quickstart, and MUST look for setup paths in the project (compose files, build targets, scripts, setup documentation, available command-line tools, and available skills or plugins that provision infrastructure).
- **FR-016**: Before creating a fixture, the walkthrough MUST check whether a usable one already exists and offer to reuse it.
- **FR-017**: No fixture MUST be started without confirmation. For quick local fixtures (local processes and containers), one confirmation suffices; slow local fixtures MUST be preceded by a time estimate and a confirmation.
- **FR-018**: Remote or paid fixtures MUST NOT be created without an explicit confirmation after stating what will be created, its rough duration, and that it may cost money; the user MAY instead receive the commands to run themselves.
- **FR-019**: Quick local fixtures MUST be stopped when the session ends; slow and remote fixtures MUST be kept by default, with the user asked, and their teardown command recorded in the runbook.
- **FR-020**: Session scratch files (logs, test data, process records, fixture list) MUST persist in a scratch folder inside the feature's spec directory that ignores itself (it carries its own ignore rule for all its contents), so it is never committed in any project without modifying shared ignore files.

#### Session

- **FR-021**: For each step, the user MUST be offered: run it themselves with the command copied to the clipboard, let the agent run it, or skip it. When the agent cannot execute the step (a browser step with no browser automation tool connected, another graphical interface, an interactive terminal program, credentials only the user holds, or an action outside the agent's sandbox), the agent option MUST be omitted and the reason stated.
- **FR-021a**: When a browser automation tool is connected, the agent MUST offer to drive browser steps itself and MUST present screenshots of the resulting pages as the step's output.
- **FR-022**: When no clipboard tool is available, the command MUST be shown for manual copying without failing the session.
- **FR-023**: When the agent runs a step, it MUST show real output: in full when about 40 lines or fewer, otherwise saved to a log with the lines relevant to each expected observation quoted verbatim and the log path given. A description MUST NOT replace output.
- **FR-023a**: Before the agent runs any step, it MUST show the exact command it is about to run.
- **FR-024**: Each expected observation MUST be shown side by side with the actual output line (or screenshot) it was compared against and marked seen or not seen; a not-seen observation MUST state what was found instead. The step result MUST record the verdict, who ran it, and the quoted output or the user's observation.
- **FR-024a**: At each step the user MUST also be offered "run the rest": the agent then runs consecutive agent-runnable steps without asking per step, applying FR-023, FR-023a, and FR-024 to each, and MUST stop at the first mismatch, the first step only the user can run, and any fixture that needs consent.
- **FR-025**: On a mismatch, the user MUST be offered investigate, fix and retry (only when a cause was identified), record and continue, or stop; there is no fixed retry limit.
- **FR-026**: When the draft's expectation was wrong rather than the feature, the step MUST be corrected in the runbook and the correction recorded.
- **FR-027**: Results MUST be written into the runbook after each step, so an interrupted session can be resumed from the first unfinished step. On resume, quick local fixtures that were stopped MUST be offered for restart; kept slow or remote fixtures MUST be checked for availability before reuse.
- **FR-028**: Before quoting output into the runbook, anything resembling a credential (tokens, passwords, keys) MUST be replaced with `[redacted]`.

#### Command forms and later runs

- **FR-029**: The walkthrough command MUST support: no argument (current branch's feature; run or resume an existing runbook, otherwise draft then run), a draft-only option (write the runbook without fixtures or steps), a force option (FR-002a), and a feature identifier (run that feature's runbook from any branch, including main). A feature identifier MUST be accepted as either the number prefix (e.g. `054`) or the full spec directory name.
- **FR-030**: On main without an argument, the walkthrough MUST list runbooks that are drafted, in progress, or failed and let the user pick.
- **FR-030a**: When a session ran on the default branch and modified a committed runbook, the walkthrough MUST show the change at the end of the session and ask once whether to commit it, offering a prepared commit message; it MUST NOT push. On a feature branch and in detach mode no commit is offered.
- **FR-031**: When code changed since a runbook was drafted (changes inside spec directories excluded), the walkthrough MUST show the changed files and offer to refresh the affected steps or run as is.
- **FR-032**: Ship MUST draft the runbook at the end of its pipeline at every ask level, start no fixtures, run no steps, and mention the runbook path and the run command in its closing message (or the one-line reason when not testable).

#### Integration

- **FR-033**: Finish MUST read the runbook status and behave as follows, never blocking: passed and current, continue without asking; passed with code changed since, list the changes and offer rerun or continue; in progress, offer resume; failed, show the failed step and offer continue or stop; drafted, offer run now or later; "not testable" recorded for the current code, continue without asking; status block unreadable, report it and offer rerun or continue; missing, start the walkthrough. The existing skip flag MUST keep working.
- **FR-033a**: In an unattended run (no human available, e.g. ship with ask level never, or finish with its auto option), finish MUST NOT prompt: when the runbook is missing it MUST draft one (as in FR-032); in every other state it MUST continue and state the runbook status in its output.
- **FR-034**: A runbook is current when no files outside spec directories and brainstorm documents changed between the tested commit and the current commit.
- **FR-035**: Verify's walkthrough reminder and the status line indicator MUST be derived from the runbook status.
- **FR-036**: Determining runbook status, managing local fixtures, copying to the clipboard, and checking runbooks for placeholders and unredacted credentials MUST be implemented as deterministic scripts (Constitution VII), with placeholder checks limited to command blocks.

#### Detach mode

- **FR-037**: Detach mode MUST be detected from the extension's enabled state, not from the presence of its directory; this applies to the walkthrough and to finish's archive step.
- **FR-038**: With detach mode enabled, runbooks and scratch files MUST NOT be committed. The walkthrough MUST confirm git ignores the runbook at its normal location; if it would not, the runbook MUST be stored inside the self-ignoring scratch folder instead and the user told why. The walkthrough MUST NOT modify the tracked ignore file or the exclusion entries owned by the detach extension (Constitution III).
- **FR-039**: With detach mode enabled, finish MUST copy the feature's spec directory back to the main checkout before removing a worktree.

#### Removal and documentation

- **FR-040**: The previous walkthrough helpers (coverage mapping, workspace creation, whole-file placeholder lint), their tests, the previous report format, and the reads of the unwritten completion state keys MUST be removed; historical reports in existing spec directories MUST be left untouched.
- **FR-041**: README, both help documents, the next-step hints in code review and deep review, the extension manifest, and the changelog MUST describe the new behavior.

### Key Entities

- **Runbook**: The readable test plan and result record of one feature: overview, test environment, steps forming one journey, not-covered list, story coverage line, status block.
- **Step**: One action with the user story it exercises, purpose, needs, command, expected observations, unexpected-result hints, and result.
- **Status block**: Machine-readable header of a runbook: status, progress, drafted and tested commits, mode, date.
- **Fixture**: Something the feature needs to be tried (local process, container, image build, cluster, cloud resource), with tier (quick local, slow local, remote/paid), owner (agent or user), and teardown command.
- **Fixture list**: The session's record of fixtures, used for cleanup and for the runbook's test environment section.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In every produced runbook, 100% of steps state their purpose, command, and expected observations before execution.
- **SC-002**: In agent-run steps, 0 cases where a description replaces real output.
- **SC-003**: For a non-testable feature, the walkthrough ends with one message and creates 0 files.
- **SC-004**: For a typical light-mode feature, the user answers at most 1 setup question before the first step is presented.
- **SC-005**: After reading the overview and steps of a runbook for a feature they have not seen before, the reviewer can state what the feature does (judged by the user on a real run).
- **SC-006**: With detach mode enabled, 0 runbook or scratch files are committed across drafting, running, and finishing.
- **SC-007**: A runbook drafted by ship is available to run from main after the merge in 100% of cases, in both normal and detach mode.
- **SC-008**: After a passed walkthrough with no code changes since, finish asks 0 walkthrough questions.
- **SC-009**: 0 remote or paid resources are created without an explicit user confirmation.
- **SC-010**: 0 placeholders appear in runbook command blocks, so every copied command runs without editing.

## Assumptions

- The command keeps its name `/speckit-spex-walkthrough`; only the output file changes, from `WALKTHROUGH.md` to `RUNBOOK.md`.
- Whether something is testable is the agent's judgment, explained to the user in plain words; it is not a keyword rule.
- macOS is the primary platform; on Linux the usual clipboard tools are supported.
- Podman is the container runtime for quick local fixtures.
- The 40-line threshold for showing output in full is a guideline for readability, not a hard limit.
- Runbooks are committed with other spec artifacts in normal mode, so they survive merges through git; detach mode relies on the copy back to the main checkout.
- The finish archive step in detach mode copies runbooks along with the other spec artifacts.
- Full mode is validated by the user on a project that needs a heavy fixture; the implementation's real-run check covers light mode.
- The walkthrough remains advisory: it never blocks finish or ship.
