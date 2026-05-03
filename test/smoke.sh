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
"$repo_root/bin/maestro" button list --json > "$tmp/buttons.json"
"$repo_root/bin/maestro" button run website.dev --dry-run --json > "$tmp/website-dev.json"
"$repo_root/bin/maestro" button run website.stop --dry-run --json > "$tmp/website-stop.json"

if ! grep -q '"ok" : true' "$tmp/config.json"; then
  printf 'Expected config validation to pass; saw:\n' >&2
  cat "$tmp/config.json" >&2
  exit 1
fi

if ! grep -q '"id" : "website.dev"' "$tmp/buttons.json" || ! grep -q '"id" : "website.stop"' "$tmp/buttons.json"; then
  printf 'Expected button list to include website command and stop buttons; saw:\n' >&2
  cat "$tmp/buttons.json" >&2
  exit 1
fi

if ! grep -q '"buttonID" : "website.dev"' "$tmp/website-dev.json" || ! grep -q '"displayCommand" : "npm run dev"' "$tmp/website-dev.json" || ! grep -q '"targetPane" : "node-dev:website.0"' "$tmp/website-dev.json"; then
  printf 'Expected website dev dry-run JSON to include rendered command and target; saw:\n' >&2
  cat "$tmp/website-dev.json" >&2
  exit 1
fi

if ! grep -q '"buttonID" : "website.stop"' "$tmp/website-stop.json" || ! grep -q '"C-c"' "$tmp/website-stop.json"; then
  printf 'Expected website stop dry-run JSON to include C-c send-keys; saw:\n' >&2
  cat "$tmp/website-stop.json" >&2
  exit 1
fi

if [[ -x "$repo_root/.build/debug/maestro-core-checks" ]]; then
  "$repo_root/.build/debug/maestro-core-checks" >/dev/null
else
  swift run --package-path "$repo_root" maestro-core-checks >/dev/null
fi
