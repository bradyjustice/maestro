# Maestro

Maestro is a native macOS floating palette for local terminal operations.

V1 does three things:

- Arrange Maestro-tagged iTerm/tmux windows with percentage layouts.
- Create or focus named tmux targets in the shared `node-dev` session.
- Send curated safe argv commands to pane `0`, with native confirmations for
  busy panes and stop buttons.

## Commands

```bash
./bin/maestro config validate --json
./bin/maestro button list --json
./bin/maestro button run website.dev --dry-run --json
```

Build and checks:

```bash
swift build
swift run maestro-core-checks
./test/smoke.sh
```

## Configuration

The only repo config file is:

```text
maestro/config/palette.json
```

Roots support `~` expansion and relative paths. Targets define a tmux
`session`, `window`, `pane`, and `cwd` from those roots. Commands are stored as
argv arrays.

## Install

Install the public wrapper into `~/.local/bin`:

```bash
./install.sh
```

Verify:

```bash
./doctor.sh
```

