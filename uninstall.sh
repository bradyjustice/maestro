#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${LOCAL_TOOLS_BIN_DIR:-$HOME/.local/bin}"
dry_run=0

usage() {
  cat <<'USAGE'
Usage: ./uninstall.sh [options]

Options:
  --bin-dir <dir>   Remove links from this directory.
  --dry-run         Print actions without changing files.
  -h, --help        Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bin-dir)
      [[ $# -ge 2 ]] || { printf 'missing value for --bin-dir\n' >&2; exit 2; }
      bin_dir="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

run() {
  if (( dry_run == 1 )); then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

link_path="$bin_dir/maestro"
source_path="$repo_root/bin/maestro"

if [[ -L "$link_path" && "$(readlink "$link_path")" = "$source_path" ]]; then
  run rm "$link_path"
  printf 'Removed: %s\n' "$link_path"
elif [[ -e "$link_path" || -L "$link_path" ]]; then
  printf 'Skipping unmanaged path: %s\n' "$link_path"
fi

