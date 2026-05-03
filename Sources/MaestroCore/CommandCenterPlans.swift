import Foundation

public enum CommandCenterSurfaceStatus: String, Codable, Equatable, Sendable {
  case matched
  case missingWindow = "missing-window"
}

public enum CommandCenterWindowOwnershipDecision: String, Codable, Equatable, Sendable {
  case reused
  case created
  case missing
  case duplicateQuarantined = "duplicate-quarantined"
}

public struct CommandCenterPaneSlotPlan: Codable, Equatable, Sendable {
  public var slotID: String
  public var label: String
  public var role: String
  public var repoID: String
  public var frame: LayoutRect
  public var paneTarget: String

  public init(
    slotID: String,
    label: String,
    role: String,
    repoID: String,
    frame: LayoutRect,
    paneTarget: String
  ) {
    self.slotID = slotID
    self.label = label
    self.role = role
    self.repoID = repoID
    self.frame = frame
    self.paneTarget = paneTarget
  }
}

public struct CommandCenterTerminalHostPlan: Codable, Equatable, Sendable {
  public var hostID: String
  public var terminalProfileID: String
  public var label: String
  public var repoID: String
  public var sessionName: String
  public var windowName: String
  public var frame: LayoutRect
  public var status: CommandCenterSurfaceStatus
  public var ownershipDecision: CommandCenterWindowOwnershipDecision
  public var window: TerminalWindowSnapshot?
  public var quarantinedWindowIDs: [String]
  public var slots: [CommandCenterPaneSlotPlan]

  public init(
    hostID: String,
    terminalProfileID: String,
    label: String,
    repoID: String,
    sessionName: String,
    windowName: String,
    frame: LayoutRect,
    status: CommandCenterSurfaceStatus,
    ownershipDecision: CommandCenterWindowOwnershipDecision,
    window: TerminalWindowSnapshot? = nil,
    quarantinedWindowIDs: [String] = [],
    slots: [CommandCenterPaneSlotPlan]
  ) {
    self.hostID = hostID
    self.terminalProfileID = terminalProfileID
    self.label = label
    self.repoID = repoID
    self.sessionName = sessionName
    self.windowName = windowName
    self.frame = frame
    self.status = status
    self.ownershipDecision = ownershipDecision
    self.window = window
    self.quarantinedWindowIDs = quarantinedWindowIDs
    self.slots = slots
  }

  public var tmuxWindowTarget: String {
    "\(sessionName):\(windowName)"
  }
}

public struct CommandCenterAppZonePlan: Codable, Equatable, Sendable {
  public var zoneID: String
  public var label: String
  public var frame: LayoutRect
  public var appTargetIDs: [String]

  public init(zoneID: String, label: String, frame: LayoutRect, appTargetIDs: [String]) {
    self.zoneID = zoneID
    self.label = label
    self.frame = frame
    self.appTargetIDs = appTargetIDs
  }
}

public struct CommandCenterLayoutPlan: Codable, Equatable, Sendable {
  public var layoutID: String
  public var label: String
  public var screen: LayoutScreen
  public var terminalHosts: [CommandCenterTerminalHostPlan]
  public var appZones: [CommandCenterAppZonePlan]
  public var unmanagedWindowCount: Int

  public init(
    layoutID: String,
    label: String,
    screen: LayoutScreen,
    terminalHosts: [CommandCenterTerminalHostPlan],
    appZones: [CommandCenterAppZonePlan],
    unmanagedWindowCount: Int
  ) {
    self.layoutID = layoutID
    self.label = label
    self.screen = screen
    self.terminalHosts = terminalHosts
    self.appZones = appZones
    self.unmanagedWindowCount = unmanagedWindowCount
  }

  public var missingHostIDs: [String] {
    terminalHosts.filter { $0.status == .missingWindow }.map(\.hostID)
  }

  public var missingTerminalProfileIDs: [String] {
    terminalHosts.filter { $0.status == .missingWindow }.map(\.terminalProfileID)
  }
}

public struct CommandCenterLayoutPlanner {
  public init() {}

  public func plan(
    layout: ScreenLayout,
    config: CommandCenterConfig,
    screen: LayoutScreen,
    windows: [TerminalWindowSnapshot] = [],
    state: CommandCenterState = CommandCenterState(),
    createdTerminalProfileIDs: Set<String> = []
  ) throws -> CommandCenterLayoutPlan {
    let taggedWindows = windows
      .filter { $0.isVisible && !$0.isMinimized && $0.targetID != nil }
      .sorted { $0.id < $1.id }
    var usedWindowIDs = Set<String>()
    var hostPlans: [CommandCenterTerminalHostPlan] = []
    let profileResolver = CommandCenterTerminalProfileResolver()

    for host in layout.terminalHosts {
      let profile = try profileResolver.profile(for: host, in: config)
      let template = try paneTemplate(profile.paneTemplateID, in: config)
      let hostFrame = host.frame.frame(in: screen.visibleFrame)
      let sessionName = CommandCenterTmuxNaming.sessionName(workspaceID: config.workspace.id, hostID: profile.id)
      let candidateWindows = taggedWindows.filter { $0.targetID == profile.id && !usedWindowIDs.contains($0.id) }
      let canonicalWindowID = state.canonicalTerminalWindow(profileID: profile.id)?.iTermWindowID
      let window = candidateWindows.first { $0.id == canonicalWindowID } ?? candidateWindows.first
      if let window {
        usedWindowIDs.insert(window.id)
      }
      let quarantinedWindowIDs = candidateWindows
        .filter { $0.id != window?.id }
        .map(\.id)
      let ownershipDecision: CommandCenterWindowOwnershipDecision
      if !quarantinedWindowIDs.isEmpty {
        ownershipDecision = .duplicateQuarantined
      } else if window == nil {
        ownershipDecision = .missing
      } else if createdTerminalProfileIDs.contains(profile.id) {
        ownershipDecision = .created
      } else {
        ownershipDecision = .reused
      }

      let slotPlans = template.slots.enumerated().map { index, slot in
        let repoID = slot.repoID ?? profile.repoID
        return CommandCenterPaneSlotPlan(
          slotID: slot.id,
          label: slot.label,
          role: slot.role,
          repoID: repoID,
          frame: slot.unit.frame(in: hostFrame),
          paneTarget: "\(sessionName):\(CommandCenterTmuxNaming.windowName).\(index)"
        )
      }

      hostPlans.append(CommandCenterTerminalHostPlan(
        hostID: host.id,
        terminalProfileID: profile.id,
        label: profile.label,
        repoID: profile.repoID,
        sessionName: sessionName,
        windowName: CommandCenterTmuxNaming.windowName,
        frame: hostFrame,
        status: window == nil ? .missingWindow : .matched,
        ownershipDecision: ownershipDecision,
        window: window,
        quarantinedWindowIDs: quarantinedWindowIDs,
        slots: slotPlans
      ))
    }

    let layoutProfileIDs = Set(try layout.terminalHosts.map {
      try profileResolver.profile(for: $0, in: config).id
    })
    let unmanaged = windows.filter { window in
      guard let profileID = window.targetID else {
        return false
      }
      return layoutProfileIDs.contains(profileID) && !usedWindowIDs.contains(window.id)
    }

    let appZones = layout.appZones.map {
      CommandCenterAppZonePlan(
        zoneID: $0.id,
        label: $0.label,
        frame: $0.frame.frame(in: screen.visibleFrame),
        appTargetIDs: $0.appTargetIDs
      )
    }

    return CommandCenterLayoutPlan(
      layoutID: layout.id,
      label: layout.label,
      screen: screen,
      terminalHosts: hostPlans,
      appZones: appZones,
      unmanagedWindowCount: unmanaged.count
    )
  }

  private func paneTemplate(_ id: String, in config: CommandCenterConfig) throws -> PaneTemplate {
    guard let template = config.paneTemplates.first(where: { $0.id == id }) else {
      throw CommandCenterConfigError.missingPaneTemplate(id)
    }
    return template
  }
}

public enum CommandCenterTmuxNaming {
  public static let windowName = "main"

  public static func sessionName(workspaceID: String, hostID: String) -> String {
    "maestro.\(sanitize(workspaceID)).\(sanitize(hostID))"
  }

  public static func sanitize(_ value: String) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    let scalars = value.unicodeScalars.map { scalar -> Character in
      allowed.contains(scalar) ? Character(scalar) : "-"
    }
    let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return sanitized.isEmpty ? "workspace" : sanitized
  }
}

public struct ResolvedCommandRepo: Codable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var cwd: String

  public init(id: String, label: String, cwd: String) {
    self.id = id
    self.label = label
    self.cwd = cwd
  }
}

public struct ResolvedTerminalHost: Codable, Equatable, Sendable {
  public var id: String
  public var layoutHostID: String
  public var label: String
  public var repo: ResolvedCommandRepo
  public var sessionName: String
  public var windowName: String
  public var paneTemplate: PaneTemplate
  public var slotRepos: [String: ResolvedCommandRepo]
  public var itermProfileName: String?
  public var startupCommands: [TerminalStartupCommand]

  public init(
    id: String,
    layoutHostID: String? = nil,
    label: String,
    repo: ResolvedCommandRepo,
    sessionName: String,
    windowName: String,
    paneTemplate: PaneTemplate,
    slotRepos: [String: ResolvedCommandRepo] = [:],
    itermProfileName: String? = nil,
    startupCommands: [TerminalStartupCommand] = []
  ) {
    self.id = id
    self.layoutHostID = layoutHostID ?? id
    self.label = label
    self.repo = repo
    self.sessionName = sessionName
    self.windowName = windowName
    self.paneTemplate = paneTemplate
    self.slotRepos = slotRepos
    self.itermProfileName = itermProfileName
    self.startupCommands = startupCommands
  }

  public var tmuxWindowTarget: String {
    "\(sessionName):\(windowName)"
  }

  public func paneTarget(slotID: String) throws -> String {
    guard let index = paneTemplate.slots.firstIndex(where: { $0.id == slotID }) else {
      throw CommandCenterConfigError.missingPaneSlot(hostID: id, slotID: slotID)
    }
    return "\(tmuxWindowTarget).\(index)"
  }

  public func repo(for slot: PaneSlot) -> ResolvedCommandRepo {
    slotRepos[slot.id] ?? repo
  }

  public func cwdForSlot(at index: Int) -> String {
    guard paneTemplate.slots.indices.contains(index) else {
      return repo.cwd
    }
    return repo(for: paneTemplate.slots[index]).cwd
  }
}

public struct TmuxHostPlan: Codable, Equatable, Sendable {
  public var host: ResolvedTerminalHost
  public var sessionExists: Bool
  public var windowExists: Bool
  public var existingPaneCount: Int
  public var commands: [TmuxCommand]
  public var attachTarget: String

  public init(
    host: ResolvedTerminalHost,
    sessionExists: Bool,
    windowExists: Bool,
    existingPaneCount: Int,
    commands: [TmuxCommand],
    attachTarget: String
  ) {
    self.host = host
    self.sessionExists = sessionExists
    self.windowExists = windowExists
    self.existingPaneCount = existingPaneCount
    self.commands = commands
    self.attachTarget = attachTarget
  }
}

public struct CommandCenterTmuxPlanner {
  public init() {}

  public func ensureHostPlan(
    host: ResolvedTerminalHost,
    sessionExists: Bool,
    windowExists: Bool,
    existingPaneCount: Int
  ) -> TmuxHostPlan {
    var commands: [TmuxCommand] = []
    let desiredPaneCount = max(1, host.paneTemplate.slots.count)
    var paneCount = existingPaneCount

    if !sessionExists {
      commands.append(TmuxCommand(arguments: [
        "new-session",
        "-d",
        "-s",
        host.sessionName,
        "-n",
        host.windowName,
        "-c",
        host.cwdForSlot(at: 0)
      ]))
      paneCount = 1
    } else if !windowExists {
      commands.append(TmuxCommand(arguments: [
        "new-window",
        "-t",
        "\(host.sessionName):",
        "-n",
        host.windowName,
        "-c",
        host.cwdForSlot(at: 0)
      ]))
      paneCount = 1
    } else {
      paneCount = max(1, paneCount)
    }

    if paneCount < desiredPaneCount {
      for slotIndex in paneCount..<desiredPaneCount {
        commands.append(TmuxCommand(arguments: [
          "split-window",
          "-t",
          host.tmuxWindowTarget,
          "-c",
          host.cwdForSlot(at: slotIndex)
        ]))
      }
    }

    if let layoutName = layoutName(for: host.paneTemplate) {
      commands.append(TmuxCommand(arguments: [
        "select-layout",
        "-t",
        host.tmuxWindowTarget,
        layoutName
      ]))
    }

    commands.append(contentsOf: tagCommands(host: host))

    return TmuxHostPlan(
      host: host,
      sessionExists: sessionExists,
      windowExists: windowExists,
      existingPaneCount: existingPaneCount,
      commands: commands,
      attachTarget: host.tmuxWindowTarget
    )
  }

  public func tagCommands(host: ResolvedTerminalHost) -> [TmuxCommand] {
    host.paneTemplate.slots.enumerated().flatMap { index, slot in
      let target = "\(host.tmuxWindowTarget).\(index)"
      let repoID = host.repo(for: slot).id
      return [
        TmuxCommand(arguments: ["set-option", "-p", "-t", target, "@maestro.repo", repoID]),
        TmuxCommand(arguments: ["set-option", "-p", "-t", target, "@maestro.role", slot.role]),
        TmuxCommand(arguments: ["set-option", "-p", "-t", target, "@maestro.slot", slot.id])
      ]
    }
  }

  public func layoutCommand(host: ResolvedTerminalHost) -> TmuxCommand? {
    guard let layoutName = layoutName(for: host.paneTemplate) else {
      return nil
    }
    return TmuxCommand(arguments: ["select-layout", "-t", host.tmuxWindowTarget, layoutName])
  }

  public func layoutName(for template: PaneTemplate) -> String? {
    switch template.slots.count {
    case 0, 1:
      return nil
    case 2:
      let first = template.slots[0].unit
      let second = template.slots[1].unit
      if first.x == second.x && first.width == second.width {
        return "even-vertical"
      }
      return "even-horizontal"
    default:
      return "tiled"
    }
  }
}

public struct CommandCenterPaneRef: Codable, Equatable, Sendable {
  public var hostID: String
  public var slotID: String

  public init(hostID: String, slotID: String) {
    self.hostID = hostID
    self.slotID = slotID
  }

  public init(parse value: String) throws {
    let parts = value.split(separator: ".", maxSplits: 1).map(String.init)
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
      throw CommandCenterPaneRefError.invalid(value)
    }
    self.hostID = parts[0]
    self.slotID = parts[1]
  }

  public var display: String {
    "\(hostID).\(slotID)"
  }
}

public enum CommandCenterPaneRefError: Error, LocalizedError, Equatable {
  case invalid(String)

  public var errorDescription: String? {
    switch self {
    case let .invalid(value):
      return "Invalid pane ref \(value). Use <host-id>.<slot-id>."
    }
  }
}

public enum CommandCenterPaneOperationKind: String, Codable, Sendable {
  case swap
  case move
}

public struct CommandCenterPaneOperationPlan: Codable, Equatable, Sendable {
  public var kind: CommandCenterPaneOperationKind
  public var source: CommandCenterPaneRef
  public var destination: CommandCenterPaneRef
  public var sourcePaneTarget: String
  public var destinationPaneTarget: String
  public var commands: [TmuxCommand]

  public init(
    kind: CommandCenterPaneOperationKind,
    source: CommandCenterPaneRef,
    destination: CommandCenterPaneRef,
    sourcePaneTarget: String,
    destinationPaneTarget: String,
    commands: [TmuxCommand]
  ) {
    self.kind = kind
    self.source = source
    self.destination = destination
    self.sourcePaneTarget = sourcePaneTarget
    self.destinationPaneTarget = destinationPaneTarget
    self.commands = commands
  }
}

public struct CommandCenterActionPlan: Codable, Equatable, Sendable {
  public var actionID: String
  public var label: String
  public var kind: CommandCenterActionKind
  public var displayCommand: String?
  public var targetPane: String?
  public var tmuxCommand: TmuxCommand?
  public var url: String?
  public var repoPath: String?
  public var appTarget: AppTarget?

  public init(
    actionID: String,
    label: String,
    kind: CommandCenterActionKind,
    displayCommand: String? = nil,
    targetPane: String? = nil,
    tmuxCommand: TmuxCommand? = nil,
    url: String? = nil,
    repoPath: String? = nil,
    appTarget: AppTarget? = nil
  ) {
    self.actionID = actionID
    self.label = label
    self.kind = kind
    self.displayCommand = displayCommand
    self.targetPane = targetPane
    self.tmuxCommand = tmuxCommand
    self.url = url
    self.repoPath = repoPath
    self.appTarget = appTarget
  }
}

public struct CommandCenterPaneBinding: Codable, Equatable, Sendable {
  public var layoutID: String
  public var hostID: String
  public var slotID: String
  public var role: String
  public var repoID: String
  public var paneTarget: String

  public init(
    layoutID: String,
    hostID: String,
    slotID: String,
    role: String,
    repoID: String,
    paneTarget: String
  ) {
    self.layoutID = layoutID
    self.hostID = hostID
    self.slotID = slotID
    self.role = role
    self.repoID = repoID
    self.paneTarget = paneTarget
  }
}
