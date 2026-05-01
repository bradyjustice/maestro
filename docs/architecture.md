# Maestro Native macOS Architecture

Status: Accepted direction, May 1, 2026.

Source references:

- `docs/prd.md`
- `docs/maestro-work-agent-integration-plan.md`
- `docs/research/hammerspoon-agentic-coding-window-management.md`
- `docs/research/jony-ive-design-principles.md`
- Existing `bin/work`, `bin/agent-*`, and `bin/iterm-*` scripts

## Summary

Maestro is a Swift-native macOS app with a Swift-owned core and compatibility
shell adapters. The primary runtime surface is the `Maestro` dashboard. The
stable command-line entrypoint is a Swift `maestro` CLI. Existing shell scripts
remain public compatibility commands until each behavior reaches native parity.

Direct macOS automation is the first provider:

- `NSWorkspace` launches and focuses apps.
- Accessibility APIs inventory and place windows.
- Apple Events/AppleScript are used only where iTerm requires them.
- Hammerspoon can become an optional provider later by implementing the same
  automation protocols.

V1 still avoids a long-running daemon. App and CLI invocations load catalogs
and state, evaluate policy, perform one action or query, write state/audit
records when needed, and return.

## Runtime Shape

Topology:

```text
SwiftUI/AppKit dashboard: Maestro
Existing shell adapters: work, agent-*
Direct CLI: maestro ...
Future optional providers: Hammerspoon, hotkeys, overlays
        |
        v
Swift packages
  MaestroCore
  MaestroAutomation
  MaestroCLI
        |
        +-- repo and command catalogs
        +-- action registry and risk policy
        +-- tmux/git/process/iTerm/window automation protocols
        +-- agent state store
        +-- audit log
        |
        v
tmux / iTerm / git / npm / codex / wrangler / macOS APIs
```

Primary components:

- `Sources/MaestroApp`: native SwiftUI/AppKit dashboard target, packaged as
  the `Maestro` executable product.
- `Sources/MaestroCore`: data models, catalogs, action registry, risk policy,
  state paths, JSON error shapes, and compatibility plans.
- `Sources/MaestroAutomation`: direct macOS automation, process execution, tmux
  execution, and provider protocols.
- `Sources/MaestroCLI`: Swift command-line target, packaged as the
  `maestro-cli` executable product and exposed through `bin/maestro`.
- `maestro/config/*.json`: checked-in data-only catalogs.
- `bin/maestro`: wrapper that runs the Swift CLI from this repo.
- `bin/work` and `bin/agent-*`: compatibility adapters retained during
  migration.

## Public Interfaces

Initial CLI surface:

```text
maestro repo list --json
maestro repo open <repo> [--json] [--dry-run]

maestro command list [--repo <repo>] --json
maestro action list --json
maestro diagnostics --json

maestro agent start <repo|repo-path> <task-slug> [prompt]
maestro agent status [--json]
maestro agent review <task>
maestro agent mark <task> <state> [note]
maestro agent clean [--force] <task>
maestro agent attach <task>
maestro agent focus <task>
```

The agent commands above are target surface, not all implemented in the first
scaffold slice.

Adapter compatibility:

- `work <repo>` remains usable while Swift repo-open behavior is verified.
- `work dev <target...>` remains shell-owned until role-based Swift execution
  preserves current tmux behavior.
- `agent-start`, `agent-status`, `agent-review`, `agent-mark`, and
  `agent-clean` remain usable until Swift-backed state and command parity are
  proven.
- Existing command output remains human-readable unless a caller requests JSON.

Error shape for JSON output:

```json
{
  "ok": false,
  "error": "Human readable message",
  "code": "stable_error_code"
}
```

## Catalog And Action Model

Repository records include:

- stable repo key
- label
- path resolver
- tmux session
- default tmux windows
- default roles
- preferred layout hint
- optional package script discovery settings

Command records include:

- repo key
- script or explicit argv
- family
- risk tier
- environment target
- tmux placement role
- behavior: foreground, long-running, singleton, or repeatable
- confirmation policy
- display label and description

Action records are generated from repo, command, agent, layout, and bundle
definitions. Dashboard controls, CLI commands, shell adapters, and future
automation providers all run these same registered actions.

Package scripts are discoverable inputs. The command catalog may auto-classify
obvious local `dev`, `check`, `test`, `build`, and `preview` scripts, but
scripts containing or named for `deploy`, `prod`, `remote`, `migrate`,
`migration`, `reset`, or destructive behavior require explicit metadata before
they can run.

## State And Persistence

Default state root:

```text
$XDG_STATE_HOME/local-tools/maestro
```

Fallback:

```text
$HOME/.local/state/local-tools/maestro
```

Override:

```text
MAESTRO_STATE_DIR
```

State files:

- `agents/*.json`: active agent task records.
- `agents/archive/*.json`: cleaned agent task records.
- `reviews/*.md`: review artifacts.
- `locks/*.lock`: per-action and per-task lock files.
- `audit/actions.jsonl`: redacted action audit log.

State writes use temporary files, `0600` permissions for private task records,
and atomic rename. JSON records include schema versions so future migrations can
be explicit.

Legacy agent `.env` registry files remain readable during migration. Maestro
must not delete or rewrite legacy registry entries unless an explicit migration
or cleanup command does so.

## Tmux And Process Orchestration

Maestro targets tmux sessions, windows, and panes through semantic roles.

Role behavior:

- Missing session: create it with repo default windows.
- Missing role target: create the expected window or pane.
- Existing singleton role: focus or reuse by default.
- Explicit restart: terminate/recreate only the targeted role, not unrelated
  panes.
- Repeatable action: create a new target or run in foreground according to
  metadata.

`work dev all` compatibility maps to website, account, and admin dev-server
roles in the existing order, with optional shell role last.

## Native macOS Automation

`MaestroAutomation` owns provider protocols and the direct native provider.

Responsibilities:

- launch/focus apps through `NSWorkspace`
- inspect permission state
- request Accessibility onboarding when the UI asks
- inventory and place windows through Accessibility APIs
- use Apple Events only for iTerm behaviors not exposed through public AppKit
  or Accessibility APIs
- run tmux/git/npm/codex/wrangler through argv arrays, not `eval`

The dashboard must show permission state and recovery paths. Automation
execution must treat missing permissions as an explicit recoverable state, not
as a silent no-op.

## Agent Lifecycle

Supported states:

```text
queued
running
needs-input
review
merged
abandoned
```

Agent start flow:

```text
resolve repo
validate task slug
derive branch and task ID
create git worktree
write private task record
launch Codex in scrubbed environment unless launch is skipped
record tmux target and audit entry
```

Review flow:

```text
resolve task
run repo check command when available
run codex review --uncommitted
write private review artifact
update task state to review or needs-input
```

Clean flow:

- Only clean `merged` or `abandoned` tasks unless `--force` is present.
- Refuse dirty worktree removal without explicit destructive confirmation.
- Archive task records after successful cleanup.

Prompts and sensitive environment values are not emitted in status tables or
audit logs.

## Security Model

- Maestro core enforces risk policy and confirmations.
- UI confirmations are convenience presentation, not the security boundary.
- No Maestro-owned execution uses `eval`.
- Package scripts execute as argv arrays such as `npm run <script>`.
- Production and destructive actions require typed confirmation.
- Agent launches scrub sensitive environment variables by default.

## Packaging

The Swift package is the source build system in this repo. Full `.app` bundle
packaging requires full Xcode; command-line tools can build and test the Swift
packages and CLI. Launch-at-login is deferred and should use `SMAppService`
after the dashboard is packaged.
