# Maestro Native macOS Implementation Slices

Status: Accepted direction, May 1, 2026.

Use this file to assign one bounded implementation scope at a time. Do not run
parallel write agents by default.

Implementation preconditions:

- `docs/prd.md` reflects the accepted Swift-native direction.
- `docs/architecture.md` reflects the accepted Swift-native direction.
- Any decision that changes CLI shape, state location, automation strategy, or
  compatibility behavior is recorded in `docs/decisions.md`.
- Previous implementation slice, if any, has passed read-only review.

## Slice 0: Planning Redirect

Write scope:

- `docs/prd.md`
- `docs/architecture.md`
- `docs/decisions.md`
- `docs/implementation-slices.md`
- related README notes if needed

Acceptance:

- Swift-native dashboard, Swift core, and direct macOS automation are the
  accepted direction.
- Hammerspoon is documented as a future optional provider, not the V1 host.
- Existing shell commands remain compatibility adapters during migration.
- State paths remain `$XDG_STATE_HOME/local-tools/maestro`,
  `$HOME/.local/state/local-tools/maestro`, and `MAESTRO_STATE_DIR`.

Reviewer focus:

- No remaining canonical doc points to Node as the target implementation.
- No remaining canonical doc makes Hammerspoon the V1 host.
- Migration is explicit and preserves current command names.

## Slice 1: Native App And Package Scaffold

Write scope:

- `Package.swift`
- `Sources/MaestroApp`
- `Sources/MaestroCore`
- `Sources/MaestroAutomation`
- `Sources/MaestroCLI`
- `maestro/config/*.json`
- focused tests

Acceptance:

- Swift package defines `Maestro`, `MaestroCore`, `MaestroAutomation`, and
  `maestro-cli` products, with `bin/maestro` preserving the public command
  name.
- Native dashboard shell loads catalog-backed repo/action data.
- Dashboard shows permission status cards, repo/action/agent sections, layouts,
  bundles, and non-mutating detail views.
- Direct macOS automation protocols exist, with a native provider for app
  launch/focus and permission checks.
- Checked-in JSON catalogs define repos, commands, actions, layouts, and
  bundles.
- `swift run maestro-core-checks` passes for core catalog and risk-policy
  behavior on command-line tools; migrate to `swift test` when the local
  toolchain exposes `XCTest` or Swift Testing.

Reviewer focus:

- App shell is useful and restrained, not a marketing page.
- Core models are Codable and stable enough for app/CLI/tests.
- No risky execution moves behind unreviewed native code.

## Slice 2: Swift Core Models And Catalogs

Write scope:

- Codable schemas for repos, commands, actions, agents, risk tiers, tmux roles,
  layouts, bundles, audit events, and JSON error output.
- Catalog loading and validation.
- Package script discovery and conservative risk classification.
- Tests for catalog shape, state paths, risk policy, action generation, and JSON
  errors.

Acceptance:

- Maestro can load checked-in JSON catalogs without external dependencies.
- Package scripts are discovered when repo package files exist.
- Safe local scripts can be classified automatically.
- Deploy, prod, remote, migration, reset, and destructive-looking scripts are
  blocked or require explicit confirmation.
- JSON error output follows the architecture shape.

Reviewer focus:

- Conservative risk defaults.
- Schema versioning.
- Codable stability.
- No `eval`.

## Slice 3: Swift CLI Parity Foundation

Write scope:

- `bin/maestro`
- `Sources/MaestroCLI`
- install, doctor, and smoke-test wiring

Acceptance:

- `maestro --help` works.
- `maestro repo list --json` returns configured repo records.
- `maestro repo open <repo> --dry-run --json` returns a tmux-compatible plan.
- `maestro command list --json` returns configured and discovered commands.
- `maestro action list --json` returns generated actions.
- `maestro diagnostics --json` reports config path, state path, catalog counts,
  and native permission state.
- Existing scripts are not yet required to delegate to Swift.

Reviewer focus:

- CLI boundaries.
- Dependency-light Swift implementation.
- JSON shape stability.
- No behavior moved from `work` or `agent-*` before compatibility tests exist.

## Slice 4: Work Migration

Write scope:

- repo-open execution
- `work <repo>` adapter path
- role-backed `work dev <target...>`
- smoke tests for existing workspace opens and dev pane ordering

Acceptance:

- `work node`, `work account`, `work admin`, `work plan`, `work board`,
  `work website`, `work email`, `work ux`, `work tools`, and `work resume`
  preserve current tmux session/window behavior.
- Environment overrides for node, tools, and resume roots still work.
- `work dev website`, `work dev website account`, `work dev all`, and
  `work dev all shell` preserve current ordering and shell-pane behavior.
- iTerm title behavior remains compatible.

Reviewer focus:

- Exact compatibility with current `work` behavior.
- Repo path validation.
- Role targeting instead of raw pane assumptions.
- No accidental termination of unrelated panes after singleton behavior
  changes.

## Slice 5: Direct macOS Automation Provider

Write scope:

- native window inventory and layout planning
- screen-aware layout execution
- permission onboarding states
- iTerm Apple Events where native APIs are insufficient
- doctor checks for permissions and iTerm expectations

Acceptance:

- Dashboard shows Accessibility and Automation recovery states.
- Terminal stack, quad, six-up, and coding workspace layouts use screen-aware
  geometry.
- Layouts work across laptop, external, ultrawide, and TV display setups.
- Unmanaged windows are left untouched unless the active layout includes them.
- Missing permissions produce clear recoverable errors.

Reviewer focus:

- Direct macOS provider stays behind protocols.
- Layout math and screen selection.
- No hard-coded coordinate regression.
- Apple Events are scoped to iTerm gaps.

## Slice 6: Agent State Store

Write scope:

- Swift agent JSON state store
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

## Slice 8: Bundles And Cockpit Workflows

Write scope:

- bundle definitions
- `maestro action list|run`
- dashboard bundle controls
- Node cockpit, backend cockpit, frontend cockpit, and agent review loop
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

## Slice 9: Packaging And Hardening

Write scope:

- README and docs updates
- `install.sh`, `doctor.sh`, and uninstall updates
- app bundle packaging when full Xcode is installed
- audit log review helpers
- final smoke checklist
- old script deprecation notes where appropriate

Acceptance:

- Smoke tests pass for `work`, `agent-*`, and Maestro JSON interfaces.
- Doctor checks cover Maestro config, state directory, tmux, git, Codex,
  iTerm, native permissions, and required profiles.
- Documentation explains install, state paths, risk policy, compatibility
  adapters, permissions, and rollback.
- Existing fixed-coordinate iTerm scripts are documented as compatibility only.
- Launch-at-login remains deferred or is implemented through `SMAppService`.

Reviewer focus:

- Migration clarity.
- Recovery paths.
- No secrets in docs or logs.
- Clear acceptance checklist before relying on Maestro daily.
