# Maestro Command Center

The source of truth is:

```text
maestro/config/palette.json
```

Schema v2 turns the old button palette into a command center:

- `repos` define workspace roots.
- `appTargets` define external browser/editor apps by bundle ID.
- `paneTemplates` define nested tmux pane geometry inside a terminal host.
- `screenLayouts` place terminal hosts and app zones on the active display.
- `actions` define safe operations: shell argv, stop, open URL, open repo in
  editor, and focus surface.

Terminal hosts use `sessionStrategy: "perHost"`. A host named `main` in the
`node` workspace maps to the tmux session `maestro.node.main`, and panes are
tagged with `@maestro.repo`, `@maestro.role`, and `@maestro.slot`.

CLI surface:

```bash
./bin/maestro config validate --json
./bin/maestro layout list --json
./bin/maestro layout apply terminal-left-third --dry-run --json
./bin/maestro action list --json
./bin/maestro action run account.check --dry-run --json
./bin/maestro pane list --layout terminal-left-third --dry-run --json
./bin/maestro pane swap main.top main.bottom --layout terminal-left-third --dry-run --json
```

Compatibility aliases remain:

```bash
./bin/maestro button list --json
./bin/maestro button run website.dev --dry-run --json
```

Layouts use the visible frame of the display under the mouse. App zones may
overlap intentionally, so Browser and VS Code can share the same two-thirds
frame while macOS app focus decides what is frontmost. Layout application only
moves Maestro-tagged iTerm windows and the configured external app targets.
