import Foundation

public struct CommandCenterConfig: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var workspace: CommandWorkspace
  public var repos: [CommandRepo]
  public var appTargets: [AppTarget]
  public var paneTemplates: [PaneTemplate]
  public var terminalProfiles: [TerminalProfile]?
  public var screenLayouts: [ScreenLayout]
  public var actions: [CommandCenterAction]
  public var sections: [CommandCenterSection]
  public var profiles: [CommandCenterProfile]?

  public init(
    schemaVersion: Int,
    workspace: CommandWorkspace,
    repos: [CommandRepo],
    appTargets: [AppTarget],
    paneTemplates: [PaneTemplate],
    terminalProfiles: [TerminalProfile]? = nil,
    screenLayouts: [ScreenLayout],
    actions: [CommandCenterAction],
    sections: [CommandCenterSection],
    profiles: [CommandCenterProfile]? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.workspace = workspace
    self.repos = repos
    self.appTargets = appTargets
    self.paneTemplates = paneTemplates
    self.terminalProfiles = terminalProfiles
    self.screenLayouts = screenLayouts
    self.actions = actions
    self.sections = sections
    self.profiles = profiles
  }
}

public struct CommandWorkspace: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String

  public init(id: String, label: String) {
    self.id = id
    self.label = label
  }
}

public struct CommandRepo: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var path: String

  public init(id: String, label: String, path: String) {
    self.id = id
    self.label = label
    self.path = path
  }
}

public enum AppTargetRole: String, Codable, CaseIterable, Sendable {
  case browser
  case editor
  case other
}

public struct AppTarget: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var bundleID: String?
  public var useSystemDefaultBrowser: Bool
  public var role: AppTargetRole
  public var defaultURL: String?

  public init(
    id: String,
    label: String,
    bundleID: String? = nil,
    useSystemDefaultBrowser: Bool = false,
    role: AppTargetRole,
    defaultURL: String? = nil
  ) {
    self.id = id
    self.label = label
    self.bundleID = bundleID
    self.useSystemDefaultBrowser = useSystemDefaultBrowser
    self.role = role
    self.defaultURL = defaultURL
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case label
    case bundleID
    case useSystemDefaultBrowser
    case role
    case defaultURL
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.label = try container.decode(String.self, forKey: .label)
    self.bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
    self.useSystemDefaultBrowser = try container.decodeIfPresent(Bool.self, forKey: .useSystemDefaultBrowser) ?? false
    self.role = try container.decode(AppTargetRole.self, forKey: .role)
    self.defaultURL = try container.decodeIfPresent(String.self, forKey: .defaultURL)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(label, forKey: .label)
    try container.encodeIfPresent(bundleID, forKey: .bundleID)
    if useSystemDefaultBrowser {
      try container.encode(useSystemDefaultBrowser, forKey: .useSystemDefaultBrowser)
    }
    try container.encode(role, forKey: .role)
    try container.encodeIfPresent(defaultURL, forKey: .defaultURL)
  }
}

public struct PaneTemplate: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var slots: [PaneSlot]

  public init(id: String, label: String, slots: [PaneSlot]) {
    self.id = id
    self.label = label
    self.slots = slots
  }
}

public struct PaneSlot: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var role: String
  public var unit: PercentRect
  public var repoID: String?

  public init(
    id: String,
    label: String,
    role: String,
    unit: PercentRect,
    repoID: String? = nil
  ) {
    self.id = id
    self.label = label
    self.role = role
    self.unit = unit
    self.repoID = repoID
  }
}

public enum TerminalSessionStrategy: String, Codable, CaseIterable, Sendable {
  case perHost
}

public struct TerminalStartupCommand: Codable, Equatable, Sendable {
  public var slotID: String
  public var argv: [String]

  public init(slotID: String, argv: [String]) {
    self.slotID = slotID
    self.argv = argv
  }
}

public struct TerminalProfile: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var repoID: String
  public var paneTemplateID: String
  public var itermProfileName: String?
  public var startupCommands: [TerminalStartupCommand]

  public init(
    id: String,
    label: String,
    repoID: String,
    paneTemplateID: String,
    itermProfileName: String? = nil,
    startupCommands: [TerminalStartupCommand] = []
  ) {
    self.id = id
    self.label = label
    self.repoID = repoID
    self.paneTemplateID = paneTemplateID
    self.itermProfileName = itermProfileName
    self.startupCommands = startupCommands
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case label
    case repoID
    case paneTemplateID
    case itermProfileName
    case startupCommands
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? id
    self.repoID = try container.decode(String.self, forKey: .repoID)
    self.paneTemplateID = try container.decode(String.self, forKey: .paneTemplateID)
    self.itermProfileName = try container.decodeIfPresent(String.self, forKey: .itermProfileName)
    self.startupCommands = try container.decodeIfPresent([TerminalStartupCommand].self, forKey: .startupCommands) ?? []
  }
}

public struct TerminalHost: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var terminalProfileID: String?
  public var repoID: String?
  public var paneTemplateID: String?
  public var frame: PercentRect
  public var sessionStrategy: TerminalSessionStrategy

  public init(
    id: String,
    label: String,
    repoID: String? = nil,
    paneTemplateID: String? = nil,
    terminalProfileID: String? = nil,
    frame: PercentRect,
    sessionStrategy: TerminalSessionStrategy = .perHost
  ) {
    self.id = id
    self.label = label
    self.terminalProfileID = terminalProfileID
    self.repoID = repoID
    self.paneTemplateID = paneTemplateID
    self.frame = frame
    self.sessionStrategy = sessionStrategy
  }

  public var effectiveTerminalProfileID: String {
    terminalProfileID ?? id
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case label
    case terminalProfileID
    case repoID
    case paneTemplateID
    case frame
    case sessionStrategy
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.terminalProfileID = try container.decodeIfPresent(String.self, forKey: .terminalProfileID)
    self.label = try container.decodeIfPresent(String.self, forKey: .label) ?? terminalProfileID ?? id
    self.repoID = try container.decodeIfPresent(String.self, forKey: .repoID)
    self.paneTemplateID = try container.decodeIfPresent(String.self, forKey: .paneTemplateID)
    self.frame = try container.decode(PercentRect.self, forKey: .frame)
    self.sessionStrategy = try container.decodeIfPresent(TerminalSessionStrategy.self, forKey: .sessionStrategy) ?? .perHost
  }
}

public struct CommandCenterTerminalProfileResolver {
  public init() {}

  public func profile(for host: TerminalHost, in config: CommandCenterConfig) throws -> TerminalProfile {
    if let profileID = host.terminalProfileID {
      guard let profile = config.terminalProfiles?.first(where: { $0.id == profileID }) else {
        throw CommandCenterConfigError.missingTerminalProfile(profileID)
      }
      return profile
    }

    guard let repoID = host.repoID, let paneTemplateID = host.paneTemplateID else {
      throw CommandCenterConfigError.missingTerminalProfile(host.id)
    }

    return TerminalProfile(
      id: host.id,
      label: host.label,
      repoID: repoID,
      paneTemplateID: paneTemplateID
    )
  }
}

public struct AppZone: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var frame: PercentRect
  public var appTargetIDs: [String]

  public init(id: String, label: String, frame: PercentRect, appTargetIDs: [String]) {
    self.id = id
    self.label = label
    self.frame = frame
    self.appTargetIDs = appTargetIDs
  }
}

public struct ScreenLayout: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var terminalHosts: [TerminalHost]
  public var appZones: [AppZone]

  public init(
    id: String,
    label: String,
    terminalHosts: [TerminalHost],
    appZones: [AppZone] = []
  ) {
    self.id = id
    self.label = label
    self.terminalHosts = terminalHosts
    self.appZones = appZones
  }
}

public enum CommandCenterActionKind: String, Codable, CaseIterable, Sendable {
  case shellArgv
  case stop
  case openURL
  case openRepoInEditor
  case focusSurface
  case codexPrompt
}

public struct CommandCenterAction: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var kind: CommandCenterActionKind
  public var hostID: String?
  public var slotID: String?
  public var appTargetID: String?
  public var repoID: String?
  public var url: String?
  public var argv: [String]?

  public init(
    id: String,
    label: String,
    kind: CommandCenterActionKind,
    hostID: String? = nil,
    slotID: String? = nil,
    appTargetID: String? = nil,
    repoID: String? = nil,
    url: String? = nil,
    argv: [String]? = nil
  ) {
    self.id = id
    self.label = label
    self.kind = kind
    self.hostID = hostID
    self.slotID = slotID
    self.appTargetID = appTargetID
    self.repoID = repoID
    self.url = url
    self.argv = argv
  }
}

public struct CommandCenterSection: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var actionIDs: [String]

  public init(id: String, label: String, actionIDs: [String]) {
    self.id = id
    self.label = label
    self.actionIDs = actionIDs
  }
}

public struct CommandCenterProfile: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var layoutIDs: [String]
  public var appTargetIDs: [String]
  public var actionSectionIDs: [String]

  public init(
    id: String,
    label: String,
    layoutIDs: [String],
    appTargetIDs: [String],
    actionSectionIDs: [String]
  ) {
    self.id = id
    self.label = label
    self.layoutIDs = layoutIDs
    self.appTargetIDs = appTargetIDs
    self.actionSectionIDs = actionSectionIDs
  }
}

public struct CommandCenterProfileResolution: Equatable, Sendable {
  public var activeProfile: CommandCenterProfile?
  public var layouts: [ScreenLayout]
  public var appTargets: [AppTarget]
  public var sections: [CommandCenterSection]

  public init(
    activeProfile: CommandCenterProfile?,
    layouts: [ScreenLayout],
    appTargets: [AppTarget],
    sections: [CommandCenterSection]
  ) {
    self.activeProfile = activeProfile
    self.layouts = layouts
    self.appTargets = appTargets
    self.sections = sections
  }
}

public struct CommandCenterProfileResolver {
  public init() {}

  public func selectedProfile(in config: CommandCenterConfig, activeProfileID: String?) -> CommandCenterProfile? {
    guard let profiles = config.profiles, !profiles.isEmpty else {
      return nil
    }
    if let activeProfileID,
       let profile = profiles.first(where: { $0.id == activeProfileID }) {
      return profile
    }
    return profiles[0]
  }

  public func resolve(config: CommandCenterConfig, activeProfileID: String?) -> CommandCenterProfileResolution {
    guard let profile = selectedProfile(in: config, activeProfileID: activeProfileID) else {
      return CommandCenterProfileResolution(
        activeProfile: nil,
        layouts: config.screenLayouts,
        appTargets: config.appTargets,
        sections: config.sections
      )
    }

    return CommandCenterProfileResolution(
      activeProfile: profile,
      layouts: ordered(profile.layoutIDs, from: config.screenLayouts),
      appTargets: ordered(profile.appTargetIDs, from: config.appTargets),
      sections: ordered(profile.actionSectionIDs, from: config.sections)
    )
  }

  private func ordered<T: Identifiable>(_ ids: [String], from values: [T]) -> [T] where T.ID == String {
    var byID: [String: T] = [:]
    for value in values where byID[value.id] == nil {
      byID[value.id] = value
    }
    return ids.compactMap { byID[$0] }
  }
}

public enum CommandCenterConfigError: Error, LocalizedError, Equatable {
  case invalidConfig([PaletteValidationIssue])
  case missingRepo(String)
  case missingAppTarget(String)
  case missingPaneTemplate(String)
  case missingPaneSlot(hostID: String, slotID: String)
  case missingTerminalProfile(String)
  case missingTerminalHost(String)
  case missingScreenLayout(String)
  case missingAction(String)
  case unsupportedSchema(Int)
  case missingActionArgv(String)
  case missingActionURL(String)

  public var errorDescription: String? {
    switch self {
    case let .invalidConfig(issues):
      return issues.map(\.message).joined(separator: " ")
    case let .missingRepo(id):
      return "Unknown repo: \(id)"
    case let .missingAppTarget(id):
      return "Unknown app target: \(id)"
    case let .missingPaneTemplate(id):
      return "Unknown pane template: \(id)"
    case let .missingPaneSlot(hostID, slotID):
      return "Unknown pane slot \(slotID) in host \(hostID)"
    case let .missingTerminalProfile(id):
      return "Unknown terminal profile: \(id)"
    case let .missingTerminalHost(id):
      return "Unknown terminal host: \(id)"
    case let .missingScreenLayout(id):
      return "Unknown screen layout: \(id)"
    case let .missingAction(id):
      return "Unknown action: \(id)"
    case let .unsupportedSchema(version):
      return "Unsupported command center schemaVersion: \(version)"
    case let .missingActionArgv(id):
      return "Action \(id) has no argv."
    case let .missingActionURL(id):
      return "Action \(id) has no URL."
    }
  }
}
