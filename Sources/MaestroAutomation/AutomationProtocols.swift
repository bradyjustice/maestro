import Foundation
import MaestroCore

public struct AutomationPermissionSnapshot: Codable, Equatable, Sendable {
  public var accessibilityTrusted: Bool
  public var appleEventsAvailable: Bool
  public var accessibilityState: PermissionRecoveryState
  public var automationState: PermissionRecoveryState
  public var accessibilityRecovery: PermissionRecovery
  public var automationRecovery: PermissionRecovery
  public var notes: [String]

  public init(
    accessibilityTrusted: Bool,
    appleEventsAvailable: Bool,
    accessibilityState: PermissionRecoveryState? = nil,
    automationState: PermissionRecoveryState? = nil,
    accessibilityRecovery: PermissionRecovery? = nil,
    automationRecovery: PermissionRecovery? = nil,
    notes: [String] = []
  ) {
    self.accessibilityTrusted = accessibilityTrusted
    self.appleEventsAvailable = appleEventsAvailable
    self.accessibilityState = accessibilityState ?? (accessibilityTrusted ? .ready : .missing)
    self.automationState = automationState ?? (appleEventsAvailable ? .ready : .unavailable)
    self.accessibilityRecovery = accessibilityRecovery ?? PermissionRecovery(
      title: accessibilityTrusted ? "Accessibility Ready" : "Accessibility Permission Required",
      message: accessibilityTrusted ? "Maestro can inventory and place windows." : "Enable Accessibility for Maestro in System Settings before applying layouts.",
      actionLabel: accessibilityTrusted ? nil : "Open Privacy & Security"
    )
    self.automationRecovery = automationRecovery ?? PermissionRecovery(
      title: appleEventsAvailable ? "Automation Available" : "Automation Unavailable",
      message: appleEventsAvailable ? "iTerm-specific Apple Events can be used when a layout requires them." : "Apple Events are unavailable in this environment.",
      actionLabel: appleEventsAvailable ? nil : "Open Privacy & Security"
    )
    self.notes = notes
  }
}

public enum PermissionRecoveryState: String, Codable, Equatable, Sendable {
  case ready
  case missing
  case unavailable
  case unknown
}

public struct PermissionRecovery: Codable, Equatable, Sendable {
  public var title: String
  public var message: String
  public var actionLabel: String?

  public init(title: String, message: String, actionLabel: String? = nil) {
    self.title = title
    self.message = message
    self.actionLabel = actionLabel
  }
}

public struct ItermReadinessSnapshot: Codable, Equatable, Sendable {
  public var bundleIdentifier: String
  public var installed: Bool
  public var running: Bool
  public var launchServicesReady: Bool
  public var knownBundlePathFound: Bool
  public var applicationPath: String?
  public var notes: [String]

  public init(
    bundleIdentifier: String = "com.googlecode.iterm2",
    installed: Bool,
    running: Bool,
    launchServicesReady: Bool? = nil,
    knownBundlePathFound: Bool = false,
    applicationPath: String? = nil,
    notes: [String] = []
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.installed = installed
    self.running = running
    self.launchServicesReady = launchServicesReady ?? installed
    self.knownBundlePathFound = knownBundlePathFound
    self.applicationPath = applicationPath
    self.notes = notes
  }
}

public struct ItermApplicationResolution: Equatable, Sendable {
  public var bundleIdentifier: String
  public var launchServicesURL: URL?
  public var knownBundleURL: URL?

  public init(
    bundleIdentifier: String,
    launchServicesURL: URL?,
    knownBundleURL: URL?
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.launchServicesURL = launchServicesURL
    self.knownBundleURL = knownBundleURL
  }

  public var applicationURL: URL? {
    launchServicesURL ?? knownBundleURL
  }

  public var launchServicesReady: Bool {
    launchServicesURL != nil
  }

  public var knownBundlePathFound: Bool {
    knownBundleURL != nil
  }

  public var installed: Bool {
    applicationURL != nil
  }
}

public struct ItermApplicationResolver {
  public static let bundleIdentifier = "com.googlecode.iterm2"

  public static let knownBundlePaths = [
    "/Applications/iTerm.app",
    "/Applications/iTerm2.app",
    "~/Applications/iTerm.app",
    "~/Applications/iTerm2.app"
  ]

  public var bundleIdentifier: String
  public var knownBundlePaths: [String]
  public var homeDirectory: String
  public var fileManager: FileManager

  public init(
    bundleIdentifier: String = ItermApplicationResolver.bundleIdentifier,
    knownBundlePaths: [String] = ItermApplicationResolver.knownBundlePaths,
    homeDirectory: String = NSHomeDirectory(),
    fileManager: FileManager = .default
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.knownBundlePaths = knownBundlePaths
    self.homeDirectory = homeDirectory
    self.fileManager = fileManager
  }

  public func resolve(launchServicesURL: URL?) -> ItermApplicationResolution {
    ItermApplicationResolution(
      bundleIdentifier: bundleIdentifier,
      launchServicesURL: launchServicesURL,
      knownBundleURL: fallbackBundleURL(excluding: launchServicesURL)
    )
  }

  private func fallbackBundleURL(excluding launchServicesURL: URL?) -> URL? {
    for path in knownBundlePaths {
      let url = URL(fileURLWithPath: expandHome(in: path))
      if let launchServicesURL,
         launchServicesURL.standardizedFileURL.path == url.standardizedFileURL.path {
        continue
      }
      guard fileManager.fileExists(atPath: url.path),
            Bundle(url: url)?.bundleIdentifier == bundleIdentifier else {
        continue
      }
      return url
    }
    return nil
  }

  private func expandHome(in path: String) -> String {
    guard path == "~" || path.hasPrefix("~/") else {
      return path
    }
    if path == "~" {
      return homeDirectory
    }
    return homeDirectory + "/" + String(path.dropFirst(2))
  }
}

public struct LayoutRuntimeReadinessSnapshot: Codable, Equatable, Sendable {
  public var ready: Bool
  public var accessibilityTrusted: Bool
  public var appleEventsAvailable: Bool
  public var iTermInstalled: Bool
  public var iTermWindowCreationAvailable: Bool
  public var blockedReasons: [String]

  public init(
    ready: Bool,
    accessibilityTrusted: Bool,
    appleEventsAvailable: Bool,
    iTermInstalled: Bool,
    iTermWindowCreationAvailable: Bool,
    blockedReasons: [String] = []
  ) {
    self.ready = ready
    self.accessibilityTrusted = accessibilityTrusted
    self.appleEventsAvailable = appleEventsAvailable
    self.iTermInstalled = iTermInstalled
    self.iTermWindowCreationAvailable = iTermWindowCreationAvailable
    self.blockedReasons = blockedReasons
  }
}

public enum ItermWindowProvisioning {
  public static let layoutVariableName = "user.maestroLayout"
  public static let slotVariableName = "user.maestroSlot"
  public static let roleVariableName = "user.maestroRole"

  public static func layoutUsesIterm(_ layout: LayoutDefinition) -> Bool {
    layout.slots.contains { AppMatcher.isIterm(appName: $0.app) }
  }

  public static func layoutUsesIterm(_ plan: LayoutPlan) -> Bool {
    plan.slots.contains { AppMatcher.isIterm(appName: $0.app) }
  }

  public static func missingItermSlots(in plan: LayoutPlan) -> [LayoutPlanSlot] {
    plan.slots.filter { slot in
      slot.status == .missingWindow && AppMatcher.isIterm(appName: slot.app)
    }
  }
}

public protocol AppAutomation {
  func launchOrFocus(bundleIdentifier: String) throws
}

public protocol WindowAutomation {
  func permissionSnapshot(promptForAccessibility: Bool) -> AutomationPermissionSnapshot
  func iTermReadiness() -> ItermReadinessSnapshot
  func screens() -> [LayoutScreen]
  func selectedScreen(_ selection: LayoutScreenSelection) throws -> LayoutScreen
  func windowInventory() throws -> [WindowSnapshot]
}

public protocol LayoutAutomation {
  func planLayout(_ layout: LayoutDefinition, screenSelection: LayoutScreenSelection) throws -> LayoutPlan
  func applyLayout(_ plan: LayoutPlan) throws -> LayoutApplicationResult
}

public protocol LayoutRuntimeReadinessProviding {
  func layoutReadiness(
    for layout: LayoutDefinition,
    promptForAccessibility: Bool
  ) -> LayoutRuntimeReadinessSnapshot
}

public protocol CommandRunning {
  @discardableResult
  func run(_ command: TmuxCommand) throws -> Int32
}

public struct ForegroundCommand: Equatable, Sendable {
  public var executable: String
  public var arguments: [String]
  public var currentDirectoryPath: String?
  public var environment: [String: String]?

  public init(
    executable: String,
    arguments: [String] = [],
    currentDirectoryPath: String? = nil,
    environment: [String: String]? = nil
  ) {
    self.executable = executable
    self.arguments = arguments
    self.currentDirectoryPath = currentDirectoryPath
    self.environment = environment
  }
}

public struct ForegroundCommandResult: Equatable, Sendable {
  public var status: Int32
  public var output: String

  public init(status: Int32, output: String) {
    self.status = status
    self.output = output
  }
}

public protocol ForegroundCommandRunning {
  func run(_ command: ForegroundCommand) throws -> ForegroundCommandResult
}

public struct ProcessCommandRunner: CommandRunning {
  public init() {}

  @discardableResult
  public func run(_ command: TmuxCommand) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command.executable] + command.arguments
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
  }
}

public struct ProcessForegroundCommandRunner: ForegroundCommandRunning {
  public init() {}

  public func run(_ command: ForegroundCommand) throws -> ForegroundCommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command.executable] + command.arguments
    if let currentDirectoryPath = command.currentDirectoryPath {
      process.currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath)
    }
    if let environment = command.environment {
      process.environment = environment
    }

    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()

    let data = output.fileHandleForReading.readDataToEndOfFile()
    return ForegroundCommandResult(
      status: process.terminationStatus,
      output: String(data: data, encoding: .utf8) ?? ""
    )
  }
}

public struct RepoOpenExecutor {
  public var runner: CommandRunning
  public var fileManager: FileManager
  public var environment: [String: String]

  public init(
    runner: CommandRunning = ProcessCommandRunner(),
    fileManager: FileManager = .default,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.runner = runner
    self.fileManager = fileManager
    self.environment = environment
  }

  public func open(_ plan: RepoOpenPlan) throws {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: plan.resolvedPath, isDirectory: &isDirectory),
          isDirectory.boolValue else {
      throw RepoOpenError.missingDirectory(plan.resolvedPath)
    }

    if environment["TERM_PROGRAM"] == "iTerm.app" {
      FileHandle.standardOutput.write(Data("\u{001B}]0;\(plan.iTermTitle)\u{0007}".utf8))
    }

    let hasSession = try runner.run(TmuxCommand(arguments: ["has-session", "-t", plan.repo.tmuxSession]))
    if hasSession != 0 {
      for command in plan.createCommands {
        let status = try runner.run(command)
        guard status == 0 else {
          throw RepoOpenError.commandFailed(command, status)
        }
      }
    }

    let focusStatus = try runner.run(plan.focusCommand)
    guard focusStatus == 0 else {
      throw RepoOpenError.commandFailed(plan.focusCommand, focusStatus)
    }
  }
}

public enum RepoOpenError: Error, LocalizedError, Equatable, Sendable {
  case missingDirectory(String)
  case commandFailed(TmuxCommand, Int32)

  public var errorDescription: String? {
    switch self {
    case let .missingDirectory(path):
      return "Repo directory does not exist: \(path)"
    case let .commandFailed(command, status):
      return "Command failed with status \(status): \(command.executable) \(command.arguments.joined(separator: " "))"
    }
  }
}
