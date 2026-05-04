# Maestro

Maestro is a local macOS workspace arranger. The current sliver is intentionally
small: one Maestro repo workspace, one Maestro-tagged iTerm window on the left
third, and Browser plus VS Code sharing the right two-thirds.

## Commands

```bash
./bin/maestro config validate --json
./bin/maestro arrange --dry-run --json
./bin/maestro arrange
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

The repo config file is:

```text
maestro/config/workspace.json
```

Schema v3 contains the workspace `id`, `label`, and `path`, plus concrete app
settings for Browser and VS Code. `maestro arrange` does not open URLs, open
repos, or run dev commands. It creates or reuses the tagged iTerm window,
attaches it to `maestro_maestro_main`, and only moves Browser or VS Code when
those apps already have windows.

## Install

Install the public wrapper into `~/.local/bin`:

```bash
./install.sh
```

Verify:

```bash
./doctor.sh
```
