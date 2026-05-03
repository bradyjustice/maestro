import Foundation
import MaestroCore

public struct ProcessRunResult: Equatable, Sendable {
  public var status: Int32
  public var stdout: String
  public var stderr: String

  public init(status: Int32, stdout: String, stderr: String) {
    self.status = status
    self.stdout = stdout
    self.stderr = stderr
  }
}

public protocol CommandRunning: Sendable {
  func run(executable: String, arguments: [String]) throws -> ProcessRunResult
}

public struct ProcessCommandRunner: CommandRunning {
  public init() {}

  public func run(executable: String, arguments: [String]) throws -> ProcessRunResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [executable] + arguments

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    return ProcessRunResult(
      status: process.terminationStatus,
      stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
      stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    )
  }
}

public enum TmuxControllerError: Error, LocalizedError {
  case commandFailed([String], Int32, String)

  public var errorDescription: String? {
    switch self {
    case let .commandFailed(argv, status, stderr):
      let suffix = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      if suffix.isEmpty {
        return "\(argv.joined(separator: " ")) failed with status \(status)."
      }
      return "\(argv.joined(separator: " ")) failed with status \(status): \(suffix)"
    }
  }
}

public struct TmuxController: Sendable {
  public var runner: any CommandRunning

  public init(runner: any CommandRunning = ProcessCommandRunner()) {
    self.runner = runner
  }

  public func sessionExists(_ session: String) throws -> Bool {
    let result = try runner.run(executable: "tmux", arguments: ["has-session", "-t", session])
    return result.status == 0
  }

  public func windowExists(session: String, window: String) throws -> Bool {
    let result = try runner.run(executable: "tmux", arguments: ["list-windows", "-t", session, "-F", "#{window_name}"])
    guard result.status == 0 else {
      return false
    }
    return result.stdout
      .split(separator: "\n", omittingEmptySubsequences: false)
      .contains { String($0) == window }
  }

  public func ensureTarget(_ target: ResolvedTerminalTarget) throws -> TmuxTargetPlan {
    let hasSession = try sessionExists(target.session)
    let hasWindow = hasSession ? try windowExists(session: target.session, window: target.window) : false
    let plan = TmuxPlanner().ensureTargetPlan(
      target: target,
      sessionExists: hasSession,
      windowExists: hasWindow
    )
    try run(plan.commands)
    return plan
  }

  public func paneCurrentCommand(_ target: ResolvedTerminalTarget) throws -> String {
    let result = try runner.run(
      executable: "tmux",
      arguments: ["display-message", "-p", "-t", target.tmuxPaneTarget, "#{pane_current_command}"]
    )
    guard result.status == 0 else {
      throw TmuxControllerError.commandFailed(
        ["tmux", "display-message", "-p", "-t", target.tmuxPaneTarget, "#{pane_current_command}"],
        result.status,
        result.stderr
      )
    }
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func run(_ commands: [TmuxCommand]) throws {
    for command in commands {
      try run(command)
    }
  }

  public func run(_ command: TmuxCommand) throws {
    let result = try runner.run(executable: command.executable, arguments: command.arguments)
    guard result.status == 0 else {
      throw TmuxControllerError.commandFailed(command.argv, result.status, result.stderr)
    }
  }
}

