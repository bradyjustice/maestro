#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

sample_root="$tmp/node"
sample_repo="$sample_root/sample"
worktree_root="$tmp/worktrees"
registry_dir="$worktree_root/_registry"

mkdir -p "$sample_root"
git init -b main "$sample_repo" >/dev/null
git -C "$sample_repo" config user.email "smoke@example.invalid"
git -C "$sample_repo" config user.name "Maestro Smoke"
printf 'smoke\n' > "$sample_repo/README.md"
git -C "$sample_repo" add README.md
git -C "$sample_repo" commit -m "Initial commit" >/dev/null

AGENT_NODE_ROOT="$sample_root" \
AGENT_WORKTREE_ROOT="$worktree_root" \
AGENT_REGISTRY_DIR="$registry_dir" \
AGENT_START_NO_LAUNCH=1 \
  "$repo_root/bin/agent-start" sample smoke-test "Smoke prompt" >/dev/null

task_id="sample-$(date '+%Y%m%d')-smoke-test"

AGENT_REGISTRY_DIR="$registry_dir" "$repo_root/bin/agent-status" >/dev/null
AGENT_REGISTRY_DIR="$registry_dir" "$repo_root/bin/agent-mark" "$task_id" abandoned "Smoke complete" >/dev/null
printf 'y\n' | AGENT_REGISTRY_DIR="$registry_dir" "$repo_root/bin/agent-clean" "$task_id" >/dev/null

"$repo_root/bin/work" --help >/dev/null
if "$repo_root/bin/work" --help | grep -q '\.\./'; then
  printf 'Expected work help to avoid relative-path shorthand; saw:\n' >&2
  "$repo_root/bin/work" --help >&2
  exit 1
fi

work_root="$tmp/work-node"
repo_tmux_log="$tmp/work-repo-tmux.log"
dev_tmux_log="$tmp/work-dev-tmux.log"
mkdir -p "$work_root/node_account"
mkdir -p "$work_root/node_admin"
mkdir -p "$work_root/node_website"
mkdir -p "$work_root/node_plan"
mkdir -p "$work_root/node_board"
tools_root="$tmp/maestro"
mkdir -p "$tools_root"
resume_root="$tmp/resume"
mkdir -p "$resume_root"

tmux() {
  printf '%s\n' "$*" >> "$tmux_log"
  if [[ "$1" == "has-session" ]]; then
    return "${TMUX_HAS_SESSION_RESULT:-1}"
  fi
  return 0
}
export -f tmux
export tmux_log

tmux_log="$repo_tmux_log" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" node >/dev/null
tmux_log="$repo_tmux_log" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" account >/dev/null
tmux_log="$repo_tmux_log" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" admin >/dev/null
tmux_log="$repo_tmux_log" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" plan >/dev/null
tmux_log="$repo_tmux_log" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" board >/dev/null
tmux_log="$repo_tmux_log" WORK_NODE_ROOT="$work_root" WORK_TOOLS_ROOT="$tools_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" tools >/dev/null
tmux_log="$repo_tmux_log" WORK_RESUME_ROOT="$resume_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" resume >/dev/null

if ! grep -q '^select-window -t node:coding1$' "$repo_tmux_log"; then
  printf 'Expected work node to select the first named window; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if ! grep -q '^select-window -t account:coding1$' "$repo_tmux_log"; then
  printf 'Expected work to select the first named window; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if ! grep -q '^select-window -t admin:coding1$' "$repo_tmux_log"; then
  printf 'Expected work admin to select the first named window; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if ! grep -q '^select-window -t plan:coding1$' "$repo_tmux_log"; then
  printf 'Expected work plan to select the first named window; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if ! grep -q '^select-window -t board:coding1$' "$repo_tmux_log"; then
  printf 'Expected work board to select coding1; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if ! grep -q '^new-session -d -s board -n coding1 -c ' "$repo_tmux_log"; then
  printf 'Expected work board to create a coding1 window; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if ! grep -q '^new-window -t board: -n coding2 -c ' "$repo_tmux_log"; then
  printf 'Expected work board to create a coding2 window; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if [[ "$(grep -c '^new-window -t board: -n ' "$repo_tmux_log")" -ne 3 ]]; then
  printf 'Expected work board to create exactly three follow-up windows; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if ! grep -q '^select-window -t tools:Coding$' "$repo_tmux_log"; then
  printf 'Expected work tools to select Coding; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if ! grep -q '^new-session -d -s tools -n Coding -c ' "$repo_tmux_log"; then
  printf 'Expected work tools to create a Coding window; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if ! grep -q '^new-window -t tools: -n shell -c ' "$repo_tmux_log"; then
  printf 'Expected work tools to create a shell window; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if [[ "$(grep -c '^new-window -t tools: -n ' "$repo_tmux_log")" -ne 1 ]]; then
  printf 'Expected work tools to create exactly one follow-up window; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if ! grep -q '^select-window -t resume:Coding$' "$repo_tmux_log"; then
  printf 'Expected work resume to select Coding; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if ! grep -q '^new-session -d -s resume -n Coding -c ' "$repo_tmux_log"; then
  printf 'Expected work resume to create a Coding window; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if ! grep -q '^new-window -t resume: -n shell -c ' "$repo_tmux_log"; then
  printf 'Expected work resume to create a shell window; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if [[ "$(grep -c '^new-window -t resume: -n ' "$repo_tmux_log")" -ne 1 ]]; then
  printf 'Expected work resume to create exactly one follow-up window; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if grep -q ' -n test ' "$repo_tmux_log"; then
  printf 'Expected work not to create a test window; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

: > "$dev_tmux_log"
tmux_log="$dev_tmux_log" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" dev website >/dev/null

if ! grep -Fqx "new-session -d -s node-dev -n dev -c $work_root/node_website" "$dev_tmux_log"; then
  printf 'Expected work dev website to create a node-dev session in node_website; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

if ! grep -Fqx "set-window-option -t node-dev:dev remain-on-exit on" "$dev_tmux_log"; then
  printf 'Expected work dev website to enable remain-on-exit; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

if ! grep -Fqx "send-keys -t node-dev:dev.0 npm run dev C-m" "$dev_tmux_log"; then
  printf 'Expected work dev website to run npm run dev in pane 0; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

if ! grep -Fqx "select-layout -t node-dev:dev tiled" "$dev_tmux_log"; then
  printf 'Expected work dev website to tile the layout; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

if ! grep -Fqx "select-pane -t node-dev:dev.0" "$dev_tmux_log"; then
  printf 'Expected work dev website to focus pane 0; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

if ! grep -Fqx "switch-client -t node-dev" "$dev_tmux_log"; then
  printf 'Expected work dev website to switch to node-dev; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

: > "$dev_tmux_log"
tmux_log="$dev_tmux_log" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" dev website account >/dev/null

if ! grep -Fqx "split-window -t node-dev:dev -c $work_root/node_account" "$dev_tmux_log"; then
  printf 'Expected work dev website account to split a pane for node_account; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

if ! grep -Fqx "send-keys -t node-dev:dev.1 npm run dev C-m" "$dev_tmux_log"; then
  printf 'Expected work dev website account to run npm run dev in pane 1; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

if [[ "$(grep -c '^split-window -t node-dev:dev -c ' "$dev_tmux_log")" -ne 1 ]]; then
  printf 'Expected work dev website account to create exactly one extra pane; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

: > "$dev_tmux_log"
tmux_log="$dev_tmux_log" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" dev all >/dev/null

website_line="$(grep -Fnx "new-session -d -s node-dev -n dev -c $work_root/node_website" "$dev_tmux_log" | cut -d: -f1)"
account_line="$(grep -Fnx "split-window -t node-dev:dev -c $work_root/node_account" "$dev_tmux_log" | cut -d: -f1)"
admin_line="$(grep -Fnx "split-window -t node-dev:dev -c $work_root/node_admin" "$dev_tmux_log" | cut -d: -f1)"

if [[ -z "$website_line" || -z "$account_line" || -z "$admin_line" ]]; then
  printf 'Expected work dev all to create website, account, and admin panes; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

if (( website_line >= account_line || account_line >= admin_line )); then
  printf 'Expected work dev all panes in website/account/admin order; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

if [[ "$(grep -c '^split-window -t node-dev:dev -c ' "$dev_tmux_log")" -ne 2 ]]; then
  printf 'Expected work dev all to create exactly two extra panes; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

: > "$dev_tmux_log"
tmux_log="$dev_tmux_log" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" dev all shell >/dev/null

admin_line="$(grep -Fnx "split-window -t node-dev:dev -c $work_root/node_admin" "$dev_tmux_log" | cut -d: -f1)"
shell_line="$(grep -Fnx "split-window -t node-dev:dev -c $work_root" "$dev_tmux_log" | cut -d: -f1)"

if [[ -z "$shell_line" ]]; then
  printf 'Expected work dev all shell to create a shell pane in the node root; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

if (( admin_line >= shell_line )); then
  printf 'Expected work dev all shell to place the shell pane last; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

if [[ "$(grep -c '^split-window -t node-dev:dev -c ' "$dev_tmux_log")" -ne 3 ]]; then
  printf 'Expected work dev all shell to create exactly three extra panes; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

if grep -Fq "send-keys -t node-dev:dev.3 npm run dev C-m" "$dev_tmux_log"; then
  printf 'Expected work dev all shell not to run npm run dev in the shell pane; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

: > "$dev_tmux_log"
tmux_log="$dev_tmux_log" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=0 "$repo_root/bin/work" dev website >/dev/null

kill_line="$(grep -Fnx 'kill-session -t node-dev' "$dev_tmux_log" | cut -d: -f1)"
new_session_line="$(grep -Fnx "new-session -d -s node-dev -n dev -c $work_root/node_website" "$dev_tmux_log" | cut -d: -f1)"

if [[ -z "$kill_line" || -z "$new_session_line" || "$kill_line" -ge "$new_session_line" ]]; then
  printf 'Expected work dev rerun to kill and recreate node-dev; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

if WORK_NODE_ROOT="$work_root" TMUX=1 "$repo_root/bin/work" dev >/dev/null 2>"$tmp/work-dev-missing.err"; then
  printf 'Expected work dev with no targets to fail.\n' >&2
  exit 1
fi

if ! grep -q '^Missing dev targets\.$' "$tmp/work-dev-missing.err"; then
  printf 'Expected work dev with no targets to report missing targets; saw:\n' >&2
  cat "$tmp/work-dev-missing.err" >&2
  exit 1
fi

if WORK_NODE_ROOT="$work_root" TMUX=1 "$repo_root/bin/work" dev shell >/dev/null 2>"$tmp/work-dev-shell.err"; then
  printf 'Expected work dev shell to fail without an app target.\n' >&2
  exit 1
fi

if ! grep -q '^Invalid dev targets\.$' "$tmp/work-dev-shell.err"; then
  printf 'Expected work dev shell to report invalid targets; saw:\n' >&2
  cat "$tmp/work-dev-shell.err" >&2
  exit 1
fi

if WORK_NODE_ROOT="$work_root" TMUX=1 "$repo_root/bin/work" dev nope >/dev/null 2>"$tmp/work-dev-invalid.err"; then
  printf 'Expected work dev nope to fail.\n' >&2
  exit 1
fi

if ! grep -q '^Invalid dev targets\.$' "$tmp/work-dev-invalid.err"; then
  printf 'Expected work dev nope to report invalid targets; saw:\n' >&2
  cat "$tmp/work-dev-invalid.err" >&2
  exit 1
fi

unset -f tmux

printf 'Smoke tests passed.\n'
