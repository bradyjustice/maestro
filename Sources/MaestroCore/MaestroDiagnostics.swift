import Foundation

public enum MaestroDiagnosticLevel: String, Codable, Equatable, Sendable {
  case debug
  case info
  case warning
  case error
}

public struct MaestroDebugOptions: Equatable, Sendable {
  public var enabled: Bool
  public var logFileURL: URL

  public init(enabled: Bool, logFileURL: URL) {
    self.enabled = enabled
    self.logFileURL = logFileURL
  }

  public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    enabled = Self.isEnabled(environment["MAESTRO_DEBUG"])
    logFileURL = Self.logFileURL(environment: environment)
  }

  public static func disabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> MaestroDebugOptions {
    MaestroDebugOptions(enabled: false, logFileURL: logFileURL(environment: environment))
  }

  private static func isEnabled(_ value: String?) -> Bool {
    guard let value else {
      return false
    }
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes":
      return true
    default:
      return false
    }
  }

  private static func logFileURL(environment: [String: String]) -> URL {
    if let explicit = nonEmpty(environment["MAESTRO_DEBUG_LOG"]) {
      return URL(fileURLWithPath: expandHome(explicit, environment: environment))
    }
    return CommandCenterStateStore.defaultStateDirectory(environment: environment)
      .appendingPathComponent("debug")
      .appendingPathComponent("command-center.jsonl")
  }
}

public struct MaestroDiagnosticEvent: Codable, Equatable, Sendable {
  public var timestamp: String
  public var level: MaestroDiagnosticLevel
  public var component: String
  public var name: String
  public var message: String
  public var context: [String: String]

  public init(
    timestamp: String? = nil,
    level: MaestroDiagnosticLevel,
    component: String,
    name: String,
    message: String,
    context: [String: String] = [:]
  ) {
    self.timestamp = timestamp ?? MaestroDiagnosticEvent.nowTimestamp()
    self.level = level
    self.component = component
    self.name = name
    self.message = message
    self.context = context
  }

  private static func nowTimestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
  }
}

public final class MaestroDiagnostics: @unchecked Sendable {
  public static let disabled = MaestroDiagnostics(options: MaestroDebugOptions.disabled(), writesToStandardError: false)

  public let options: MaestroDebugOptions

  private let fileManager: FileManager
  private let writesToStandardError: Bool
  private let lock = NSLock()
  private let encoder: JSONEncoder

  public init(
    options: MaestroDebugOptions = MaestroDebugOptions(),
    fileManager: FileManager = .default,
    writesToStandardError: Bool = true
  ) {
    self.options = options
    self.fileManager = fileManager
    self.writesToStandardError = writesToStandardError
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    self.encoder = encoder
  }

  public var isEnabled: Bool {
    options.enabled
  }

  public func emit(
    level: MaestroDiagnosticLevel,
    component: String,
    name: String,
    message: String,
    context: [String: String] = [:]
  ) {
    emit(MaestroDiagnosticEvent(
      level: level,
      component: component,
      name: name,
      message: message,
      context: context
    ))
  }

  public func emit(_ event: MaestroDiagnosticEvent) {
    guard options.enabled else {
      return
    }

    lock.lock()
    defer {
      lock.unlock()
    }

    guard let line = try? encoder.encode(event) else {
      return
    }
    let jsonLine = line + Data([0x0a])

    if writesToStandardError {
      FileHandle.standardError.write(jsonLine)
    }

    do {
      try fileManager.createDirectory(
        at: options.logFileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if !fileManager.fileExists(atPath: options.logFileURL.path) {
        fileManager.createFile(atPath: options.logFileURL.path, contents: nil)
      }
      let handle = try FileHandle(forWritingTo: options.logFileURL)
      defer {
        try? handle.close()
      }
      try handle.seekToEnd()
      try handle.write(contentsOf: jsonLine)
    } catch {
      return
    }
  }

  public static func safeErrorContext(_ error: any Error) -> [String: String] {
    let errorType = String(describing: type(of: error))
    return [
      "error_type": errorType,
      "summary": errorType
    ]
  }

  public static func safeSummary(_ value: String, limit: Int = 160) -> String {
    let collapsed = value
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard collapsed.count > limit else {
      return collapsed
    }
    let index = collapsed.index(collapsed.startIndex, offsetBy: limit)
    return String(collapsed[..<index])
  }
}
