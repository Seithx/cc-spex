# Research: Create the Worktree Together with the Feature Branch

## R1: How are `before_specify` hooks ordered?

**Decision**: Treat `priority` as the intended order (lower runs first), but do not rely on it. The worktree step must give the right result in either order.

**Rationale**:
- spec-kit's `HookExecutor.get_hooks_for_event()` sorts enabled hooks by `priority` ascending with a stable sort (default `10`, from `DEFAULT_HOOK_PRIORITY`). That is the documented semantics.
- The agent-facing `/speckit-specify` skill (upstream, not modifiable per FR-015) tells the agent to read `.specify/extensions.yml` and dispatch hooks. It never mentions `priority`. In this project's own session on 2026-10-16, the agent ran `git.feature` (no priority, file position 1) before `spex.flow-state` (priority 1, file position 2), so it used file order.
- File order equals registration order. `register_hooks()` appends a manifest's entries to the end of each event list. The `git` extension is installed by `specify init` before spex reinstalls its own extensions, so git's `before_specify` entry always comes first in the file.

**Consequence**: A `spex-worktrees` `before_specify` hook at `priority: 1` will run before `git.feature` when the agent honors priority, and after it when the agent follows file order. Both orders must be handled:
- **Early** (worktree step runs first): create a detached worktree at the default branch's tip and move the session into it. `git.feature` then runs inside the worktree and its `git checkout -b` only affects the worktree. The main checkout never moves.
- **Late** (`git.feature` already ran in the main checkout): restore the main checkout's previous ref at once, then attach the branch to a new worktree. The main checkout is switched for the few agent hook turns between `git.feature` and the worktree step (not the whole specify run), and its reflog gains one switch and one restore. The step prints a notice so the cause stays visible.

**Layered fix (decided in plan review, 2026-10-16)**: Late mode is the last line of defense, not the main path.
1. The brainstorm handoff and ship run `prepare` themselves before invoking `/speckit-specify`, independent of hook order.
2. The spex methodology skill (`speckit.spex.using-superpowers`, spex-owned) tells agents to dispatch hooks by `priority`, matching `HookExecutor`.
3. Late mode repairs a plain `/speckit-specify` whose agent still used file order.
4. An upstream proposal asks spec-kit's templates to state the priority order.

**Alternatives considered**:
- Reorder `.specify/extensions.yml` from spex init: edits another extension's hook registration and violates Constitution III.
- Remove and re-add the `git` extension so its hooks register last: also tampers with another extension, and resets its config.
- Patch the generated `/speckit-specify` skill to sort by priority: violates FR-015. Worth proposing upstream (the template should state the order `HookExecutor` already uses), tracked as a follow-up rather than a dependency.
- Disable `git.feature` and let spex create the branch: violates Constitution III and duplicates naming logic.

## R2: How to reuse the branch naming rules without creating the branch in the main checkout?

**Decision**: Call the `git` extension's `create-new-feature.sh --dry-run --json --short-name <name> <description>` from the main checkout to get `BRANCH_NAME`, and use it for the worktree path. The branch itself is still created by the unchanged `git.feature` hook inside the worktree.

**Rationale**: The dry run computes the same name as the real run (sequential or timestamp numbering, `GIT_BRANCH_NAME` override). It scans `specs/` across all worktrees and all local and remote branches, and a detached worktree at the default branch tip has the same `specs/` content as the default branch. Nothing is created by the dry run.

**Mismatch handling**: If the agent later chooses a different short name for `git.feature`, the branch name and the worktree directory differ. `finalize` (after specify) detects this and runs `git worktree move` so the directory matches the branch again. Path conventions used by `ensure`, `list` and `finish` keep working.

**Alternatives considered**: A provisional path (`.claude/worktrees/.pending-<ts>`) renamed after the branch exists. Rejected because the worktree would carry a meaningless name for the whole specify run and a crashed session would leave an unnamed, detached worktree that `list` does not show.

## R3: Base commit for the new branch

**Decision**: `git worktree add --detach <path> <default-branch>`. The default branch is resolved as spex does today: `origin/HEAD`, then a local `main`, then `master`. If none resolves, stop with a hint (`git remote set-head origin --auto`).

**Rationale**: FR-017 (clarified 2026-10-16). `--detach` lets the worktree use the default branch's commit while the main checkout has the default branch checked out. `git.feature` then branches from that detached commit.

## R4: Where does the logic live?

**Decision**: A new script `spex/scripts/spex-worktree.sh` with subcommands `prepare`, `finalize` and `adopt`, synced into `spex/extensions/spex-worktrees/scripts/`. The `manage` command markdown delegates to it.

**Rationale**: Constitution VII (State as Scripts). The current `create` action is about 200 lines of inline bash the agent has to execute faithfully, including the `.spex-state` and `feature.json` handling. A script is deterministic and can be tested in a temporary repository (`tests/test_worktree.sh`), following the pattern of `tests/test_ship_state.sh`.

## R5: Flow and ship state written before the worktree exists

**Decision**: Two layers.
1. Move the spex `before_specify` flow-state hook from `priority: 1` to `priority: 2`, so with priority ordering it runs after the worktree step (`priority: 1`) and writes its state inside the worktree.
2. `prepare` also moves `.specify/.spex-state` from the main checkout into the worktree when that state belongs to the specify run in progress: flow state with `running == "specify"`, or ship state with `stage == "specify"`. Any other state file in the main checkout is left alone, because it may belong to another session.

**Rationale**: Layer 1 covers agents that honor priority, and layer 2 covers file order and the ship pipeline, whose state file is created before stage 0 runs.

## R6: Ship pipeline

**Decision**: Ship stage 0 runs `spex-worktree.sh prepare` itself before it invokes `/speckit-specify`, changes into the worktree and re-exports `SHIP_STATE_FILE` to the worktree's state file. The `before_specify` worktree hook then finds itself inside a worktree and does nothing (`READY`). After specify, ship reads the branch from inside the worktree. The old step-5 fallback ("invoke manage create when no worktree exists") is replaced by `finalize`.

**Rationale**: Ship controls its own sequence, so it does not depend on hook order at all (User Story 3, FR-009, FR-010). When `spex-worktrees` is enabled but the `git` extension is not, ship stops in its prerequisites instead of creating a branch by hand.

## R7: Legacy path (`adopt`)

**Decision**: When `finalize` runs outside a worktree (the `before_specify` worktree hook was skipped) and when `ensure` creates a worktree, `adopt` does what `create` does today. It differs in one way: it commits only the feature's spec directory to the feature branch, never `git add -u` or `brainstorm/`.

**Rationale**: Untracked and modified tracked files follow `git checkout` to the default branch, so the sweep was never needed for the switch. It is the mechanism that nearly moved another session's uncommitted work onto the feature branch (seen during this feature's own specify run). Keeping the rest of the legacy behavior unchanged honors the spec's scope ("`ensure` fallback keeps today's behavior").

## R8: Init

**Decision**: In `spex-init.sh install_extensions()`, when `spex-worktrees` is enabled in the registry and `specify extension enable git` fails, print an `ERROR:` line naming both fixes and exit `1`. When `spex-worktrees` is disabled, the check is skipped.

**Rationale**: FR-014. The init skill already reports a failing script exit to the user.

## R9: Status line

**Finding**: `spex-ship-statusline.sh` resolves the state file from `SHIP_STATE_FILE`, or else from the root of the session's own checkout. Once `prepare` has moved the state into the worktree, a session in the main checkout finds no state file and shows no feature progress (User Story 3, scenario 3). No status line change is needed. The behavior is covered by a test.
