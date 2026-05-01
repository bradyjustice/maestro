# Maestro Native macOS Product Requirements

Status: Accepted direction, May 1, 2026.

Source references:

- `docs/maestro-work-agent-integration-plan.md`
- `docs/research/hammerspoon-agentic-coding-window-management.md`
- `docs/research/jony-ive-design-principles.md`
- Existing `bin/work`, `bin/agent-*`, and `bin/iterm-*` compatibility commands

## Summary

Maestro is a Swift-native macOS control plane for Node Social Club workspaces.
The primary V1 surface is a real SwiftUI/AppKit dashboard for repos, actions,
tmux roles, agents, layouts, permissions, audit history, and command results.

The current shell commands stay usable during migration, but their long-term
role is compatibility over a Swift-owned core. Direct macOS automation is the
first automation strategy. Hammerspoon is a future optional provider that can
implement the same automation protocols after the native provider is proven.

## User And Problem

Primary user:

- Founder/operator using local terminals, tmux, Codex agents, iTerm, macOS
  automation, and Node Social Club repos for daily engineering work.

Primary problem:

- Repo sessions, dev servers, deploy commands, migrations, agent worktrees,
  review loops, and iTerm layouts are currently spread across shell scripts,
  tmux conventions, iTerm profiles, and manual memory. This creates duplicated
  behavior, brittle layout logic, inconsistent safety checks, and no primary
  surface that can show what Maestro knows before it acts.

## Goals

- Make the native dashboard the first-class operator surface.
- Make Swift packages the source of truth for repo, command, action, tmux,
  bundle, layout, risk, state, and agent metadata.
- Preserve current terminal ergonomics while moving behavior behind Maestro.
- Replace coordinate-first iTerm scripts with screen-aware native layout
  planning and execution.
- Run repo package scripts through a risk-aware command catalog.
- Target semantic tmux roles rather than raw panes.
- Make agent tasks first-class resources with durable private state.
- Add local auditability for meaningful action attempts and results.
- Support phased migration without breaking existing commands.

## Non-Goals

- Cloud-hosted service, team SaaS product, or remote control plane.
- Background daemon in the first dashboard slice.
- Launch-at-login in the first dashboard slice.
- Replacing tmux, iTerm, Codex, npm, git, Wrangler, or shell adapters all at
  once.
- Making Hammerspoon the V1 host runtime.
- Automating production deploys or migrations without explicit human
  confirmation.
- Managing unrelated macOS windows unless a selected layout profile includes
  them.

## Core Workflows

1. User opens Maestro and sees current repos, actions, permission state, agent
   state, layouts, and recent command outcomes.
2. User opens a repo workspace through the dashboard, `maestro`, `work`, or a
   future automation provider; all paths resolve to the same Swift action.
3. User starts or focuses dev servers, previews, checks, builds, migrations,
   deploys, and shell panes by repo and role.
4. User launches a cockpit bundle such as Node cockpit, backend cockpit,
   frontend cockpit, release check, or agent review loop.
5. User starts an agent task, sees task status, reviews artifacts, marks state,
   attaches/focuses the tmux target, and cleans completed worktrees.
6. User reflows iTerm, editor, Codex, and browser windows across laptop,
   external, ultrawide, and TV display setups.
7. User runs risky staging, production, remote, or destructive actions only
   after Maestro presents target context and enforces the required
   confirmation.

## Functional Requirements

Native dashboard:

- Show repos, actions, tmux roles, agents, layouts, permissions, audit history,
  and command results.
- Use catalog-backed data from the Swift core, with mock or read-only detail
  states allowed only in the first scaffold slice.
- Present clear recovery states when Accessibility, Automation, iTerm, tmux, or
  catalog state is unavailable.
- Avoid hidden magic: actions must expose target repo, role, risk,
  confirmation, and expected placement before meaningful execution.

Repository catalog:

- Define `node`, `account`, `admin`, `website`, `email`, `ux`, `board`,
  `plan`, `tools`, and `resume` workspaces.
- Each repo definition includes path, label, tmux session, default windows,
  default terminal roles, and preferred layout behavior.
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

- Expose a single action model for dashboard controls, CLI, shell adapters,
  future Hammerspoon hotkeys, overlays, and bundles.
- Every executable action has a stable ID, label, target context, risk tier,
  execution adapter, expected placement, and confirmation policy.
- Actions can be listed in machine-readable form for external adapters.

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

- Direct macOS automation uses `NSWorkspace` for app launch/focus,
  Accessibility APIs for window inventory and placement, and Apple
  Events/AppleScript only where iTerm requires it.
- Layout behavior uses current screen dimensions and the screen under the mouse
  where appropriate.
- Unmanaged windows are left alone unless the active layout profile includes
  them.
- Existing fixed-coordinate iTerm scripts are migration compatibility, not the
  future layout engine.
- A future `HammerspoonProvider` may implement the same automation protocol.

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
- Confirmation is enforced in the Swift core, not only in a UI adapter.
- Secrets are redacted from status, audit logs, and UI surfaces.
- Agent launches scrub sensitive environment variables by default.
- The dashboard favors quiet clarity, visible signifiers, cared-for empty/error
  states, and a deliberate transition from the current CLI workflow.
- CLI, dashboard, shell adapter, and future automation-provider behavior must
  stay in parity.

## Acceptance Criteria

- The Swift package builds with `swift build` on command-line tools.
- The native dashboard target loads catalog-backed repos/actions and shows
  permission status without mutating state in the scaffold slice.
- `maestro repo list --json`, `maestro command list --json`,
  `maestro action list --json`, and `maestro diagnostics --json` work.
- `work <repo>` continues to open the same workspace behavior during migration.
- Maestro can list repos, commands, actions, and future agent tasks in JSON.
- Maestro blocks unclassified risky scripts and enforces confirmation for
  production/destructive actions.
- Agent start, status, review, mark, and clean remain usable through existing
  command names until Swift-backed parity is proven.
- Audit records exist for meaningful action attempts and outcomes before risky
  execution moves fully into Swift.
- Smoke tests cover compatibility adapters for `work`, `agent-*`, and the
  Swift CLI JSON interfaces.

## Open Decisions

- Exact `.app` packaging shape after full Xcode is installed.
- Final display metadata handoff between Maestro JSON and optional external
  automation providers.
- Exact first bundle set for V1 acceptance.
- Final schema versioning strategy for Maestro state files.
- PRD approver.
