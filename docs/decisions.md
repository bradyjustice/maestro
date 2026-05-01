# Maestro Decisions

Use this file to keep important decisions out of chat history. Record accepted
choices here before implementation depends on them.

## Accepted Decisions

### Canonical Planning Docs

Decision: Maestro planning is split into `docs/prd.md`,
`docs/architecture.md`, `docs/implementation-slices.md`, and
`docs/decisions.md`.

Rationale: The project needs node_board-style durable planning docs instead of
a single chat-derived integration note.

### Maestro Owns The Source Of Truth

Decision: Maestro owns repo, command, action, tmux role, bundle, layout policy,
and agent metadata. Hammerspoon, hotkeys, shell adapters, and future UI
surfaces call into Maestro-owned actions.

Rationale: One action system prevents drift between CLI behavior, hotkeys,
overlays, and scripts.

### Local CLI Core

Decision: V1 uses a dependency-light `bin/maestro` Node CLI core, not a
Hammerspoon-only implementation.

Rationale: Node gives safer structured JSON handling, atomic state management,
and testable policy logic while fitting the existing local Node workflow.

### No Daemon In V1

Decision: Maestro V1 is process-per-action and does not run a background daemon.

Rationale: A daemon adds lifecycle, observability, and recovery complexity
before the action model is proven.

### Hammerspoon Is An Adapter

Decision: Hammerspoon owns hotkeys, overlays, screen-aware window layout, app
focus, and iTerm window creation. It does not own source-of-truth action policy
or durable state.

Rationale: Hammerspoon is the right macOS automation host, but policy and state
need to be testable outside the UI layer.

### Preserve Shell Compatibility

Decision: `work` and `agent-*` remain user-facing compatibility commands during
migration.

Rationale: Existing terminal ergonomics should not break while behavior moves
behind Maestro.

### Package Scripts Are Inputs, Not Policy

Decision: Package scripts may be discovered automatically, but execution policy
comes from Maestro metadata.

Rationale: Script names and shell bodies are not enough to safely infer deploy,
production, remote, migration, or destructive behavior.

### Unknown Risky Scripts Are Blocked

Decision: Scripts named for or containing deploy, prod, remote, migrate,
migration, reset, or destructive behavior are blocked until explicitly
classified.

Rationale: Conservative defaults are required because this tool can reach
Cloudflare, D1, production deploys, and destructive reset helpers.

### Core-Enforced Confirmations

Decision: Risk-tier confirmations are enforced in Maestro core, not only in
Hammerspoon.

Rationale: CLI and adapter callers need the same safety boundary.

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

Rationale: Duplicate dev servers, previews, and agents waste resources and
make local state hard to reason about.

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

Rationale: Screen-aware Hammerspoon geometry is more durable across laptop,
external, ultrawide, and TV display setups.

### Slice Review Gate

Decision: Every implementation slice needs read-only review before the next
slice starts.

Rationale: Maestro will become a high-leverage local control plane, so contract
drift and safety regressions should be caught early.

## Defaults Pending Confirmation

### Config Format

Default: Use checked-in JSON or `.mjs` config modules under `maestro/`, with a
preference for JSON where data-only definitions are sufficient.

### Hammerspoon Install Shape

Default: Keep Hammerspoon config repo-owned and symlink or install it through
local-tools, matching the existing local-tools install pattern.

### First Bundle Set

Default: Ship Node cockpit, backend cockpit, frontend cockpit, and agent review
loop first.

## Decisions To Lock Before Coding

- Final config file format and directory layout.
- Exact first V1 bundle set.
- Schema versioning and migration command names for Maestro state.
- PRD acceptance.
- Architecture acceptance.
