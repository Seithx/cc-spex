# Deep Review Findings

**Date:** 2026-10-18
**Branch:** 057-codex-bundled-init
**Rounds:** 3 (plus a final external check of the round-3 changes)
**Gate Outcome:** FAIL (1 Important finding remains; it needs a spec decision, not a code fix)
**Invocation:** quality-gate (ship pipeline, ask=smart)

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 16 | 15 | 1 |
| Minor | 26 | 19 | 7 |
| Notable | 5 | - | 5 |
| **Total** | **47** | **34** | **13** |

**Agents completed:** 5/6 (Goal Alignment skipped: no PR) + CodeRabbit + Codex (Copilot disabled in config)
**Agents failed:** none

Commits from the fix loop: `0a24afb`, `85b01a5` (rounds 1 and 2), `a34ffc9`, `3b10635` (round 3).

## Findings

### FINDING-1
- **Severity:** Important
- **Confidence:** 90
- **File:** spex/setup.yml (selected-extensions, enforce-git-extension)
- **Category:** correctness
- **Source:** correctness-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** `selected-extensions` printed its list with `jq -r`, and spec-kit stores step stdout verbatim, so the value ended in `\n`. `enforce-git-extension` matches `,$SELECTED,` against `*,spex-worktrees,*`, which fails when spex-worktrees is the last element (for example `spex-gates,spex-worktrees`). Reproduced with the real `specify`: setup completed with spex-worktrees enabled and no git extension.
**Why this matters:** It breaks the FR-003 git dependency and the guard against hand-made branches in the main checkout.
**How it was resolved:** `jq -j` in `selected-extensions`, `extension-mode` and `security-mode`. New real-specify test "selecting spex-worktrees last still enables the git extension" and glue tests asserting no trailing newline.

### FINDING-2
- **Severity:** Important
- **Confidence:** 85
- **File:** spex/setup.yml (selected-extensions)
- **Category:** production-readiness
- **Source:** production-agent (also reported by: correctness-agent, coderabbit)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** `resolve ... | jq` under `/bin/sh` without pipefail returned jq's status, so a resolver failure became an empty selection and a misleading "empty extension selection" error in a later step.
**How it was resolved:** The resolver output is captured and the step exits on failure. `normalize_extensions` names the unknown extensions. `spex-setup-report.sh` prints the step's stderr.

**External tool analysis (CodeRabbit):**
> Capture the output of spex-setup-profile.py resolve before passing it to jq and exit with the resolver's failure status so its validation error is preserved.

### FINDING-3
- **Severity:** Important
- **Confidence:** 80
- **File:** spex/setup.yml (install-ext-* before the selection steps)
- **Category:** production-readiness
- **Source:** production-agent (also reported by: correctness-agent)
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** All extensions were reinstalled (enabled) before the selection was resolved, and spex-detach was no longer disabled after install. Any failure in between left every optional extension, including spex-detach (stealth mode), enabled.
**How it was resolved:** The selection and security steps now run before migrate-commands, init-project and the installs. spex-detach is disabled right after install and enabled only by apply-extensions. A step-order unit test and a real-specify "invalid selection leaves the project unchanged" test cover it.

### FINDING-4
- **Severity:** Important
- **Confidence:** 82
- **File:** spex/setup.yml (selected-extensions, selected-security)
- **Category:** security
- **Source:** security-agent (also reported by: test-quality-agent)
- **Round found:** 1
- **Resolution:** fixed (rounds 1 and 3)

**What is wrong:** The interactive prompt reply was substituted textually into a double-quoted shell assignment, so backticks or `$(...)` in a reply would execute.
**How it was resolved:** Round 1 moved the reply into a quoted here-document. Round 3 removed the reply from shell source entirely (see FINDING-15 and FINDING-14).

### FINDING-5
- **Severity:** Important
- **Confidence:** 70
- **File:** spex/codex/skills/cc-spex-init/scripts/bootstrap.sh
- **Category:** security
- **Source:** security-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, disclosure); Ambiguous

**What is wrong:** With a committed declaration requesting `yolo`, `$cc-spex-init` applied it with no visible security level.
**How it was resolved:** The summary line names the stored level, a `NOTE:` line calls out any level other than `safe`, and the Codex skill tells the agent to show it. Gating the run on confirmation was not added, because FR-011 requires the declaration to be applied unchanged; that would be a spec change.

### FINDING-6
- **Severity:** Important
- **Confidence:** 80
- **File:** spex/codex/skills/cc-spex-init/scripts/bootstrap.sh
- **Category:** production-readiness
- **Source:** production-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** Only `specify` was checked; a missing `jq` failed deep inside the workflow with exit 127 after extensions were reinstalled.
**How it was resolved:** bootstrap checks `jq` and `python3`; README lists the prerequisites.

### FINDING-7
- **Severity:** Important
- **Confidence:** 85
- **File:** spex/extensions/spex/commands/speckit.spex.ship.md
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (rounds 1 to 3)

**What is wrong:** The ship prerequisite check still said `specify extension disable spex-worktrees` (FR-019) and suggested manual `enable` calls that a refresh reverts.
**How it was resolved:** Guidance now says to re-run setup with the current selection minus spex-worktrees (or plus gates and deep-review), with the command to read the current list. A static test asserts that no file under `spex/` says `extension disable spex-worktrees`.

### FINDING-8
- **Severity:** Important
- **Confidence:** 80
- **File:** spex/skills/init/SKILL.md (Step 2 block); also setup.yml, spex-init.sh, spex-apply-extensions.sh
- **Category:** architecture
- **Source:** architecture-agent
- **Round found:** 1
- **Resolution:** fixed (round 1, drift); Ambiguous

**What is wrong:** The "spex-worktrees needs git" rule exists in four places, and the init skill's copy had drifted (only `add git`, no FR-019 guidance).
**How it was resolved:** The skill block now runs `enable || add` and prints both fixes. Consolidating the four copies into one helper is left as a Minor refactor (FINDING-R2).

### FINDING-9
- **Severity:** Important
- **Confidence:** 75
- **File:** tests/test_cc_spex_codex_plugin.sh, tests/test_apply_extensions.sh, tests/test_init_worktrees_git.sh, tests/test_workflow_setup.sh
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** `TMP="$(cd "$(mktemp -d ...)" && pwd -P)"` turns into the current directory under bash 3.2 when mktemp fails, and the EXIT trap then runs `rm -rf` on it (the repository root under make).
**How it was resolved:** mktemp and cd are separate checked steps, followed by a guard that the directory exists and is not the current directory.

### FINDING-10
- **Severity:** Important
- **Confidence:** 75
- **File:** tests/test_workflow_setup.sh, tests/test_cc_spex_codex_plugin.sh (git stubs)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The network git stubs matched only `$1`, so `git -C dir clone` reached the real git unlogged.
**How it was resolved:** The stubs skip global options before matching and keep the original arguments for the real git; a self-test covers `git -C x -c k=v clone`.

### FINDING-11
- **Severity:** Important
- **Confidence:** 80
- **File:** tests/test_cc_spex_codex_plugin.sh
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** The FR-019 test echoed text from a hand-made state.json and never exercised setup.yml.
**How it was resolved:** Real-specify test with a `specify` wrapper that refuses the git extension: setup fails at enforce-git-extension, the report contains the FR-019 guidance and no manual disable, and no declaration is written. Static checks on setup.yml and the init skill.

### FINDING-12
- **Severity:** Important
- **Confidence:** 75
- **File:** tests/test_init_worktrees_git.sh, tests/test_setup_profile.py
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (round 1)

**What is wrong:** FR-022 (`DECLARATION_EXISTED`, resolve/apply/persist sequence) had no automated coverage.
**How it was resolved:** Stubbed tests for `DECLARATION_EXISTED=true|false` and the inputs passed to the workflow; unit test for create (harness claude, mapped security) and update (harness kept).

### FINDING-13
- **Severity:** Important
- **Confidence:** 70
- **File:** spex/setup.yml (selected-extensions)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Round found:** 1
- **Resolution:** fixed (rounds 1 and 3)

**What is wrong:** The shell glue between the workflow and `spex-setup-profile.py` was never executed by a test.
**How it was resolved:** `SetupWorkflowGlueTests` renders the setup.yml blocks as the engine does and runs them with `/bin/sh` for every mode, the interactive fallback, unknown names and security levels.

### FINDING-14
- **Severity:** Important
- **Confidence:** 90
- **File:** spex/setup.yml (interactive mode); installed spec-kit `workflows/steps/prompt/__init__.py`
- **Category:** correctness
- **Source:** re-review agent (round 2) (also reported by: coderabbit, round 3 external check)
- **Round found:** 2
- **Resolution:** resolved by spec evolution (user decision 2026-10-18): agents own the interactive choice; FR-003, US3 scenario 6 and the edge case updated

**What is wrong:** spec-kit's prompt step does not return the agent's reply (`stdout` is always empty; its docstring calls capture "a planned enhancement"). The setup workflow's interactive mode could therefore never apply a user's answer: it always resolved to `recommended` and `safe`. This predates the branch.
**Why this matters:** US3 scenario 6 and FR-003's interactive rules ("all" reply, naming spex-detach) cannot be met by `specify workflow run ... -i extensions=interactive`.
**What was done:** The prompt steps are removed (they launched a nested agent whose answer was discarded). Interactive mode applies the empty-reply fallback with a `NOTE:`. `/spex:init` without a declaration passes the defaults, and the init skill asks the user in Step 2 and persists the answer. The Codex skill asks the user itself and passes an explicit list. README documents the limitation.
**Human action needed:** Decide via spec evolution whether the interactive choice belongs to the agent layer (Claude skill Step 2, Codex skill), with workflow `interactive` meaning "recommended with a notice", or wait for spec-kit to capture prompt replies.

### FINDING-15
- **Severity:** Important
- **Confidence:** 85
- **File:** spex/setup.yml (reply here-documents)
- **Category:** security
- **Source:** coderabbit (round 2) (also reported by: codex round 3, re-review agent round 3)
- **Round found:** 2
- **Resolution:** fixed (round 3)

**What is wrong:** A reply containing the here-document terminator on its own line would end the here-document and run the following lines as shell. Latent, because replies are never captured today.
**How it was resolved:** No shell step embeds prompt output anymore; a unit test asserts there is no prompt step and no `prompt.output` in any shell block.

### FINDING-16
- **Severity:** Important
- **Confidence:** 75
- **File:** spex/scripts/spex-init.sh (install_extensions)
- **Category:** correctness
- **Source:** coderabbit (round 2) (also reported by: re-review agent round 2)
- **Round found:** 2
- **Resolution:** fixed (round 2)

**What is wrong:** A refresh without a declaration left a newly installed spex-detach enabled, and on the declaration path an error before apply left it enabled.
**How it was resolved:** After reinstalling, spex-detach is disabled unless it was enabled before (no declaration) or the declaration enables it in the apply step. Tests for both defaults.

### Minor findings fixed

| # | File | Finding | Source | Round |
|---|------|---------|--------|-------|
| M1 | spex/setup.yml | migrate-detach exit status ignored | production | 1 |
| M2 | spex/setup.yml | no-op switch branches with misleading ids | architecture | 1 |
| M3 | spex/scripts/spex-init.sh | dead `optional_extensions` loop and stale comment | architecture | 1 |
| M4 | spex/scripts/spex-apply-extensions.sh | "single place" comment was wrong | architecture | 1 |
| M5 | speckit.spex.extensions.md | manual toggles not marked as temporary | architecture | 1 |
| M6 | spex/setup.yml | report script depends on step ids silently | architecture | 1 |
| M7 | tests/test_workflow_setup.sh | cc-spex-init-* scan included the real TMPDIR | coderabbit, test-quality | 1 |
| M8 | tests/test_cc_spex_codex_plugin.sh | SPEX_SOURCE over ./spex and incomplete ./spex untested | test-quality | 1 |
| M9 | tests/test_workflow_setup.sh | US3 scenario 7 untested end to end | test-quality | 1 |
| M10 | README.md | harness rewritten to codex not documented | architecture (Notable) | 1 |
| M11 | spex/setup.yml | snapshot left behind when validation fails | re-review r2 | 2 |
| M12 | spex/setup.yml | predictable reply file path (symlink) | re-review r2 | 2, obsolete in 3 |
| M13 | speckit.spex.ship.md | `--extensions recommended` replaces the selection | re-review r2 | 2 |
| M14 | tests/test_setup_profile.py | step-order test ignored migrate-commands and init-project | re-review r2 | 2 |
| M15 | speckit.spex.extensions.md | placeholder path not copyable | coderabbit r2 | 2 |
| M16 | spex/setup.yml | security NOTE dead because `default('safe')` replaces "" | re-review r3 | 3, obsolete |
| M17 | spex/scripts/spex-init.sh | NOTE misleading on the Claude first-run path | re-review r3 | 3 |
| M18 | speckit.spex.extensions.md | spex-detach manual disable sticks (FR-023) | re-review r3 | 3 |
| M19 | speckit.spex.ship.md, tests | worktrees fix text dropped other extensions; test name and comment overstated | re-review r3 | 3 |

## Remaining Findings

- **FINDING-14** (Important): resolved by spec evolution, see above.
- **R1** (Minor, Ambiguous) FR-020: `.agents/plugins/marketplace.json` has no `version` field and `make release` does not set one. Codex's marketplace format carries no per-plugin version (the installed version comes from the manifest). Spec evolution candidate (architecture, correctness, test-quality).
- **R2** (Minor) The git rule is still written in four places (setup.yml, spex-init.sh, spex-apply-extensions.sh, init SKILL). Candidate for one helper (architecture).
- **R3** (Minor) The optional extension list is spelled out in five files (architecture).
- **R4** (Minor) `{{ inputs.extensions }}` is substituted into shell before validation in direct `specify workflow run` invocations; bootstrap validates its own arguments (security).
- **R5** (Minor) The Claude status line points at the source tree; a deleted temporary source breaks it (test-quality, FR-002 scope question).
- **R6** (Minor) `spex-init.sh` calls `spex-setup-report.sh` without a run id, so a run that fails before creating state reports the previous run (production).
- **R7** (Minor) If enabling spex-detach fails after the post-install disable, the next refresh's FR-023 migration drops it from the declaration (re-review r3).

False positives dismissed: Codex round 3 P2 (stored security downgraded on refresh: the fallback text is only inside the `MODE = interactive` branch); Codex round 4 P1 (defaults on `/spex:init` "lose" interactive answers: those answers were never captured, and the skill applies the user's choice in Step 2).

## Notable Observations

### NOTABLE-1
- **File:** spex/codex/skills/cc-spex-init/scripts/bootstrap.sh:99-101
- **Category:** security
- **Source:** security-agent
- **Description:** The `./spex` source branch runs any repository's `spex/setup.yml` when it looks like cc-spex, ahead of the trusted bundled tree (FR-009 order).
- **Rationale:** Worth an identity check or opt-in when contributing to untrusted repositories.

### NOTABLE-2
- **File:** spex/setup.yml, spex/scripts/spex-init.sh, spex/skills/init/SKILL.md
- **Category:** architecture
- **Source:** architecture-agent
- **Description:** The snapshot, migrate, resolve, apply, persist sequence is orchestrated three times.
- **Rationale:** A single wrapper would keep the init paths from drifting.

### NOTABLE-3
- **File:** spex/scripts/spex-init.sh (legacy fast path)
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** The legacy path (no setup.yml next to the script) silences install_extensions failures other than the git refusal.
- **Rationale:** Low impact today; the path runs only without setup.yml.

### NOTABLE-4
- **File:** spex/setup.yml (apply-extensions before enforce-git-extension and persist-request)
- **Category:** correctness
- **Source:** correctness-agent
- **Description:** A git refusal after apply leaves the new selection enabled but not persisted.
- **Rationale:** FR-005 covers successful runs only; security validation now runs before apply.

### NOTABLE-5
- **File:** spex/setup.yml
- **Category:** production-readiness
- **Source:** production-agent
- **Description:** Some scripts are executed directly and depend on executable bits in the plugin cache.
- **Rationale:** Calling them via `python3`/`sh` would remove that dependency.

## Post-Fix Spec Coverage

The fix loop removed code (the two prompt steps, the dead install loop), so all requirements were re-checked.

| Requirement | Implementation | Status |
|-------------|---------------|--------|
| FR-001, FR-002 | setup.yml install-ext-* `--dev` | ✓ |
| FR-003 | spex-setup-profile.py, spex-apply-extensions.sh, setup.yml selected-extensions/apply-extensions/enforce-git-extension | ✓ (interactive reply: FINDING-14) |
| FR-004, FR-005 | setup.yml extension-mode, persist-request; spex-init.sh declaration branch | ✓ |
| FR-006 | spex-apply-extensions.sh OPTIONAL_EXTENSIONS | ✓ |
| FR-007 to FR-011 | spex/.codex-plugin/plugin.json, bootstrap.sh | ✓ |
| FR-012, FR-013, FR-017, FR-021 | manifests, marketplace, .gitignore | ✓ |
| FR-014 | README, help.md copies, constitution | ✓ |
| FR-015 | tests/* | ✓ |
| FR-016 | spex-init.sh prev_disabled branch | ✓ |
| FR-018 | spex-apply-extensions.sh, spex-setup-report.sh | ✓ |
| FR-019 | setup.yml, spex-init.sh, both SKILL.md files, ship.md | ✓ |
| FR-020 | Makefile (manifest); marketplace entry has no version | ✓ (R1) |
| FR-022 | init SKILL Step 2, DECLARATION_EXISTED | ✓ |
| FR-023 | migrate-detach in setup.yml and spex-init.sh | ✓ |

All spec requirements verified after the fix loop; none dropped.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| baseline | make sync-scripts-check test-apply-extensions test-codex-plugin test-workflow-setup test-worktree test-generated-trees test-setup-profile test-ship-state | 0 | 0 | passed |
| 1 | same | 0 | 0 | passed |
| 2 | same | 0 | 0 | passed |
| 3 | same (plus `make validate`) | 0 | 0 | passed |

Test suite passed in all fix rounds.
