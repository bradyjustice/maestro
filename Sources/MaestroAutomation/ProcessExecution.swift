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
  public var diagnostics: MaestroDiagnostics

  public init(
    runner: any CommandRunning = ProcessCommandRunner(),
    diagnostics: MaestroDiagnostics = .disabled
  ) {
    self.runner = runner
    self.diagnostics = diagnostics
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

  public func paneCount(session: String, window: String) throws -> Int {
    let result = try runner.run(executable: "tmux", arguments: ["list-panes", "-t", "\(session):\(window)", "-F", "#{pane_index}"])
    guard result.status == 0 else {
      return 0
    }
    return result.stdout.split(separator: "\n", omittingEmptySubsequences: true).count
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

  public func ensureHost(_ host: ResolvedTerminalHost) throws -> TmuxHostPlan {
    let hasSession = try sessionExists(host.sessionName)
    let hasWindow = hasSession ? try windowExists(session: host.sessionName, window: host.windowName) : false
    let panes = hasWindow ? try paneCount(session: host.sessionName, window: host.windowName) : 0
    let plan = CommandCenterTmuxPlanner().ensureHostPlan(
      host: host,
      sessionExists: hasSession,
      windowExists: hasWindow,
      existingPaneCount: panes
    )
    try run(plan.commands)
    return plan
  }

  public func paneCurrentCommand(_ target: ResolvedTerminalTarget) throws -> String {
    try paneCurrentCommand(paneTarget: target.tmuxPaneTarget)
  }

  public func paneCurrentCommand(paneTarget: String) throws -> String {
    let result: ProcessRunResult
    do {
      result = try runner.run(
        executable: "tmux",
        arguments: ["display-message", "-p", "-t", paneTarget, "#{pane_current_command}"]
      )
    } catch {
      emitCommandFailure(
        commandName: "display-message",
        target: paneTarget,
        status: nil,
        stderr: nil,
        error: error
      )
      throw error
    }
    guard result.status == 0 else {
      emitCommandFailure(
        commandName: "display-message",
        target: paneTarget,
        status: result.status,
        stderr: result.stderr
      )
      throw TmuxControllerError.commandFailed(
        ["tmux", "display-message", "-p", "-t", paneTarget, "#{pane_current_command}"],
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
    let result: ProcessRunResult
    do {
      result = try runner.run(executable: command.executable, arguments: command.arguments)
    } catch {
      emitCommandFailure(
        commandName: command.arguments.first ?? command.executable,
        target: targetArgument(in: command.arguments),
        status: nil,
        stderr: nil,
        error: error
      )
      throw error
    }
    guard result.status == 0 else {
      emitCommandFailure(
        commandName: command.arguments.first ?? command.executable,
        target: targetArgument(in: command.arguments),
        status: result.status,
        stderr: result.stderr
      )
      throw TmuxControllerError.commandFailed(command.argv, result.status, result.stderr)
    }
  }

  public func listMaestroPanes(sessions: [String]) throws -> [LiveTmuxPaneSnapshot] {
    guard !sessions.isEmpty else {
      return []
    }
    let result: ProcessRunResult
    do {
      result = try runner.run(
        executable: "tmux",
        arguments: [
          "list-panes",
          "-a",
          "-F",
          "#{session_name}\t#{window_name}\t#{pane_index}\t#{pane_id}\t#{@maestro.repo}\t#{@maestro.role}\t#{@maestro.slot}\t#{pane_current_command}"
        ]
      )
    } catch {
      emitCommandFailure(
        commandName: "list-panes",
        target: nil,
        status: nil,
        stderr: nil,
        error: error
      )
      throw error
    }
    guard result.status == 0 else {
      emitCommandFailure(
        commandName: "list-panes",
        target: nil,
        status: result.status,
        stderr: result.stderr
      )
      return []
    }
    let sessionSet = Set(sessions)
    return LiveTmuxPaneSnapshot.parse(result.stdout).filter { sessionSet.contains($0.sessionName) }
  }

  private func emitCommandFailure(
    commandName: String,
    target: String?,
    status: Int32?,
    stderr: String?,
    error: (any Error)? = nil
  ) {
    var context: [String: String] = [
      "command": commandName
    ]
    if let target {
      context["target"] = target
    }
    if let status {
      context["status"] = String(status)
    }
    if let stderr {
      context["stderr_bytes"] = String(stderr.utf8.count)
    }
    if let error {
      context.merge(MaestroDiagnostics.safeErrorContext(error), uniquingKeysWith: { current, _ in current })
    }
    diagnostics.emit(
      level: .error,
      component: "tmux",
      name: "tmux.command.failure",
      message: "tmux command failed",
      context: context
    )
  }

  private func targetArgument(in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: "-t"),
          arguments.indices.contains(arguments.index(after: index)) else {
      return nil
    }
    return arguments[arguments.index(after: index)]
  }
}

public struct LiveTmuxPaneSnapshot: Codable, Equatable, Sendable {
  public var sessionName: String
  public var windowName: String
  public var paneIndex: Int
  public var paneID: String
  public var repoID: String?
  public var role: String?
  public var slotID: String?
  public var currentCommand: String

  public init(
    sessionName: String,
    windowName: String,
    paneIndex: Int,
    paneID: String,
    repoID: String?,
    role: String?,
    slotID: String?,
    currentCommand: String
  ) {
    self.sessionName = sessionName
    self.windowName = windowName
    self.paneIndex = paneIndex
    self.paneID = paneID
    self.repoID = repoID
    self.role = role
    self.slotID = slotID
    self.currentCommand = currentCommand
  }

  static func parse(_ output: String) -> [LiveTmuxPaneSnapshot] {
    output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
      guard fields.count >= 8, let paneIndex = Int(fields[2]) else {
        return nil
      }
      return LiveTmuxPaneSnapshot(
        sessionName: fields[0],
        windowName: fields[1],
        paneIndex: paneIndex,
        paneID: fields[3],
        repoID: fields[4].isEmpty ? nil : fields[4],
        role: fields[5].isEmpty ? nil : fields[5],
        slotID: fields[6].isEmpty ? nil : fields[6],
        currentCommand: fields[7]
      )
    }
  }
}
