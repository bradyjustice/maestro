#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

"$repo_root/bin/maestro" --help > "$tmp/help.txt"
"$repo_root/bin/maestro" config validate --json > "$tmp/config.json"
"$repo_root/bin/maestro" arrange --dry-run --json > "$tmp/arrange.json"

if grep -Eq 'maestro (layout|pane|action|button) ' "$tmp/help.txt"; then
  printf 'Expected help to expose only config validate and arrange; saw:\n' >&2
  cat "$tmp/help.txt" >&2
  exit 1
fi

if ! grep -q '"ok" : true' "$tmp/config.json"; then
  printf 'Expected config validation to pass; saw:\n' >&2
  cat "$tmp/config.json" >&2
  exit 1
fi

if ! grep -q '"id" : "maestro"' "$tmp/arrange.json" || ! grep -q '"sessionName" : "maestro_maestro_main"' "$tmp/arrange.json"; then
  printf 'Expected arrange dry-run JSON to include the workspace and tmux session; saw:\n' >&2
  cat "$tmp/arrange.json" >&2
  exit 1
fi

if ! grep -q '"label" : "Browser"' "$tmp/arrange.json" || ! grep -q '"label" : "VS Code"' "$tmp/arrange.json"; then
  printf 'Expected arrange dry-run JSON to include browser and VS Code app area; saw:\n' >&2
  cat "$tmp/arrange.json" >&2
  exit 1
fi

if [[ -x "$repo_root/.build/debug/maestro-core-checks" ]]; then
  "$repo_root/.build/debug/maestro-core-checks" >/dev/null
else
  swift run --package-path "$repo_root" maestro-core-checks >/dev/null
fi
