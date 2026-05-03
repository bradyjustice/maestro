# Maestro Command Center

The source of truth is:

```text
maestro/config/palette.json
```

Schema v2 turns the old button palette into a command center:

- `repos` define workspace roots.
- `appTargets` define external browser/editor apps by bundle ID.
- `paneTemplates` define nested tmux pane geometry inside a terminal host.
- `terminalProfiles` optionally define stable Maestro-owned terminal surfaces.
- `screenLayouts` place terminal profiles and app zones on the active display.
- `actions` define safe operations: shell argv, stop, open URL, open repo in
  editor, and focus surface.

Terminal profiles own the tmux session, iTerm window tag, optional iTerm
profile name, and optional per-slot startup commands. A profile named `main`
in the `node` workspace maps to the tmux session `maestro.node.main`, and panes
are tagged with `@maestro.repo`, `@maestro.role`, and `@maestro.slot`.

Existing layout hosts that still define `repoID` and `paneTemplateID` remain
valid; Maestro treats the host ID as an implicit terminal profile ID. New
layouts can instead reference `terminalProfileID`:

```json
{
  "terminalProfiles": [
    {
      "id": "work",
      "label": "Work",
      "repoID": "website",
      "paneTemplateID": "work-stack",
      "itermProfileName": "Maestro Work",
      "startupCommands": [
        { "slotID": "top", "argv": ["npm", "run", "dev"] }
      ]
    }
  ],
  "screenLayouts": [
    {
      "id": "terminal-left-third",
      "label": "Terminal Left Third",
      "terminalHosts": [
        {
          "id": "work-left",
          "terminalProfileID": "work",
          "frame": { "x": 0, "y": 0, "width": 0.3333333333, "height": 1 }
        }
      ]
    }
  ]
}
```

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
moves canonical Maestro-tagged iTerm windows and the configured external app
targets. Duplicate tagged terminal windows are recorded as quarantined in
command-center state rather than closed.
