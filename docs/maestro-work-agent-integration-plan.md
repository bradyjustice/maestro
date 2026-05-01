# Maestro Work + Agent Integration Plan

Status: Superseded by the canonical Maestro planning docs.

Canonical docs:

- `docs/prd.md`
- `docs/architecture.md`
- `docs/implementation-slices.md`
- `docs/decisions.md`

This file is retained as source context for the original integration direction.
Do not treat it as the implementation source of truth. Details below, including
Lua-owned metadata and the original phase breakdown, may be superseded by the
canonical docs.

## Summary

Maestro should become the long-term control plane for windows, tmux, `work`, agents, and repo commands. The existing shell command names stay during migration, but they become compatibility adapters over Maestro instead of separately owned behavior.

The core idea is a single Maestro action system: UI buttons, hotkeys, CLI calls, bundles, `work`, and `agent-*` all trigger the same registered actions.

## Core Model

- **Repository Catalog**: Maestro owns repo definitions for `website`, `account`, `admin`, `ux`, `email`, `tools`, `plan`, `board`, and related workspaces, including path, default tmux session, default terminal roles, and app/layout preferences.
- **Command Catalog**: package scripts are auto-discovered from each repo's `package.json`, then enriched with Lua metadata:
  - command family: `dev`, `check`, `test`, `build`, `deploy`, `migration`, `content`, `agent`
  - risk: `safe`, `remote`, `prod`, `destructive`
  - placement role: `dev-server`, `preview`, `deploy`, `migration`, `shell`, `agent`, `status`
  - behavior: foreground, long-running, singleton, or repeatable
- **Tmux Topology**: Maestro targets semantic roles, not raw panes. Example: run `npm run dev` for `account` in the `dev-server` role, and Maestro creates or reuses the correct tmux session/window/pane.
- **Agent Tasks**: agents become first-class Maestro resources with repo, branch, worktree, prompt, state, review artifact, and tmux target. They remain attachable to any visible terminal slot.

## Phased Implementation

- **Phase 1: Windowing + Core Schemas**
  - Build dynamic screen-aware window layouts, active grid state, right-side terminal defaults, and action registry.
  - Define repo, command, tmux-role, bundle, and agent-task schemas.
  - Wire only a few basic actions: terminal stack/quad/six, attach existing tmux session, and launch a simple workspace.
- **Phase 2: Work Migration**
  - Move `work` repo/session definitions into Maestro.
  - Generate command catalog from `package.json` scripts in `node_website`, `node_account`, `node_admin`, `node_ux`, and `node_email`.
  - Add role-based tmux command execution for dev servers, checks, deploys, migrations, previews, and shell panes.
  - Convert `work` into a thin adapter that calls Maestro actions.
- **Phase 3: Agent Migration**
  - Move agent task metadata and lifecycle into Maestro.
  - Support start, status, review, mark, clean, focus, attach, and reflow from the command center.
  - Convert `agent-*` scripts into thin adapters while preserving terminal usability.
- **Phase 4: Macro Bundles**
  - Compose repo commands, agent actions, tmux targeting, and window layouts into reusable bundles.
  - Examples: `node.cockpit`, `account.devAndMigrate`, `website.previewDeploy`, `agent.reviewLoop`, `staging.releaseCheck`.
  - Support progressive expansion: start with two terminals, add two, then add two more while reflowing browser/editor space.

## Safety And UX Rules

- Use **risk-tiered confirmations**:
  - safe local commands can run immediately,
  - staging/remote commands show clear target context,
  - prod or destructive commands require typed confirmation.
- Command execution defaults to **role-based slots**, with manual override from the overlay.
- Long-running role commands like `dev` or `preview` reuse/focus existing panes unless explicitly restarted.
- Unmanaged windows stay untouched unless the active profile includes them.
- The command center displays repo, command, environment, target tmux role, and risk before running meaningful remote/prod actions.

## Test Plan

- Unit-test layout solving across 16:10, 16:9, 21:9, 32:9, and 32:9 plus LGTV.
- Test package-script discovery and curated metadata overlays.
- Test tmux role creation/reuse for dev, deploy, migration, shell, and agent targets.
- Test risk confirmation behavior for prod deploys, prod migrations, and reset commands.
- Smoke-test compatibility adapters for `work` and `agent-*`.
- Manual acceptance: one overlay can launch workspaces, run repo commands, attach agents, reflow terminals, and keep CLI/hotkey/UI behavior in parity.

## Assumptions

- Full migration is the long-term target, but implementation stays phased.
- Maestro owns the source of truth for repo/session/agent metadata.
- Package scripts remain discoverable inputs, not the whole product model.
- Hammerspoon remains the V1 host runtime for overlay, hotkeys, windows, and iTerm control.
