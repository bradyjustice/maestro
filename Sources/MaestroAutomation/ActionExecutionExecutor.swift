import Foundation
import MaestroCore

public struct ActionExecutionExecutor {
  public var catalog: CatalogBundle
  public var environment: [String: String]
  public var pathResolver: RepoPathResolver
  public var runner: CommandRunning
  public var fileManager: FileManager
  public var layoutAutomation: any LayoutAutomation
  public var screenSelection: LayoutScreenSelection
  public var auditLog: ActionAuditLog

  public init(
    catalog: CatalogBundle,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    pathResolver: RepoPathResolver? = nil,
    runner: CommandRunning = ProcessCommandRunner(),
    fileManager: FileManager = .default,
    layoutAutomation: any LayoutAutomation = NativeMacAutomation(),
    screenSelection: LayoutScreenSelection = .active,
    auditLog: ActionAuditLog? = nil
  ) {
    self.catalog = catalog
    self.environment = environment
    self.pathResolver = pathResolver ?? RepoPathResolver(environment: environment)
    self.runner = runner
    self.fileManager = fileManager
    self.layoutAutomation = layoutAutomation
    self.screenSelection = screenSelection
    self.auditLog = auditLog ?? ActionAuditLog(
      stateDirectory: MaestroPaths.defaultStateDirectory(environment: environment),
      fileManager: fileManager
    )
  }

  public func plan(actionID: String) throws -> ActionExecutionPlan {
    try ActionExecutionPlanner(
      catalog: catalog,
      pathResolver: pathResolver,
      environment: environment
    ).plan(actionID: actionID)
  }

  public func run(actionID: String) throws -> ActionExecutionResult {
    try run(plan: plan(actionID: actionID))
  }

  public func run(plan: ActionExecutionPlan) throws -> ActionExecutionResult {
    let startedAt = Date()
    var stepResults: [ActionExecutionStepResult] = []

    try appendAudit(
      actionID: plan.actionID,
      target: plan.type == .bundle ? "bundle:\(plan.actionID)" : "action:\(plan.actionID)",
      risk: plan.steps.map(\.risk).max(by: riskIsLower) ?? .safe,
      outcome: "started",
      message: "Started \(plan.label)."
    )

    guard plan.runnable else {
      let message = plan.blockedReasons.joined(separator: " ")
      for step in plan.steps where !step.runnable {
        let skipped = ActionExecutionStepResult(
          id: step.id,
          actionID: step.actionID,
          label: step.label,
          type: step.type,
          outcome: .skipped,
          message: step.blockedReason ?? "Step is blocked.",
          startedAt: nil,
          finishedAt: Date()
        )
        stepResults.append(skipped)
        try appendStepAudit(step: step, outcome: "skipped", message: skipped.message)
      }
      try appendAudit(
        actionID: plan.actionID,
        target: plan.type == .bundle ? "bundle:\(plan.actionID)" : "action:\(plan.actionID)",
        risk: plan.steps.map(\.risk).max(by: riskIsLower) ?? .safe,
        outcome: "failed",
        message: "Action was blocked before execution."
      )
      return ActionExecutionResult(
        ok: false,
        actionID: plan.actionID,
        label: plan.label,
        startedAt: startedAt,
        finishedAt: Date(),
        message: message.isEmpty ? "Action is blocked." : message,
        plan: plan,
        steps: stepResults
      )
    }

    var failedMessage: String?
    for (offset, step) in plan.steps.enumerated() {
      let stepStartedAt = Date()
      try appendStepAudit(step: step, outcome: "started", message: "Started \(step.label).")

      do {
        let message = try execute(step)
        let result = ActionExecutionStepResult(
          id: step.id,
          actionID: step.actionID,
          label: step.label,
          type: step.type,
          outcome: .succeeded,
          message: message,
          startedAt: stepStartedAt,
          finishedAt: Date()
        )
        stepResults.append(result)
        try appendStepAudit(step: step, outcome: "succeeded", message: result.message)
      } catch {
        let message = sanitizedFailureMessage(for: step, error: error)
        let result = ActionExecutionStepResult(
          id: step.id,
          actionID: step.actionID,
          label: step.label,
          type: step.type,
          outcome: .failed,
          message: message,
          startedAt: stepStartedAt,
          finishedAt: Date()
        )
        stepResults.append(result)
        try appendStepAudit(step: step, outcome: "failed", message: message)
        failedMessage = message

        for skippedStep in plan.steps.dropFirst(offset + 1) {
          let skipped = ActionExecutionStepResult(
            id: skippedStep.id,
            actionID: skippedStep.actionID,
            label: skippedStep.label,
            type: skippedStep.type,
            outcome: .skipped,
            message: "Skipped after \(step.label) failed.",
            startedAt: nil,
            finishedAt: Date()
          )
          stepResults.append(skipped)
          try appendStepAudit(step: skippedStep, outcome: "skipped", message: skipped.message)
        }
        break
      }
    }

    let ok = failedMessage == nil
    let message = failedMessage ?? "Completed \(plan.label)."
    try appendAudit(
      actionID: plan.actionID,
      target: plan.type == .bundle ? "bundle:\(plan.actionID)" : "action:\(plan.actionID)",
      risk: plan.steps.map(\.risk).max(by: riskIsLower) ?? .safe,
      outcome: ok ? "succeeded" : "failed",
      message: message
    )

    return ActionExecutionResult(
      ok: ok,
      actionID: plan.actionID,
      label: plan.label,
      startedAt: startedAt,
      finishedAt: Date(),
      message: message,
      plan: plan,
      steps: stepResults
    )
  }

  private func execute(_ step: ActionExecutionStep) throws -> String {
    switch step.type {
    case .repoOpen:
      guard let plan = step.repoOpenPlan else {
        throw ActionExecutionExecutorError.missingStepPlan(step.actionID)
      }
      try RepoOpenExecutor(
        runner: runner,
        fileManager: fileManager,
        environment: environment
      ).open(plan)
      return "Opened \(plan.repo.label) in tmux session \(plan.repo.tmuxSession)."
    case .commandRun:
      guard let plan = step.commandRunPlan else {
        throw ActionExecutionExecutorError.missingStepPlan(step.actionID)
      }
      try RepoOpenExecutor(
        runner: runner,
        fileManager: fileManager,
        environment: environment
      ).open(plan.repoOpenPlan)
      for command in plan.tmuxCommands {
        let status = try runner.run(command)
        guard status == 0 else {
          throw ActionExecutionExecutorError.commandFailed(step.actionID, status)
        }
      }
      return "Started command \(plan.commandID) in \(plan.tmuxPane)."
    case .layout:
      guard let layoutID = step.layoutID,
            let layout = catalog.layouts.first(where: { $0.id == layoutID }) else {
        throw ActionExecutionExecutorError.missingStepPlan(step.actionID)
      }
      let plan = try layoutAutomation.planLayout(layout, screenSelection: screenSelection)
      let result = try layoutAutomation.applyLayout(plan)
      return "Applied \(layout.label): moved \(result.movedWindowCount) window(s), skipped \(result.skippedSlotCount) slot(s)."
    case .agent:
      throw ActionExecutionExecutorError.unsupportedAction(step.actionID)
    case .bundle:
      throw ActionExecutionExecutorError.unsupportedAction(step.actionID)
    }
  }

  private func appendStepAudit(
    step: ActionExecutionStep,
    outcome: String,
    message: String?
  ) throws {
    try appendAudit(
      actionID: step.actionID,
      target: auditTarget(for: step),
      risk: step.risk,
      outcome: outcome,
      message: message
    )
  }

  private func appendAudit(
    actionID: String,
    target: String,
    risk: RiskTier,
    outcome: String,
    message: String?
  ) throws {
    try auditLog.append(
      AuditEvent(
        timestamp: Date(),
        actionID: actionID,
        actor: environment["USER"].flatMap { $0.isEmpty ? nil : $0 } ?? "local",
        target: target,
        risk: risk,
        outcome: outcome,
        message: message
      )
    )
  }

  private func auditTarget(for step: ActionExecutionStep) -> String {
    if let repoKey = step.repoKey {
      return "repo:\(repoKey)"
    }
    if let layoutID = step.layoutID {
      return "layout:\(layoutID)"
    }
    if let commandID = step.commandID {
      return "command:\(commandID)"
    }
    if let bundleID = step.bundleID {
      return "bundle:\(bundleID)"
    }
    return "action:\(step.actionID)"
  }

  private func sanitizedFailureMessage(for step: ActionExecutionStep, error: Error) -> String {
    switch error {
    case let error as RepoOpenError:
      switch error {
      case let .missingDirectory(path):
        return "Repo directory does not exist: \(path)"
      case let .commandFailed(_, status):
        return "\(step.label) failed while preparing tmux with status \(status)."
      }
    case let error as ActionExecutionExecutorError:
      return error.localizedDescription
    default:
      return error.localizedDescription
    }
  }

  private func riskIsLower(_ lhs: RiskTier, _ rhs: RiskTier) -> Bool {
    riskRank(lhs) < riskRank(rhs)
  }

  private func riskRank(_ risk: RiskTier) -> Int {
    switch risk {
    case .safe: 0
    case .remote: 1
    case .production: 2
    case .destructive: 3
    case .unclassified: 4
    }
  }
}

public enum ActionExecutionExecutorError: Error, LocalizedError, Equatable, Sendable {
  case missingStepPlan(String)
  case commandFailed(String, Int32)
  case unsupportedAction(String)

  public var errorDescription: String? {
    switch self {
    case let .missingStepPlan(actionID):
      return "Action step \(actionID) is missing an executable plan."
    case let .commandFailed(actionID, status):
      return "Action step \(actionID) failed with status \(status)."
    case let .unsupportedAction(actionID):
      return "Action step \(actionID) is not supported by the action executor."
    }
  }
}
