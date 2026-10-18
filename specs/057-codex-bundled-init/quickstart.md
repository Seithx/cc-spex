# Quickstart: Validating Codex Bundled Init

## Automated

```bash
make test-codex-plugin     # bootstrap: source order, inputs, no fetch, versions
make test-apply-extensions # exact selection script with a stub specify registry
make test-workflow-setup   # real specify: TMPDIR source, exact selection per mode
make test-worktree         # includes init refresh with and without declaration
make test-generated-trees  # marketplace file allowed, other .agents/ files still rejected
make test-setup-profile
make sync-scripts-check
make validate
```

| Case | Expected |
|------|----------|
| bootstrap in a non-repo project, no `SPEX_SOURCE` | `specify workflow run <repo>/spex/setup.yml` with `SPEX_SOURCE=<repo>/spex`; stderr names `bundled` |
| bootstrap with `git clone/fetch/ls-remote` and `curl` failing | succeeds; no `cc-spex-init-*` directory under `$TMPDIR` |
| bootstrap without a declaration | passes `integration=codex`, `extensions=recommended`, `security=safe` |
| bootstrap with a declaration, no overrides | passes only `integration=codex` |
| bootstrap with `--extensions all` and a declaration | passes `integration=codex` and `extensions=all` |
| bootstrap with `SPEX_SOURCE` set | uses it; invalid `SPEX_SOURCE` exits 1 |
| bootstrap inside the cc-spex repo | uses `./spex` |
| bootstrap from a broken bundled tree (no `setup.yml`) | exits 1 naming the missing file, no fetch |
| version check | `spex/.codex-plugin/plugin.json .version` equals the `setup.yml` workflow version and `spex/.claude-plugin/plugin.json .version` |
| setup from a source copy under `$TMPDIR` | 7 of 7 extensions installed; still working after the copy is deleted |
| setup `recommended` | gates, worktrees, deep-review enabled; teams, collab, detach disabled |
| setup `all` | all except detach enabled |
| setup explicit list `spex-teams` | teams and gates enabled (dependency), others disabled |
| refresh without input | declaration applied again, same enabled set |
| `all` then `recommended` | teams and collab disabled, reported as `Disabled:` |
| `spex-init.sh --refresh` with declaration | enabled set follows the declaration (manually re-enabled extension is disabled again) |
| `spex-init.sh --refresh` without declaration | previously disabled extensions stay disabled (unchanged behavior) |

## Manual (needs Codex CLI)

1. In this repository: `codex plugin marketplace add .` (or the equivalent Codex command), then install `cc-spex`.
2. Check that the Codex skill list shows `cc-spex-init` and not `init`.
3. In a fresh git project: run `$cc-spex-init`. Expect setup to complete, no `cc-spex-init-*` directory under `$TMPDIR`, and `.specify/spex.json` with `harness: codex`.
4. Re-run `$cc-spex-init` after `$cc-spex-init --extensions all --security autonomous`: the same extensions stay enabled and security stays `autonomous`.
5. On a machine with the old thin plugin from a local marketplace path: follow the README migration steps and check that Codex lists exactly one `cc-spex` plugin.
