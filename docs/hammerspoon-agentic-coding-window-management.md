# Hammerspoon Window Management Strategy for Agentic Coding on macOS

## Purpose

This guide explains how to use **Hammerspoon** as a programmable window-management layer for a developer or agentic-coding workflow on macOS.

The core idea is:

```text
tmux owns repo/session/process organization.
iTerm owns terminal windows/profiles.
Hammerspoon owns hotkeys, screen-aware placement, app focus, launch/reset commands, and layout orchestration.
```

This lets you move away from separate coordinate-based scripts for desktop vs laptop screens and toward a single dynamic layout system that adapts to the active display.

---

## Why Hammerspoon Fits This Workflow

Hammerspoon is useful when you want more than simple snapping. It lets you write Lua code that can:

- Move focused windows into halves, quadrants, thirds, or custom regions
- Arrange all visible iTerm windows into a quad or stacked layout
- Launch or focus apps like iTerm, VS Code, Codex, Safari, or Chrome
- Run shell commands like `work account`, `work website`, or `agent-status`
- Use AppleScript when iTerm-specific behavior is needed
- Detect the current screen frame dynamically
- React when monitors are connected or disconnected
- Provide global keyboard shortcuts for all of the above

The main benefit is that layout logic becomes **intent-based** rather than **pixel-coordinate-based**.

Instead of:

```text
Put window at {0, 38, 1028, 683}
```

You use:

```text
Put this window in the top-left quadrant of the screen under my mouse.
```

---

## Recommended Architecture

Keep your existing command-line and tmux workflow. Use Hammerspoon above it.

```text
local-tools/
  work
  agent-start
  agent-status
  agent-review
  agent-mark
  agent-clean
  iterm-quad-laptop
  iterm-quad-left
  iterm-stack-laptop
  iterm-stack-left
  iterm-reset-left

tmux
  repo sessions
  shell processes
  long-running agents
  dev servers

iTerm
  terminal windows
  profiles
  fonts/colors

Hammerspoon
  global hotkeys
  window movement
  screen-aware layouts
  app focus
  workspace/cockpit commands
```

The long-term goal is not to throw away your scripts. It is to **move geometry out of shell scripts and into Hammerspoon**.

---

## Desired End State

A mature setup could look like this:

```text
⌃⌥⌘W       Start Node cockpit
⌃⌥⌘Q       Arrange iTerm windows in quad layout
⌃⌥⌘A       Arrange iTerm windows in stacked layout
⌃⌥⌘P       Arrange coding workspace
⌃⌥⌘T       Focus iTerm
⌃⌥⌘V       Focus VS Code
⌃⌥⌘C       Focus Codex
⌃⌥⌘O       Focus browser
⌃⌥⌘1       Open work account
⌃⌥⌘2       Open work website
⌃⌥⌘3       Open work email
⌃⌥⌘4       Open work ux
⌃⌥⌘Space   Show interactive grid
⌃⌥⌘R       Reload Hammerspoon config
```

The workflow becomes:

```text
Press one hotkey to open or focus a repo session.
Press one hotkey to snap terminals into a quad.
Press one hotkey to switch to Codex, VS Code, browser, or iTerm.
Press one hotkey to restore the whole work cockpit.
```

---

# Phase 1: Basic Hammerspoon Setup

Create your Hammerspoon config:

```bash
mkdir -p ~/.hammerspoon
code ~/.hammerspoon/init.lua
```

Start with this foundation:

```lua
-- ~/.hammerspoon/init.lua

hs.window.animationDuration = 0

local hyper = {"cmd", "alt", "ctrl"}

local units = {
  full = {x = 0,   y = 0,   w = 1,   h = 1},

  left = {x = 0,   y = 0,   w = 0.5, h = 1},
  right = {x = 0.5, y = 0,   w = 0.5, h = 1},

  top = {x = 0,   y = 0,   w = 1,   h = 0.5},
  bottom = {x = 0, y = 0.5, w = 1,   h = 0.5},

  topLeft = {x = 0,   y = 0,   w = 0.5, h = 0.5},
  topRight = {x = 0.5, y = 0,   w = 0.5, h = 0.5},
  bottomLeft = {x = 0, y = 0.5, w = 0.5, h = 0.5},
  bottomRight = {x = 0.5, y = 0.5, w = 0.5, h = 0.5},

  leftTwoThirds = {x = 0, y = 0, w = 0.6667, h = 1},
  rightThird = {x = 0.6667, y = 0, w = 0.3333, h = 1},

  center = {x = 0.1, y = 0.08, w = 0.8, h = 0.84},
}

local function frameFromUnit(screen, unit)
  local f = screen:frame()
  return {
    x = f.x + (f.w * unit.x),
    y = f.y + (f.h * unit.y),
    w = f.w * unit.w,
    h = f.h * unit.h,
  }
end

local function moveWindowToUnit(win, unit, screen)
  if not win then return end
  screen = screen or win:screen() or hs.screen.mainScreen()
  win:setFrame(frameFromUnit(screen, unit))
end

local function moveFocused(unit)
  moveWindowToUnit(hs.window.focusedWindow(), unit)
end

-- Simple snapping
hs.hotkey.bind(hyper, "F", function() moveFocused(units.full) end)
hs.hotkey.bind(hyper, "H", function() moveFocused(units.left) end)
hs.hotkey.bind(hyper, "L", function() moveFocused(units.right) end)
hs.hotkey.bind(hyper, "K", function() moveFocused(units.top) end)
hs.hotkey.bind(hyper, "J", function() moveFocused(units.bottom) end)

-- Quad snapping
hs.hotkey.bind(hyper, "Y", function() moveFocused(units.topLeft) end)
hs.hotkey.bind(hyper, "U", function() moveFocused(units.topRight) end)
hs.hotkey.bind(hyper, "B", function() moveFocused(units.bottomLeft) end)
hs.hotkey.bind(hyper, "N", function() moveFocused(units.bottomRight) end)

-- Coding layout shapes
hs.hotkey.bind(hyper, "M", function() moveFocused(units.center) end)
hs.hotkey.bind(hyper, "G", function() hs.grid.show() end)

-- Reload config
hs.hotkey.bind(hyper, "R", function()
  hs.reload()
end)

hs.alert.show("Hammerspoon loaded")
```

This gives you immediate window-control shortcuts:

```text
⌃⌥⌘F = fullscreen/maximized
⌃⌥⌘H = left half
⌃⌥⌘L = right half
⌃⌥⌘K = top half
⌃⌥⌘J = bottom half
⌃⌥⌘Y = top-left
⌃⌥⌘U = top-right
⌃⌥⌘B = bottom-left
⌃⌥⌘N = bottom-right
⌃⌥⌘G = interactive grid
⌃⌥⌘R = reload Hammerspoon
```

---

# Phase 2: App Launch and Focus

Add fast app switching:

```lua
local function launchOrFocus(appName)
  hs.application.launchOrFocus(appName)
end

hs.hotkey.bind(hyper, "T", function() launchOrFocus("iTerm") end)
hs.hotkey.bind(hyper, "V", function() launchOrFocus("Visual Studio Code") end)
hs.hotkey.bind(hyper, "C", function() launchOrFocus("Codex") end)
hs.hotkey.bind(hyper, "S", function() launchOrFocus("Safari") end)
hs.hotkey.bind(hyper, "O", function() launchOrFocus("Google Chrome") end)
```

Add a helper to discover exact macOS app names and bundle IDs:

```lua
hs.hotkey.bind(hyper, "I", function()
  local app = hs.application.frontmostApplication()
  if not app then return end

  local name = app:name() or "unknown"
  local bundle = app:bundleID() or "unknown"

  hs.alert.show(name .. "\n" .. bundle)
  print("Frontmost app:", name, bundle)
end)
```

Use `⌃⌥⌘I` while an app is focused to identify the exact name Hammerspoon sees.

---

# Phase 3: Arrange Existing iTerm Windows

This replaces your hard-coded quad scripts with a dynamic version.

```lua
local function visibleWindowsForApp(appName)
  local app = hs.application.find(appName)
  if not app then return {} end

  local wins = app:visibleWindows() or {}

  table.sort(wins, function(a, b)
    return (a:id() or 0) < (b:id() or 0)
  end)

  return wins
end

local function arrangeWindows(windows, layout, screen)
  screen = screen or hs.screen.mainScreen()

  for i, unit in ipairs(layout) do
    local win = windows[i]
    if win then
      moveWindowToUnit(win, unit, screen)
    end
  end
end

local quadLayout = {
  units.topLeft,
  units.topRight,
  units.bottomLeft,
  units.bottomRight,
}

local stackLayout = {
  {x = 0, y = 0,   w = 1, h = 0.5},
  {x = 0, y = 0.5, w = 1, h = 0.5},
}

local function arrangeITermQuad()
  local screen = hs.screen.mainScreen()
  local wins = visibleWindowsForApp("iTerm")
  arrangeWindows(wins, quadLayout, screen)
  hs.alert.show("iTerm quad")
end

local function arrangeITermStack()
  local screen = hs.screen.mainScreen()
  local wins = visibleWindowsForApp("iTerm")
  arrangeWindows(wins, stackLayout, screen)
  hs.alert.show("iTerm stack")
end

hs.hotkey.bind(hyper, "Q", arrangeITermQuad)
hs.hotkey.bind(hyper, "A", arrangeITermStack)
```

Now:

```text
⌃⌥⌘Q = arrange first 4 visible iTerm windows into quad layout
⌃⌥⌘A = arrange first 2 visible iTerm windows into stacked layout
```

---

# Phase 4: Create iTerm Windows and Run `work`

You can have Hammerspoon create a new iTerm window and run your existing `work` command.

```lua
local function applescriptQuote(s)
  return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

local function runInNewITermWindow(profileName, command)
  local script = string.format([[
    tell application id "com.googlecode.iterm2"
      set newWindow to (create window with profile %s)
      tell current session of newWindow
        write text %s
      end tell
      activate
    end tell
  ]], applescriptQuote(profileName), applescriptQuote(command))

  local ok, result = hs.osascript.applescript(script)
  if not ok then
    hs.alert.show("iTerm AppleScript failed")
    print(result)
  end
end

local function openWork(repo)
  runInNewITermWindow("Quad Left", "work " .. repo)
end

hs.hotkey.bind(hyper, "1", function() openWork("account") end)
hs.hotkey.bind(hyper, "2", function() openWork("website") end)
hs.hotkey.bind(hyper, "3", function() openWork("email") end)
hs.hotkey.bind(hyper, "4", function() openWork("ux") end)
hs.hotkey.bind(hyper, "5", function() openWork("plan") end)
hs.hotkey.bind(hyper, "6", function() openWork("tools") end)
```

Workflow:

```text
⌃⌥⌘1 → new iTerm window running work account
⌃⌥⌘2 → new iTerm window running work website
⌃⌥⌘3 → new iTerm window running work email
⌃⌥⌘4 → new iTerm window running work ux
⌃⌥⌘Q → arrange those windows into a quad
```

---

# Phase 5: One-Key Node Cockpit

This is the most valuable piece for agentic coding.

```lua
local function nodeCockpit()
  -- Open the repo/agent terminals.
  openWork("account")
  openWork("website")
  openWork("email")
  openWork("ux")

  -- Give iTerm a moment to create windows, then arrange.
  hs.timer.doAfter(1.0, function()
    arrangeITermQuad()
  end)

  -- Bring other coding apps online.
  hs.timer.doAfter(1.2, function()
    hs.application.launchOrFocus("Visual Studio Code")
  end)

  hs.timer.doAfter(1.4, function()
    hs.application.launchOrFocus("Codex")
  end)
end

hs.hotkey.bind(hyper, "W", nodeCockpit)
```

Now:

```text
⌃⌥⌘W = open account/website/email/ux terminals, quad them, launch VS Code, launch Codex
```

You can also create focused variants:

```lua
local function backendCockpit()
  openWork("account")
  openWork("email")
  openWork("tools")
  hs.timer.doAfter(1.0, arrangeITermQuad)
end

local function frontendCockpit()
  openWork("website")
  openWork("ux")
  openWork("account")
  hs.timer.doAfter(1.0, arrangeITermQuad)
end

hs.hotkey.bind(hyper, "D", backendCockpit)
hs.hotkey.bind(hyper, "E", frontendCockpit)
```

---

# Phase 6: Arrange VS Code, Codex, Browser, and Terminal Together

For a coding workspace, a useful layout might be:

```text
Left 66%:         VS Code
Right 34% top:    Codex
Right 34% bottom: Browser or iTerm
```

Add:

```lua
local function firstVisibleWindow(appName)
  local wins = visibleWindowsForApp(appName)
  return wins[1]
end

local function arrangeCodingWorkspace()
  local screen = hs.screen.mainScreen()

  local vscode = firstVisibleWindow("Visual Studio Code")
  local codex = firstVisibleWindow("Codex")
  local browser = firstVisibleWindow("Google Chrome") or firstVisibleWindow("Safari")
  local iterm = firstVisibleWindow("iTerm")

  if vscode then
    moveWindowToUnit(vscode, {x = 0, y = 0, w = 0.66, h = 1}, screen)
  end

  if codex then
    moveWindowToUnit(codex, {x = 0.66, y = 0, w = 0.34, h = 0.5}, screen)
  end

  if browser then
    moveWindowToUnit(browser, {x = 0.66, y = 0.5, w = 0.34, h = 0.5}, screen)
  elseif iterm then
    moveWindowToUnit(iterm, {x = 0.66, y = 0.5, w = 0.34, h = 0.5}, screen)
  end

  hs.alert.show("Coding workspace arranged")
end

hs.hotkey.bind(hyper, "P", arrangeCodingWorkspace)
```

Now:

```text
⌃⌥⌘P = arrange editor + Codex + browser/terminal
```

This is where Hammerspoon is especially strong. It can understand app roles, not just generic window snapping.

---

# Phase 7: Use the Screen Under Your Mouse

Instead of always using the main screen, use whichever screen your mouse is currently on.

```lua
local function screenUnderMouse()
  local point = hs.mouse.absolutePosition()
  return hs.screen.find(point) or hs.screen.mainScreen()
end

local function arrangeITermQuadOnMouseScreen()
  local screen = screenUnderMouse()
  local wins = visibleWindowsForApp("iTerm")
  arrangeWindows(wins, quadLayout, screen)
  hs.alert.show("iTerm quad on mouse screen")
end

hs.hotkey.bind(hyper, "X", arrangeITermQuadOnMouseScreen)
```

Now:

```text
⌃⌥⌘X = arrange iTerm quad on the display under the mouse
```

This is especially useful when switching between laptop-only, external monitor, or multi-display setups.

---

# Phase 8: Reflow When Displays Change

You can have Hammerspoon react when monitors are connected or disconnected.

```lua
screenWatcher = hs.screen.watcher.new(function()
  hs.timer.doAfter(1.0, function()
    arrangeITermQuadOnMouseScreen()
  end)
end)

screenWatcher:start()
```

Important: keep `screenWatcher` global, not `local`, so it does not get garbage-collected after config load.

Use this carefully. Auto-reflow is helpful after docking/undocking, but it can be annoying if windows move when you did not expect them to.

---

# Phase 9: Add an Interactive Grid

For one-off layouts, use `hs.grid`.

```lua
hs.grid.setGrid("4x4")
hs.grid.setMargins({x = 0, y = 0})

hs.hotkey.bind(hyper, "Space", function()
  hs.grid.show()
end)
```

Now:

```text
⌃⌥⌘Space = show interactive grid overlay
```

Use exact hotkeys for common layouts and the grid for unusual layouts.

---

# Suggested File Organization

Eventually, split the config into modules:

```text
~/.hammerspoon/
  init.lua
  layouts.lua
  apps.lua
  iterm.lua
  agents.lua
  screens.lua
```

Or keep it inside your local tools repo:

```text
local-tools/
  hammerspoon/
    init.lua
    layouts.lua
    apps.lua
    iterm.lua
    agents.lua
  install.sh
  doctor.sh
```

Then symlink:

```bash
ln -s "$HOME/Documents/Coding/local-tools/hammerspoon" "$HOME/.hammerspoon"
```

Or have `install.sh` manage the symlink.

---

# Suggested `doctor.sh` Checks

Add checks for:

```text
Hammerspoon installed
~/.hammerspoon/init.lua exists
iTerm installed
VS Code installed
Codex installed, if applicable
work is on PATH
agent-status is on PATH
required iTerm profiles exist
required iTerm fonts/profile settings match
```

This fits your existing pattern of using `doctor.sh` to verify local tooling.

---

# What to Avoid

## Avoid making `hs.window.layout` the core engine

Hammerspoon has higher-level layout modules, but for this workflow I would keep the engine explicit:

```lua
screen:frame()
win:setFrame(...)
```

This is easier to debug and easier to adapt to your own layout vocabulary.

## Avoid overfitting to iTerm profile names

Use iTerm profiles for appearance and shell behavior. Use Hammerspoon for geometry.

Better split:

```text
iTerm profile:
  font
  color
  shell behavior
  badge/title
  environment

Hammerspoon:
  screen
  position
  size
  layout
  app focus
```

## Avoid using macOS Spaces too early

Solve these first:

```text
screen-aware layouts
app focus
repo launch
quad/stack terminal reset
coding workspace reset
```

Then add Spaces/workspace-specific behavior later if needed.

---

# Recommended Implementation Order

## Step 1

Install Hammerspoon and create `~/.hammerspoon/init.lua`.

## Step 2

Add focused-window snapping:

```text
left, right, top, bottom, full, quadrants
```

## Step 3

Add app focus shortcuts:

```text
iTerm, VS Code, Codex, browser
```

## Step 4

Add iTerm quad and stack arrangements.

## Step 5

Add `openWork(repo)` using AppleScript into iTerm.

## Step 6

Add one-key cockpit commands:

```text
nodeCockpit()
backendCockpit()
frontendCockpit()
```

## Step 7

Add screen-under-mouse placement.

## Step 8

Add display-change watcher only after the manual commands feel reliable.

---

# Bottom Line

The goal is to move from this:

```text
repo script + iTerm profile + hard-coded screen coordinates
```

To this:

```text
repo script + tmux session + Hammerspoon screen-aware layout engine
```

That lets you keep the useful parts of your existing workflow while removing the brittle laptop-vs-desktop geometry problem.

Hammerspoon becomes your programmable cockpit:

```text
Open repo sessions.
Arrange agent terminals.
Focus Codex.
Focus VS Code.
Reset layouts.
Adapt to monitor size.
Keep your hands on the keyboard.
```
