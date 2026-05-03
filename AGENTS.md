# Maestro Agent Guidance

## Project Purpose
Maestro is a local macOS coordination tool for opening repo workspaces, arranging terminal windows, running safe local commands, and tracking coding-agent tasks.

## Architecture Boundaries
- `MaestroCore` owns catalog models, validation, path resolution, agent records, state-store mutation, and serializable plans/results.
- `MaestroAutomation` owns process execution, tmux/git interaction, native macOS automation, and executable workflow orchestration.
- `MaestroCLI` owns argument parsing, terminal output, and confirmation prompts.
- `MaestroApp` owns dashboard presentation and calls the same Swift executors as the CLI.
- `bin/` wrappers preserve public commands and should delegate into Swift unless a compatibility shim is explicitly needed.

## Implementation-Slice Discipline
Keep changes narrowly scoped to the requested workflow. Prefer adding focused plan/result types over ad hoc dictionaries, and keep new behavior testable in `maestro-core-checks` or `test/smoke.sh`.

## Commands To Run
- `swift build`
- `swift run maestro-core-checks`
- `./test/smoke.sh`

Run the full set after changes that touch core models, CLI behavior, wrappers, app controls, or automation execution.

## Safety Constraints
Only safe local operations may execute without a future typed production-confirmation milestone. Remote, production, destructive, and unclassified package actions must remain blocked by catalog policy.

## State And Compatibility Cautions
New agent starts write Swift JSON records under `$MAESTRO_STATE_DIR/agents/active`; archived Swift records move to `$MAESTRO_STATE_DIR/agents/archive`. Legacy `.env` records under `AGENT_REGISTRY_DIR` remain readable and mutable, but do not reserialize prompt or secret material.

## Shell Adapter Rules
Do not add shell `eval` to Maestro-owned execution paths. Run modeled commands through argv arrays. The public shell wrappers should stay thin and should not duplicate workflow logic already owned by Swift.

## macOS Automation Rules
Layout application depends on Accessibility and Apple Events readiness. Planning should remain prompt-free; applying layouts may be blocked when permissions are unavailable. Keep force cleanup and other risky flows out of the app.

## What Not To Touch Casually
Do not churn catalog IDs, task ID formats, branch naming, tmux session/window conventions, state paths, wrapper names, or legacy environment variable names without an explicit migration task.

## Review Focus
Review agent-workflow changes for unsafe command execution, prompt/secret serialization, destructive cleanup behavior, legacy compatibility, and whether app/CLI paths share the same Swift-backed implementation.
