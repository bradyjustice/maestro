import Foundation
import MaestroCore

public struct AutomationPermissionSnapshot: Codable, Equatable, Sendable {
  public var accessibilityTrusted: Bool
  public var appleEventsAvailable: Bool
  public var notes: [String]

  public init(accessibilityTrusted: Bool, appleEventsAvailable: Bool, notes: [String] = []) {
    self.accessibilityTrusted = accessibilityTrusted
    self.appleEventsAvailable = appleEventsAvailable
    self.notes = notes
  }
}

public protocol AppAutomation {
  func launchOrFocus(bundleIdentifier: String) throws
}

public protocol WindowAutomation {
  func permissionSnapshot(promptForAccessibility: Bool) -> AutomationPermissionSnapshot
}

public protocol CommandRunning {
  @discardableResult
  func run(_ command: TmuxCommand) throws -> Int32
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
