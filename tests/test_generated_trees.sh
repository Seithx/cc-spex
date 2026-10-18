#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# The committed Codex marketplace (FR-013) is the only tracked path allowed
# under .agents/.
filter_generated() {
  awk '
    /^\.agents\// && $0 != ".agents/plugins/marketplace.json" { print }
    /^\.codex\// || /^\.claude\/skills\// { print }
  '
}

tracked_generated() {
  git -C "$1" ls-files | filter_generated
}

for generated in \
  .agents/skills/example/SKILL.md \
  .agents/plugins/other.json \
  .agents/skills/x/SKILL.md \
  .codex/hooks.json \
  .claude/skills/example/SKILL.md; do
  if ! git -C "$REPO_ROOT" check-ignore -q "$generated"; then
    echo "FAIL: generated path is not ignored: $generated" >&2
    exit 1
  fi
done

for committed in .specify/spex.json .agents/plugins/marketplace.json; do
  if git -C "$REPO_ROOT" check-ignore -q "$committed"; then
    echo "FAIL: committed path is ignored: $committed" >&2
    exit 1
  fi
done

# The exemption is exact: the marketplace file passes, any other .agents/
# path is still reported.
sample="$(printf '%s\n' \
  .agents/plugins/marketplace.json \
  .agents/plugins/other.json \
  .agents/plugins/marketplace.json.bak \
  .agents/skills/x/SKILL.md \
  README.md | filter_generated)"
expected="$(printf '%s\n' \
  .agents/plugins/other.json \
  .agents/plugins/marketplace.json.bak \
  .agents/skills/x/SKILL.md)"
if [[ "$sample" != "$expected" ]]; then
  echo "FAIL: .agents/ exemption is not exact. Reported:" >&2
  printf '%s\n' "$sample" >&2
  exit 1
fi

tracked="$(tracked_generated "$REPO_ROOT")"
if [[ -n "$tracked" ]]; then
  echo "FAIL: generated harness artifacts are tracked:" >&2
  printf '%s\n' "$tracked" >&2
  echo "Edit canonical sources under spex/ instead." >&2
  exit 1
fi

fixture="$(mktemp -d "${TMPDIR:-/tmp}/spex-generated-guard.XXXXXX")"
trap 'rm -rf -- "$fixture"' EXIT
git -C "$fixture" init -q
cp "$REPO_ROOT/.gitignore" "$fixture/.gitignore"
mkdir -p "$fixture/.agents/skills/generated" "$fixture/.agents/plugins"
printf '%s\n' generated > "$fixture/.agents/skills/generated/SKILL.md"
printf '%s\n' '{}' > "$fixture/.agents/plugins/marketplace.json"
git -C "$fixture" add .agents/plugins/marketplace.json
if [[ -n "$(tracked_generated "$fixture")" ]]; then
  echo "FAIL: guard fixture rejected the committed Codex marketplace" >&2
  exit 1
fi
git -C "$fixture" add -f .agents/skills/generated/SKILL.md
if [[ "$(tracked_generated "$fixture")" != ".agents/skills/generated/SKILL.md" ]]; then
  echo "FAIL: guard fixture did not detect a force-tracked generated skill" >&2
  exit 1
fi

echo "PASS: generated harness trees are ignored and tracked copies are rejected; only the Codex marketplace is exempt"
