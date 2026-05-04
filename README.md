# Maestro

Maestro is a native macOS command center for local workspace coordination. It
owns Maestro-tagged iTerm windows, per-host tmux sessions, app focus zones, and
curated safe commands.

The current config schema is v2. It models repos, app targets, screen layouts,
terminal hosts, pane templates, pane slots, and actions. Legacy v1
`palette.json` files remain readable through a migration adapter, and
`maestro button ...` stays available as an alias for command and stop actions.

## Commands

```bash
./bin/maestro config validate --json
./bin/maestro layout list --json
./bin/maestro layout apply terminal-left-third --dry-run --json
./bin/maestro action list --json
./bin/maestro action run account.check --dry-run --json
./bin/maestro pane list --layout terminal-left-third --dry-run --json
./bin/maestro button list --json
./bin/maestro button run website.dev --dry-run --json
```

Build and checks:

```bash
swift build
swift run maestro-core-checks
./test/smoke.sh
```

## Debug Mode

Set `MAESTRO_DEBUG` to `1`, `true`, or `yes` to enable structured diagnostics on stderr when launching the UI app:

```bash
MAESTRO_DEBUG=1 swift run Maestro
```

To write the JSONL log to a specific path:

```bash
MAESTRO_DEBUG=1 MAESTRO_DEBUG_LOG=~/maestro-debug.jsonl swift run Maestro
```

## Configuration

The only repo config file is:

```text
maestro/config/palette.json
```

Repo paths support `~` expansion and relative paths. Terminal hosts use
`sessionStrategy: "perHost"` and create sessions such as
`maestro_node_main`. Shell actions store argv arrays and render shell text only
at the `tmux send-keys` boundary.

## Install

Install the public wrapper into `~/.local/bin`:

```bash
./install.sh
```

Verify:

```bash
./doctor.sh
```
