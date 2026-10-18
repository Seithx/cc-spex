# Data Model: Codex Init from a Bundled Spex Source

## Project declaration (`.specify/spex.json`)

The schema is unchanged and validated by `spex/scripts/spex-setup-profile.py`.

| Field | Values | Written by |
|-------|--------|------------|
| `schema_version` | `1` | all writers |
| `harness` | `auto`, `claude`, `codex`, `opencode` | setup workflow (`integration` input or the stored value); `/spex:init` writes `claude` only when creating the file |
| `extensions` | list incl. `spex` plus resolved optional extensions | setup workflow, `/spex:init` (FR-022) |
| `security` | `safe`, `autonomous`, `yolo` | setup workflow; `/spex:init` maps None to `safe`, Standard to `autonomous`, YOLO to `yolo` |

**Invariant (FR-005)**: after any successful setup or `/spex:init`, the optional extensions enabled in `.specify/extensions/.registry` equal the optional entries of `extensions`.

## Extension registry (`.specify/extensions/.registry`)

Owned by `specify`. spex changes the `enabled` state only through `specify extension enable` and `specify extension disable`: for the six optional spex extensions in both directions, and for the spec-kit `git` extension only to enable it when `spex-worktrees` is selected.

## Codex plugin (installed copy of `spex/`)

```
spex/
├── .claude-plugin/plugin.json        # Claude Code manifest (unchanged)
├── .codex-plugin/plugin.json         # NEW: name cc-spex, version = release version, skills ./codex/skills/
├── codex/skills/cc-spex-init/        # NEW: the only Codex skill
│   ├── SKILL.md
│   ├── agents/openai.yaml
│   └── scripts/bootstrap.sh
├── setup.yml                         # bundled source used by bootstrap
├── extensions/ ...                   # bundled extensions
└── skills/init/SKILL.md              # Claude-only, not exposed to Codex
```

## Codex marketplace (`.agents/plugins/marketplace.json`)

```json
{
  "name": "cc-spex",
  "interface": { "displayName": "cc-spex" },
  "plugins": [
    {
      "name": "cc-spex",
      "source": { "source": "local", "path": "./spex" },
      "policy": { "installation": "AVAILABLE", "authentication": "ON_INSTALL" },
      "category": "Productivity"
    }
  ]
}
```

## Selection state transitions

```
installed (all 7, enabled by specify)
  └─ resolve selection (mode / list / declaration, plus dependencies)
       └─ spex-apply-extensions.sh  →  enabled == selection, others disabled
            └─ persist declaration (setup workflow, /spex:init)
```
