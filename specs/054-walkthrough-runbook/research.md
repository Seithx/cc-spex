# Research: Walkthrough as a Runbook

## R1. Detecting "the tested code is still current" across squash and rebase

**Decision**: Record two values at draft and at test time: the commit SHA and a **code fingerprint**. The fingerprint is a hash of the working tree's file list with blob IDs, excluding `specs/` and `brainstorm/`, computed through a temporary index (`GIT_INDEX_FILE=<tmp> git add -A && git write-tree`, then `git ls-tree -r <tree>` filtered and hashed). "Current" means the fingerprint now equals the recorded one. The SHA is used only to list changed files when it still exists.

**Rationale**: `finish` squashes the branch (`git reset --soft` plus one commit), and the post-merge flow runs on `main`, so a recorded SHA is often unreachable or meaningless later. A content fingerprint is identical before and after squash, rebase, and merge. Using the working tree (not HEAD) covers walkthroughs that run before the last changes are committed: after `finish` commits them, the fingerprint is unchanged. Excluding `specs/` and `brainstorm/` keeps "committing the runbook" or "updating docs in the spec" from looking like a code change (FR-034).

**Alternatives considered**: SHA-only `git diff` (breaks after squash, FR-034 unmet on main); HEAD tree fingerprint (misses uncommitted changes tested in the session, causes false "stale" after finish commits them); hashing every file's bytes directly (slower, reimplements what git already hashes).

## R2. Status block format

**Decision**: YAML frontmatter with flat keys only, plus a human-readable status line directly under the H1 between `<!-- runbook-status -->` and `<!-- /runbook-status -->` markers. Both are written exclusively by `spex-runbook-status.py`. Step results are stored as one comma-separated list (`step_results: passed,failed,skipped,pending`), from which counts and the overall status are derived (FR-010a).

**Rationale**: Frontmatter renders cleanly in Marked 2 and Obsidian and is readable by `yq`. Flat keys parse with a small regex in Python without requiring PyYAML (not guaranteed installed). Deriving status in a script instead of having the agent write it satisfies Constitution VII and removes the "agent forgot to update status" failure class that broke 053.

**Alternatives considered**: Status only as a markdown line (fragile to parse); a sidecar JSON file (two files to keep in sync, and the runbook would no longer be self-describing when copied or archived); nested YAML (needs a YAML library).

## R3. Self-ignoring scratch folder

**Decision**: The scratch folder `specs/<feature>/.walkthrough/` is created with a `.gitignore` containing `*`. This ignores everything in the folder, including the `.gitignore` itself.

**Rationale**: The 053 rule `specs/**/.walkthrough/` exists only in cc-spex's own `.gitignore`; user projects lack it, so `finish`'s `git add -A` would commit logs and PID files. A self-ignoring folder works in every repository with no edits to shared files (Constitution III, FR-020).

**Alternatives considered**: Adding a rule to the project `.gitignore` (modifies a shared tracked file, leaks spec-driven development into upstream repos in detach mode); writing to `.git/info/exclude` (owned by spex-detach in detach mode).

## R4. Runbook location in detach mode

**Decision**: A `locate` command decides the runbook path: the normal path `specs/<feature>/RUNBOOK.md`, unless detach is enabled and `git check-ignore` reports the normal path as not ignored; then `specs/<feature>/.walkthrough/RUNBOOK.md`. Detach state is read with `.specify/extensions/spex-detach/scripts/spex-detach.sh is-enabled` (exit 0 = enabled; missing script = disabled).

**Rationale**: `is-enabled` reads the extension registry flag, unlike the directory check that wrongly reported detach as enabled in this repo. Choosing a location instead of changing exclusion files keeps the walkthrough out of detach's files (FR-037, FR-038).

## R5. Language per helper

**Decision**: Python 3 with a POSIX `sh` shim for parsing-heavy helpers (`spex-runbook-status`, `spex-runbook-check`), following the existing `spex-ship-state.sh` / `.py` and `spex-detach.sh` / `.py` pattern. Bash plus `jq` for `spex-runbook-fixture.sh`, `spex-runbook-clip.sh`, and `spex-finish-preserve-specs.sh`.

**Rationale**: Frontmatter parsing, markdown fence scanning, secret regexes, and git plumbing are clearer and better tested in Python. Process and container management is natural in shell. No new runtime dependencies: Python 3, `jq`, `yq`, and git are already required.

## R6. Local fixture management

**Decision**: `spex-runbook-fixture.sh` supports three kinds with a single state file `.walkthrough/fixtures.json`:
- `process`: started with `nohup` in the background, PID and log path recorded; stop sends TERM, waits up to 5 s, then KILL.
- `container`: the given `podman run -d ...` command is executed; the container ID from stdout is recorded; stop runs `podman stop` then `podman rm`.
- `compose`: `podman compose -f <file> up -d`; stop runs `podman compose -f <file> down`.
Slow and remote fixtures are never started by the script; `record` adds them with tier, owner, and teardown command so the runbook's test environment section and cleanup stay complete.

**Rationale**: Covers the podman-style backends the user wants automated while keeping clusters and cloud resources under the project's own tooling with explicit consent (FR-015 to FR-019). Persisting PIDs and IDs in a file makes cleanup work across the fresh shells each agent command runs in, the failure that 053 worked around with inline bash.

**Alternatives considered**: Docker support (user mandates podman; `podman` with a docker alias still works); having the script provision clusters (out of scope and dangerous; project tooling owns it).

## R7. Clipboard

**Decision**: `spex-runbook-clip.sh` reads the command from stdin and tries, in order, `pbcopy`, `wl-copy`, `xclip -selection clipboard`, `xsel --clipboard --input`. Exit 0 prints the tool used; exit 3 means no clipboard tool.

**Rationale**: macOS primary, common Linux tools supported, and a distinct exit code lets the skill fall back to showing the command (FR-022) without treating it as an error.

## R8. Mechanical step-format check

**Decision**: `spex-runbook-check.py` enforces, per step heading `### Step N of M: ...`: presence of `**Why this step:**`, `**What you should see:**`, `**If you see something else:**`, and either a `**Run:**` section with a fenced code block or a `**Do:**` section (browser and GUI steps). It also flags placeholder tokens inside fenced command blocks only (`<word>`, `/path/to/`, `TODO`, `PLACEHOLDER`, `YOUR_...`) and credential-looking strings anywhere in the file that are not `[redacted]` (bearer tokens, `ghp_`/`gho_`/`github_pat_`, `sk-...`, `AKIA...`, JWTs, `password|token|secret|api_key = <long value>`). Exit 0 clean, 1 findings (one line each), 2 usage.

**Rationale**: The 053 failure (terse cards without real content) passed every existing check because only placeholders were linted. Checking the required sections mechanically enforces FR-005 the same way Constitution VII intends; it cannot judge prose quality, but it prevents the structural regression. Limiting placeholder checks to command blocks avoids false positives on explanatory prose.

## R9. Preserving spec artifacts on worktree removal in detach mode

**Decision**: New `spex-finish-preserve-specs.sh <worktree-path> <main-worktree> <feature-dir>`: when detach is enabled (via `is-enabled`, run in the worktree), `rsync -a` the feature dir from the worktree to the main checkout; otherwise no-op. `finish` calls it before every `git worktree remove`.

**Rationale**: Spec artifacts excluded from git exist only on disk; worktree creation copies them in, nothing copies them back. A script instead of inline markdown bash, because this guards against data loss and must not be skipped (Constitution VII rationale).

## R10. Harness-neutral command vocabulary

**Decision**: The rewritten command uses the existing `{harness:interactive-choice}` style markers already used by `finish` and other commands for prompts, and describes browser automation generically ("a browser automation tool, such as Playwright MCP, when connected").

**Rationale**: The plugin is installed for Claude Code, Codex, and OpenCode; harness-specific tool names in command markdown break other agents (feature 038 neutral command vocabulary).
