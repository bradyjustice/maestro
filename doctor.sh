#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${LOCAL_TOOLS_BIN_DIR:-$HOME/.local/bin}"
failures=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

pass() {
  printf 'PASS: %s\n' "$*"
}

if [[ -L "$bin_dir/maestro" && "$(readlink "$bin_dir/maestro")" = "$repo_root/bin/maestro" ]]; then
  pass "maestro symlink"
else
  fail "$bin_dir/maestro is not installed from this repo"
fi

resolved="$(command -v maestro 2>/dev/null || true)"
if [[ "$resolved" = "$bin_dir/maestro" ]]; then
  pass "maestro PATH resolution"
else
  fail "maestro resolves to ${resolved:-nothing}, expected $bin_dir/maestro"
fi

for dep in bash swift tmux osascript; do
  if command -v "$dep" >/dev/null 2>&1; then
    pass "dependency $dep"
  else
    fail "missing dependency: $dep"
  fi
done

if "$repo_root/bin/maestro" config validate --json >/dev/null; then
  pass "workspace config"
else
  fail "workspace config validation"
fi

if [[ -d /Applications/iTerm.app || -d /Applications/iTerm2.app ]]; then
  pass "iTerm app"
else
  fail "missing iTerm app"
fi

if (( failures > 0 )); then
  printf '\n%d check(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nAll checks passed.\n'
