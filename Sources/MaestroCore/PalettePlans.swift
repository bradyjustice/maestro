import Foundation

public enum PaletteLayoutSlotStatus: String, Codable, Equatable, Sendable {
  case matched
  case missingWindow = "missing-window"
}

public struct PaletteLayoutPlanSlot: Codable, Equatable, Sendable {
  public var slotID: String
  public var targetID: String
  public var frame: LayoutRect
  public var status: PaletteLayoutSlotStatus
  public var window: TerminalWindowSnapshot?

  public init(
    slotID: String,
    targetID: String,
    frame: LayoutRect,
    status: PaletteLayoutSlotStatus,
    window: TerminalWindowSnapshot? = nil
  ) {
    self.slotID = slotID
    self.targetID = targetID
    self.frame = frame
    self.status = status
    self.window = window
  }
}

public struct PaletteLayoutPlan: Codable, Equatable, Sendable {
  public var layoutID: String
  public var label: String
  public var regionID: String
  public var screen: LayoutScreen
  public var container: LayoutRect
  public var slots: [PaletteLayoutPlanSlot]
  public var unmanagedWindowCount: Int

  public init(
    layoutID: String,
    label: String,
    regionID: String,
    screen: LayoutScreen,
    container: LayoutRect,
    slots: [PaletteLayoutPlanSlot],
    unmanagedWindowCount: Int
  ) {
    self.layoutID = layoutID
    self.label = label
    self.regionID = regionID
    self.screen = screen
    self.container = container
    self.slots = slots
    self.unmanagedWindowCount = unmanagedWindowCount
  }

  public var missingTargetIDs: [String] {
    slots.filter { $0.status == .missingWindow }.map(\.targetID)
  }
}

public struct PaletteLayoutPlanner {
  public init() {}

  public func plan(
    layout: TerminalLayout,
    config: PaletteConfig,
    screen: LayoutScreen,
    windows: [TerminalWindowSnapshot] = []
  ) throws -> PaletteLayoutPlan {
    guard let region = config.regions.first(where: { $0.id == layout.region }) else {
      throw PaletteConfigError.missingRegion(layout.region)
    }

    let container = region.container.frame(in: screen.visibleFrame)
    let visibleTaggedWindows = windows
      .filter { $0.isVisible && !$0.isMinimized && $0.targetID != nil }
      .sorted { $0.id < $1.id }

    var usedWindowIDs = Set<String>()
    var slots: [PaletteLayoutPlanSlot] = []

    for slot in layout.slots {
      let frame = slot.unit.frame(in: container)
      let match = visibleTaggedWindows.first { window in
        !usedWindowIDs.contains(window.id) && window.targetID == slot.target
      }
      if let match {
        usedWindowIDs.insert(match.id)
        slots.append(PaletteLayoutPlanSlot(
          slotID: slot.id,
          targetID: slot.target,
          frame: frame,
          status: .matched,
          window: match
        ))
      } else {
        slots.append(PaletteLayoutPlanSlot(
          slotID: slot.id,
          targetID: slot.target,
          frame: frame,
          status: .missingWindow
        ))
      }
    }

    let layoutTargetIDs = Set(layout.slots.map(\.target))
    let unmanaged = windows.filter { window in
      guard let targetID = window.targetID else {
        return false
      }
      return layoutTargetIDs.contains(targetID) && !usedWindowIDs.contains(window.id)
    }

    return PaletteLayoutPlan(
      layoutID: layout.id,
      label: layout.label,
      regionID: layout.region,
      screen: screen,
      container: container,
      slots: slots,
      unmanagedWindowCount: unmanaged.count
    )
  }
}

public struct TmuxCommand: Codable, Equatable, Sendable {
  public var executable: String
  public var arguments: [String]

  public init(executable: String = "tmux", arguments: [String]) {
    self.executable = executable
    self.arguments = arguments
  }

  public var argv: [String] {
    [executable] + arguments
  }
}

public struct TmuxTargetPlan: Codable, Equatable, Sendable {
  public var target: ResolvedTerminalTarget
  public var sessionExists: Bool
  public var windowExists: Bool
  public var commands: [TmuxCommand]
  public var focusCommand: TmuxCommand

  public init(
    target: ResolvedTerminalTarget,
    sessionExists: Bool,
    windowExists: Bool,
    commands: [TmuxCommand],
    focusCommand: TmuxCommand
  ) {
    self.target = target
    self.sessionExists = sessionExists
    self.windowExists = windowExists
    self.commands = commands
    self.focusCommand = focusCommand
  }
}

public struct TmuxPlanner {
  public init() {}

  public func ensureTargetPlan(
    target: ResolvedTerminalTarget,
    sessionExists: Bool,
    windowExists: Bool
  ) -> TmuxTargetPlan {
    var commands: [TmuxCommand] = []

    if !sessionExists {
      commands.append(TmuxCommand(arguments: [
        "new-session",
        "-d",
        "-s",
        target.session,
        "-n",
        target.window,
        "-c",
        target.cwd
      ]))
    } else if !windowExists {
      commands.append(TmuxCommand(arguments: [
        "new-window",
        "-t",
        "\(target.session):",
        "-n",
        target.window,
        "-c",
        target.cwd
      ]))
    }

    let focus = TmuxCommand(arguments: ["select-window", "-t", target.tmuxWindowTarget])
    commands.append(focus)

    return TmuxTargetPlan(
      target: target,
      sessionExists: sessionExists,
      windowExists: windowExists,
      commands: commands,
      focusCommand: focus
    )
  }
}

public struct CommandButtonPlan: Codable, Equatable, Sendable {
  public var buttonID: String
  public var label: String
  public var kind: CommandButtonKind
  public var target: ResolvedTerminalTarget
  public var targetPane: String
  public var displayCommand: String?
  public var tmuxCommand: TmuxCommand

  public init(
    buttonID: String,
    label: String,
    kind: CommandButtonKind,
    target: ResolvedTerminalTarget,
    displayCommand: String?,
    tmuxCommand: TmuxCommand
  ) {
    self.buttonID = buttonID
    self.label = label
    self.kind = kind
    self.target = target
    self.targetPane = target.tmuxPaneTarget
    self.displayCommand = displayCommand
    self.tmuxCommand = tmuxCommand
  }
}

public struct CommandButtonPlanner {
  public init() {}

  public func plan(button: CommandButton, target: ResolvedTerminalTarget) throws -> CommandButtonPlan {
    switch button.kind {
    case .command:
      guard let argv = button.argv, !argv.isEmpty else {
        throw PaletteConfigError.missingCommandArgv(button.id)
      }
      let display = ShellCommandRenderer.render(argv)
      return CommandButtonPlan(
        buttonID: button.id,
        label: button.label,
        kind: button.kind,
        target: target,
        displayCommand: display,
        tmuxCommand: TmuxCommand(arguments: ["send-keys", "-t", target.tmuxPaneTarget, display, "C-m"])
      )
    case .stop:
      return CommandButtonPlan(
        buttonID: button.id,
        label: button.label,
        kind: button.kind,
        target: target,
        displayCommand: nil,
        tmuxCommand: TmuxCommand(arguments: ["send-keys", "-t", target.tmuxPaneTarget, "C-c"])
      )
    }
  }
}

public enum ShellCommandRenderer {
  public static func render(_ argv: [String]) -> String {
    argv.map(quote).joined(separator: " ")
  }

  public static func quote(_ argument: String) -> String {
    guard !argument.isEmpty else {
      return "''"
    }

    let safeScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
    if argument.unicodeScalars.allSatisfy({ safeScalars.contains($0) }) {
      return argument
    }

    return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }
}

public enum ShellProcessClassifier {
  public static let shellCommands: Set<String> = [
    "bash",
    "dash",
    "fish",
    "login",
    "nu",
    "sh",
    "tcsh",
    "tmux",
    "zsh"
  ]

  public static func isShell(_ command: String) -> Bool {
    let basename = URL(fileURLWithPath: command).lastPathComponent
    return shellCommands.contains(basename)
  }
}

public enum ButtonRunStatus: String, Codable, Equatable, Sendable {
  case sent
  case blocked
}

public struct ButtonRunResult: Codable, Equatable, Sendable {
  public var ok: Bool
  public var buttonID: String
  public var status: ButtonRunStatus
  public var message: String
  public var targetPane: String
  public var displayCommand: String?

  public init(
    ok: Bool,
    buttonID: String,
    status: ButtonRunStatus,
    message: String,
    targetPane: String,
    displayCommand: String?
  ) {
    self.ok = ok
    self.buttonID = buttonID
    self.status = status
    self.message = message
    self.targetPane = targetPane
    self.displayCommand = displayCommand
  }
}
