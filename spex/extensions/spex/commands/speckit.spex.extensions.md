---
description: "Manage spex extensions: enable, disable, or list active extensions"
---

# Spex Extensions Management

Manage which spex extensions are active. Extensions provide additional capabilities such as quality gates, team orchestration, worktree isolation, and deep review.

**Available extensions**: `spex-gates`, `spex-deep-review`, `spex-teams`, `spex-worktrees`

---

## Parse Arguments

Parse `$ARGUMENTS` for the subcommand and optional extension name:

- No arguments or `list` -> **List**
- `enable <extension-name>` -> **Enable**
- `disable <extension-name>` -> **Disable**

## Subcommand: List (default)

Run via Bash:

```bash
specify extension list
```

Display the output to the user.

## Persistence note (enable and disable)

When the project has a declaration (`.specify/spex.json`), it is the source of truth for the optional spex extensions. A manual `specify extension enable` or `disable` lasts only until the next refresh (`/spex:init --refresh`, `$cc-spex-init`, or a setup workflow run without an explicit selection), which re-applies the declaration. Tell the user this when you enable or disable a spex extension. One exception: disabling `spex-detach` by hand while the declaration lists it removes it from the declaration at the next refresh (legacy migration, FR-023), so that disable sticks; re-run setup naming `spex-detach` to keep it. To change the selection permanently, re-run setup with an explicit selection (`/spex:init`, `$cc-spex-init --extensions NAME,NAME`, or `specify workflow run <spex source>/setup.yml -i extensions=NAME,NAME`, where the spex source is `spex/` in the cc-spex repository or the installed plugin directory), which updates the declaration.

## Subcommand: Enable

Run via Bash:

```bash
specify extension enable <extension-name>
```

Report the result to the user.

## Subcommand: Disable

1. Run `specify extension list` and check if the extension is already disabled. If so, report that and STOP.
2. **Warn the user**: Disabling an extension requires regenerating all spec-kit files, which resets any manual customizations to `.claude/skills/speckit-*/SKILL.md` and `.specify/templates/*.md` files.
3. {harness:interactive-choice} to confirm:
   - **Question**: "Disabling an extension will reset all spec-kit files to defaults (losing any manual customizations). Proceed?"
   - **Header**: "Confirm"
   - **Options**:
     - Label: "Yes, disable", Description: "Reset spec-kit files and remove this extension's overlays"
     - Label: "Cancel", Description: "Keep current extension configuration unchanged"
4. If cancelled: report "Extension disable cancelled." and STOP.
5. If confirmed, run these commands sequentially via Bash:
   ```bash
   specify extension disable <extension-name>
   specify init --here --ai claude --force
   specify extension apply
   ```
6. Report which extensions are still active.
