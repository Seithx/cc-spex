# Upstream Proposal (draft, not filed): state the hook priority order in command templates

**Target**: github/spec-kit

**Status**: Draft. Not filed. Review before opening an issue or PR.

**Suggested title**: `fix(templates): tell agents to dispatch extension hooks by priority`

## Problem

Extension hooks registered in `.specify/extensions.yml` carry a `priority` field. spec-kit's own `HookExecutor.get_hooks_for_event()` sorts the enabled hooks of an event by `priority` ascending (stable sort, default `10`). That is the documented semantics.

The agent-facing command templates do not say so. Their hook sections tell the agent to read `.specify/extensions.yml`, look under `hooks.<event>`, filter out disabled hooks and skip hooks with a `condition`, and then run "each remaining hook". Nothing mentions `priority`. Agents therefore dispatch hooks in file order.

File order is registration order: `register_hooks()` appends a manifest's entries to the end of each event list. An extension installed early (for example the bundled `git` extension, installed by `specify init`) always comes first in the file, whatever priority a later extension declares.

## Observed behavior

In a project with the `git` extension and the spex extensions installed, `hooks.before_specify` holds, in file order:

1. `speckit.git.feature` (no priority, so `10`)
2. `speckit.spex.flow-state` (priority `1`)

During `/speckit-specify` on 2026-10-16 the agent ran `speckit.git.feature` first, which follows file order and contradicts the priority order `HookExecutor` would use. spex's next release adds a third entry, `speckit.spex-worktrees.manage` at priority `1`, which also lands after `speckit.git.feature` in the file. For the worktree extension this matters: it has to create an isolated worktree before the branch hook runs, otherwise the branch is checked out in the main checkout, where other agent sessions keep working and may commit onto the new feature branch.

spex now works around this (a repair step restores the main checkout when the order was wrong), but the root cause is that the templates and `HookExecutor` disagree.

## Affected templates

The hook sections of the command templates, both the `before_*` (pre-execution) and `after_*` (post-execution) parts:

- `templates/commands/specify.md`
- `templates/commands/clarify.md`
- `templates/commands/plan.md`
- `templates/commands/tasks.md`
- `templates/commands/implement.md`

The other command templates that use the same hook block (`analyze`, `checklist`, `constitution`, `taskstoissues`) should get the same sentence for consistency.

## Suggested change

Add one sentence to every hook section, right after the line that filters out disabled hooks:

> Sort the remaining hooks by their `priority` field, lowest first (a hook without `priority` counts as `10`; hooks with equal priority keep their file order), and execute them in that order.

This matches `HookExecutor.get_hooks_for_event()` exactly, so the CLI and the agent-dispatched path behave the same.

## Alternatives considered

- **Write `extensions.yml` sorted by priority** at registration time. This would also fix it without template changes, but it rewrites the order of other extensions' entries and makes diffs of the file noisier.
- **Leave it to each extension** to cope with both orders. This is what spex does today. It works, but every extension that depends on ordering has to reimplement the same repair.
