#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${LOCAL_TOOLS_BIN_DIR:-$HOME/.local/bin}"
failures=0

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

bash_scripts=(
  maestro
  agent-lib
  agent-start
  agent-status
  agent-review
  agent-mark
  agent-clean
  work
)

zsh_scripts=(
  iterm-quad-laptop
  iterm-quad-left
  iterm-reset-left
  iterm-stack-laptop
  iterm-stack-left
)

dependencies=(
  bash
  zsh
  swift
  git
  tmux
  codex
  osascript
  plutil
  jq
)

iterm_profiles=(
  "Quad Laptop"
  "Quad Left"
  "Stack Laptop"
  "Stack Left"
)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

pass() {
  printf 'PASS: %s\n' "$*"
}

expand_path_dir() {
  local dir="$1"
  case "$dir" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s/%s\n' "$HOME" "${dir#~/}" ;;
    *) printf '%s\n' "$dir" ;;
  esac
}

canonical_dir() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    (cd "$dir" && pwd -P)
  else
    return 1
  fi
}

check_installed_links() {
  local command_name
  local link_path
  local source_path
  local resolved

  for command_name in "${managed_commands[@]}"; do
    link_path="$bin_dir/$command_name"
    source_path="$repo_root/bin/$command_name"

    if [[ ! -L "$link_path" ]]; then
      fail "$link_path is not a symlink"
      continue
    fi

    resolved="$(readlink "$link_path")"
    if [[ "$resolved" != "$source_path" ]]; then
      fail "$link_path points to $resolved"
      continue
    fi

    pass "$command_name symlink"
  done
}

check_path_resolution() {
  local canonical_bin
  local command_name
  local resolved_command
  local path_dir
  local expanded_dir
  local canonical_path_dir
  local seen_bin

  canonical_bin="$(canonical_dir "$bin_dir")" || {
    fail "bin dir does not exist: $bin_dir"
    return
  }

  for command_name in "${managed_commands[@]}"; do
    resolved_command="$(command -v "$command_name" 2>/dev/null || true)"
    if [[ "$resolved_command" != "$bin_dir/$command_name" ]]; then
      fail "$command_name resolves to ${resolved_command:-nothing}, expected $bin_dir/$command_name"
    else
      pass "$command_name PATH resolution"
    fi

    seen_bin=0
    IFS=':' read -r -a path_entries <<< "$PATH"
    for path_dir in "${path_entries[@]}"; do
      expanded_dir="$(expand_path_dir "$path_dir")"
      canonical_path_dir="$(canonical_dir "$expanded_dir" 2>/dev/null || true)"

      if [[ -n "$canonical_path_dir" && "$canonical_path_dir" = "$canonical_bin" ]]; then
        seen_bin=1
        break
      fi

      if [[ -n "$expanded_dir" && -x "$expanded_dir/$command_name" ]]; then
        fail "$command_name is shadowed before $bin_dir by $expanded_dir/$command_name"
        break
      fi
    done

    if (( seen_bin == 0 )); then
      fail "$bin_dir is not in PATH"
    fi
  done
}

check_dependencies() {
  local dep
  for dep in "${dependencies[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
      pass "dependency $dep"
    else
      fail "missing dependency: $dep"
    fi
  done
}

iterm_prefs_plist() {
  defaults export com.googlecode.iterm2 - 2>/dev/null
}

iterm_bookmarks_json() {
  local prefs_plist="$1"

  plutil -extract 'New Bookmarks' json -o - - 2>/dev/null <<< "$prefs_plist"
}

iterm_default_bookmark_guid() {
  local prefs_plist="$1"

  plutil -extract 'Default Bookmark Guid' raw -o - - 2>/dev/null <<< "$prefs_plist"
}

iterm_profile_exists() {
  local bookmarks_json="$1"
  local profile="$2"

  jq -e --arg profile "$profile" \
    '.[]? | select(.Name == $profile)' \
    <<< "$bookmarks_json" >/dev/null
}

iterm_profile_value() {
  local bookmarks_json="$1"
  local profile="$2"
  local key="$3"

  jq -r --arg profile "$profile" --arg key "$key" \
    '.[]? | select(.Name == $profile) | .[$key] // empty' \
    <<< "$bookmarks_json" | head -n 1
}

iterm_default_profile_value() {
  local bookmarks_json="$1"
  local default_guid="$2"
  local key="$3"

  jq -r --arg guid "$default_guid" --arg key "$key" \
    '.[]? | select(.Guid == $guid) | .[$key] // empty' \
    <<< "$bookmarks_json" | head -n 1
}

check_iterm_profile_font() {
  local bookmarks_json="$1"
  local profile="$2"
  local key="$3"
  local expected="$4"
  local actual

  actual="$(iterm_profile_value "$bookmarks_json" "$profile" "$key")"
  if [[ "$actual" = "$expected" ]]; then
    pass "iTerm profile $profile $key matches default ($actual)"
  else
    fail "iTerm profile $profile $key is ${actual:-unset}, expected $expected"
  fi
}

check_iterm() {
  local profile
  local prefs_plist
  local bookmarks_json
  local default_guid
  local default_normal_font
  local default_non_ascii_font

  if [[ -d /Applications/iTerm.app ]]; then
    pass "iTerm app"
  else
    fail "missing iTerm app: /Applications/iTerm.app"
    return
  fi

  if ! defaults export com.googlecode.iterm2 - >/dev/null 2>&1; then
    fail "iTerm preferences unavailable"
    return
  fi

  prefs_plist="$(iterm_prefs_plist)" || {
    fail "iTerm preferences unreadable"
    return
  }

  bookmarks_json="$(iterm_bookmarks_json "$prefs_plist")" || {
    fail "iTerm profiles unreadable"
    return
  }

  default_guid="$(iterm_default_bookmark_guid "$prefs_plist")" || {
    fail "iTerm default profile unavailable"
    return
  }

  default_normal_font="$(iterm_default_profile_value "$bookmarks_json" "$default_guid" "Normal Font")"
  default_non_ascii_font="$(iterm_default_profile_value "$bookmarks_json" "$default_guid" "Non Ascii Font")"
  if [[ -z "$default_normal_font" || -z "$default_non_ascii_font" ]]; then
    fail "iTerm default profile font unavailable"
    return
  fi

  for profile in "${iterm_profiles[@]}"; do
    if iterm_profile_exists "$bookmarks_json" "$profile"; then
      pass "iTerm profile $profile"
      check_iterm_profile_font "$bookmarks_json" "$profile" "Normal Font" "$default_normal_font"
      check_iterm_profile_font "$bookmarks_json" "$profile" "Non Ascii Font" "$default_non_ascii_font"
    else
      fail "missing iTerm profile: $profile"
    fi
  done
}

check_syntax() {
  local script_name

  for script_name in "${bash_scripts[@]}"; do
    if bash -n "$repo_root/bin/$script_name"; then
      pass "bash syntax $script_name"
    else
      fail "bash syntax $script_name"
    fi
  done

  for script_name in "${zsh_scripts[@]}"; do
    if zsh -n "$repo_root/bin/$script_name"; then
      pass "zsh syntax $script_name"
    else
      fail "zsh syntax $script_name"
    fi
  done

  for script_name in install.sh uninstall.sh doctor.sh test/smoke.sh; do
    if bash -n "$repo_root/$script_name"; then
      pass "bash syntax $script_name"
    else
      fail "bash syntax $script_name"
    fi
  done
}

check_installed_links
check_path_resolution
check_dependencies
check_iterm
check_syntax

if (( failures > 0 )); then
  printf '\nDoctor found %s issue(s).\n' "$failures" >&2
  exit 1
fi

printf '\nDoctor passed.\n'
