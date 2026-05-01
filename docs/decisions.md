# Maestro Decisions

Use this file to keep important decisions out of chat history. Record accepted
choices here before implementation depends on them.

## Accepted Decisions

### Canonical Planning Docs

Decision: Maestro planning is split into `docs/prd.md`,
`docs/architecture.md`, `docs/implementation-slices.md`, and
`docs/decisions.md`.

Rationale: The project needs durable planning docs instead of a single
chat-derived integration note.

### Native Dashboard Is The Primary Surface

Decision: V1 is a Swift-native macOS app. The first primary surface is the
`Maestro` dashboard, not a Hammerspoon overlay or a Node CLI.

Rationale: Maestro should make repo, action, permission, agent, layout, risk,
and result state visible before it automates high-leverage local workflows.

### Swift Core Now

Decision: Core models, catalogs, action registry, risk policy, state paths,
automation protocols, and JSON output are implemented in Swift packages.

Rationale: Swift keeps the app, CLI, automation provider, tests, and state
contracts in one native toolchain.

### Swift CLI Wrapper

Decision: The stable `maestro` command is a Swift CLI, launched by
`bin/maestro` during development.

Rationale: Existing shell commands need a durable CLI adapter while behavior
migrates into the Swift core.

### Direct macOS Automation First

Decision: V1 automation uses native macOS APIs first: `NSWorkspace`,
Accessibility APIs, and Apple Events/AppleScript only for iTerm-specific gaps.

Rationale: A native app should own its macOS automation path directly before
adding optional external providers.

### Hammerspoon Is Future Optional

Decision: Hammerspoon is no longer the V1 host. It can later become a modular
`HammerspoonProvider` that implements Maestro automation protocols.

Rationale: Keeping Hammerspoon optional avoids making Lua and an external host
the primary product boundary while preserving a future hotkey/overlay path.

### No Daemon In First Dashboard Slice

Decision: Maestro does not run a background daemon in the first native slice.

Rationale: A daemon adds lifecycle, observability, and recovery complexity
before the dashboard and action model are proven.

### Preserve Shell Compatibility

Decision: `work` and `agent-*` remain user-facing compatibility commands during
migration.

Rationale: Existing terminal ergonomics should not break while behavior moves
behind Maestro.

### Checked-In JSON Catalogs

Decision: Use checked-in JSON files under `maestro/config/` for data-only repo,
command, action, layout, and bundle definitions.

Rationale: Catalogs should be readable by tests, the CLI, the dashboard, and
future providers without executing code.

### Package Scripts Are Inputs, Not Policy

Decision: Package scripts may be discovered automatically, but execution policy
comes from Maestro metadata and Swift risk classification.

Rationale: Script names and shell bodies are not enough to safely infer deploy,
production, remote, migration, or destructive behavior.

### Unknown Risky Scripts Are Blocked

Decision: Scripts named for or containing deploy, prod, remote, migrate,
migration, reset, or destructive behavior are blocked until explicitly
classified.

Rationale: Conservative defaults are required because this tool can reach
Cloudflare, D1, production deploys, and destructive reset helpers.

### Core-Enforced Confirmations

Decision: Risk-tier confirmations are enforced in Maestro core, not only in the
dashboard or a future automation adapter.

Rationale: CLI, dashboard, shell adapter, and external-provider callers need
the same safety boundary.

### No Eval For Maestro Execution

Decision: Maestro-owned execution uses argv arrays. It does not use `eval` for
package scripts or configured commands.

Rationale: Command policy must not be bypassed or made ambiguous by shell
string evaluation.

### Semantic Tmux Roles

Decision: Maestro targets semantic tmux roles instead of raw pane indexes.

Rationale: Roles make command placement durable as layouts change and allow
singleton reuse/focus behavior.

### Singleton Reuse By Default

Decision: Long-running singleton roles reuse or focus existing targets by
default. Restart requires an explicit flag or action.

Rationale: Duplicate dev servers, previews, and agents waste resources and make
local state hard to reason about.

### JSON Agent State

Decision: Agent task state moves toward private JSON records with atomic writes
and schema versions.

Rationale: JSON is safer for structured state than shell-sourced `.env` files
and avoids accidental code execution during reads.

### Legacy Agent Registry Read Compatibility

Decision: Maestro must read existing agent `.env` registry entries during
migration before any destructive or rewrite behavior is introduced.

Rationale: Active worktrees and review artifacts cannot be lost during the
state-store transition.

### Default State Directory

Decision: Maestro state defaults to `$XDG_STATE_HOME/local-tools/maestro` or
`$HOME/.local/state/local-tools/maestro`, with `MAESTRO_STATE_DIR` override.

Rationale: Runtime state should not live in the repo, and the override keeps
tests and recovery workflows straightforward.

### Secret Scrubbing

Decision: Agent launches scrub sensitive environment variables by default.
Secret inheritance requires explicit opt-in.

Rationale: Agent worktrees and review loops should not receive production or
vendor credentials accidentally.

### Redacted Audit Log

Decision: Maestro records JSONL audit entries for meaningful action attempts
and results, with prompts, secrets, and sensitive command values redacted.

Rationale: Local auditability is useful for debugging and trust, but logs must
not become a secret sink.

### Fixed iTerm Coordinates Are Compatibility Only

Decision: Existing fixed-coordinate iTerm scripts are retained as compatibility
inputs, not the future layout engine.

Rationale: Screen-aware native layout planning is more durable across laptop,
external, ultrawide, and TV display setups.

### Slice Review Gate

Decision: Every implementation slice needs read-only review before the next
slice starts.

Rationale: Maestro will become a high-leverage local control plane, so contract
drift and safety regressions should be caught early.

## Defaults Pending Confirmation

### First Bundle Set

Default: Ship Node cockpit, backend cockpit, frontend cockpit, and agent review
loop first.

### App Packaging

Default: Use SwiftPM for package and CLI development now. Add Xcode project or
workspace packaging when full Xcode is installed and app bundle signing is
needed.

### Launch At Login

Default: Defer launch-at-login. Use `SMAppService` later instead of ad hoc
login item scripts.

## Decisions To Lock Before Risky Execution Migration

- Exact first V1 bundle set.
- Schema versioning and migration command names for Maestro state.
- App bundle packaging and signing shape.
- Audit event retention policy.
- PRD approver.
- Architecture approver.
