---
name: cc-spex-init
description: Install or refresh Spex specification-driven workflows in the current project from the Spex source bundled with the cc-spex plugin. Use when a Codex user asks to initialize Spex, configure Spex extensions or security, or update an existing Spex project through the cc-spex plugin.
---

# Initialize Spex

This plugin bundles the complete Spex source (setup workflow, extensions and
scripts). Initialization runs from that installed copy. Nothing is cloned or
downloaded, and no temporary checkout is created.

## Run the bootstrap

Resolve the absolute path of `scripts/bootstrap.sh` from this skill
directory. Run it as `sh <absolute path>/scripts/bootstrap.sh [arguments]`
while keeping the working directory at the project root where the user
invoked `$cc-spex-init`. Never
`cd` into the skill or plugin directory, and never clone the cc-spex
repository or download Spex yourself. Pass through any arguments supplied
after `$cc-spex-init`.

The bootstrap picks the Spex source in this order:

1. `SPEX_SOURCE`, when it is set (an explicit local Spex source).
2. `./spex` in the project, when the project is the cc-spex repository.
3. The Spex source bundled with this plugin.

If the bootstrap reports that the bundled source is missing or incomplete,
show the error and stop. Do not fall back to cloning or downloading.

If setup stops with `spex-worktrees requires the spec-kit git extension`, show
the message and its fixes: add the git extension (`specify extension add git`)
and run `$cc-spex-init` again, or re-run `$cc-spex-init --extensions NAME,NAME`
with a selection that leaves out `spex-worktrees`. Do not disable
`spex-worktrees` by hand.

## Defaults and overrides

The harness is always `codex` unless the user passes `--integration`.

When the project has no `.specify/spex.json` yet, these defaults apply:

- extensions: `recommended` (`spex-gates,spex-worktrees,spex-deep-review`)
- security: `safe`

When `.specify/spex.json` exists, the project's stored extension selection and
security are applied unchanged. Only values the user passes explicitly
override them. The bootstrap names the stored security level on stderr; when
it prints a `NOTE:` about a security level other than `safe`, show that line
to the user in your report.

Supported overrides:

```text
--integration codex|claude|opencode|auto
--extensions recommended|all|interactive|NAME,NAME
--security safe|autonomous|yolo|interactive
```

The `interactive` values currently apply `recommended` and `safe` (the setup
workflow cannot read the reply back and prints a notice). When the user wants
to choose, ask them yourself and pass the answer as an explicit
`--extensions NAME,NAME` or `--security LEVEL`.

The selection is exact: the selected extensions are enabled and every other
optional Spex extension is disabled. `all` enables every optional extension
except `spex-detach`, which is enabled only when named explicitly.

Before running a non-default selection, summarize the selected values in one
line. Do not conduct a survey or ask about options the user already supplied.

## Report

After success, report the effective command prefix as `$`, remind the user to
start a new Codex session so generated skills are discovered, and suggest
`$speckit-spex-help`. Do not suggest slash-prefixed Spex commands or claim
that `$speckit-spex-ship` is necessarily the next workflow step.
