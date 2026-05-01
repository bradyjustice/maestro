# Maestro V1 Architecture

Status: Draft for acceptance.

Source references:

- `docs/prd.md`
- `docs/maestro-work-agent-integration-plan.md`
- `docs/research/hammerspoon-agentic-coding-window-management.md`
- Existing `bin/work`, `bin/agent-*`, and `bin/iterm-*` scripts
- Node Social Club package script conventions in sibling repos

## Summary

Maestro is a local control-plane core with multiple adapters. The authoritative
runtime is a dependency-light `bin/maestro` CLI implemented with Node `.mjs`
modules. Hammerspoon is the macOS presentation adapter for hotkeys, overlays,
screen detection, app focus, and iTerm window control. Existing shell commands
become compatibility adapters over the same Maestro action system.

V1 intentionally avoids a daemon. Each invocation loads config and state,
evaluates policy, performs one action or query, writes durable state and audit
records when needed, and exits.

## Runtime Shape

Topology:

```text
Hammerspoon hotkeys/overlay
Existing shell adapters: work, agent-*
Direct CLI: maestro ...
        |
        v
bin/maestro Node CLI core
        |
        +-- repo and command catalogs
        +-- action registry and risk policy
        +-- tmux orchestration
        +-- agent state store
        +-- audit log
        |
        v
tmux / iTerm / git / npm / codex / wrangler
```

Primary components:

- `bin/maestro`: stable user and adapter entrypoint.
- `maestro/`: repo-owned config, catalog definitions, policy metadata, and
  core modules.
- `work`: compatibility adapter for workspace and dev commands.
- `agent-*`: compatibility adapters for agent lifecycle commands.
- Hammerspoon config: invokes Maestro JSON actions and handles windows.
- iTerm: terminal window host.
- tmux: repo/session/process topology.

## Public Interfaces

Initial CLI surface:

```text
maestro repo list --json
maestro repo open <repo>

maestro command list [--repo <repo>] --json
maestro command run <repo> <script> [--restart] [--confirm <token>]

maestro action list --json
maestro action run <action-id> [--json] [--confirm <token>]

maestro agent start <repo|repo-path> <task-slug> [prompt]
maestro agent status [--json]
maestro agent review <task>
maestro agent mark <task> <state> [note]
maestro agent clean [--force] <task>
maestro agent attach <task>
maestro agent focus <task>
```

Adapter compatibility:

- `work <repo>` maps to `maestro repo open <repo>`.
- `work dev <target...>` maps to Maestro command and tmux role actions.
- `agent-start`, `agent-status`, `agent-review`, `agent-mark`, and
  `agent-clean` map to `maestro agent ...`.
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
- preferred terminal profile or layout hints
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

Action records are generated from repo, command, agent, tmux, layout, and bundle
definitions. UI buttons, hotkeys, bundles, CLI commands, `work`, and `agent-*`
all run these same registered actions.

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
write task record
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

## Hammerspoon And Windowing

Hammerspoon is an adapter, not the source of truth for action policy or state.

Responsibilities:

- bind hotkeys
- render command center or chooser UI
- call `maestro action list --json`
- call `maestro action run ...`
- enforce additional UI confirmation where helpful
- create/focus iTerm windows
- arrange app windows using screen-aware geometry
- keep unmanaged windows untouched unless a layout profile includes them

Layout engine requirements:

- derive frames from active display dimensions
- support screen-under-mouse placement
- support terminal stack, quad, six-up, coding workspace, and cockpit layouts
- handle laptop-only, external display, ultrawide, and TV display setups
- retain current iTerm profile compatibility while phasing out fixed
  coordinates

## Security Model

- Maestro core enforces risk policy and confirmations.
- Hammerspoon confirmations are convenience UI, not the security boundary.
- No Maestro-owned execution uses `eval`.
- Package scripts execute as argv arrays such as `npm run <script>`.
- Explicit non-package commands must be represented as argv arrays in config.
- Agent launch scrubs sensitive environment variables by default.
- Secret inheritance requires an explicit opt-in.
- Audit logs include action context, risk, target, result, and redacted command
  summaries only.
- Production and destructive actions require typed confirmation tokens tied to
  the target action.

## Testing Strategy

Unit tests:

- repo path resolution and environment overrides
- package script discovery and metadata overlay precedence
- risk classification and blocking of unclassified risky scripts
- confirmation token requirements
- redaction of prompts, secrets, and command summaries
- agent JSON read/write, legacy `.env` read, state transitions, and archive

Tmux tests with mocked `tmux`:

- session creation
- role creation
- singleton reuse/focus
- explicit restart
- `work dev` compatibility ordering
- stale target recovery

Adapter smoke tests:

- `work <repo>`
- `work dev website`, `work dev all`, and `work dev all shell`
- each `agent-*` command shape
- JSON output for Hammerspoon callers

Manual acceptance:

- Hammerspoon lists actions from Maestro.
- Safe local command runs from the overlay.
- Production/destructive command is blocked without typed confirmation.
- Workspace launch and layout reflow work across active displays.
- Agent task can be started, reviewed, marked, focused, and cleaned.

## Risks And Open Decisions

- Config file format and module boundary need final acceptance before coding.
- Hammerspoon overlay implementation may be incremental if command-line parity
  lands first.
- Legacy `.env` task import must be careful to avoid corrupting active work.
- Long-running process detection can drift from tmux reality and needs stale
  target recovery from the first implementation.
- Architecture acceptance date and approver are still required before coding.
