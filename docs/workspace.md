# Maestro Workspace

The source of truth is:

```text
maestro/config/workspace.json
```

Schema v3 is the simple workspace sliver:

- `workspace.id`, `workspace.label`, and `workspace.path` define the single repo.
- `browser` defines the browser app target.
- `vsCode` defines the VS Code app target.

CLI surface:

```bash
./bin/maestro config validate --json
./bin/maestro arrange --dry-run --json
./bin/maestro arrange
```

`maestro arrange` creates or reuses one Maestro-tagged iTerm window, ensures the
`maestro_maestro_main` tmux session rooted at the workspace path, and places the
terminal on the left third of the active display. Browser and VS Code are moved
to the right two-thirds only when they already have windows.
