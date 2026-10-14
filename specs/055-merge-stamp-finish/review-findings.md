# Deep Review Findings

**Date:** 2026-10-13
**Branch:** 055-merge-stamp-finish
**Rounds:** 3 (fix rounds) + final re-review
**Gate Outcome:** PASS
**Invocation:** quality-gate (ship pipeline, review-code stage)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 9 | 8 | 0 (1 dismissed: contradicts spec) |
| Minor | 34 | 24 | 10 |
| Notable | 8 | - | 8 |
| **Total** | **51** | **32** | **18** |

**Agents completed:** 5/6 (Goal Alignment skipped: no PR for the branch) + CodeRabbit (initial pass)
**External tools:** CodeRabbit completed on the initial review (2 findings); both re-review runs failed with `Connection failed: WebSocket closed`. Codex failed (usage limit reached). Copilot disabled in config.
**cc-review:** not detected; built-in review used.

## Findings

### FINDING-1 (Important, fixed round 1)
- **File:** spex/extensions/spex/commands/speckit.spex.finish.md (Phase 3)
- **Category:** correctness
- **Source:** coderabbit (major), also reported by correctness agent (FINDING-3)

**What is wrong:** Phase 0 checks the record once. The `before_finish` hooks and the walkthrough run afterwards and may edit code, and Phase 3 then ran `git add -A`, commit, and squash without checking again.

**Why this matters:** Code edited after verification in the same finish run was landed unverified (US1, SC-001).

**How it was resolved:** I added Phase 3 Step 0. It re-runs `check --feature`, and when the record is stale (or the check errors) it applies the Phase 0 verify rows again before anything is staged. A stop row stops finish with its exact FR-009a message.

### FINDING-2 (Important, dismissed)
- **File:** spex/scripts/spex-verify-record.sh:77-80
- **Category:** external
- **Source:** coderabbit (major)

**What is wrong:** CodeRabbit asked for the spec.md content to be part of the record fingerprint, so that spec changes invalidate the pass.

**Why it was not applied:** It contradicts the spec. FR-006, FR-009c, and the Assumptions state that changes inside spec directories do not invalidate a pass (the same rule as walkthrough currency). Changing it is a spec decision, not a code fix.

### FINDING-3 (Important, fixed round 1, hardened rounds 2-3)
- **File:** spex/extensions/spex-gates/commands/speckit.spex-gates.verify.md (step 7); spex/scripts/spex-verify-record.sh
- **Category:** correctness
- **Source:** correctness agent

**What is wrong:** The pass was fingerprinted when `record` ran, not when the gates ran. Verify tells the agent to fix tests and hygiene issues mid-run, so the record could cover code that the tests never ran against (FR-007).

**How it was resolved:** `spex-verify-record.sh begin` stores the start fingerprint in the git dir (`spex-verify-start`). `record` compares against it (or against an explicit `--expect`), refuses with exit 1 on a mismatch, and removes the start file. Verify runs `begin` at the start of The Process and restarts once on a mismatch (running `begin` again). It then reports ERROR with `git status --short` and points to gitignoring test artifacts. Any other record failure maps to `warning: pass not recorded`.

### FINDING-4 (Important, fixed round 1, corrected rounds 2-3)
- **File:** spex/scripts/spex-runbook-status.py (code_tree)
- **Category:** production-readiness
- **Source:** production agent

**What is wrong:** The fingerprint rebuilt a temp index from empty on every call, re-hashing the whole tree. It now runs on every `git commit` through the reminder hook, which has a 5s timeout. Measured: 150k files took 14s and always timed out, so the reminder fired even right after a pass.

**How it was resolved:** The temp index is seeded from the real index only when seeding cannot change the tree SHA (`_plain_index`). Seeding is skipped when the index has assume-unchanged, skip-worktree or sparse entries, unmerged entries, gitlinks, or tracked-ignored files, and the listings run from the top level. In all other cases the build starts from an empty index, as before. Tests compare the result against an empty-index build for each of these cases.

### FINDING-5 (Important, fixed round 1)
- **File:** specs/055-merge-stamp-finish/quickstart.md
- **Category:** test-quality
- **Source:** test-quality agent

**What is wrong:** Most finish Phase 0 rows had no automated or documented check: unattended stop, re-run after a code change, combined skip flags, no spex-gates, the no-spec and incomplete stop shapes, `--embedded`, FR-011a, and the default-branch edge case.

**How it was resolved:** I added manual steps 5-14 to quickstart section 6, one per scenario, each with its exact expected output.

### FINDING-6 (Important, fixed round 2): seeded index changed fingerprint semantics
- **File:** spex/scripts/spex-runbook-status.py
- **Source:** re-review round 1

Seeding hid edits to assume-unchanged and skip-worktree files, and kept tracked-ignored files. The `_plain_index` gate fixes this (see FINDING-4), and the equality tests guard it. A mutation check confirmed the tests fail without the gate.

### FINDING-7 (Important, fixed round 2): start fingerprint lost between shell calls
- **File:** speckit.spex-gates.verify.md
- **Source:** re-review round 1

`VERIFY_START_FP` was a shell variable. Verify spans many separate Bash calls, so the variable was empty by step 7 and the check was silently skipped. It is now persisted by `begin` in the git dir (see FINDING-3).

### FINDING-8 (Important, fixed round 2): unbounded verify restart loop
- **File:** speckit.spex-gates.verify.md
- **Source:** re-review round 1

A test suite that writes untracked artifacts changes the fingerprint on every run, so the restart could loop forever. The restart is now limited to one, followed by ERROR with the changed paths.

### FINDING-9 (Important, fixed round 3): SIGTERM grace period ineffective
- **File:** spex/scripts/hooks/pretool-gate.py
- **Source:** re-review round 2

`proc.wait` waited only for the `sh` group leader, which dies immediately on SIGTERM. SIGKILL then arrived while Python was still cleaning up, so temp index copies leaked. The hook now polls `killpg(pid, 0)` for up to 1.5s until the whole group is gone, then sends SIGKILL. The fingerprint helper turns SIGTERM into SystemExit so its `finally` block runs. A test with a slow `git` shim checks that TMPDIR ends up empty, and a mutation check confirmed it fails without the drain loop.

### Minor findings fixed (24)
- Ship: the stage count in the start announcement (`/9` to `/8`), the stage order in the Overview, and finish removed from the "review stages" list (architecture 1-3).
- Both help files: "Ship Stage 8" wording, and the over-long finish line re-wrapped (architecture 4, 6).
- README: `after_implement` no longer claims to run verification (architecture 5).
- finish and verify use the `-f` lookup plus `sh "$RECORD"`, consistent with sibling lookups (architecture 7).
- Submit removes `.specify/.spex-state` when watch mode falls back because `gh` is missing (correctness 2).
- Relative `--feature` paths are resolved to repo-relative (correctness 4).
- `skipped-no-gates` is exempt from the commit-reminder confirmation (correctness 5).
- Hooks run the record check last, after the cheap skips (production 3). The hook kills the whole process group on timeout (production 2).
- Verify checks the `record` exit status (production 5, write side).
- Tests: legacy session marker ignored, pretool `/speckit-spex-finish` and empty-output assertions, committed/untracked/deleted staleness, preconditions on the commit and the fingerprint, git config isolation (test-quality 3-7).
- Round 1 re-review: temp leak on SIGKILL, finish Step 0 double verify, missing seeded-index tests.
- Round 2 re-review: listings from a subdirectory, uninitialized submodule, the restart now re-runs `begin`, the `VERIFY_RECORDED` flag.
- Found while testing: `fingerprint` from a subdirectory hashed nothing (`ls-tree -r` is cwd-relative). Fixed with `--full-tree`.

## Remaining Findings (Minor, 10)

1. spex/scripts/spex-ship-statusline.sh:302: the `finish)` case arm is unreachable (finish is not a ship stage). Fix: remove the arm and run `make sync-scripts`.
2. spex/scripts/spex-verify-record.sh: the `head` field is written but never read. Fix: document it as diagnostic or drop it.
3. spex/scripts/hooks/pretool-gate.py:270: `session_id` is unused in `check_verification_gate`. Fix: drop the parameter and its call site.
4. spex/scripts/hooks/pretool-gate.py (check): `_is_verified` runs the fingerprint, which writes blobs for untracked files into `.git/objects` (unreferenced, pruned by gc). Fix: document it, or hash untracked files without `-w`.
5. spex/scripts/adapters/codex/pretool-gate.py:149-153 and opencode: when the adapters' outer 5s timeout expires on verify-gate.sh, the result is `allow`, while the Claude hook fires the reminder. Fix: give verify-gate.sh its own bound, or align the adapter fallback.
6. spex/scripts/hooks/pretool-gate.py: the hook shows the same reminder text for missing/stale and for error/timeout. Fix: show "verification status unavailable" for exit 2, 127, or a timeout.
7. tests/: no static guard for the FR-010/FR-012 removals (stage 8, stamp tokens, manifest entry, README migration row). Fix: add rg-based assertions to the suite.
8. spex/scripts/hooks/pretool-gate.py:351-354: a redundant `except` clause, and `import time` inside the except path (cosmetic).
9. tests/test_verify_record.sh ("flag outside cwd subdir"): one test covers two fixes (`ls-files` cwd and `ls-tree --full-tree`).
10. Runbook fingerprints recorded by older code from a subdirectory show as stale once after upgrade (expected).

## Notable Observations

### NOTABLE-1
- **File:** spex/scripts/spex-verify-record.sh:117-145
- **Category:** security
- **Description:** Anyone with shell access, including the agent, can run `record` directly and forge a pass. Finish's already-verified row then skips verification.
- **Rationale:** The record only works on the honor system. Ways to make bypasses visible: print the record details when finish uses it, flag direct `record` calls in pretool-gate, or store a summary of gate evidence in the record.

### NOTABLE-2
- **File:** spex/scripts/hooks/pretool-gate.py:302-311; verify-gate.sh:45-47
- **Category:** security
- **Description:** If the plugin copy is missing, the hooks fall back to running a project-provided `.specify/extensions/spex-gates/scripts/spex-verify-record.sh`.
- **Rationale:** This widens the set of hooks that run project code on their own. The plugin copy normally shadows it.

### NOTABLE-3
- **File:** spex/scripts/hooks/pretool-gate.py:302-311
- **Category:** architecture
- **Description:** The hooks prefer the plugin's copy of the record script, while verify and finish use the project-installed copies.
- **Rationale:** If the fingerprint algorithm ever changes, the writer and reader could disagree. Fix: version the algorithm in the record.

### NOTABLE-4
- **File:** README.md:129-165
- **Category:** architecture
- **Description:** The workflow flowchart has no finish or submit node, so the close-out step is not shown.

### NOTABLE-5
- **File:** spex/scripts/spex-runbook-status.py:80-90
- **Category:** correctness
- **Description:** The fingerprint ignores file mode, so a `chmod +x` does not invalidate a pass. Adding the mode would also change walkthrough currency.

### NOTABLE-6
- **File:** spex/scripts/hooks/pretool-gate.py
- **Category:** production-readiness
- **Description:** The hook checks the record in the hook's cwd, not in the checkout the commit targets (`git -C`, `cd x &&`).

### NOTABLE-7
- **File:** spex/extensions/spex/commands/speckit.spex.submit.md
- **Category:** production-readiness
- **Description:** With `--embedded`, the state file stays behind when submit fails after a passing verify. This should be documented as intentional for retries, or cleaned up.

### NOTABLE-8
- **File:** tests/test_verify_record.sh
- **Category:** test-quality
- **Description:** No test pins FR-009d (the record survives `/speckit-spex-clear` and state cleanup with spex-init's exclude patterns).

## Post-Fix Spec Coverage

Code was removed only in the form of replaced blocks (lookup lines, ordering). All 21 functional requirements (FR-001 to FR-016, including 009a-d and 011a) were rechecked after round 3, and all are still implemented.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| 1 | make test-walkthrough | 0 | 0 | passed |
| 2 | make test-walkthrough | 0 | 0 | passed |
| 3 | make test-walkthrough | 0 | 0 | passed (twice, no flakes) |

`make sync-scripts-check` and `make validate` passed after every round. Validate showed pre-existing warnings about unquoted `${CLAUDE_PLUGIN_ROOT}` in hooks.json. `tests/test_marketplace_install.sh` was not run, by instruction.
