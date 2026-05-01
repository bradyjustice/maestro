# Design Principles For Maestro

Status: Working design source for the native dashboard direction.

This note captures the product-design stance Maestro should follow while it
migrates from shell utilities into a native macOS control plane.

## Principles

- Design the whole experience, not only the visible screen. Install, first
  launch, permission recovery, command confirmation, failure handling, and
  rollback all need the same care as the dashboard.
- Prefer quiet clarity over density for its own sake. The app should feel like
  an operator console: calm, scannable, and deliberate.
- Make signifiers visible. Actions need clear labels, icons, state, risk,
  target repo, and expected placement before they run.
- Treat error states as designed states. Missing permissions, missing repos,
  stale tmux targets, blocked commands, and failed checks should explain the
  recoverable next state without blaming the user.
- Preserve continuity. The current CLI workflow is valuable muscle memory, so
  the native app should reveal and gradually absorb it instead of abruptly
  replacing it.
- Keep controls honest. A button should either do the thing, show the required
  confirmation, or be visibly unavailable with a reason.
- Let restraint carry trust. Avoid decorative surfaces that compete with the
  operational state Maestro needs to expose.

## Dashboard Implications

- First screen is the dashboard, not a landing page.
- Repos, actions, agents, layouts, permissions, and recent outcomes are all
  first-class dashboard areas.
- Permission cards are operational status, not onboarding marketing.
- Risk badges and blocked states are part of normal action presentation.
- Non-mutating detail views are acceptable during scaffolding, but they must
  look like real product surfaces rather than placeholders.
