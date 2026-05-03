import Foundation

public enum CommandCenterOwnedTerminalWindowStatus: String, Codable, Equatable, Sendable {
  case canonical
  case quarantined
  case unmanaged
}

public struct CommandCenterOwnedTerminalWindow: Codable, Equatable, Sendable {
  public var profileID: String
  public var iTermWindowID: String
  public var sessionName: String
  public var windowName: String
  public var layoutID: String?
  public var screenID: String?
  public var frame: LayoutRect?
  public var lastSeenAt: String
  public var status: CommandCenterOwnedTerminalWindowStatus

  public init(
    profileID: String,
    iTermWindowID: String,
    sessionName: String,
    windowName: String,
    layoutID: String? = nil,
    screenID: String? = nil,
    frame: LayoutRect? = nil,
    lastSeenAt: String = ISO8601DateFormatter().string(from: Date()),
    status: CommandCenterOwnedTerminalWindowStatus
  ) {
    self.profileID = profileID
    self.iTermWindowID = iTermWindowID
    self.sessionName = sessionName
    self.windowName = windowName
    self.layoutID = layoutID
    self.screenID = screenID
    self.frame = frame
    self.lastSeenAt = lastSeenAt
    self.status = status
  }
}

public struct CommandCenterState: Codable, Equatable, Sendable {
  public var activeLayoutID: String?
  public var hostSessions: [String: String]
  public var terminalWindows: [CommandCenterOwnedTerminalWindow]
  public var updatedAt: String

  public init(
    activeLayoutID: String? = nil,
    hostSessions: [String: String] = [:],
    terminalWindows: [CommandCenterOwnedTerminalWindow] = [],
    updatedAt: String = ISO8601DateFormatter().string(from: Date())
  ) {
    self.activeLayoutID = activeLayoutID
    self.hostSessions = hostSessions
    self.terminalWindows = terminalWindows
    self.updatedAt = updatedAt
  }

  public func canonicalTerminalWindow(profileID: String) -> CommandCenterOwnedTerminalWindow? {
    terminalWindows.first {
      $0.profileID == profileID && $0.status == .canonical
    }
  }

  private enum CodingKeys: String, CodingKey {
    case activeLayoutID
    case hostSessions
    case terminalWindows
    case updatedAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.activeLayoutID = try container.decodeIfPresent(String.self, forKey: .activeLayoutID)
    self.hostSessions = try container.decodeIfPresent([String: String].self, forKey: .hostSessions) ?? [:]
    self.terminalWindows = try container.decodeIfPresent([CommandCenterOwnedTerminalWindow].self, forKey: .terminalWindows) ?? []
    self.updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ISO8601DateFormatter().string(from: Date())
  }
}

public struct CommandCenterStateStore: @unchecked Sendable {
  public var stateDirectory: URL
  public var fileManager: FileManager

  public init(
    stateDirectory: URL,
    fileManager: FileManager = .default
  ) {
    self.stateDirectory = stateDirectory
    self.fileManager = fileManager
  }

  public init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) {
    self.init(
      stateDirectory: Self.defaultStateDirectory(environment: environment),
      fileManager: fileManager
    )
  }

  public static func defaultStateDirectory(environment: [String: String]) -> URL {
    if let explicit = nonEmpty(environment["MAESTRO_STATE_DIR"]) {
      return URL(fileURLWithPath: expandHome(explicit, environment: environment))
    }
    let home = nonEmpty(environment["HOME"]) ?? NSHomeDirectory()
    return URL(fileURLWithPath: home).appendingPathComponent(".maestro/state")
  }

  public var stateFileURL: URL {
    stateDirectory.appendingPathComponent("command-center-state.json")
  }

  public func load() -> CommandCenterState {
    guard let data = try? Data(contentsOf: stateFileURL),
          let state = try? MaestroJSON.decoder.decode(CommandCenterState.self, from: data) else {
      return CommandCenterState()
    }
    return state
  }

  public func save(_ state: CommandCenterState) throws {
    try fileManager.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    let data = try MaestroJSON.encoder.encode(state)
    try data.write(to: stateFileURL, options: [.atomic])
  }
}
