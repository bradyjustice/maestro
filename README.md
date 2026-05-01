# Maestro

Maestro is becoming a Swift-native macOS control plane for local Node Social
Club workspaces. The native app and Swift CLI own the long-term core; the
existing shell commands stay in place as compatibility adapters during the
migration.

## Managed Commands

- `maestro`
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

## Native Scaffold

Swift package products:

- `Maestro`: SwiftUI/AppKit dashboard target.
- `maestro-cli`: Swift CLI product, exposed publicly through `bin/maestro`.
- `MaestroCore`: catalogs, models, action registry, risk policy, and state
  paths.
- `MaestroAutomation`: macOS automation and process/tmux provider protocols.

Run the CLI through the repo wrapper:

```bash
./bin/maestro --help
./bin/maestro repo list --json
./bin/maestro command list --json
./bin/maestro action list --json
./bin/maestro diagnostics --json
```

Build and test:

```bash
swift build
swift run maestro-core-checks
./test/smoke.sh
```

Full `.app` bundle packaging requires full Xcode. Command-line tools can build
and run the Swift package targets. This machine's command-line toolchain does
not currently expose `XCTest`/`Testing`, so the core checks run as an executable
test harness.

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

## Configuration

Catalogs live under:

```text
maestro/config/
```

Runtime state lives under:

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

The compatibility commands keep their existing environment variables:

- `AGENT_NODE_ROOT`
- `AGENT_WORKTREE_ROOT`
- `AGENT_REGISTRY_DIR`
- `AGENT_BASE_REF`
- `AGENT_TMUX_SESSION`
- `WORK_NODE_ROOT`
- `WORK_TOOLS_ROOT`
- `WORK_RESUME_ROOT`

`~/.zshrc` only needs the install target in `PATH`:

```zsh
typeset -U path PATH
path=("$HOME/.local/bin" "${path[@]}")
export PATH
```

## iTerm Compatibility

The existing iTerm layout commands are retained as compatibility scripts while
native screen-aware layout automation is built.

The scripts require these iTerm profiles to exist:

- `Quad Laptop`
- `Quad Left`
- `Stack Laptop`
- `Stack Left`

Keep all layout profiles' `Normal Font` and `Non Ascii Font` settings in sync
with the default iTerm profile. `doctor.sh` verifies that the profiles exist
and match the default font settings.
