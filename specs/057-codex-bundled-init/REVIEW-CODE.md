# Code Review: Codex Init from a Bundled Spex Source

**Spec:** specs/057-codex-bundled-init/spec.md
**Contract:** specs/057-codex-bundled-init/contracts/cli.md
**Date:** 2026-10-18
**Reviewer:** Claude (speckit.spex-gates.review-code)

## Compliance Summary

**Overall Score: 94%** (97% before the deep review; it found that interactive mode cannot apply a reply, FINDING-14)

- Functional Requirements: 21/23 compliant, 2 deviations (FR-003 interactive reply, FR-020), both spec evolution candidates
- Edge Cases: 10/10 (100%)
- Success Criteria (script-verifiable parts of SC-001 to SC-006): 6/6
- Spec-declared constants: none (no `## Constants` section)

## Detailed Review

### Functional Requirements

| Req | Implementation | Status |
|-----|---------------|--------|
| FR-001 install from any location | `spex/setup.yml` install-ext-* steps always pass `--dev` | Compliant |
| FR-002 survives deleting a temporary source | `--dev` copies into the project; `tests/test_workflow_setup.sh` deletes the source and checks for dangling links | Compliant |
| FR-003 exact selection per mode, deps, detach opt-in, git | `spex-setup-profile.py` `MODES`/`mode_extensions`/`normalize_extensions`; `spex-apply-extensions.sh`; setup.yml `selected-extensions`, `apply-extensions`, `enforce-git-extension` | Deviation (interactive reply cannot reach setup, FINDING-14; git check fixed in review) |
| FR-004 refresh applies declaration (both paths) | setup.yml `extension-mode` reads the declaration; `spex-init.sh install_extensions` declaration branch | Compliant |
| FR-005 declaration agrees with enabled set | setup.yml `persist-request` after `apply-extensions`; skill Step 2 resolve, apply, persist under `set -e` | Compliant |
| FR-006 never disable non-spex extensions | `OPTIONAL_EXTENSIONS` list in `spex-apply-extensions.sh`; `git` only enabled | Compliant |
| FR-007 `spex/` installable as Codex plugin, version equal | `spex/.codex-plugin/plugin.json` (6.1.0, equals setup.yml and Claude manifest) | Compliant |
| FR-008 no clone, download or temp checkout | `bootstrap.sh` (no git, curl or mktemp) | Compliant |
| FR-009 source order | `bootstrap.sh` SPEX_SOURCE, `./spex`, bundled tree four levels up | Compliant |
| FR-010 actionable error, no fallback | `bootstrap.sh` errors naming the missing file and `SPEX_SOURCE` | Compliant |
| FR-011 integration always, defaults only without declaration | `bootstrap.sh` input assembly | Compliant |
| FR-012 Claude plugin unchanged | Claude manifest untouched; Codex skills under `spex/codex/skills/` | Compliant |
| FR-013 committed marketplace, ignore rules | `.agents/plugins/marketplace.json`; `.gitignore` exceptions (verified with `git check-ignore`) | Compliant |
| FR-014 docs and constitution | README Codex section, both help.md copies, constitution 2.1.1 | Compliant |
| FR-015 tests | `tests/test_workflow_setup.sh`, `tests/test_cc_spex_codex_plugin.sh`, `tests/test_apply_extensions.sh`, `tests/test_setup_profile.py`, `tests/test_init_worktrees_git.sh` | Compliant |
| FR-016 no declaration keeps registry state | `spex-init.sh` `prev_disabled` branch | Compliant |
| FR-017 identity `cc-spex` in marketplace `cc-spex` | plugin and marketplace names | Compliant |
| FR-018 name every changed extension | `spex-apply-extensions.sh` output; `spex-setup-report.sh` surfaces run-state stderr | Compliant |
| FR-019 git guidance re-runs setup | setup.yml `enforce-git-extension`, `worktrees_git_error`, both SKILL.md files | Compliant |
| FR-020 release sets Codex manifest and marketplace entry version | Makefile sets `spex/.codex-plugin/plugin.json`; the Codex marketplace entry has no `version` field | Deviation (minor) |
| FR-021 only `cc-spex-init` exposed to Codex | manifest `"skills": "./codex/skills/"` | Compliant |
| FR-022 interactive `/spex:init` writes declaration | `spex/skills/init/SKILL.md` Step 2 block, `DECLARATION_EXISTED` from `spex-init.sh` | Compliant |
| FR-023 legacy spex-detach migration | `spex-setup-profile.py migrate-detach`; setup.yml `snapshot-registry`; `spex-init.sh` declaration branch | Compliant |

**FR-020 deviation:** Codex's marketplace format carries no per-plugin `version`; the installed version comes from the plugin manifest the entry points to (research R9). The code is correct for the format, the spec text over-specifies. Recommendation: spec evolution (reword FR-020 to "the Codex plugin manifest, which the marketplace entry points to").

### Edge Cases

All 10 edge cases are handled: unresolvable plugin root and incomplete bundled tree (bootstrap errors; a missing optional extension fails the setup install step with its name, surfaced by `spex-setup-report.sh`), invalid `SPEX_SOURCE`, dependency closure, empty interactive reply (recommended), non-spex extensions untouched, legacy `all` declarations, manual toggles reset and reported, Claude plugin unaffected, re-run idempotence (remove + add per extension).

### Extra Features (Not in Spec)

- `spex-setup-report.sh`: prints the run-state stderr of the snapshot and apply steps and of a failed step, because `specify workflow run` does not print step stderr. Needed for FR-018 and FR-019. Helpful.
- `bootstrap.sh --help`. Helpful.

Spec evolution candidates: FR-020 wording; FR-003 / US3 scenario 6 (where the interactive choice is collected, FINDING-14).

## Deep Review Report

**Gate: FAIL** (after fix round 3). 1 Important finding remains, and it needs a spec decision rather than a code fix.

| Agent | Found | Fixed | Remaining | Status |
|-------|-------|-------|-----------|--------|
| Correctness | 6 | 3 | 1 Minor + 2 Notable | completed |
| Architecture & Idioms | 10 | 6 | 3 Minor + 1 Notable | completed |
| Security | 4 | 2 | 1 Minor + 1 Notable | completed |
| Production Readiness | 6 | 4 | 1 Minor + 1 Notable | completed |
| Test Quality | 10 | 8 | 1 Minor + 1 Notable (FR-020, merged) | completed |
| Goal Alignment | 0 | 0 | 0 | skipped (no PR found) |
| Re-review round 2 | 6 | 5 | 1 Important | completed |
| Re-review round 3 | 7 | 6 | 1 Minor | completed |
| CodeRabbit (external) | 7 | 7 | 0 | completed (4 runs) |
| Copilot (external) | 0 | 0 | 0 | skipped (disabled in config) |
| Codex (external) | 3 | 1 | 0 (2 false positives dismissed) | completed (4 runs) |
| Test Suite (regression) | 0 | 0 | 0 | passed every round |

MVP: Architecture & Idioms (10 findings)

Severity totals after merging duplicates:

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 16 | 16 | 0 |
| Minor | 26 | 19 | 7 |
| Notable | 5 | - | 5 |

Key fixes applied:
1. spex-worktrees selected last skipped the git extension check (trailing newline in step stdout); verified with the real `specify` and fixed (correctness).
2. Selection and security are resolved and validated before anything is reinstalled; spex-detach stays disabled until the selection enables it (production, correctness).
3. Resolver failures are no longer masked by a pipe, and unknown extension names are reported (production, CodeRabbit).
4. Agent replies are never substituted into shell source; the prompt steps whose replies spec-kit discards were removed (security, CodeRabbit, Codex).
5. bootstrap requires jq and python3 and names the stored security level (production, security).
6. FR-019 guidance fixed in ship.md and aligned in the init skill; extensions command explains that manual toggles are reset (architecture).
7. Tests: mktemp guards that can no longer delete the working directory, git stubs that see through global options, real-specify cases for git enforcement, invalid input and US3 scenario 7, glue and FR-022 tests (test quality).

Remaining findings (1 Important):
- FINDING-14 (Important) resolved by spec evolution (user decision 2026-10-18): the interactive choice is collected by the agents (Claude init skill Step 2, Codex skill) and passed as an explicit list; the workflow's own `interactive` mode applies recommended/safe with a notice. FR-003, US3 scenario 6 and the edge case were updated. FR-020 was reworded to match Codex's marketplace format (no version field).

Post-fix spec coverage: 23/23 requirements still implemented ✓ (FR-003 interactive deviation and FR-020 as noted)

Notable observations: 5 captured to brainstorm/idea-inbox.md

Details: specs/057-codex-bundled-init/review-findings.md
