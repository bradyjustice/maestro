# Maestro Palette

Maestro is a native macOS floating palette for a small set of terminal actions:
arrange tagged iTerm/tmux windows, create or focus named tmux targets, and send
curated argv-based commands to pane `0`.

The source of truth is:

```text
maestro/config/palette.json
```

The V1 starter config uses one tmux session, `node-dev`, with four windows:
`website`, `account`, `admin`, and `shell`.

CLI surface:

```bash
./bin/maestro config validate --json
./bin/maestro button list --json
./bin/maestro button run website.dev --dry-run --json
```

Command buttons store `argv` arrays. Maestro renders them into shell-safe text
only at the boundary where `tmux send-keys` sends the command to pane `0`.

Layouts use the visible frame of the display under the mouse. Regions and slot
units are percentages and have no gaps. Layout application only moves iTerm
windows tagged by Maestro session variables.

