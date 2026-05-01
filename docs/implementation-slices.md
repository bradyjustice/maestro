# Maestro Implementation Slices

Status: Draft for acceptance.

Use this file to assign one bounded implementation scope at a time after the
PRD and architecture are accepted. Do not run parallel write agents by default.

Implementation preconditions:

- `docs/prd.md` is accepted with date and approver.
- `docs/architecture.md` is accepted with date and approver.
- Any decision that changes CLI shape, state location, or compatibility
  behavior is recorded in `docs/decisions.md`.
- Previous implementation slice, if any, has passed read-only review.

## Slice 1: Maestro Core Scaffold

Write scope:

- `bin/maestro`
- initial `maestro/` modules and config files
- minimal tests and smoke-test wiring

Acceptance:

- `maestro --help` works.
- `maestro repo list --json` returns configured repo records.
- Config loads without external dependencies.
- JSON errors follow the architecture shape.
- Existing scripts are not yet migrated.

Reviewer focus:

- CLI boundaries.
- Dependency-light Node implementation.
- No daemon behavior.
- No behavior moved from `work` or `agent-*` before compatibility tests exist.

Gate to next slice:

- Read-only review is complete and findings are resolved, deferred, or recorded
  as blockers.

## Slice 2: Repository Catalog And `work` Open Compatibility

Write scope:

- repo catalog
- `maestro repo open <repo>`
- `work <repo>` adapter path
- smoke tests for existing workspace opens

Acceptance:

- `work node`, `work account`, `work admin`, `work plan`, `work board`,
  `work website`, `work email`, `work ux`, `work tools`, and `work resume`
  preserve current tmux session/window behavior.
- Environment overrides for node, tools, and resume roots still work.
- iTerm title behavior remains compatible.

Reviewer focus:

- Exact compatibility with current `work` behavior.
- Repo path validation.
- No regression in tmux attach/switch behavior.

Gate to next slice:

- Read-only review is complete and findings are resolved, deferred, or recorded
  as blockers.

## Slice 3: Command Catalog And Risk Policy

Write scope:

- package script discovery
- command metadata overlays
- risk classification and confirmation enforcement
- command list JSON output

Acceptance:

- `maestro command list --json` shows discovered scripts and policy metadata.
- Safe local scripts can be classified automatically.
- Deploy, prod, remote, migration, reset, and destructive-looking scripts are
  blocked until explicitly classified.
- Production and destructive actions require typed confirmation in Maestro
  core.

Reviewer focus:

- Conservative default policy.
- No `eval`.
- Stable metadata that Hammerspoon can display.
- Clear operator context for staging, production, and destructive actions.

Gate to next slice:

- Read-only review is complete and findings are resolved, deferred, or recorded
  as blockers.

## Slice 4: Tmux Role Execution

Write scope:

- tmux role resolver
- `maestro command run <repo> <script>`
- singleton reuse/focus and explicit restart
- `work dev <target...>` adapter path

Acceptance:

- Dev, preview, check, build, deploy, migration, shell, agent, and status roles
  can be represented.
- Long-running singleton roles reuse or focus by default.
- `--restart` restarts only the targeted role.
- `work dev website`, `work dev website account`, `work dev all`, and
  `work dev all shell` preserve current ordering and shell-pane behavior.

Reviewer focus:

- Role targeting instead of raw pane assumptions.
- Stale session/window/pane recovery.
- No accidental termination of unrelated panes.

Gate to next slice:

- Read-only review is complete and findings are resolved, deferred, or recorded
  as blockers.

## Slice 5: Hammerspoon Action And Layout Adapter

Write scope:

- Hammerspoon modules under repo-owned config path if introduced
- action listing and running through `maestro action ...`
- screen-aware iTerm/editor/Codex/browser layout functions
- doctor checks for Hammerspoon and iTerm expectations

Acceptance:

- Hammerspoon can list Maestro actions in a chooser or command center.
- Safe local actions run from Hammerspoon.
- Risky actions show context and defer to Maestro core confirmation.
- Terminal stack, quad, six-up, and coding workspace layouts use screen-aware
  geometry.
- Unmanaged windows are left untouched unless the active layout includes them.

Reviewer focus:

- Hammerspoon remains adapter-only.
- Layout math across laptop, external, ultrawide, and TV displays.
- No hard-coded coordinate regression.

Gate to next slice:

- Read-only review is complete and findings are resolved, deferred, or recorded
  as blockers.

## Slice 6: Agent State Store

Write scope:

- Maestro agent JSON state store
- private review artifact paths
- legacy `.env` registry reader
- state transition tests

Acceptance:

- Active tasks are represented as `0600` JSON records with schema versions.
- Existing legacy `.env` task records can be read for status and review.
- State writes are atomic.
- Prompts and secrets are excluded from status and audit output.
- Agent states match the current lifecycle: queued, running, needs-input,
  review, merged, abandoned.

Reviewer focus:

- No loss of existing worktrees or review artifacts.
- Private file permissions.
- Migration behavior is read-safe before any rewrite behavior exists.

Gate to next slice:

- Read-only review is complete and findings are resolved, deferred, or recorded
  as blockers.

## Slice 7: Agent Command Migration

Write scope:

- `maestro agent start|status|review|mark|clean|attach|focus`
- `agent-*` compatibility adapters
- agent smoke tests

Acceptance:

- Existing `agent-start`, `agent-status`, `agent-review`, `agent-mark`, and
  `agent-clean` command shapes still work.
- Agent launch creates worktrees, writes task records, opens tmux targets, and
  scrubs sensitive environment variables by default.
- Review runs repo checks and `codex review --uncommitted`, then records the
  artifact and state.
- Clean refuses unsafe removal unless current state and confirmation rules are
  satisfied.

Reviewer focus:

- Git/worktree safety.
- Environment scrubbing parity with current scripts.
- Review artifact reliability.
- Dirty worktree cleanup refusal.

Gate to next slice:

- Read-only review is complete and findings are resolved, deferred, or recorded
  as blockers.

## Slice 8: Macro Bundles

Write scope:

- bundle definitions
- `maestro action list|run`
- initial cockpit and review-loop bundles
- focused tests for bundle expansion

Acceptance:

- Bundles compose repo, command, agent, tmux, app-focus, and layout actions.
- Initial bundles include Node cockpit plus backend/frontend variants.
- Bundle expansion is visible in dry-run or JSON output before execution.
- Risk policy applies to every action inside a bundle.

Reviewer focus:

- No policy bypass through bundles.
- Deterministic action ordering.
- Useful progressive expansion for terminal layouts.

Gate to next slice:

- Read-only review is complete and findings are resolved, deferred, or recorded
  as blockers.

## Slice 9: Hardening, Documentation, And Rollout

Write scope:

- README and docs updates
- doctor checks
- audit log review helpers
- final smoke checklist
- old script deprecation notes where appropriate

Acceptance:

- Smoke tests pass for `work`, `agent-*`, and Maestro JSON interfaces.
- Doctor checks cover Maestro config, state directory, tmux, git, Codex,
  Hammerspoon, iTerm, and required profiles.
- Documentation explains install, state paths, risk policy, compatibility
  adapters, and recovery from stale tmux/agent state.
- Existing fixed-coordinate iTerm scripts are documented as compatibility only.

Reviewer focus:

- Migration clarity.
- Recovery paths.
- No secrets in docs or logs.
- Clear acceptance checklist before relying on Maestro daily.

Gate to release:

- Read-only review is complete and findings are resolved, deferred, or recorded
  as blockers.
