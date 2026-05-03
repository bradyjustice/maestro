import Foundation

public struct CommandCenterState: Codable, Equatable, Sendable {
  public var activeLayoutID: String?
  public var hostSessions: [String: String]
  public var updatedAt: String

  public init(
    activeLayoutID: String? = nil,
    hostSessions: [String: String] = [:],
    updatedAt: String = ISO8601DateFormatter().string(from: Date())
  ) {
    self.activeLayoutID = activeLayoutID
    self.hostSessions = hostSessions
    self.updatedAt = updatedAt
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
