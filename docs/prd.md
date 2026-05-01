# Maestro V1 Product Requirements

Status: Draft for acceptance.

Source references:

- `docs/maestro-work-agent-integration-plan.md`
- `docs/research/hammerspoon-agentic-coding-window-management.md`
- Senior architecture review in project chat, May 1, 2026
- Existing `bin/work`, `bin/agent-*`, and `bin/iterm-*` compatibility commands

## Summary

Maestro is a local developer control plane for Node Social Club workspaces. V1
turns the current shell-first workflow into one action system for windows,
tmux, repo commands, `work`, agent tasks, and reusable cockpit bundles.

The current shell commands stay usable during migration, but their long-term
role is compatibility over Maestro-owned behavior. Hammerspoon remains the
macOS host for hotkeys, overlays, app focus, iTerm creation, and screen-aware
window layout.

## User And Problem

Primary user:

- Founder/operator using local terminals, tmux, Codex agents, Hammerspoon,
  iTerm, and Node Social Club repos for daily engineering work.

Primary problem:

- Repo sessions, dev servers, deploy commands, migrations, agent worktrees,
  review loops, and iTerm layouts are currently spread across shell scripts,
  tmux conventions, iTerm profiles, and manual memory. This creates duplicated
  behavior, brittle layout logic, inconsistent safety checks, and no single
  surface that can power hotkeys, CLI calls, overlays, and future automation.

## Goals

- Make Maestro the source of truth for repo, command, tmux, bundle, layout, and
  agent metadata.
- Provide one action registry used by UI buttons, Hammerspoon hotkeys, CLI
  commands, `work`, `agent-*`, and future bundles.
- Preserve current terminal ergonomics while moving behavior behind Maestro.
- Replace coordinate-first iTerm scripts with screen-aware layout behavior.
- Run repo package scripts through a risk-aware command catalog.
- Target semantic tmux roles rather than raw panes.
- Make agent tasks first-class resources with durable private state.
- Add local auditability for meaningful action attempts and results.
- Support phased migration without breaking existing commands.

## Non-Goals

- Cloud-hosted service, team SaaS product, or remote control plane.
- Background daemon in V1.
- Replacing tmux, iTerm, Hammerspoon, Codex, npm, git, or Wrangler.
- Automating production deploys or migrations without explicit human
  confirmation.
- Rewriting all shell scripts in one step.
- Managing unrelated macOS windows unless a selected layout profile includes
  them.
- Running coding agents without the same security and confirmation rules as CLI
  usage.

## Core Workflows

1. User opens a repo workspace through `work account`, a Maestro CLI command,
   or a Hammerspoon overlay; all paths resolve to the same Maestro action.
2. User starts or focuses dev servers, previews, checks, builds, migrations,
   deploys, and shell panes by repo and role instead of manually targeting tmux
   panes.
3. User launches a cockpit bundle such as Node cockpit, backend cockpit,
   frontend cockpit, release check, or agent review loop.
4. User starts an agent task, sees task status, reviews artifacts, marks state,
   attaches/focuses the tmux target, and cleans completed worktrees.
5. User reflows iTerm, editor, Codex, and browser windows across laptop,
   external, ultrawide, and TV display setups.
6. User runs risky staging, production, remote, or destructive actions only
   after Maestro presents target context and enforces the required
   confirmation.

## Functional Requirements

Repository catalog:

- Define `node`, `account`, `admin`, `website`, `email`, `ux`, `board`,
  `plan`, `tools`, and `resume` workspaces.
- Each repo definition includes path, label, tmux session, default windows,
  default terminal roles, and preferred app/layout behavior.
- Repo paths support environment overrides compatible with current
  `WORK_NODE_ROOT`, `WORK_TOOLS_ROOT`, and `WORK_RESUME_ROOT`.

Command catalog:

- Discover package scripts from each repo's `package.json`.
- Enrich discovered scripts with explicit metadata for family, risk,
  environment, placement role, singleton/repeatable behavior, and confirmation.
- Treat package scripts as discoverable inputs, not trusted policy.
- Block or hide risky unknown scripts until metadata classifies them.
- Cover command families including `dev`, `check`, `test`, `build`, `preview`,
  `deploy`, `migration`, `content`, `status`, `shell`, and `agent`.

Action registry:

- Expose a single action model for CLI, shell adapters, Hammerspoon hotkeys,
  overlays, and bundles.
- Every executable action has a stable ID, label, target context, risk tier,
  execution adapter, and expected placement.
- Actions can be listed in machine-readable form for Hammerspoon.

Tmux topology:

- Target semantic roles instead of pane numbers.
- Roles include `dev-server`, `preview`, `check`, `build`, `deploy`,
  `migration`, `shell`, `agent`, and `status`.
- Long-running singleton roles reuse/focus existing targets by default.
- Restarting singleton roles is explicit.

Agent tasks:

- Track repo, branch, worktree, prompt reference, state, note, check result,
  review result, review artifact, tmux session, tmux window, timestamps, and
  cleanup status.
- Support start, status, review, mark, clean, focus, attach, and reflow.
- Preserve existing `agent-*` command shapes during migration.

Windowing and layouts:

- Hammerspoon provides screen-aware layouts for terminal stack, quad, six-up,
  coding workspace, and cockpit layouts.
- Layout behavior uses current screen dimensions and the screen under the
  mouse where appropriate.
- Unmanaged windows are left alone unless the active layout profile includes
  them.
- Existing fixed-coordinate iTerm scripts are migration compatibility, not the
  future layout engine.

Bundles:

- Compose repo commands, tmux targeting, agent actions, app focus, and window
  layouts into named bundles.
- Initial candidate bundles include `node.cockpit`, `backend.cockpit`,
  `frontend.cockpit`, `account.devAndMigrate`, `website.previewDeploy`,
  `agent.reviewLoop`, and `staging.releaseCheck`.

## Safety And UX Requirements

- Safe local actions can run immediately.
- Staging or remote actions show clear target context before execution.
- Production or destructive actions require typed confirmation.
- Confirmation is enforced in the Maestro core, not only in Hammerspoon.
- Command center displays repo, command, environment, tmux target, behavior,
  and risk before meaningful remote, production, or destructive actions.
- Secrets are redacted from status, audit logs, and UI surfaces.
- Agent launches scrub sensitive environment variables by default.
- The system favors focus/reuse over duplicate long-running panes.
- CLI, hotkey, and overlay behavior must stay in parity.

## Acceptance Criteria

- `work <repo>` continues to open the same workspace behavior through Maestro.
- Maestro can list repos, commands, actions, and agent tasks in JSON.
- Maestro can run safe local package scripts in the intended tmux role.
- Maestro blocks unclassified risky scripts and enforces confirmation for
  production/destructive actions.
- Dev server and preview actions reuse/focus their role by default and restart
  only when requested.
- Hammerspoon can launch/focus workspaces and reflow iTerm/editor/Codex/browser
  windows through Maestro-backed actions.
- Agent start, status, review, mark, and clean remain usable through existing
  command names and Maestro-owned state.
- Existing active agent registry entries can be read or migrated without losing
  review artifacts or worktrees.
- Audit records exist for meaningful action attempts and outcomes.
- Smoke tests cover compatibility adapters for `work` and `agent-*`.

## Open Decisions

- Final config file format and exact directory layout under `maestro/`.
- Final display metadata handoff between Maestro JSON and the Hammerspoon UI.
- Exact first bundle set for V1 acceptance.
- Final schema versioning strategy for Maestro state files.
- PRD acceptance date and approver.
