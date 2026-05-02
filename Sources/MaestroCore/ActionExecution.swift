import Foundation

public struct ActionExecutionPlan: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var actionID: String
  public var label: String
  public var type: ActionType
  public var runnable: Bool
  public var blockedReasons: [String]
  public var steps: [ActionExecutionStep]

  public init(
    schemaVersion: Int = 1,
    actionID: String,
    label: String,
    type: ActionType,
    runnable: Bool,
    blockedReasons: [String],
    steps: [ActionExecutionStep]
  ) {
    self.schemaVersion = schemaVersion
    self.actionID = actionID
    self.label = label
    self.type = type
    self.runnable = runnable
    self.blockedReasons = blockedReasons
    self.steps = steps
  }
}

public struct ActionExecutionStep: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var index: Int
  public var actionID: String
  public var label: String
  public var description: String
  public var type: ActionType
  public var risk: RiskTier
  public var confirmation: ConfirmationPolicy
  public var runnable: Bool
  public var blockedReason: String?
  public var repoKey: String?
  public var commandID: String?
  public var layoutID: String?
  public var bundleID: String?
  public var repoOpenPlan: RepoOpenPlan?
  public var commandRunPlan: CommandRunPlan?

  public init(
    id: String = "",
    index: Int = 0,
    actionID: String,
    label: String,
    description: String,
    type: ActionType,
    risk: RiskTier,
    confirmation: ConfirmationPolicy,
    runnable: Bool,
    blockedReason: String? = nil,
    repoKey: String? = nil,
    commandID: String? = nil,
    layoutID: String? = nil,
    bundleID: String? = nil,
    repoOpenPlan: RepoOpenPlan? = nil,
    commandRunPlan: CommandRunPlan? = nil
  ) {
    self.id = id
    self.index = index
    self.actionID = actionID
    self.label = label
    self.description = description
    self.type = type
    self.risk = risk
    self.confirmation = confirmation
    self.runnable = runnable
    self.blockedReason = blockedReason
    self.repoKey = repoKey
    self.commandID = commandID
    self.layoutID = layoutID
    self.bundleID = bundleID
    self.repoOpenPlan = repoOpenPlan
    self.commandRunPlan = commandRunPlan
  }

  public func indexed(_ index: Int) -> ActionExecutionStep {
    var copy = self
    copy.index = index
    copy.id = "\(index + 1).\(actionID)"
    return copy
  }
}

public struct CommandRunPlan: Codable, Equatable, Sendable {
  public var commandID: String
  public var repoKey: String
  public var role: TmuxRole
  public var behavior: CommandBehavior
  public var argv: [String]
  public var displayCommand: String
  public var resolvedPath: String
  public var tmuxSession: String
  public var tmuxWindow: String
  public var tmuxPane: String
  public var repoOpenPlan: RepoOpenPlan
  public var tmuxCommands: [TmuxCommand]

  public init(
    commandID: String,
    repoKey: String,
    role: TmuxRole,
    behavior: CommandBehavior,
    argv: [String],
    displayCommand: String,
    resolvedPath: String,
    tmuxSession: String,
    tmuxWindow: String,
    tmuxPane: String,
    repoOpenPlan: RepoOpenPlan,
    tmuxCommands: [TmuxCommand]
  ) {
    self.commandID = commandID
    self.repoKey = repoKey
    self.role = role
    self.behavior = behavior
    self.argv = argv
    self.displayCommand = displayCommand
    self.resolvedPath = resolvedPath
    self.tmuxSession = tmuxSession
    self.tmuxWindow = tmuxWindow
    self.tmuxPane = tmuxPane
    self.repoOpenPlan = repoOpenPlan
    self.tmuxCommands = tmuxCommands
  }
}

public enum ActionExecutionStepOutcome: String, Codable, Equatable, Sendable {
  case succeeded
  case failed
  case skipped
}

public struct ActionExecutionStepResult: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var actionID: String
  public var label: String
  public var type: ActionType
  public var outcome: ActionExecutionStepOutcome
  public var message: String
  public var startedAt: Date?
  public var finishedAt: Date?

  public init(
    id: String,
    actionID: String,
    label: String,
    type: ActionType,
    outcome: ActionExecutionStepOutcome,
    message: String,
    startedAt: Date? = nil,
    finishedAt: Date? = nil
  ) {
    self.id = id
    self.actionID = actionID
    self.label = label
    self.type = type
    self.outcome = outcome
    self.message = message
    self.startedAt = startedAt
    self.finishedAt = finishedAt
  }
}

public struct ActionExecutionResult: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var ok: Bool
  public var actionID: String
  public var label: String
  public var startedAt: Date
  public var finishedAt: Date
  public var message: String
  public var plan: ActionExecutionPlan
  public var steps: [ActionExecutionStepResult]

  public init(
    schemaVersion: Int = 1,
    ok: Bool,
    actionID: String,
    label: String,
    startedAt: Date,
    finishedAt: Date,
    message: String,
    plan: ActionExecutionPlan,
    steps: [ActionExecutionStepResult]
  ) {
    self.schemaVersion = schemaVersion
    self.ok = ok
    self.actionID = actionID
    self.label = label
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.message = message
    self.plan = plan
    self.steps = steps
  }
}

public struct ActionExecutionPlanner: Sendable {
  public var catalog: CatalogBundle
  public var pathResolver: RepoPathResolver
  public var environment: [String: String]

  public init(
    catalog: CatalogBundle,
    pathResolver: RepoPathResolver = RepoPathResolver(),
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.catalog = catalog
    self.pathResolver = pathResolver
    self.environment = environment
  }

  public func plan(actionID: String) throws -> ActionExecutionPlan {
    guard let action = action(named: actionID) else {
      throw CatalogError.missingAction(actionID)
    }

    let rawSteps: [ActionExecutionStep]
    if action.type == .bundle {
      rawSteps = expandBundle(action, visitedBundleIDs: [])
    } else {
      rawSteps = [step(for: action)]
    }

    let steps = rawSteps.enumerated().map { index, step in
      step.indexed(index)
    }
    let blockedReasons = steps.compactMap { step -> String? in
      guard let reason = step.blockedReason else {
        return nil
      }
      return "\(step.label): \(reason)"
    }
    let runnable = !steps.isEmpty && steps.allSatisfy(\.runnable)

    let emptyBundleReason = action.type == .bundle && steps.isEmpty ? ["\(action.label): Bundle has no child actions."] : []
    return ActionExecutionPlan(
      actionID: action.id,
      label: action.label,
      type: action.type,
      runnable: runnable && emptyBundleReason.isEmpty,
      blockedReasons: blockedReasons + emptyBundleReason,
      steps: steps
    )
  }

  private func expandBundle(
    _ action: ActionDefinition,
    visitedBundleIDs: Set<String>
  ) -> [ActionExecutionStep] {
    guard action.enabled else {
      return [blockedStep(for: action, reason: "This action is blocked by catalog policy.")]
    }
    guard let bundleID = action.bundleID else {
      return [blockedStep(for: action, reason: "No bundle target is configured for this action.")]
    }
    guard let bundle = catalog.bundles.first(where: { $0.id == bundleID }) else {
      return [blockedStep(for: action, reason: "The configured bundle target is not in the catalog.")]
    }
    guard !visitedBundleIDs.contains(bundle.id) else {
      return [blockedStep(for: action, reason: "Bundle expansion cycle detected for \(bundle.id).")]
    }

    var nextVisited = visitedBundleIDs
    nextVisited.insert(bundle.id)

    return bundle.actionIDs.flatMap { childActionID -> [ActionExecutionStep] in
      guard let child = self.action(named: childActionID) else {
        return [
          ActionExecutionStep(
            actionID: childActionID,
            label: childActionID,
            description: "Missing bundled action.",
            type: .bundle,
            risk: .unclassified,
            confirmation: .blocked,
            runnable: false,
            blockedReason: "The bundled action is not in the catalog."
          )
        ]
      }

      if child.type == .bundle {
        return expandBundle(child, visitedBundleIDs: nextVisited)
      }
      return [step(for: child)]
    }
  }

  private func step(for action: ActionDefinition) -> ActionExecutionStep {
    guard action.enabled else {
      return blockedStep(for: action, reason: "This action is blocked by catalog policy.")
    }

    switch action.type {
    case .repoOpen:
      guard let repoKey = action.repoKey else {
        return blockedStep(for: action, reason: "No repo target is configured for this action.")
      }
      guard let repo = repo(named: repoKey) else {
        return blockedStep(for: action, reason: "The configured repo target is not in the catalog.")
      }
      let resolvedPath = pathResolver.resolve(repo.path)
      return ActionExecutionStep(
        actionID: action.id,
        label: action.label,
        description: action.description,
        type: action.type,
        risk: action.risk,
        confirmation: action.confirmation,
        runnable: true,
        repoKey: repo.key,
        commandID: action.commandID,
        layoutID: action.layoutID,
        bundleID: action.bundleID,
        repoOpenPlan: RepoOpenPlan(
          repo: repo,
          resolvedPath: resolvedPath,
          inTmux: environment["TMUX"]?.isEmpty == false
        )
      )
    case .commandRun:
      return commandStep(for: action)
    case .layout:
      guard let layoutID = action.layoutID else {
        return blockedStep(for: action, reason: "No layout target is configured for this action.")
      }
      guard catalog.layouts.contains(where: { $0.id == layoutID }) else {
        return blockedStep(for: action, reason: "The configured layout target is not in the catalog.")
      }
      return baseStep(for: action, runnable: true)
    case .agent:
      return blockedStep(for: action, reason: "Agent action execution is not supported in executable bundles yet.")
    case .bundle:
      return blockedStep(for: action, reason: "Nested bundle action did not expand.")
    }
  }

  private func commandStep(for action: ActionDefinition) -> ActionExecutionStep {
    guard let commandID = action.commandID else {
      return blockedStep(for: action, reason: "No command target is configured for this action.")
    }
    guard let command = command(named: commandID) else {
      return blockedStep(for: action, reason: "The configured command target is not in the catalog.")
    }
    guard command.risk == .safe && action.risk == .safe else {
      return blockedStep(for: action, reason: "Only safe local commands can run from actions.")
    }
    guard command.confirmation == .none && action.confirmation == .none else {
      return blockedStep(for: action, reason: "Only commands with no confirmation requirement can run from actions.")
    }
    guard command.environment == .local else {
      return blockedStep(for: action, reason: "Only local command targets can run from actions.")
    }
    guard let argv = command.argv, !argv.isEmpty else {
      return blockedStep(for: action, reason: "The command does not have a modeled argv.")
    }
    guard command.behavior == .singleton else {
      return blockedStep(for: action, reason: "Unsupported command behavior: \(command.behavior.rawValue).")
    }
    guard let repoKey = action.repoKey ?? command.repoKey else {
      return blockedStep(for: action, reason: "No repo target is configured for this command.")
    }
    guard let repo = repo(named: repoKey) else {
      return blockedStep(for: action, reason: "The configured repo target is not in the catalog.")
    }

    let role = action.role ?? command.role
    guard let window = repo.roles[role.rawValue] else {
      return blockedStep(for: action, reason: "Repo \(repo.key) has no tmux window for role \(role.rawValue).")
    }

    let resolvedPath = pathResolver.resolve(repo.path)
    let repoOpenPlan = RepoOpenPlan(
      repo: repo,
      resolvedPath: resolvedPath,
      inTmux: environment["TMUX"]?.isEmpty == false
    )
    let displayCommand = Self.commandLine(from: argv)
    let tmuxPane = "\(repo.tmuxSession):\(window).0"
    let tmuxCommands = [
      TmuxCommand(arguments: ["select-window", "-t", "\(repo.tmuxSession):\(window)"]),
      TmuxCommand(arguments: ["send-keys", "-t", tmuxPane, displayCommand, "C-m"])
    ]

    return ActionExecutionStep(
      actionID: action.id,
      label: action.label,
      description: action.description,
      type: action.type,
      risk: action.risk,
      confirmation: action.confirmation,
      runnable: true,
      repoKey: repo.key,
      commandID: command.id,
      layoutID: action.layoutID,
      bundleID: action.bundleID,
      commandRunPlan: CommandRunPlan(
        commandID: command.id,
        repoKey: repo.key,
        role: role,
        behavior: command.behavior,
        argv: argv,
        displayCommand: displayCommand,
        resolvedPath: resolvedPath,
        tmuxSession: repo.tmuxSession,
        tmuxWindow: window,
        tmuxPane: tmuxPane,
        repoOpenPlan: repoOpenPlan,
        tmuxCommands: tmuxCommands
      )
    )
  }

  private func baseStep(
    for action: ActionDefinition,
    runnable: Bool,
    blockedReason: String? = nil
  ) -> ActionExecutionStep {
    ActionExecutionStep(
      actionID: action.id,
      label: action.label,
      description: action.description,
      type: action.type,
      risk: action.risk,
      confirmation: action.confirmation,
      runnable: runnable,
      blockedReason: blockedReason,
      repoKey: action.repoKey,
      commandID: action.commandID,
      layoutID: action.layoutID,
      bundleID: action.bundleID
    )
  }

  private func blockedStep(
    for action: ActionDefinition,
    reason: String
  ) -> ActionExecutionStep {
    baseStep(for: action, runnable: false, blockedReason: reason)
  }

  private func action(named id: String) -> ActionDefinition? {
    catalog.actions.first { $0.id == id }
  }

  private func command(named id: String) -> CommandDefinition? {
    catalog.commands.first { $0.id == id }
  }

  private func repo(named key: String) -> RepoDefinition? {
    catalog.repos.first { $0.key == key }
  }

  public static func commandLine(from argv: [String]) -> String {
    argv.map(shellQuote).joined(separator: " ")
  }

  private static func shellQuote(_ value: String) -> String {
    guard !value.isEmpty else {
      return "''"
    }
    if value.range(of: #"^[A-Za-z0-9_@%+=:,./-]+$"#, options: .regularExpression) != nil {
      return value
    }
    return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
  }
}

public struct ActionAuditLog {
  public var stateDirectory: URL
  public var fileManager: FileManager

  public init(
    stateDirectory: URL = MaestroPaths.defaultStateDirectory(),
    fileManager: FileManager = .default
  ) {
    self.stateDirectory = stateDirectory
    self.fileManager = fileManager
  }

  public var fileURL: URL {
    stateDirectory.appendingPathComponent("audit").appendingPathComponent("actions.jsonl")
  }

  public func append(_ event: AuditEvent) throws {
    let directory = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    if !fileManager.fileExists(atPath: fileURL.path) {
      fileManager.createFile(atPath: fileURL.path, contents: nil)
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(event)
    let handle = try FileHandle(forWritingTo: fileURL)
    defer {
      try? handle.close()
    }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
    try handle.write(contentsOf: Data("\n".utf8))
  }
}
