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

symlink_bin="$tmp/symlink-bin"
no_package_dir="$tmp/no-package"
mkdir -p "$symlink_bin" "$no_package_dir"
ln -s "$repo_root/bin/maestro" "$symlink_bin/maestro"
ln -s "$repo_root/bin/work" "$symlink_bin/work"

(cd "$no_package_dir" && "$symlink_bin/maestro" --help) >/dev/null
(cd "$no_package_dir" && "$symlink_bin/work" --help) >/dev/null

"$repo_root/bin/maestro" --help >/dev/null
if [[ -x "$repo_root/.build/debug/maestro-core-checks" ]]; then
  "$repo_root/.build/debug/maestro-core-checks" >/dev/null
else
  swift run --package-path "$repo_root" maestro-core-checks >/dev/null
fi
"$repo_root/bin/maestro" repo list --json > "$tmp/maestro-repos.json"
"$repo_root/bin/maestro" repo open account --dry-run --json > "$tmp/maestro-repo-open.json"
"$repo_root/bin/maestro" command list --json > "$tmp/maestro-commands.json"
"$repo_root/bin/maestro" action list --json > "$tmp/maestro-actions.json"
"$repo_root/bin/maestro" action run bundle.node.cockpit.run --dry-run --json > "$tmp/maestro-node-bundle-plan.json"
"$repo_root/bin/maestro" action run bundle.backend.cockpit.run --dry-run --json > "$tmp/maestro-backend-bundle-plan.json"
"$repo_root/bin/maestro" action run bundle.frontend.cockpit.run --dry-run --json > "$tmp/maestro-frontend-bundle-plan.json"
"$repo_root/bin/maestro" action run layout.terminal.stack.apply --dry-run --json > "$tmp/maestro-layout-action-plan.json"
"$repo_root/bin/maestro" action run agent.status.show --dry-run --json > "$tmp/maestro-blocked-action-plan.json"
"$repo_root/bin/maestro" work dev all shell --dry-run --json > "$tmp/maestro-work-dev.json"
"$repo_root/bin/maestro" layout list --json > "$tmp/maestro-layouts.json"
"$repo_root/bin/maestro" layout plan terminal.quad --screen main --json > "$tmp/maestro-layout-plan.json"
"$repo_root/bin/maestro" diagnostics --json > "$tmp/maestro-diagnostics.json"

if ! grep -q '"key" : "account"' "$tmp/maestro-repos.json"; then
  printf 'Expected maestro repo list JSON to include account; saw:\n' >&2
  cat "$tmp/maestro-repos.json" >&2
  exit 1
fi

if ! grep -q '"iTermTitle" : "work:account"' "$tmp/maestro-repo-open.json"; then
  printf 'Expected maestro repo open dry-run JSON to include the account title; saw:\n' >&2
  cat "$tmp/maestro-repo-open.json" >&2
  exit 1
fi

if ! grep -q '"id" : "account.dev"' "$tmp/maestro-commands.json"; then
  printf 'Expected maestro command list JSON to include account.dev; saw:\n' >&2
  cat "$tmp/maestro-commands.json" >&2
  exit 1
fi

if ! grep -q '"id" : "repo.account.open"' "$tmp/maestro-actions.json"; then
  printf 'Expected maestro action list JSON to include repo.account.open; saw:\n' >&2
  cat "$tmp/maestro-actions.json" >&2
  exit 1
fi

if ! grep -q '"actionID" : "bundle.node.cockpit.run"' "$tmp/maestro-node-bundle-plan.json" || ! grep -q '"actionID" : "layout.coding.workspace.apply"' "$tmp/maestro-node-bundle-plan.json"; then
  printf 'Expected node cockpit dry-run JSON to include expanded layout action; saw:\n' >&2
  cat "$tmp/maestro-node-bundle-plan.json" >&2
  exit 1
fi

if ! grep -q '"actionID" : "command.account.dev.run"' "$tmp/maestro-backend-bundle-plan.json" || ! grep -q '"tmuxPane" : "account:dev.0"' "$tmp/maestro-backend-bundle-plan.json"; then
  printf 'Expected backend cockpit dry-run JSON to include account dev command target; saw:\n' >&2
  cat "$tmp/maestro-backend-bundle-plan.json" >&2
  exit 1
fi

if ! grep -q '"actionID" : "command.website.dev.run"' "$tmp/maestro-frontend-bundle-plan.json" || ! grep -q '"displayCommand" : "npm run dev"' "$tmp/maestro-frontend-bundle-plan.json"; then
  printf 'Expected frontend cockpit dry-run JSON to include website dev command; saw:\n' >&2
  cat "$tmp/maestro-frontend-bundle-plan.json" >&2
  exit 1
fi

if ! grep -q '"actionID" : "layout.terminal.stack.apply"' "$tmp/maestro-layout-action-plan.json" || ! grep -q '"type" : "layout"' "$tmp/maestro-layout-action-plan.json"; then
  printf 'Expected layout action dry-run JSON to include terminal stack layout action; saw:\n' >&2
  cat "$tmp/maestro-layout-action-plan.json" >&2
  exit 1
fi

if ! grep -q '"runnable" : false' "$tmp/maestro-blocked-action-plan.json" || ! grep -q 'Agent action execution is not supported' "$tmp/maestro-blocked-action-plan.json"; then
  printf 'Expected blocked action dry-run JSON to include a readable blocked state; saw:\n' >&2
  cat "$tmp/maestro-blocked-action-plan.json" >&2
  exit 1
fi

if ! grep -q '"session" : "node-dev"' "$tmp/maestro-work-dev.json" || ! grep -q '"target" : "shell"' "$tmp/maestro-work-dev.json"; then
  printf 'Expected maestro work dev dry-run JSON to include node-dev and shell; saw:\n' >&2
  cat "$tmp/maestro-work-dev.json" >&2
  exit 1
fi

if ! grep -q '"id" : "terminal.six-up"' "$tmp/maestro-layouts.json"; then
  printf 'Expected maestro layout list JSON to include terminal.six-up; saw:\n' >&2
  cat "$tmp/maestro-layouts.json" >&2
  exit 1
fi

if ! grep -q '"layoutID" : "terminal.quad"' "$tmp/maestro-layout-plan.json" || ! grep -q '"slotID" : "top-left-terminal"' "$tmp/maestro-layout-plan.json"; then
  printf 'Expected maestro layout plan JSON to include terminal.quad geometry; saw:\n' >&2
  cat "$tmp/maestro-layout-plan.json" >&2
  exit 1
fi

if ! grep -q '"stateDirectory"' "$tmp/maestro-diagnostics.json"; then
  printf 'Expected maestro diagnostics JSON to include stateDirectory; saw:\n' >&2
  cat "$tmp/maestro-diagnostics.json" >&2
  exit 1
fi

if ! grep -q '"validation"' "$tmp/maestro-diagnostics.json" || ! grep -q '"ok" : true' "$tmp/maestro-diagnostics.json"; then
  printf 'Expected maestro diagnostics JSON to include passing catalog validation; saw:\n' >&2
  cat "$tmp/maestro-diagnostics.json" >&2
  exit 1
fi

if ! grep -q '"layoutCount"' "$tmp/maestro-diagnostics.json" || ! grep -q '"iTerm"' "$tmp/maestro-diagnostics.json"; then
  printf 'Expected maestro diagnostics JSON to include layout and iTerm readiness details; saw:\n' >&2
  cat "$tmp/maestro-diagnostics.json" >&2
  exit 1
fi

work_root="$tmp/work-node"
repo_tmux_log="$tmp/work-repo-tmux.log"
dev_tmux_log="$tmp/work-dev-tmux.log"
symlink_tmux_log="$tmp/work-symlink-tmux.log"
fake_bin="$tmp/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/tmux" <<'TMUX'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$tmux_log"
if [[ "${1:-}" == "has-session" ]]; then
  exit "${TMUX_HAS_SESSION_RESULT:-1}"
fi
exit 0
TMUX
chmod +x "$fake_bin/tmux"
mkdir -p "$work_root/node_account"
mkdir -p "$work_root/node_admin"
mkdir -p "$work_root/node_website"
mkdir -p "$work_root/node_plan"
mkdir -p "$work_root/node_board"
mkdir -p "$work_root/node_email"
mkdir -p "$work_root/node_ux"
tools_root="$tmp/maestro"
mkdir -p "$tools_root"
resume_root="$tmp/resume"
mkdir -p "$resume_root"
action_tmux_log="$tmp/action-tmux.log"
action_state="$tmp/action-state"

tmux() {
  printf '%s\n' "$*" >> "$tmux_log"
  if [[ "$1" == "has-session" ]]; then
    return "${TMUX_HAS_SESSION_RESULT:-1}"
  fi
  return 0
}
export -f tmux
export tmux_log

tmux_log="$symlink_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$symlink_bin/work" node >/dev/null
if ! grep -q '^select-window -t node:coding1$' "$symlink_tmux_log"; then
  printf 'Expected symlinked work node to select the first named window; saw:\n' >&2
  cat "$symlink_tmux_log" >&2
  exit 1
fi

tmux_log="$action_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" MAESTRO_STATE_DIR="$action_state" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/maestro" action run command.website.dev.run --json > "$tmp/maestro-action-run.json"

if ! grep -Fqx "new-session -d -s website -n coding1 -c $work_root/node_website" "$action_tmux_log"; then
  printf 'Expected action command run to open the website repo session; saw:\n' >&2
  cat "$action_tmux_log" >&2
  exit 1
fi

if ! grep -Fqx "send-keys -t website:dev.0 npm run dev C-m" "$action_tmux_log"; then
  printf 'Expected action command run to send npm run dev to the configured dev pane; saw:\n' >&2
  cat "$action_tmux_log" >&2
  exit 1
fi

if [[ ! -s "$action_state/audit/actions.jsonl" ]]; then
  printf 'Expected action execution to create an audit log under MAESTRO_STATE_DIR.\n' >&2
  exit 1
fi

if ! grep -q '"actionID":"command.website.dev.run"' "$action_state/audit/actions.jsonl" || ! grep -q '"outcome":"succeeded"' "$action_state/audit/actions.jsonl"; then
  printf 'Expected audit log to include command.website.dev.run success; saw:\n' >&2
  cat "$action_state/audit/actions.jsonl" >&2
  exit 1
fi

tmux_log="$repo_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" node >/dev/null
tmux_log="$repo_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" account >/dev/null
tmux_log="$repo_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" admin >/dev/null
tmux_log="$repo_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" plan >/dev/null
tmux_log="$repo_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" board >/dev/null
tmux_log="$repo_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" website >/dev/null
tmux_log="$repo_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" email >/dev/null
tmux_log="$repo_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" ux >/dev/null
tmux_log="$repo_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" WORK_TOOLS_ROOT="$tools_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" tools >/dev/null
tmux_log="$repo_tmux_log" PATH="$fake_bin:$PATH" WORK_RESUME_ROOT="$resume_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" resume >/dev/null

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

if ! grep -Fqx "new-session -d -s account -n coding1 -c $work_root/node_account" "$repo_tmux_log"; then
  printf 'Expected work account to use WORK_NODE_ROOT; saw:\n' >&2
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

if ! grep -q '^select-window -t website:coding1$' "$repo_tmux_log"; then
  printf 'Expected work website to select coding1; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if ! grep -q '^select-window -t email:coding1$' "$repo_tmux_log"; then
  printf 'Expected work email to select coding1; saw:\n' >&2
  cat "$repo_tmux_log" >&2
  exit 1
fi

if ! grep -q '^select-window -t ux:coding1$' "$repo_tmux_log"; then
  printf 'Expected work ux to select coding1; saw:\n' >&2
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

if ! grep -Fqx "new-session -d -s tools -n Coding -c $tools_root" "$repo_tmux_log"; then
  printf 'Expected work tools to use WORK_TOOLS_ROOT; saw:\n' >&2
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

if ! grep -Fqx "new-session -d -s resume -n Coding -c $resume_root" "$repo_tmux_log"; then
  printf 'Expected work resume to use WORK_RESUME_ROOT; saw:\n' >&2
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

if PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$tmp/missing-node" TMUX=1 "$repo_root/bin/work" account >/dev/null 2>"$tmp/work-repo-missing.err"; then
  printf 'Expected work account with a missing repo directory to fail.\n' >&2
  exit 1
fi

if ! grep -Fqx "Repo directory does not exist: $tmp/missing-node/node_account" "$tmp/work-repo-missing.err"; then
  printf 'Expected work missing repo directory error to stay clear; saw:\n' >&2
  cat "$tmp/work-repo-missing.err" >&2
  exit 1
fi

if PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 "$repo_root/bin/work" nope >/dev/null 2>"$tmp/work-repo-unknown.err"; then
  printf 'Expected work with an unknown repo to fail.\n' >&2
  exit 1
fi

if ! grep -q '^Unknown repo: nope$' "$tmp/work-repo-unknown.err"; then
  printf 'Expected work unknown repo error to stay clear; saw:\n' >&2
  cat "$tmp/work-repo-unknown.err" >&2
  exit 1
fi

: > "$dev_tmux_log"
tmux_log="$dev_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" dev website >/dev/null

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
tmux_log="$dev_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" dev website account >/dev/null

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
tmux_log="$dev_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" dev all >/dev/null

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
tmux_log="$dev_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=1 "$repo_root/bin/work" dev all shell >/dev/null

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
tmux_log="$dev_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 TMUX_HAS_SESSION_RESULT=0 "$repo_root/bin/work" dev website >/dev/null

kill_line="$(grep -Fnx 'kill-session -t node-dev' "$dev_tmux_log" | cut -d: -f1)"
new_session_line="$(grep -Fnx "new-session -d -s node-dev -n dev -c $work_root/node_website" "$dev_tmux_log" | cut -d: -f1)"

if [[ -z "$kill_line" || -z "$new_session_line" || "$kill_line" -ge "$new_session_line" ]]; then
  printf 'Expected work dev rerun to kill and recreate node-dev; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

: > "$dev_tmux_log"
if tmux_log="$dev_tmux_log" PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$tmp/missing-dev-root" TMUX=1 "$repo_root/bin/work" dev website >/dev/null 2>"$tmp/work-dev-missing-dir.err"; then
  printf 'Expected work dev website with a missing directory to fail.\n' >&2
  exit 1
fi

if ! grep -Fqx "Dev target directory does not exist: $tmp/missing-dev-root/node_website" "$tmp/work-dev-missing-dir.err"; then
  printf 'Expected work dev missing directory error to stay clear; saw:\n' >&2
  cat "$tmp/work-dev-missing-dir.err" >&2
  exit 1
fi

if [[ -s "$dev_tmux_log" ]]; then
  printf 'Expected work dev missing directory to fail before tmux mutation; saw:\n' >&2
  cat "$dev_tmux_log" >&2
  exit 1
fi

if PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 "$repo_root/bin/work" dev >/dev/null 2>"$tmp/work-dev-missing.err"; then
  printf 'Expected work dev with no targets to fail.\n' >&2
  exit 1
fi

if ! grep -q '^Missing dev targets\.$' "$tmp/work-dev-missing.err"; then
  printf 'Expected work dev with no targets to report missing targets; saw:\n' >&2
  cat "$tmp/work-dev-missing.err" >&2
  exit 1
fi

if PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 "$repo_root/bin/work" dev shell >/dev/null 2>"$tmp/work-dev-shell.err"; then
  printf 'Expected work dev shell to fail without an app target.\n' >&2
  exit 1
fi

if ! grep -q '^Invalid dev targets\.$' "$tmp/work-dev-shell.err"; then
  printf 'Expected work dev shell to report invalid targets; saw:\n' >&2
  cat "$tmp/work-dev-shell.err" >&2
  exit 1
fi

if PATH="$fake_bin:$PATH" WORK_NODE_ROOT="$work_root" TMUX=1 "$repo_root/bin/work" dev nope >/dev/null 2>"$tmp/work-dev-invalid.err"; then
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
