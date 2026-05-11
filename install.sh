#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${LOCAL_TOOLS_BIN_DIR:-$HOME/.local/bin}"
backup_dir="${LOCAL_TOOLS_BACKUP_DIR:-$HOME/.local/share/maestro/backups/$(date '+%Y%m%d-%H%M%S')}"
backup_dir_ready=0
dry_run=0
force=0

managed_commands=(maestro)

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

Options:
  --bin-dir <dir>       Install symlinks into this directory.
  --dry-run             Print actions without changing files.
  --force               Back up differing existing files instead of failing.
  -h, --help            Show this help.
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
    --force)
      force=1
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

ensure_backup_dir() {
  if (( backup_dir_ready == 0 )); then
    run mkdir -p "$backup_dir"
    backup_dir_ready=1
  fi
}

backup_existing() {
  local path="$1"
  local candidate="$backup_dir/$(basename "$path")"
  local n=1

  [[ -e "$path" || -L "$path" ]] || return 0
  ensure_backup_dir
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    candidate="$backup_dir/$(basename "$path").$n"
    n=$((n + 1))
  done
  run mv "$path" "$candidate"
  printf 'Backed up %s -> %s\n' "$path" "$candidate"
}

install_one() {
  local command_name="$1"
  local source_path="$repo_root/bin/$command_name"
  local dest_path="$bin_dir/$command_name"
  local current_target=""

  [[ -f "$source_path" ]] || { printf 'missing source: %s\n' "$source_path" >&2; exit 1; }

  if [[ -L "$dest_path" ]]; then
    current_target="$(readlink "$dest_path")"
    if [[ "$current_target" = "$source_path" ]]; then
      printf 'Already installed: %s\n' "$dest_path"
      return 0
    fi
    (( force == 1 )) || { printf 'refusing to replace symlink: %s -> %s\n' "$dest_path" "$current_target" >&2; exit 1; }
    backup_existing "$dest_path"
  elif [[ -e "$dest_path" ]]; then
    if cmp -s "$source_path" "$dest_path" || (( force == 1 )); then
      backup_existing "$dest_path"
    else
      printf 'refusing to replace differing file: %s\n' "$dest_path" >&2
      exit 1
    fi
  fi

  run ln -s "$source_path" "$dest_path"
  printf 'Installed: %s -> %s\n' "$dest_path" "$source_path"
}

run mkdir -p "$bin_dir"
for command_name in "${managed_commands[@]}"; do
  install_one "$command_name"
done

printf '\nInstall complete. Verify with:\n  %s/doctor.sh\n' "$repo_root"

