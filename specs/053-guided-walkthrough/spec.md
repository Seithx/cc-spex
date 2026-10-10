# Feature Specification: Guided Walkthrough (pair testing)

**Feature Branch**: `053-guided-walkthrough`

**Created**: 2026-10-09

**Status**: Draft

**Input**: Brainstorm [47-guided-walkthrough-pair-testing.md](../../brainstorm/47-guided-walkthrough-pair-testing.md). Replace the `speckit-spex-smoke-test` "Guided Demo" with a user-story-anchored, agent-driven interactive walkthrough (pair testing) that runs against a persistent real environment and gives the reviewer runnable, inspectable evidence.

## Clarifications

### Session 2026-10-10

- Q: When a scenario ends in a FAIL verdict, should that block the ship/finish pipeline, or is the walkthrough advisory? → A: Advisory / report-only. FAIL is recorded; the pipeline does not hard-block; the reviewer decides.
- Q: Where do the exact per-step commands come from for an arbitrary feature? → A: The agent infers them from the acceptance scenarios plus repo conventions, previewing every command before running it.

## User Scenarios & Testing *(mandatory)*

The user of this feature is the **reviewer**: the developer validating a completed feature before it ships. The system under walkthrough is whatever the feature's spec describes. The skill is the navigator; the reviewer is the driver-of-record.

### User Story 1 - Walk user-story scenarios against a real environment and judge from real artifacts (Priority: P1)

The reviewer runs the walkthrough on a feature. The skill builds scenarios from the spec's user stories (priority order), sets up a real environment, and for each step shows the exact command before running it, runs it, opens the resulting artifact (file contents, log output, directory tree, screenshot), states expected vs actual, and pauses for the reviewer's judgment before moving on.

**Why this priority**: This is the core value: putting a human in contact with real, running behavior to catch the gaps automated tests and code review structurally cannot.

**Independent Test**: Run the skill on a feature whose spec has user stories with acceptance scenarios. Confirm the agent previews each command, executes it, surfaces the actual artifact inline, and waits for a verdict at each checkpoint rather than narrating a summary.

**Acceptance Scenarios**:

1. **Given** a spec with P1/P2 user stories and Given/When/Then acceptance scenarios, **When** the walkthrough runs, **Then** scenarios are presented in priority order, each backed by the story's acceptance scenario (Given→setup, When→action, Then→inspection).
2. **Given** a walkthrough step, **When** the agent is about to run a command, **Then** the exact command is shown before execution, and after execution the real artifact it produced is opened inline (not narrated).
3. **Given** a step has produced output, **When** the agent presents expected vs actual, **Then** it pauses and waits for the reviewer's judgment before the next step.

---

### User Story 2 - Reproduce and inspect every result after the fact (Priority: P1)

Every command the walkthrough presents is complete and runnable against a workspace that still exists after the run. The reviewer can copy any command from the live session or the report, run it verbatim, and see the same artifact. Nothing the walkthrough created is auto-deleted.

**Why this priority**: The original failure was a verdict the reviewer could only trust, never verify (placeholder commands, no persisted artifacts). Reproducibility is what makes the verdict trustworthy.

**Independent Test**: After a walkthrough run, copy a command from the report and run it in a fresh shell with no edits. Confirm it executes against the persisted workspace and reproduces the reported artifact.

**Acceptance Scenarios**:

1. **Given** any command presented during the walkthrough or in the report, **When** the reviewer inspects it, **Then** it contains concrete paths and arguments with no placeholders (no `<scratch>`, `<path>`, `<store>`, etc.).
2. **Given** a completed walkthrough, **When** the reviewer looks for the environment, **Then** the run workspace still exists at a path the report prints, and the report states the single command to remove it.
3. **Given** the report, **When** the reviewer reads a scenario's result, **Then** it links or points to the concrete artifacts (file paths, captured log excerpts) that produced the verdict.

---

### User Story 3 - Agent drives by default, reviewer intervenes for manual steps (Priority: P2)

The agent runs steps itself by default. When it cannot run a step, it hands the reviewer the exact command and waits for their observation. The reviewer can also take over any step at will.

**Why this priority**: Keeps the session efficient (agent drives) while preserving honesty (no faking steps the agent cannot actually run) and reviewer control.

**Independent Test**: Construct a scenario with a step requiring infrastructure the agent cannot provision. Confirm the agent delegates the exact command to the reviewer and waits, rather than simulating the result. Separately, confirm the reviewer can claim any step and the agent waits.

**Acceptance Scenarios**:

1. **Given** a step the agent cannot execute (missing infrastructure it cannot provision, interactive TUI, external credentials, GUI/visual judgment, or an action outside the sandbox), **When** that step is reached, **Then** the agent presents the exact command for the reviewer to run and waits for their observation.
2. **Given** any step, **When** the reviewer chooses to drive it, **Then** the agent yields, shows the command, and waits for the reviewer's result.
3. **Given** a delegated or reviewer-driven step, **When** the result is recorded, **Then** the report notes who ran it (agent or reviewer).

---

### User Story 4 - Honest coverage without silently skipping anything (Priority: P2)

Scenarios come from user stories; functional requirements are mapped onto the steps that exercise them. Requirements not covered by any scenario are reported as orphans rather than dropped. The walkthrough skips only when there is genuinely nothing to walk.

**Why this priority**: The old keyword-based auto-skip hid exactly the areas where human-only gaps live. Honest coverage is what makes the walkthrough trustworthy as a gate.

**Independent Test**: Run on a spec whose requirements include ones the old heuristic would call "internal-only." Confirm they are reachable through their user story's scenario and that any uncovered requirement is listed as an orphan. Run on a spec with no user stories and no acceptance scenarios; confirm an honest skip.

**Acceptance Scenarios**:

1. **Given** a spec with user stories, **When** scenarios are synthesized, **Then** each functional requirement exercised by a scenario is tagged with the covering scenario, and requirements exercised by no scenario are listed as orphans.
2. **Given** a spec with no user stories and no acceptance scenarios, **When** the walkthrough runs, **Then** it skips with a clear message and still writes a report recording the skip and reason.
3. **Given** a requirement the previous keyword heuristic would have classified "internal-only," **When** it is part of a user story's behavior, **Then** it is walked through that story rather than auto-skipped.

### Edge Cases

- **App will not start**: the agent reports the failure, shows captured output, and offers to let the reviewer start it manually before continuing.
- **Stale process from a prior run** on a known port: the agent asks before killing it (it may be unrelated work).
- **Browser automation unavailable**: the agent degrades to exact manual steps for the reviewer.
- **A step fails**: the agent offers to investigate, propose a fix, and retry (bounded retries), recording both the failure and the outcome.
- **Unattended pipeline (no human present)**: the walkthrough is skipped with a "manual walkthrough required" notice, scenarios recorded as deferred/manual, report written, pipeline continues (FR-022).
- **Partial environment** (some but not all infrastructure available): the agent presents real proxy evidence with an explicit disclaimer about what it does and does not prove.

## Requirements *(mandatory)*

### Functional Requirements

**Scenario synthesis**

- **FR-001**: The skill MUST synthesize walkthrough scenarios from the spec's user stories, presented in the stories' priority order (P1 first).
- **FR-002**: Each scenario MUST use the story's acceptance scenarios (Given/When/Then) as its backbone: Given maps to setup, When to the driven actions, Then to the inspection and judgment.
- **FR-003**: The skill MUST map each functional requirement onto the scenario step(s) that exercise it, and record this mapping as coverage.
- **FR-004**: The skill MUST report any functional requirement not exercised by any scenario as an orphan (not covered by a walkthrough scenario), rather than omitting it silently.
- **FR-005**: The skill MUST NOT classify requirements as "observable" vs "internal-only" or auto-skip them on that basis. The prior keyword heuristic is removed.
- **FR-006**: The skill MUST skip the walkthrough only when the spec has no user stories and no acceptance scenarios, and in that case MUST still write a report recording the skip and its reason.

**Environment and persistence**

- **FR-007**: Each run MUST create a persistent, uniquely named run workspace at a path under the feature directory, and MUST print that path to the reviewer.
- **FR-008**: The run workspace MUST NOT be committed to git, but MUST remain on disk after the run completes.
- **FR-009**: The skill MUST NOT auto-delete the run workspace or its artifacts. Application processes the skill started MUST be stopped on exit; created files MUST persist.
- **FR-010**: Every command the skill presents (live or in the report) MUST be complete and runnable with no placeholder tokens; all paths and arguments MUST be the concrete values actually used.

**Walkthrough loop**

- **FR-011**: For every step, the skill MUST show the exact command it is about to run before running it.
- **FR-011a**: The skill MUST infer each step's concrete command from the scenario's acceptance criteria (Given/When/Then) and the repository's conventions (entry points, README, Makefile, and the `/run` skill when available). No author-declared command list is required; the command preview (FR-011) is the safeguard against mis-inference.
- **FR-012**: By default the skill MUST run the step itself, then open the resulting artifact inline (file contents, log excerpt, directory tree, or screenshot), then state expected vs actual.
- **FR-013**: After presenting a step's evidence the skill MUST pause and wait for the reviewer before proceeding.
- **FR-014**: The skill MUST delegate a step to the reviewer, presenting the exact command and waiting for their observation, when it cannot run the step itself. Delegation triggers MUST include at least: infrastructure the skill cannot provision, interactive terminal programs, required external credentials, GUI/visual judgment, and actions outside the execution sandbox.
- **FR-015**: The skill MUST allow the reviewer to take over any step; when they do, the skill yields, shows the command, and waits for the reviewer's result.
- **FR-016**: The skill MUST never simulate, fake, or hand-reproduce system behavior. If a step cannot be genuinely executed by either party, it MUST be recorded as skipped or manual with honest reasoning. When a step runs without full infrastructure, the skill MUST present the real proxy evidence with an explicit partial-evidence disclaimer stating what it does and does not prove.
- **FR-017**: The skill MUST record a verdict per scenario (pass / fail / skip / manual), with optional per-step notes, and MUST record who ran each step (agent or reviewer).
- **FR-018**: On a failed step the skill MUST offer to investigate, propose a fix, and retry, bounded to at most 2 retries per scenario, recording both the initial failure and the retry outcome.

**Report**

- **FR-019**: The skill MUST write a report artifact to the feature directory, scenario-anchored and ordered by user-story priority. Each scenario MUST include its steps, the real runnable commands, artifact pointers, expected vs actual, the execution mode of each step (agent-ran or reviewer-ran/delegated), any partial-evidence disclaimer, and the verdict with notes.
- **FR-020**: The report MUST record the run workspace path and the command to remove it, plus coverage: user-story coverage, functional-requirement coverage tags, and orphan requirements.
- **FR-021**: The skill MUST output the full results report on every exit path, including early exits and pipeline mode.
- **FR-021a**: The walkthrough is advisory. A FAIL verdict MUST be recorded in the report but MUST NOT hard-block `finish` or `ship`; the reviewer decides whether to fix (via the FR-018 retry loop) or proceed knowingly. The walkthrough is not a blocking gate.

**Integration and honesty**

- **FR-022**: The walkthrough is always interactive and MUST require a human regardless of the pipeline's ask level. When reached inside an unattended pipeline (no human available, e.g. ship with `--ask never`), the skill MUST skip the interactive walkthrough with a clear "manual walkthrough required" notice, record every scenario as deferred/manual in the report, write the report, and let the pipeline continue (it MUST NOT block indefinitely or fail the stage).
- **FR-023**: The skill MUST be renamed from `speckit-spex-smoke-test` to `speckit-spex-walkthrough`, with the report artifact renamed from `SMOKE-TEST.md` to `WALKTHROUGH.md`. All references in the ship pipeline, finish command, help, README, and the extension manifest MUST be updated, and the rename MUST be documented in the changelog.

**Determinism and state (Constitution Principle VII)**

- **FR-024**: Deterministic concerns MUST be implemented in external shell/Python scripts that the skill markdown delegates to, not as prompt-only agent behavior, mirroring the existing `spex-closeout-gate.sh` pattern. At minimum this covers: run-workspace creation and path resolution (FR-007), detection of the skip gate (FR-006), and computation of functional-requirement coverage and orphan requirements from the spec (FR-003/FR-004).
- **FR-025**: The no-placeholder guarantee (FR-010) MUST be enforced by a script that scans the presented and reported commands for placeholder tokens and fails if any are found, rather than relying solely on agent discipline. This makes SC-003 and SC-005 mechanically verifiable.

### Key Entities

- **Scenario**: a user-story-derived journey with an ordered list of steps, a priority, FR coverage tags, and a verdict.
- **Step**: a single action with its exact command, who runs it, the artifact it produces, expected vs actual, and an optional note.
- **Run workspace**: the persistent, gitignored directory holding everything a run created, referenced by concrete path in every command and in the report.
- **Walkthrough report** (`WALKTHROUGH.md`): the scenario-anchored record with commands, artifacts, verdicts, and coverage.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of commands presented during a walkthrough and in its report run verbatim, with no edits, against the persisted workspace.
- **SC-002**: A reviewer can independently reproduce every PASS verdict by running the reported command(s) and observing the same artifact.
- **SC-003**: Zero placeholder tokens appear in any presented or reported command.
- **SC-004**: Every run produces a report, including skipped and early-exit runs.
- **SC-005**: Every functional requirement in the spec appears in the report either as covered (with its scenario) or as an orphan; none is silently absent.
- **SC-006**: After a run, the run workspace and its artifacts still exist on disk and are reachable from the path printed in the report.
- **SC-007**: No walkthrough step is recorded as passed without real execution evidence (no simulated results).

## Assumptions

- **Run workspace location**: `specs/<feature>/.walkthrough/<timestamp>/`, covered by a gitignore rule so it persists on disk without being committed. (Open question 1 resolved as a reasonable default.)
- **Verdict granularity**: the scenario is the unit of verdict; per-step notes are optional. (Open question 2.)
- **Delegation triggers** are the enumerated categories in FR-014; the agent prefers to run a step itself and delegates only when one of those applies. (Open question 3.)
- **Retention**: all run workspaces are kept until the reviewer removes them manually; the report always prints the cleanup command. Automatic pruning is out of scope for v1. (Open question 4.)
- The walkthrough runs in a developer environment where the feature's own tooling (its CLI, build, or app) is available or provisionable; the skill reuses the existing `/run` skill for app startup and browser automation when available.
- Honesty gates from the current skill (no simulated tests, always interactive, mandatory report) are preserved.
- **Unattended pipeline (open question 5)**: when no human is present, the walkthrough skips with a "manual walkthrough required" notice, records scenarios as deferred/manual, writes the report, and lets the pipeline continue rather than blocking or failing (FR-022).
- **Determinism**: per Constitution Principle VII, the deterministic parts (workspace lifecycle, skip-gate detection, coverage/orphan computation, no-placeholder check) are backed by external scripts mirroring `spex-closeout-gate.sh`, with the skill markdown delegating to them (FR-024/FR-025).
