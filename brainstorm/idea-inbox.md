# Idea Inbox

Ideas captured from code reviews for future brainstorming.

### flow-state-unconditional-update

- **Source**: deep-review
- **Date**: 2026-07-02
- **Reference**: 033-plugin-root-refs
- **Summary**: The `&&` chain in flow state update commands prevents `implemented` from running when `gate review-code` fails, contradicting the "MANDATORY: regardless of gate outcome" instruction.

> The `FLOW_STATE gate review-code && FLOW_STATE implemented` pattern in deep-review.run.md and review-code.md gates the `implemented` call on the success of `gate review-code`. If the gate fails, the status line never shows `R checkmark`. Restructuring to `{ gate review-code || true; implemented; }` would ensure the terminal state update always fires. This affects 2 files and should be a standalone fix.

### github-issue-brainstorm-flow

- **Source**: conversation
- **Date**: 2026-07-08
- **Reference**: v6.0.0 planning
- **Summary**: Add a full GitHub-based flow where a GitHub issue triggers brainstorm document creation through interactive dialogues, connecting issue tracking to the SDD pipeline entry point.

> Instead of starting brainstorming locally, allow the workflow to begin from a GitHub issue. The issue would serve as the seed, and an interactive dialogue (possibly via issue comments or a dedicated command) would refine the idea into a structured brainstorm document. This bridges the gap between project management (issues) and the spec-driven development pipeline (brainstorm -> specify -> plan -> implement).

### deep-review-trigger-hardening

- **Source**: PR #42-#44 review cycle (Codex plugin restructuring)
- **Date**: 2026-07-26
- **Reference**: 047-codex-plugin-support
- **Summary**: Deep review did not trigger because the initial code review scored 94.3% (below the 95% threshold). After fixing the 4 findings, the review was not re-run, so deep review agents and CodeRabbit never fired.

> The deep review trigger depends on the initial code review score meeting a threshold (95%). When findings are fixed but the review is not re-run, the deep review pipeline never activates. This creates a gap: PRs that improve during review never get the deep review pass. Options: (1) automatically re-trigger review after findings are resolved, (2) lower the threshold, (3) allow manual deep review invocation regardless of score, (4) track "findings resolved" as a separate trigger condition. The fix-then-forget pattern is likely common and should be handled gracefully.

_Review-related ideas (goal-alignment-skip-behavior, spec-completeness, platform-abstraction) moved to [cc-review/brainstorm/idea-inbox.md](https://github.com/rhuss/cc-review/blob/main/brainstorm/idea-inbox.md) on 2026-08-03._

### preserve-path-containment-guard

- **Source**: deep-review
- **Date**: 2026-10-11
- **Reference**: 054-walkthrough-runbook
- **Summary**: `spex-finish-preserve-specs.sh` and `spex-runbook-status.py` `do_locate` build copy/mkdir targets from a caller-supplied feature dir without a `..`/containment guard.

> Git ref rules forbid `..` in branch names so the documented callers are safe today, but a script whose whole job is writing into another checkout would benefit from defense-in-depth: require the path to start with `specs/`, reject `..` components, or realpath-assert the destination stays under the main checkout.

### shared-frontmatter-parser

- **Source**: deep-review
- **Date**: 2026-10-11
- **Reference**: 054-walkthrough-runbook
- **Summary**: The runbook frontmatter format is parsed by two independent hand-rolled parsers (`spex-runbook-check.py` and `spex-runbook-status.py`) with slightly different contracts.

> Both read a format written only by `serialize_frontmatter`. If that format ever gains multi-line or quoted values the parsers must change in lockstep or silently disagree. The single-file script model (whole-file `make sync-scripts`) makes a shared module non-free, so decide deliberately: either a shared `spex-runbook-common.py` in the sync inventory, or a cross-reference comment pinning both parsers to the canonical writer.

### runbook-version-unused

- **Source**: deep-review
- **Date**: 2026-10-11
- **Reference**: 054-walkthrough-runbook
- **Summary**: `runbook_version` is written into every runbook's frontmatter but never read — no required-key check, no migration or version dispatch.

> A persisted format-version marker with no reader and no migration path is speculative generality. Either drop it until a second format version exists, or mark it explicitly as an intentional forward-compat field with no current reader.

### fixture-start-record-atomicity

- **Source**: deep-review
- **Date**: 2026-10-11
- **Reference**: 054-walkthrough-runbook
- **Summary**: In `spex-runbook-fixture.sh` `cmd_start`, the real resource (process/container/compose) is created before `append_fixture` records it; an append failure under `set -e` leaves a live but untracked fixture.

> Narrow (requires a corrupt state file or mktemp failure) but the leak is unrecoverable by the tool, since `stop --quick` cannot see an unrecorded fixture. Consider tearing down the just-created resource on record failure, or ordering creation and recording transactionally.

### statusline-python-per-render

- **Source**: deep-review
- **Date**: 2026-10-11
- **Reference**: 054-walkthrough-runbook
- **Summary**: The flow-mode status line spawns a Python interpreter (`spex-runbook-status.sh show … --no-git`) on every render while a spec dir is active.

> `--no-git` already avoids the expensive fingerprint path, so this is Python startup latency, not git latency. For a per-render hot path consider parsing the runbook status inline with jq/awk, or caching the walkthrough segment keyed by the runbook's mtime so Python runs only when the file changed.

### preserve-detach-error-handling

- **Source**: deep-review
- **Date**: 2026-10-11
- **Reference**: 054-walkthrough-runbook
- **Summary**: `spex-finish-preserve-specs.sh` collapses any failure of the detach `is-enabled` probe (bad path, `cd` failure) into `enabled=false`, indistinguishable from detach genuinely being off, and `rsync` has no fallback.

> Because the script prevents data loss before `finish` removes a worktree, misclassifying an environment/path error as "detach off" silently skips the copy. Consider validating `$WORKTREE` up front (exit non-zero on a bad path), distinguishing a clean "disabled" signal from an error, and optionally falling back to `cp -a` when `rsync` is absent.
