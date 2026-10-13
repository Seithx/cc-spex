# Brainstorm: Merge stamp into finish

**Date:** 2026-10-13
**Status:** active

## Problem Framing

Closing out a feature involves three commands whose names overlap and whose docs contradict each other:

- `/speckit-spex-gates-verify` (spex-gates) does the real work: closeout gate, tests, code hygiene, spec compliance (100% required), drift check, success criteria. Ship runs it as its final stage, which the hooks and status line call "stamp" (stage 8).
- `/speckit-spex-gates-stamp` is a one-line wrapper that invokes verify. It adds nothing.
- `/speckit-spex-finish` (core spex) runs the walkthrough gate, squashes, and merges, opens a PR, or keeps the branch. It never runs verify.

The docs claim otherwise. `speckit.spex-gates.stamp.md` says "for verification + merge/PR/cleanup in one step, use finish", and `speckit.spex.using-superpowers.md` describes finish as "verify + merge/PR/keep" and "verifies + merges/creates PR in one step". A user following the docs lands code that was never verified. The pre-commit reminder hook (`pretool-gate.py`, `verify-gate.sh`) points to stamp, adding a third name to the mix.

Ship still needs a check-only step that does not merge, so a standalone verify has to remain.

## Approaches Considered

### A: Finish verifies, drop stamp (chosen)
- finish runs verify as its first phase, then the walkthrough gate, squash, and merge/PR/keep.
- stamp is removed. verify stays as the check-only command ship uses.
- Pros: one command to close out a feature, and the docs become true. Check-only stays available for ship and for ad-hoc use. Small change surface.
- Cons: the core extension (finish) calls into spex-gates (verify), so finish must handle spex-gates being disabled.

### B: One command with a check-only flag
- finish absorbs verify. `finish --check` runs only verification and ship calls that. stamp and verify are both removed.
- Pros: fewest command names.
- Cons: moves gate logic out of spex-gates into core, breaking the extension split. A "finish" that does not finish is a confusing name for ship's last stage.

### C: Docs only
- Keep all three commands and fix the false claims in the docs.
- Pros: cheapest.
- Cons: the redundant name and the confusion stay.

## Decision

Approach A. Finish becomes the single close-out command, with verify as a blocking first phase. Stamp is removed outright, with no deprecation alias.

## Key Requirements

- **Verify as Phase 0 of finish.** finish runs verify before the walkthrough gate, squash, or any merge.
- **Blocking on failure.** When verify fails, finish stops before squash or merge. It lists the failing gates and the two ways out: fix and rerun, or reconcile with `/speckit-spex-evolve`.
- **Escape hatch.** `--no-verify` skips the verify phase explicitly. The existing `--no-walkthrough` keeps working.
- **No duplicate runs.** finish skips verify when it already passed for the current code (for example, right after ship's final stage).
- **spex-gates disabled.** finish skips verification with a one-line note instead of failing.
- **Unattended runs.** finish keeps its existing ship guard behavior (no prompts at ask levels smart/never). A verify failure still blocks.
- **Remove stamp everywhere.** Delete `speckit.spex-gates.stamp.md`, its `extension.yml` entry, and the codex adapter mapping (`suppress-prompts-stamp`).
- **Rename ship's final stage** from "stamp" to "verify" in `pretool-gate.py`, `stage-gate.sh`, and the status line (`stamp|finish` case).
- **Commit reminder.** The pre-commit reminder points to `/speckit-spex-gates-verify` or `/speckit-spex-finish`.
- **Docs.** Update README (commands table, migration table row `/spex:stamp` now maps to finish), `spex/docs/help.md`, `using-superpowers.md`, the context-hook skill list, the opencode preamble, and CLAUDE.md's extension description.

Out of scope: changing what verify checks, and the mechanical compliance gate (#46).

## Open Questions

- "Already verified": track it per session (the existing `spex-verified` marker) or per commit (survives `/clear` and new sessions, invalidated by any new code)?
- Should finish work on the default branch with no feature branch (verify only, nothing to squash or merge), or keep requiring a feature branch?
- Should the 054 walkthrough spec drift found on 2026-10-13 (T030 wording, the "Step n of M" rule) be reconciled with evolve before or as part of this change?
