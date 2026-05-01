import Foundation
import MaestroCore

public struct WorkDevExecutor {
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

  public func open(_ plan: WorkDevPlan) throws {
    try validateDirectories(for: plan)

    if environment["TERM_PROGRAM"] == "iTerm.app" {
      FileHandle.standardOutput.write(Data("\u{001B}]0;\(plan.iTermTitle)\u{0007}".utf8))
    }

    let hasSession = try runner.run(plan.hasSessionCommand)
    if hasSession == 0 {
      try runRequired(plan.killExistingSessionCommand)
    }

    try runRequired(plan.createSessionCommand)
    try runRequired(plan.remainOnExitCommand)

    for command in plan.paneCommands {
      try runRequired(command)
    }
    for command in plan.layoutCommands {
      try runRequired(command)
    }

    try runRequired(plan.focusCommand)
  }

  private func validateDirectories(for plan: WorkDevPlan) throws {
    for target in plan.targets {
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: target.resolvedPath, isDirectory: &isDirectory),
            isDirectory.boolValue else {
        throw WorkDevExecutionError.missingDirectory(target.resolvedPath)
      }
    }
  }

  private func runRequired(_ command: TmuxCommand) throws {
    let status = try runner.run(command)
    guard status == 0 else {
      throw WorkDevExecutionError.commandFailed(command, status)
    }
  }
}

public enum WorkDevExecutionError: Error, LocalizedError, Equatable, Sendable {
  case missingDirectory(String)
  case commandFailed(TmuxCommand, Int32)

  public var errorDescription: String? {
    switch self {
    case let .missingDirectory(path):
      return "Dev target directory does not exist: \(path)"
    case let .commandFailed(command, status):
      return "Command failed with status \(status): \(command.executable) \(command.arguments.joined(separator: " "))"
    }
  }

  public var code: String {
    switch self {
    case .missingDirectory:
      return "missing_dev_target_directory"
    case .commandFailed:
      return "work_dev_command_failed"
    }
  }
}
