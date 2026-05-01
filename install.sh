#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${LOCAL_TOOLS_BIN_DIR:-$HOME/.local/bin}"
backup_dir="${LOCAL_TOOLS_BACKUP_DIR:-$HOME/.local/share/maestro/backups/$(date '+%Y%m%d-%H%M%S')}"
backup_dir_ready=0
dry_run=0
force=0
cleanup_legacy=0

managed_commands=(
  maestro
  agent-lib
  agent-start
  agent-status
  agent-review
  agent-mark
  agent-clean
  work
  iterm-quad-laptop
  iterm-quad-left
  iterm-reset-left
  iterm-stack-laptop
  iterm-stack-left
)

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

Options:
  --bin-dir <dir>       Install symlinks into this directory.
  --cleanup-legacy      Back up managed commands that still live in ~/bin.
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
    --cleanup-legacy)
      cleanup_legacy=1
      shift
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

print_cmd() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
}

run() {
  if (( dry_run == 1 )); then
    print_cmd "$@"
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
  local base
  local candidate
  local n

  [[ -e "$path" || -L "$path" ]] || return 0

  ensure_backup_dir
  base="$(basename "$path")"
  candidate="$backup_dir/$base"
  n=1
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    candidate="$backup_dir/$base.$n"
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

    if (( force == 0 )); then
      printf 'refusing to replace symlink: %s -> %s\n' "$dest_path" "$current_target" >&2
      printf 'rerun with --force to back it up first\n' >&2
      exit 1
    fi

    backup_existing "$dest_path"
  elif [[ -e "$dest_path" ]]; then
    if cmp -s "$source_path" "$dest_path"; then
      backup_existing "$dest_path"
    elif (( force == 1 )); then
      backup_existing "$dest_path"
    else
      printf 'refusing to replace differing file: %s\n' "$dest_path" >&2
      printf 'rerun with --force to back it up first\n' >&2
      exit 1
    fi
  fi

  run ln -s "$source_path" "$dest_path"
  printf 'Installed: %s -> %s\n' "$dest_path" "$source_path"
}

cleanup_legacy_shadows() {
  local legacy_dirs=("$HOME/bin")
  local legacy_dir
  local command_name
  local source_path
  local legacy_path
  local current_target

  for legacy_dir in "${legacy_dirs[@]}"; do
    [[ "$legacy_dir" != "$bin_dir" ]] || continue
    [[ -d "$legacy_dir" ]] || continue

    for command_name in "${managed_commands[@]}"; do
      source_path="$repo_root/bin/$command_name"
      legacy_path="$legacy_dir/$command_name"

      [[ -e "$legacy_path" || -L "$legacy_path" ]] || continue

      if [[ -L "$legacy_path" ]]; then
        current_target="$(readlink "$legacy_path")"
        [[ "$current_target" = "$source_path" ]] && continue
      fi

      if cmp -s "$source_path" "$legacy_path"; then
        backup_existing "$legacy_path"
      elif (( force == 1 )); then
        backup_existing "$legacy_path"
      else
        printf 'legacy command shadows install: %s\n' "$legacy_path" >&2
        printf 'rerun with --force to back it up first\n' >&2
        exit 1
      fi
    done
  done
}

run mkdir -p "$bin_dir"

for command_name in "${managed_commands[@]}"; do
  install_one "$command_name"
done

if (( cleanup_legacy == 1 )); then
  cleanup_legacy_shadows
fi

printf '\nInstall complete. Verify with:\n  %s/doctor.sh\n' "$repo_root"
