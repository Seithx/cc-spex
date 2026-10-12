# Deep Review Findings

**Date:** 2026-10-11
**Branch:** 054-walkthrough-runbook
**Rounds:** 1
**Gate Outcome:** PASS
**Invocation:** manual

## Summary

| Severity | Found | Fixed | Remaining |
|----------|-------|-------|-----------|
| Critical | 0 | 0 | 0 |
| Important | 10 | 10 | 0 |
| Minor | 10 | 3 | 7 |
| Notable | 6 | - | 6 |
| **Total** | **26** | **13** | **13** |

**Agents completed:** 5/6 internal (Goal Alignment skipped: no PR) + 1 external (CodeRabbit)
**Agents failed:** Codex (usage limit reached); Copilot (disabled in config)
**Re-review:** round-2 focused re-review of all fixes — no new Critical/Important regressions.
**Test suite:** `make test-walkthrough` — 147 assertions, 0 failures (after fixes).

> Deduplication note: the compose-`eval` issue was reported by both Security and
> Correctness; the FR-036 placeholder-scope issue by Correctness, Test Quality,
> and the orchestrator; the `not_testable` global-key issue by CodeRabbit and
> Correctness. Each is listed once below with cross-attribution.

---

## Findings (Important — all fixed in round 1)

### FINDING-1
- **Severity:** Important
- **Confidence:** 90
- **File:** spex/extensions/spex/commands/speckit.spex.finish.md:356
- **Category:** external (CodeRabbit) / integration
- **Source:** coderabbit
- **Resolution:** fixed (round 1)

**What is wrong:**
The worktree-removal preservation call hard-coded the feature directory as
`"specs/$CURRENT_BRANCH"` instead of the `FEATURE_DIR` already resolved in Phase 1
(line 106: `spec_dir` from `.spex-state`, with a `specs/<branch>` fallback).

**Why this matters:**
In detach mode the spec directory exists only on disk in the worktree. If the spec
directory name ever differs from the branch name, `spex-finish-preserve-specs.sh`
sees a non-existent `SRC`, prints `PRESERVE_SKIPPED reason=no-spec-dir`, and
`finish` then removes the worktree — losing the only copy of the runbook (violates
FR-039 / SC-007).

**How it was resolved:**
Changed the call to `"${FEATURE_DIR:-specs/$CURRENT_BRANCH}"`, reusing the authoritative
variable the rest of `finish` operates on while keeping the original string as a
safe fallback.

**External tool analysis (CodeRabbit):**
> Update the preservation call to pass the Phase 1-resolved FEATURE_DIR instead of
> always deriving the feature directory from CURRENT_BRANCH. Preserve the
> specs/$CURRENT_BRANCH fallback when FEATURE_DIR is unset.

### FINDING-2
- **Severity:** Important
- **Confidence:** 80
- **File:** spex/scripts/spex-runbook-check.py:28-41
- **Category:** security
- **Source:** security-agent
- **Resolution:** fixed (round 1)

**What is wrong:**
`SECRET_PATTERNS` (the deterministic redaction backstop for FR-028/FR-036) missed
several high-signal, zero-false-positive credential markers common to this tool's
domain (walkthroughs that run `kubectl`/`oc login`/cloud CLIs): PEM/OpenSSH private
key blocks, kubeconfig `client-key-data`/`client-certificate-data`, Google `AIza…`,
Slack `xox[baprs]-…`, GitLab `glpat-…`. Also `sk-[A-Za-z0-9]{20,}` stopped at the
hyphen in modern `sk-proj-…` OpenAI keys, so they were not matched.

**Why this matters:**
This script is the last deterministic line of defense before a runbook is written
and, in normal mode, committed with the other spec artifacts. If the LLM fails to
honor the FR-028 redaction instruction, a real TLS/SSH private key, kubeconfig
cert-key, or provider token could be persisted to a shared repository.

**How it was resolved:**
Added PEM, kubeconfig (redaction-aware via a `(?!\[redacted\])` lookahead), AIza,
xox, and glpat patterns, and changed `sk-` to `sk-[A-Za-z0-9-]{20,}` to catch
`sk-proj-…`. The bare 40-char AWS *secret* key was deliberately NOT added (it would
false-positive on git SHAs/base64 output). Test coverage extended (FINDING-10).

### FINDING-3
- **Severity:** Important
- **Confidence:** 75
- **File:** spex/scripts/spex-runbook-fixture.sh:106-113, 143-146 (start/stop_one compose)
- **Category:** security / correctness
- **Source:** security-agent (also reported by: correctness-agent)
- **Resolution:** fixed (round 1)

**What is wrong:**
The compose teardown was stored as an interpolated string
`teardown="$PODMAN compose -f $file down"` and later executed with `eval "$teardown"`.
A compose file whose path contains shell metacharacters (plausible from an untrusted
project) would inject commands at teardown; a path with spaces would simply break
teardown and the `|| true` would silently mark the still-running stack as stopped.

**Why this matters:**
`eval` on a reconstructed command string built from a filesystem path is a textbook
injection vector, and the silent-leak path defeats FR-019 (teardown recorded and
performed).

**How it was resolved:**
The compose file path is now persisted in `fixtures.json` and teardown runs
`"$PODMAN" compose -f "$file" down` directly (no `eval`), matching the container
branch. The recorded display string now quotes `$file` so the copyable command is
also correct.

### FINDING-4
- **Severity:** Important
- **Confidence:** 75
- **File:** spex/scripts/spex-runbook-fixture.sh:88-94, 119-139, 228-246
- **Category:** production-readiness
- **Source:** production-agent
- **Resolution:** fixed (round 1)

**What is wrong:**
Quick `process` fixtures were tracked only by the PID captured at start. `stop_one`
killed that PID unconditionally and `cmd_status` probed it with `kill -0`, with no
check that the PID still belonged to the fixture. After an interrupted session where
the process died and the OS recycled the PID (macOS recycles quickly), `status` would
report the fixture running and wrap-up `stop` would signal an unrelated process.

**Why this matters:**
Killing the wrong process on a developer's machine is a real, hard-to-diagnose
hazard on exactly the FR-027 resume path the feature promises.

**How it was resolved:**
Start now records the process start time (`ps -o lstart=`) as `pid_start`. `stop_one`
and `cmd_status` only treat the PID as the fixture when it is alive AND the current
start time matches the recorded one, falling back to prior behavior when `pid_start`
is unavailable.

### FINDING-5
- **Severity:** Important
- **Confidence:** 72
- **File:** spex/scripts/spex-runbook-fixture.sh (all state writes)
- **Category:** production-readiness
- **Source:** production-agent
- **Resolution:** fixed (round 1)

**What is wrong:**
Every `fixtures.json` write used `tmp=$(mktemp)` (in `$TMPDIR`) then `mv` to the
scratch dir. When `$TMPDIR` and the scratch dir are on different filesystems (common
on Linux where `/tmp` is tmpfs), `mv` is copy-then-unlink — not an atomic rename — so
an interruption can corrupt the only record of live fixtures, leaking them.

**Why this matters:**
`fixtures.json` drives cleanup and FR-027 resume; corruption makes every subsequent
`jq` read fail and leaves containers/processes orphaned.

**How it was resolved:**
Added `state_tmp()` which creates the temp file in the state directory (same
filesystem), so the final `mv` is an atomic rename. All five write sites use it. This
mirrors the already-correct atomic write in `spex-runbook-status.py:write_runbook`.

### FINDING-6
- **Severity:** Important
- **Confidence:** 70
- **File:** spex/scripts/spex-runbook-fixture.sh:95-105
- **Category:** production-readiness
- **Source:** production-agent
- **Resolution:** fixed (round 1)

**What is wrong:**
`container` start captured output synchronously (`out=$("${cmd[@]}" …)`) and trusted
the agent-supplied command to include `-d`. A command missing `-d` (or an image that
runs foreground) blocks the entire interactive walkthrough indefinitely, with no
timeout.

**Why this matters:**
Fixtures are typically long-running services; an indefinite hang is a severe UX
failure mode for an unattended or interactive session.

**How it was resolved:**
The container command is now validated to contain `-d`/`--detach` before
`require_runtime`; a non-detaching command fails cleanly with a usage error instead
of hanging. The no-runtime exit-4 path is preserved.

### FINDING-7
- **Severity:** Important
- **Confidence:** 80
- **File:** spex/scripts/spex-runbook-check.py:102-125
- **Category:** correctness / spec-compliance (FR-036)
- **Source:** correctness-agent (also reported by: test-quality-agent, orchestrator)
- **Resolution:** fixed (round 1)

**What is wrong:**
The placeholder scan toggled `in_fence` on *every* fenced block and scanned all of
them, but FR-036 requires placeholder checks "limited to command blocks." Real
command output recorded into a ```text fence (FR-023/FR-024) that happens to contain
`/path/to/`, `TODO`, or a `<...>` token would raise a spurious
`RUNBOOK_CHECK_FAIL placeholder`.

**Why this matters:**
Over-reporting contradicts the explicit FR-036 scoping and SC-010 (placeholders in
*command* blocks) and would fail legitimate runbooks at the wrap-up check.

**How it was resolved:**
The scan now only inspects fences that directly follow a `**Run:**` marker (command
blocks); output/result/prose fences are left unchecked. A regression test was added
(FINDING-9). Existing command-fence and prose tests remain green.

### FINDING-8
- **Severity:** Important
- **Confidence:** 80
- **File:** tests/test_finish_preserve_specs.sh:50-66
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** fixed (round 1)

**What is wrong:**
The positive preserve test copied `spec.md`/`plan.md` but never a detach-relocated
runbook at `specs/foo/.walkthrough/RUNBOOK.md` — exactly the gitignored,
hidden-directory file the script exists to protect (US6 scenario 2 / FR-039 / SC-007).

**How it was resolved:**
The test now creates `specs/foo/.walkthrough/RUNBOOK.md` in the worktree and asserts
it is present in the main checkout after copy-back.

### FINDING-9
- **Severity:** Important
- **Confidence:** 78
- **File:** tests/test_runbook_check.sh (placeholder tests)
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** fixed (round 1)

**What is wrong:**
No test exercised a placeholder-looking token inside a non-command (output) fence,
so the FR-036 command-block-vs-output-block distinction (FINDING-7) was unprotected.

**How it was resolved:**
Added a test that appends a ```text output fence containing `/path/to/` and
`<generated-id>` and asserts `RUNBOOK_CHECK_PASS`. This test fails against the old
scan-everything code and passes against the fixed scoping.

### FINDING-10
- **Severity:** Important
- **Confidence:** 85
- **File:** tests/test_runbook_check.sh:160-171
- **Category:** test-quality
- **Source:** test-quality-agent
- **Resolution:** fixed (round 1)

**What is wrong:**
The secret test covered only 4 of the 8 original patterns (`gho_`, `github_pat_`,
`sk-`, `bearer` untested), so a regression in any untested regex would pass silently.

**How it was resolved:**
The secret loop now covers `gho_`, `github_pat_`, `glpat-`, `sk-`, `sk-proj-`, a PEM
BEGIN marker, and `Bearer …` in addition to the originals — validating both the
pre-existing and newly added (FINDING-2) patterns.

---

## Remaining Findings (Minor — reported, not auto-fixed)

Per the fix-loop contract, the autonomous loop addresses Critical/Important only.
These Minor findings are left for your decision; three closely-related Minors in files
already being edited were fixed opportunistically and are marked **[fixed]**.

- **[fixed] CORR-1 — container state detection** (`spex-runbook-fixture.sh` cmd_status):
  `podman inspect` returns 0 for exited containers, so a dead container was reported
  `running`. Fixed to `inspect -f '{{.State.Running}}'`.
- **[fixed] PROD-5 — unquoted `$names` in `stop --quick`** (`spex-runbook-fixture.sh`):
  word-splitting/globbing could skip a fixture with a space/glob in its name. Fixed to
  `while IFS= read -r` over process substitution.
- **[fixed] ARCH-2 — wrong FR citations:** `speckit.spex.walkthrough.md` "omit agent-run"
  rule cited FR-024a (correct: FR-021); `speckit.spex.finish.md` advisory line cited
  FR-021a (correct: FR-033). Both corrected.
- **CR-2 / CORR-4 — `not_testable` verdict uses a single global state key**
  (`spex-runbook-status.py:478-508`): `not_testable_recorded(spec_dir)` ignores
  `spec_dir`; two features sharing an identical non-spec code fingerprint would
  cross-contaminate the verdict. Low impact (one-feature-at-a-time). **Decision needed:**
  namespace the state key by `spec_dir`, or drop the unused parameter to make the
  global-code-state semantics explicit. Left unfixed because it is a design choice.
- **ARCH-3 — `--no-git` advertised but unhandled** (`speckit.spex.walkthrough.md:3`):
  the `argument-hint` lists `--no-git` but no command form/phase handles it (it exists
  only on the underlying `show` subcommand). **Decision needed:** remove it from the
  hint, or wire it through Phase 1. Left unfixed because it is a design choice.
- **TEST-4 — structure "neither Run+fence nor Do" failure branch untested.**
- **TEST-5 — `steps.passed/failed/skipped/pending` counts and the status-line count
  segment never asserted** (FR-010).
- **TEST-6 — init `drafted_at` / `updated` fields never asserted** (FR-010).
- **TEST-7 — fixture `compose` kind, usage/validation exit-2 paths, and the
  `podman info` fails exit-4 branch untested.**
- **TEST-8 — clip.sh fallback chain (`wl-copy`/`xclip`/`xsel`) untested; only pbcopy.**

## Notable Observations

Captured to `brainstorm/idea-inbox.md` for future brainstorming (informational, not bugs).

### NOTABLE-1
- **File:** spex/scripts/spex-finish-preserve-specs.sh:35-45 (and spex-runbook-status.py:238 do_locate)
- **Category:** security
- **Description:** `FEATURE_DIR`/`spec_dir` are used to build copy/mkdir targets without a `..`/containment guard; safety depends entirely on the caller.
- **Rationale:** Git ref rules forbid `..` in branch names so the documented caller is safe; defense-in-depth for a script whose job is writing into another checkout.

### NOTABLE-2
- **File:** spex/scripts/spex-runbook-check.py:40-59 (and spex-runbook-status.py:111-128)
- **Category:** architecture
- **Description:** Two independent hand-rolled frontmatter parsers read the same on-disk format written only by `serialize_frontmatter`.
- **Rationale:** "Duplication that will diverge" if the format gains multi-line/quoted values; the single-file script model makes a shared module non-free, so this is a deliberate-tradeoff note.

### NOTABLE-3
- **File:** spex/scripts/spex-runbook-status.py:22-25,309
- **Category:** architecture
- **Description:** `runbook_version` is written into every runbook but never read (no `REQUIRED_KEYS` entry, no migration/dispatch).
- **Rationale:** Speculative generality unless forward-compat is intended; mark it as such or drop it.

### NOTABLE-4
- **File:** spex/scripts/spex-runbook-fixture.sh:88-116
- **Category:** production-readiness
- **Description:** In `cmd_start` the real resource is created before `append_fixture` records it; if the append fails under `set -e`, the started process/container leaks untracked.
- **Rationale:** Narrow (requires append failure) but the leak is unrecoverable by the tool; consider teardown-on-record-failure or transactional ordering.

### NOTABLE-5
- **File:** spex/scripts/spex-ship-statusline.sh:239-261
- **Category:** production-readiness
- **Description:** The flow-mode status line spawns a Python interpreter (`spex-runbook-status.sh show … --no-git`) on every render while a spec dir is active.
- **Rationale:** `--no-git` avoids the expensive fingerprint path, but Python startup per render adds prompt latency; consider inline jq/awk parsing or mtime-keyed caching.

### NOTABLE-6
- **File:** spex/scripts/spex-finish-preserve-specs.sh:22-45
- **Category:** production-readiness
- **Description:** A failure of the `(cd "$WORKTREE" && sh "$DETACH" is-enabled)` compound (bad path, `cd` failure) collapses to `enabled=false` → `PRESERVE_SKIPPED reason=detach-off`, indistinguishable from detach genuinely being off; `rsync` has no fallback.
- **Rationale:** Misclassifying an environment error as "detach off" silently skips the data-loss-preventing copy. Consider validating `$WORKTREE` up front and distinguishing error from disabled.

## Goal Alignment

Skipped — no open PR for this branch, so declared goals could not be extracted.
(FR-040 removal and FR-041 documentation coverage were instead verified directly by
the Architecture agent: both PASS — old walkthrough helpers/tests fully removed with
no dangling references; README, both help docs, review-code/deep-review next-step
hints, extension.yml, and CHANGELOG all describe the new runbook behavior.)

## Post-Fix Spec Coverage

No FR-implementing code was removed during the fix loop (the compose `eval` was
replaced by a direct, equivalent teardown call, not dropped). Touched requirements
remain covered and were strengthened: FR-028/FR-036 (redaction + placeholder scope),
FR-017/FR-019/FR-020/FR-027 (fixture lifecycle/resume), FR-039 (spec-dir
preservation). All spec requirements verified present after the fix loop.

## Test Suite Results

| Round | Test Command | Exit Code | Failures | Status |
|-------|-------------|-----------|----------|--------|
| 1     | make test-walkthrough | 0 | 0 | passed |

147 assertions across 5 test files (runbook-status, runbook-check, runbook-fixture,
runbook-clip, finish-preserve-specs). Test suite passed after fixes.

## External Tools

| Tool | Status | Findings |
|------|--------|----------|
| CodeRabbit | completed | 2 (1 Important → fixed, 1 Minor → reported) |
| Codex | failed (usage limit reached) | 0 |
| Copilot | skipped (disabled in config) | 0 |
