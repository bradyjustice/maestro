#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

"$repo_root/bin/maestro" --help >/dev/null
"$repo_root/bin/maestro" config validate --json > "$tmp/config.json"
"$repo_root/bin/maestro" layout list --json > "$tmp/layouts.json"
"$repo_root/bin/maestro" layout apply terminal-left-third --dry-run --json > "$tmp/layout-apply.json"
"$repo_root/bin/maestro" action list --json > "$tmp/actions.json"
"$repo_root/bin/maestro" action run account.check --dry-run --json > "$tmp/action-account-check.json"
"$repo_root/bin/maestro" pane list --layout terminal-left-third --dry-run --json > "$tmp/panes.json"
"$repo_root/bin/maestro" pane swap main.top main.bottom --layout terminal-left-third --dry-run --json > "$tmp/pane-swap.json"
"$repo_root/bin/maestro" button list --json > "$tmp/buttons.json"
"$repo_root/bin/maestro" button run website.dev --dry-run --json > "$tmp/website-dev.json"
"$repo_root/bin/maestro" button run website.stop --dry-run --json > "$tmp/website-stop.json"
"$repo_root/bin/maestro" button run account.check --dry-run --json > "$tmp/account-check.json"

if ! grep -q '"ok" : true' "$tmp/config.json"; then
  printf 'Expected config validation to pass; saw:\n' >&2
  cat "$tmp/config.json" >&2
  exit 1
fi

if ! grep -q '"id" : "terminal-left-third"' "$tmp/layouts.json" || ! grep -q '"id" : "quad-full"' "$tmp/layouts.json"; then
  printf 'Expected layout list to include starter command-center layouts; saw:\n' >&2
  cat "$tmp/layouts.json" >&2
  exit 1
fi

if ! grep -q '"layoutID" : "terminal-left-third"' "$tmp/layout-apply.json" || ! grep -q '"sessionName" : "maestro_node_main"' "$tmp/layout-apply.json"; then
  printf 'Expected layout dry-run JSON to include layout and per-host session; saw:\n' >&2
  cat "$tmp/layout-apply.json" >&2
  exit 1
fi

if ! grep -q '"id" : "account.check"' "$tmp/actions.json" || ! grep -q '"kind" : "openRepoInEditor"' "$tmp/actions.json"; then
  printf 'Expected action list to include command and app actions; saw:\n' >&2
  cat "$tmp/actions.json" >&2
  exit 1
fi

if ! grep -q '"actionID" : "account.check"' "$tmp/action-account-check.json" || ! grep -q '"targetPane" : "maestro_node_main:main.1"' "$tmp/action-account-check.json"; then
  printf 'Expected action dry-run JSON to include rendered target pane; saw:\n' >&2
  cat "$tmp/action-account-check.json" >&2
  exit 1
fi

if ! grep -q '"slotID" : "top"' "$tmp/panes.json" || ! grep -q '"paneTarget" : "maestro_node_main:main.1"' "$tmp/panes.json"; then
  printf 'Expected pane list dry-run JSON to include configured pane slots; saw:\n' >&2
  cat "$tmp/panes.json" >&2
  exit 1
fi

if ! grep -q '"kind" : "swap"' "$tmp/pane-swap.json" || ! grep -q '"swap-pane"' "$tmp/pane-swap.json"; then
  printf 'Expected pane swap dry-run JSON to include tmux swap-pane plan; saw:\n' >&2
  cat "$tmp/pane-swap.json" >&2
  exit 1
fi

if ! grep -q '"id" : "website.dev"' "$tmp/buttons.json" || ! grep -q '"id" : "website.stop"' "$tmp/buttons.json"; then
  printf 'Expected button list to include website command and stop buttons; saw:\n' >&2
  cat "$tmp/buttons.json" >&2
  exit 1
fi

if ! grep -q '"buttonID" : "website.dev"' "$tmp/website-dev.json" || ! grep -q '"displayCommand" : "npm run dev"' "$tmp/website-dev.json" || ! grep -q '"targetPane" : "maestro_node_main:main.0"' "$tmp/website-dev.json"; then
  printf 'Expected website dev dry-run JSON to include rendered command and target; saw:\n' >&2
  cat "$tmp/website-dev.json" >&2
  exit 1
fi

if ! grep -q '"buttonID" : "website.stop"' "$tmp/website-stop.json" || ! grep -q '"C-c"' "$tmp/website-stop.json"; then
  printf 'Expected website stop dry-run JSON to include C-c send-keys; saw:\n' >&2
  cat "$tmp/website-stop.json" >&2
  exit 1
fi

if ! grep -q '"buttonID" : "account.check"' "$tmp/account-check.json" || ! grep -q '"displayCommand" : "npm run check"' "$tmp/account-check.json"; then
  printf 'Expected hidden-profile account check dry-run JSON to remain runnable; saw:\n' >&2
  cat "$tmp/account-check.json" >&2
  exit 1
fi

if [[ -x "$repo_root/.build/debug/maestro-core-checks" ]]; then
  "$repo_root/.build/debug/maestro-core-checks" >/dev/null
else
  swift run --package-path "$repo_root" maestro-core-checks >/dev/null
fi
