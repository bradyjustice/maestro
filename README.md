# Maestro

Canonical repo-owned source for Maestro shell utilities that should be
available from one stable bin directory.

## Managed Commands

- `agent-start`
- `agent-status`
- `agent-review`
- `agent-mark`
- `agent-clean`
- `agent-lib`
- `work`
- `iterm-quad-laptop`
- `iterm-quad-left`
- `iterm-reset-left`
- `iterm-stack-laptop`
- `iterm-stack-left`

Large binaries and third-party symlinks are intentionally not managed here.

## Install

Install symlinks into `~/.local/bin`:

```bash
./install.sh
```

Move old copies from `~/bin` out of the way after backing them up:

```bash
./install.sh --cleanup-legacy --force
```

Verify the installed commands:

```bash
./doctor.sh
```

Run smoke tests:

```bash
./test/smoke.sh
```

## Configuration

The agent commands default to the Node workspace under:

```text
$HOME/Documents/Coding/node
```

Override defaults with environment variables:

- `AGENT_NODE_ROOT`
- `AGENT_WORKTREE_ROOT`
- `AGENT_REGISTRY_DIR`
- `AGENT_BASE_REF`
- `AGENT_TMUX_SESSION`
- `WORK_NODE_ROOT`
- `WORK_TOOLS_ROOT`
- `WORK_RESUME_ROOT`

Compatibility environment variable names still use `LOCAL_TOOLS_*` and
`WORK_TOOLS_ROOT` so existing shell configuration keeps working.

`~/.zshrc` only needs the install target in `PATH`:

```zsh
typeset -U path PATH
path=("$HOME/.local/bin" "${path[@]}")
export PATH
```

The iTerm layout commands require these iTerm profiles to exist:

- `Quad Laptop`
- `Quad Left`
- `Stack Laptop`
- `Stack Left`

Keep all layout profiles' `Normal Font` and `Non Ascii Font` settings in sync with the default iTerm profile. `doctor.sh` verifies that the profiles exist and match the default font settings.

On a new Mac, duplicate the default iTerm profile for each layout and rename the copies exactly as above before running `doctor.sh`.

Use `iterm-reset-left` to move existing iTerm windows from the `Quad Laptop`, `Quad Left`, `Stack Laptop`, and `Stack Left` profiles back to their scripted positions. Windows opened by the current layout scripts are tagged with their layout slot; older untagged windows fall back to profile and nearest-slot matching.
