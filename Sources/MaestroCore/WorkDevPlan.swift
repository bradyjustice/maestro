import Foundation

public enum WorkDevTarget: String, Codable, CaseIterable, Sendable {
  case website
  case account
  case admin
  case shell
}

public struct WorkDevTargetPlan: Codable, Equatable, Sendable {
  public var target: WorkDevTarget
  public var resolvedPath: String
  public var paneIndex: Int
  public var runsDevServer: Bool

  public init(
    target: WorkDevTarget,
    resolvedPath: String,
    paneIndex: Int,
    runsDevServer: Bool
  ) {
    self.target = target
    self.resolvedPath = resolvedPath
    self.paneIndex = paneIndex
    self.runsDevServer = runsDevServer
  }
}

public struct WorkDevPlan: Codable, Equatable, Sendable {
  public var session: String
  public var window: String
  public var iTermTitle: String
  public var targets: [WorkDevTargetPlan]
  public var hasSessionCommand: TmuxCommand
  public var killExistingSessionCommand: TmuxCommand
  public var createSessionCommand: TmuxCommand
  public var remainOnExitCommand: TmuxCommand
  public var paneCommands: [TmuxCommand]
  public var layoutCommands: [TmuxCommand]
  public var focusCommand: TmuxCommand

  public init(
    targets selectedTargets: [WorkDevTarget],
    pathResolver: RepoPathResolver = RepoPathResolver(),
    inTmux: Bool
  ) throws {
    guard let firstTarget = selectedTargets.first else {
      throw WorkDevPlanError.missingTargets
    }

    let session = "node-dev"
    let window = "dev"
    let plannedTargets = selectedTargets.enumerated().map { index, target in
      WorkDevTargetPlan(
        target: target,
        resolvedPath: Self.resolvedPath(for: target, pathResolver: pathResolver),
        paneIndex: index,
        runsDevServer: target != .shell
      )
    }
    let firstPath = Self.resolvedPath(for: firstTarget, pathResolver: pathResolver)

    self.session = session
    self.window = window
    self.iTermTitle = "work:\(session)"
    self.targets = plannedTargets
    self.hasSessionCommand = TmuxCommand(arguments: ["has-session", "-t", session])
    self.killExistingSessionCommand = TmuxCommand(arguments: ["kill-session", "-t", session])
    self.createSessionCommand = TmuxCommand(
      arguments: ["new-session", "-d", "-s", session, "-n", window, "-c", firstPath]
    )
    self.remainOnExitCommand = TmuxCommand(
      arguments: ["set-window-option", "-t", "\(session):\(window)", "remain-on-exit", "on"]
    )
    self.paneCommands = Self.paneCommands(
      session: session,
      window: window,
      targets: plannedTargets
    )
    self.layoutCommands = [
      TmuxCommand(arguments: ["select-layout", "-t", "\(session):\(window)", "tiled"]),
      TmuxCommand(arguments: ["select-pane", "-t", "\(session):\(window).0"])
    ]
    self.focusCommand = TmuxCommand(
      arguments: inTmux ? ["switch-client", "-t", session] : ["attach-session", "-t", session]
    )
  }

  public static func targets(from arguments: [String]) throws -> [WorkDevTarget] {
    guard !arguments.isEmpty else {
      throw WorkDevPlanError.missingTargets
    }

    var wantWebsite = false
    var wantAccount = false
    var wantAdmin = false
    var wantShell = false

    for argument in arguments {
      switch argument {
      case "all":
        wantWebsite = true
        wantAccount = true
        wantAdmin = true
      case "website":
        wantWebsite = true
      case "account":
        wantAccount = true
      case "admin":
        wantAdmin = true
      case "shell":
        wantShell = true
      default:
        throw WorkDevPlanError.invalidTargets
      }
    }

    guard wantWebsite || wantAccount || wantAdmin else {
      throw WorkDevPlanError.invalidTargets
    }

    var targets: [WorkDevTarget] = []
    if wantWebsite {
      targets.append(.website)
    }
    if wantAccount {
      targets.append(.account)
    }
    if wantAdmin {
      targets.append(.admin)
    }
    if wantShell {
      targets.append(.shell)
    }
    return targets
  }

  private static func paneCommands(
    session: String,
    window: String,
    targets: [WorkDevTargetPlan]
  ) -> [TmuxCommand] {
    targets.flatMap { target -> [TmuxCommand] in
      var commands: [TmuxCommand] = []
      if target.paneIndex > 0 {
        commands.append(
          TmuxCommand(arguments: ["split-window", "-t", "\(session):\(window)", "-c", target.resolvedPath])
        )
      }
      if target.runsDevServer {
        commands.append(
          TmuxCommand(arguments: ["send-keys", "-t", "\(session):\(window).\(target.paneIndex)", "npm run dev", "C-m"])
        )
      }
      return commands
    }
  }

  private static func resolvedPath(
    for target: WorkDevTarget,
    pathResolver: RepoPathResolver
  ) -> String {
    switch target {
    case .website:
      return pathResolver.resolve(RepoPath(root: .node, relative: "node_website"))
    case .account:
      return pathResolver.resolve(RepoPath(root: .node, relative: "node_account"))
    case .admin:
      return pathResolver.resolve(RepoPath(root: .node, relative: "node_admin"))
    case .shell:
      return pathResolver.resolve(RepoPath(root: .node))
    }
  }
}

public enum WorkDevPlanError: Error, LocalizedError, Equatable, Sendable {
  case missingTargets
  case invalidTargets

  public var errorDescription: String? {
    switch self {
    case .missingTargets:
      return "Missing dev targets."
    case .invalidTargets:
      return "Invalid dev targets."
    }
  }

  public var code: String {
    switch self {
    case .missingTargets:
      return "missing_dev_targets"
    case .invalidTargets:
      return "invalid_dev_targets"
    }
  }
}
