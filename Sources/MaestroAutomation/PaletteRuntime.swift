import Foundation
import MaestroCore

public protocol PaletteWindowAutomation: Sendable {
  func activeScreen() -> LayoutScreen
  func taggedTerminalWindows() throws -> [TerminalWindowSnapshot]
  func createTerminalWindow(for target: ResolvedTerminalTarget, attachCommand: String) throws
  func focusTerminalWindow(targetID: String) throws
  func moveTerminalWindows(_ framesByTargetID: [String: LayoutRect]) throws
}

public protocol PaletteConfirmationProviding: Sendable {
  func confirmBusy(target: ResolvedTerminalTarget, command: String, currentCommand: String) -> Bool
  func confirmStop(target: ResolvedTerminalTarget) -> Bool
}

public struct DenyPaletteConfirmation: PaletteConfirmationProviding {
  public init() {}

  public func confirmBusy(target: ResolvedTerminalTarget, command: String, currentCommand: String) -> Bool {
    false
  }

  public func confirmStop(target: ResolvedTerminalTarget) -> Bool {
    false
  }
}

public struct AllowPaletteConfirmation: PaletteConfirmationProviding {
  public init() {}

  public func confirmBusy(target: ResolvedTerminalTarget, command: String, currentCommand: String) -> Bool {
    true
  }

  public func confirmStop(target: ResolvedTerminalTarget) -> Bool {
    true
  }
}

public struct PaletteRuntime: Sendable {
  public var config: PaletteConfig
  public var configDirectory: URL
  public var environment: [String: String]
  public var tmux: TmuxController
  public var windows: any PaletteWindowAutomation

  public init(
    config: PaletteConfig,
    configDirectory: URL,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    tmux: TmuxController = TmuxController(),
    windows: any PaletteWindowAutomation = NativeMacAutomation()
  ) {
    self.config = config
    self.configDirectory = configDirectory
    self.environment = environment
    self.tmux = tmux
    self.windows = windows
  }

  public func resolvedTarget(id: String) throws -> ResolvedTerminalTarget {
    guard let target = config.targets.first(where: { $0.id == id }) else {
      throw PaletteConfigError.missingTarget(id)
    }
    return try PalettePathResolver(configDirectory: configDirectory, environment: environment)
      .resolve(target: target, in: config)
  }

  public func buttonPlan(id: String) throws -> CommandButtonPlan {
    guard let button = config.buttons.first(where: { $0.id == id }) else {
      throw PaletteConfigError.missingButton(id)
    }
    return try CommandButtonPlanner().plan(
      button: button,
      target: resolvedTarget(id: button.target)
    )
  }

  public func runButton(
    id: String,
    confirmation: any PaletteConfirmationProviding
  ) throws -> ButtonRunResult {
    let plan = try buttonPlan(id: id)

    switch plan.kind {
    case .command:
      _ = try tmux.ensureTarget(plan.target)
      let currentCommand = try tmux.paneCurrentCommand(plan.target)
      if !ShellProcessClassifier.isShell(currentCommand) {
        guard confirmation.confirmBusy(
          target: plan.target,
          command: plan.displayCommand ?? "",
          currentCommand: currentCommand
        ) else {
          return ButtonRunResult(
            ok: false,
            buttonID: plan.buttonID,
            status: .blocked,
            message: "blocked",
            targetPane: plan.target.tmuxPaneTarget,
            displayCommand: plan.displayCommand
          )
        }
      }
      try tmux.run(plan.tmuxCommand)
      return ButtonRunResult(
        ok: true,
        buttonID: plan.buttonID,
        status: .sent,
        message: "sent",
        targetPane: plan.target.tmuxPaneTarget,
        displayCommand: plan.displayCommand
      )
    case .stop:
      guard confirmation.confirmStop(target: plan.target) else {
        return ButtonRunResult(
          ok: false,
          buttonID: plan.buttonID,
          status: .blocked,
          message: "blocked",
          targetPane: plan.target.tmuxPaneTarget,
          displayCommand: nil
        )
      }
      try tmux.run(plan.tmuxCommand)
      return ButtonRunResult(
        ok: true,
        buttonID: plan.buttonID,
        status: .sent,
        message: "sent",
        targetPane: plan.target.tmuxPaneTarget,
        displayCommand: nil
      )
    }
  }

  public func focusTarget(id: String) throws {
    let target = try resolvedTarget(id: id)
    _ = try tmux.ensureTarget(target)

    let tagged = try windows.taggedTerminalWindows()
    if tagged.contains(where: { $0.targetID == target.id }) {
      try windows.focusTerminalWindow(targetID: target.id)
    } else {
      try windows.createTerminalWindow(for: target, attachCommand: attachCommand(for: target))
    }
  }

  public func applyLayout(id: String) throws -> PaletteLayoutPlan {
    guard let layout = config.layouts.first(where: { $0.id == id }) else {
      throw PaletteConfigError.missingLayout(id)
    }

    let targetIDs = Array(Set(layout.slots.map(\.target))).sorted()
    let targets = try targetIDs.map { try resolvedTarget(id: $0) }
    for target in targets {
      _ = try tmux.ensureTarget(target)
    }

    let screen = windows.activeScreen()
    var tagged = try windows.taggedTerminalWindows()
    var plan = try PaletteLayoutPlanner().plan(
      layout: layout,
      config: config,
      screen: screen,
      windows: tagged
    )

    let missingIDs = Set(plan.missingTargetIDs)
    for target in targets where missingIDs.contains(target.id) {
      try windows.createTerminalWindow(for: target, attachCommand: attachCommand(for: target))
    }

    if !missingIDs.isEmpty {
      tagged = try waitForTaggedWindows(targetIDs: missingIDs, existing: tagged)
      plan = try PaletteLayoutPlanner().plan(
        layout: layout,
        config: config,
        screen: screen,
        windows: tagged
      )
    }

    var framesByTargetID: [String: LayoutRect] = [:]
    for slot in plan.slots {
      framesByTargetID[slot.targetID] = slot.frame
    }
    try windows.moveTerminalWindows(framesByTargetID)
    return plan
  }

  private func waitForTaggedWindows(
    targetIDs: Set<String>,
    existing: [TerminalWindowSnapshot]
  ) throws -> [TerminalWindowSnapshot] {
    let deadline = Date().addingTimeInterval(5)
    var latest = existing
    while Date() < deadline {
      let present = Set(latest.compactMap(\.targetID))
      if targetIDs.isSubset(of: present) {
        return latest
      }
      Thread.sleep(forTimeInterval: 0.1)
      latest = try windows.taggedTerminalWindows()
    }
    return latest
  }

  private func attachCommand(for target: ResolvedTerminalTarget) -> String {
    let cwd = ShellCommandRenderer.quote(target.cwd)
    let tmuxTarget = ShellCommandRenderer.quote(target.tmuxWindowTarget)
    return "cd \(cwd) && tmux attach-session -t \(tmuxTarget)"
  }
}

