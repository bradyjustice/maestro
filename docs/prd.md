# Maestro Native macOS iTerm Layout PRD

Status: Draft reboot PRD, May 11, 2026.

Primary branch: `pivot`

Archive reference: the pre-reboot local `main` snapshot is preserved at
`origin/archive/main-2026-05-11`, pointing to
`59d686306771f70b06fdbf4753a8ad1257dfd991`.

## Context

Maestro is being restarted from a scratch `pivot` branch. The previous project
direction grew into a broad local workspace control plane: repo catalogs,
command execution, tmux roles, agent workflows, action safety, browser/editor
placement, and iTerm layout automation. That work is useful historical input,
but it is not the product boundary for this reboot.

The new product should start smaller and be useful sooner. V1 is a native
macOS utility for creating, owning, arranging, remembering, and reflowing iTerm
windows. It should solve the daily pain of putting terminal windows into
predictable places on different displays without reviving the old workspace
automation surface.

The first two known display environments are:

- 5120 x 1440 desktop ultrawide monitor.
- 3456 x 2234 2025 MacBook Pro 16-inch display.

The product must handle these displays differently when the usable horizontal
space changes what layout density makes sense. It should not pretend every
layout can be universal across every screen.

## Purpose

Maestro is a native macOS iTerm window layout utility for repeatable, relative,
display-aware terminal placement.

The core promise is simple: choose or edit a layout, let Maestro create the
needed iTerm windows, and trust Maestro to put the windows back into the right
relative positions later.

## User And Problem

Primary user:

- A macOS developer/operator who uses iTerm heavily across a laptop screen and
  external displays.

Primary problem:

- Terminal window placement is repetitive and fragile. Manual resizing wastes
  time, fixed coordinates fail across displays, and existing iTerm windows are
  easy to mix up. The user needs a small native app that knows which iTerm
  windows it created, remembers the intended layout, and can re-apply that
  layout when the screen environment changes.

Current pain points:

- A layout that works on a 5120 x 1440 ultrawide may be too dense on a laptop.
- Fixed pixel coordinates do not adapt to menu bar, dock, display scaling, or
  different screen sizes.
- Manual iTerm windows should not be moved unexpectedly.
- Window ownership needs to survive app relaunches so the user can reflow or
  restore the same working set.
- The first version should make terminal placement dependable before it tries
  to run commands, manage repos, or orchestrate tmux.

## Product Goals

- Create and arrange one or more Maestro-owned iTerm windows from the native
  app.
- Remember the iTerm windows Maestro created so they can be re-arranged,
  snapped to different slots, restored, or removed from the owned set.
- Use relative layout geometry based on the active display's visible frame
  instead of fixed pixel coordinates.
- Support display-class variants so the same named layout can behave
  differently on ultrawide, laptop, and default displays.
- Provide fast daily controls from a menu bar utility.
- Provide a main app window for owned-window status, layout editing, display
  variants, and recovery actions.
- Include a visual rectangle-canvas editor for creating and modifying layouts.
- Leave all unowned iTerm windows untouched.
- Keep V1 focused on window placement and ownership, with no command runner,
  repo automation, or tmux dependency.

## Non-Goals

V1 does not include:

- tmux session, window, or pane orchestration.
- Running shell commands in new windows.
- Repo or workspace opening.
- Browser, editor, Codex, or non-iTerm window placement.
- Hammerspoon integration.
- Cloud sync or team/shared layouts.
- Background agent workflows.
- GitHub, Cloudflare, deploy, migration, or package-script automation.
- Auto-adoption of existing iTerm windows.
- Manual adoption of existing iTerm windows.
- A desktop overlay that draws directly over the real screen.
- A general-purpose macOS window manager.

These exclusions are intentional. They keep the first product loop small enough
to make the ownership and layout model reliable.

## Product Surfaces

### Menu Bar Utility

The menu bar utility is the daily control surface. It should be available
without keeping the main window open.

Required menu bar actions:

- Deploy a selected layout.
- Reflow the current owned windows onto the active display.
- Restore the last applied layout.
- Open the main Maestro window.
- Show a compact status summary for owned windows and permissions.
- Quit Maestro.

The menu bar surface should favor direct action. It should not become a dense
configuration UI.

### Main App Window

The main app window is the configuration and recovery surface.

Required main-window areas:

- Owned windows: list the iTerm windows Maestro created, their status, assigned
  layout slot, last seen time, and current display when known.
- Layouts: list starter and custom layouts, with display-class variants.
- Visual editor: show a scaled canvas for the selected display class and allow
  editing layout slots as relative rectangles.
- Display targeting: show the active display and allow explicit display
  selection when multiple displays are connected.
- Permissions: show macOS Accessibility and Automation permission state with
  recovery guidance.
- Apply preview: show which windows will be created, moved, restored, or left
  unchanged before applying when useful.

The main window should be compact and practical. It is a tool surface, not a
landing page.

## Core Workflows

### Deploy A Starter Layout

1. User selects a starter layout from the menu bar or main window.
2. Maestro resolves the target display, defaulting to the active display.
3. Maestro chooses the best layout variant for the display class.
4. Maestro creates any missing owned iTerm windows needed by the layout.
5. Maestro tags each created iTerm window as owned by Maestro.
6. Maestro moves owned windows into the layout slots.
7. Maestro persists the ownership and last-applied layout state.

Success means the requested number of iTerm windows are visible on the target
display and arranged according to the selected layout variant.

### Reflow Existing Owned Windows

1. User changes display setup, moves to the laptop, or connects the ultrawide.
2. User chooses Reflow.
3. Maestro inventories its owned windows.
4. Maestro resolves the active display and display class.
5. Maestro applies the last selected layout variant to the existing owned
   windows.

Success means Maestro moves only owned windows and adapts placement to the
current display class.

### Edit A Layout

1. User opens the main window and selects a layout.
2. User chooses a display class variant, such as laptop or ultrawide.
3. Maestro shows a scaled rectangle canvas representing the visible display
   frame.
4. User adds, moves, resizes, or deletes slot rectangles.
5. Maestro validates the layout for overlap, minimum size, and bounds.
6. User saves the layout variant.
7. User previews or applies it to owned iTerm windows.

The editor should work with relative geometry. It should not require the user
to think in pixel coordinates.

### Snap A Window To A Different Slot

1. User opens the owned-window list.
2. User selects a Maestro-owned iTerm window.
3. User assigns it to a different slot in the current layout.
4. Maestro moves that window to the chosen slot and persists the assignment.

This workflow supports quick correction without rebuilding the whole layout.

### Recover A Missing Window

1. Maestro starts or refreshes its inventory.
2. A previously owned window is no longer found.
3. Maestro marks the window as missing.
4. User can recreate the window, remove it from the registry, or ignore it.

Maestro should not silently replace missing windows unless the user deploys a
layout that requires missing windows to be created.

## Ownership Model

Maestro manages only iTerm windows it creates.

An owned window is an iTerm window that:

- was created by Maestro;
- has a stable Maestro-owned window ID;
- is tagged in iTerm with Maestro-specific metadata where iTerm allows it;
- appears in Maestro's local ownership registry;
- can be inventoried, moved, focused, forgotten, or recreated by Maestro.

The registry should persist enough data to recover after app relaunch:

- Maestro window ID.
- Human label.
- iTerm window ID when available.
- iTerm session ID or alternate identifier when available.
- Ownership tag value written into iTerm when available.
- Assigned layout ID.
- Assigned slot ID.
- Last display class.
- Last target display identity when available.
- Last applied relative frame.
- Last observed absolute frame.
- Created time.
- Last seen time.
- Status: active, missing, closed, or stale.

The app must tolerate iTerm identifiers changing or becoming unavailable. iTerm
metadata tags and local registry data should work together; neither should be
the only recovery mechanism.

Unowned iTerm windows are out of bounds. Maestro may list a warning that
unowned windows exist, but it must not move, close, resize, or retag them in
V1.

## Layout Model

Layouts are named collections of slots. A slot is a relative rectangle inside
the target display's visible frame.

Each slot should include:

- Slot ID.
- Label.
- Relative x, y, width, and height values from 0.0 to 1.0.
- Minimum usable width and height guidance.
- Optional preferred window label.

Each layout should include:

- Layout ID.
- Label.
- Description.
- Supported window count.
- Display-class variants.
- Default variant.
- Slot definitions per variant.

Required starter layouts:

- Single: one terminal occupying the primary usable area.
- Side-by-side: two terminals split horizontally.
- Stack: two terminals split vertically.
- Quad: four terminals in a two-by-two grid.

Display classes:

- `ultrawide`: intended for wide desktop monitors such as 5120 x 1440.
- `laptop`: intended for built-in MacBook displays such as 3456 x 2234.
- `default`: fallback when no specific class matches.

The exact display-class thresholds can be refined during implementation, but
the PRD expectation is that width, height, aspect ratio, and visible frame all
matter. A 5120 x 1440 ultrawide should be allowed denser horizontal layouts
than a laptop screen.

## Display Targeting

Default targeting:

- Use the active display.
- Active display means the display under the mouse or, when that is
  unavailable, the display containing the focused/frontmost relevant app.

Required behavior:

- When one display is connected, use it without prompting.
- When multiple displays are connected, show the resolved active display in
  the main window.
- Allow explicit display selection before applying a layout.
- Persist the last applied display class with the layout state.
- Recompute absolute frames from relative slots every time a layout is applied.

The app should use the display's visible frame rather than raw full-screen
bounds so the menu bar and dock do not cause unintended placement.

## iTerm Behavior

V1 creates plain iTerm windows.

Required behavior:

- Launch iTerm if needed.
- Create missing windows needed for the selected layout.
- Use the default iTerm profile unless the user later configures a profile.
- Open a normal shell.
- Apply Maestro ownership tags as soon as practical after creation.
- Move windows by setting iTerm window bounds.
- Focus a selected owned window when requested.

V1 must not:

- run a command after creating a window;
- create or attach tmux sessions;
- assume specific iTerm profiles exist;
- require shell startup scripts;
- modify manual iTerm windows.

## Permissions And Error States

Maestro depends on macOS permissions to inspect and move windows.

The app should clearly detect and explain:

- Accessibility permission missing.
- Automation or Apple Events permission missing for iTerm.
- iTerm not installed.
- iTerm not launchable.
- Window creation failed.
- Window move failed.
- Expected owned window missing.
- Layout invalid.
- No display available.

Errors should be recoverable when possible. The user should know whether the
problem is a permissions issue, an iTerm issue, a missing window, or a layout
configuration issue.

## Safety Requirements

- Never move unowned iTerm windows in V1.
- Never close an owned window without a direct user action.
- Never run shell commands in V1-created windows.
- Never infer ownership from title alone.
- Always recompute placement from relative layout data before applying.
- Keep local state readable and recoverable.
- Provide a way to forget stale owned-window records.
- Avoid destructive migrations while the ownership registry format is still
  young.

## Data And Persistence

V1 should store local user data outside the repo. The exact path belongs in the
implementation design, but the PRD expects a normal macOS app-support or user
state location.

Persisted data should include:

- Owned-window registry.
- Saved layouts.
- Display-class variants.
- Last applied layout.
- Last selected display class.
- Basic app preferences.

Checked-in defaults should include the starter layouts. User-edited layouts
should be local user data rather than repo-tracked runtime state.

## Acceptance Criteria

V1 is acceptable when:

- The native macOS app launches and provides both a menu bar utility and a main
  configuration window.
- The app can create one, two, and four Maestro-owned iTerm windows.
- The app can apply the Single, Side-by-side, Stack, and Quad starter layouts.
- The app creates missing owned windows automatically when a selected layout
  needs more windows.
- The app tags and persists created iTerm windows as Maestro-owned.
- The app can relaunch, rediscover owned iTerm windows, and reflow them.
- The app can mark missing owned windows and let the user recreate or forget
  them.
- The app leaves manually created iTerm windows untouched.
- The app applies layout geometry relative to the active display visible frame.
- The app supports distinct laptop, ultrawide, and default display-class
  variants.
- The app can apply a useful layout on both the 5120 x 1440 ultrawide and the
  3456 x 2234 MacBook Pro display.
- The main window includes a rectangle-canvas editor for changing and saving a
  custom layout variant.
- The user can snap an owned window to a different layout slot.
- The app reports missing Accessibility, Automation, iTerm, and layout
  validation errors in a way that points to a concrete recovery action.

## Later Scope

These ideas are explicitly later scope unless promoted by a future PRD update:

- Manual adoption of existing iTerm windows.
- Auto-detection or suggested adoption of iTerm windows.
- tmux session and pane integration.
- Running configured commands in terminal windows.
- Repo-specific workspaces.
- Browser and editor placement.
- Global keyboard shortcuts.
- Import/export of layout packs.
- Hammerspoon provider.
- Cloud sync.
- Team/shared configuration.
- A live desktop overlay editor.
- Full command palette.

## Implementation Notes For The Next Planning Step

The next document after this PRD should be a concise architecture plan. It
should decide:

- Swift package and app target structure.
- Menu bar lifecycle.
- Registry storage path and schema.
- iTerm ownership tagging mechanism.
- Accessibility and Apple Events automation boundaries.
- Layout validation rules.
- Display-class detection thresholds.
- Starter layout defaults.
- Manual test matrix for the ultrawide and laptop displays.

Do not start by rebuilding the old command center. The first implementation
should prove the smaller loop: create owned iTerm windows, place them with
relative layout geometry, remember them, and reflow them safely.
