import Foundation

public struct ActionRegistry: Sendable {
  public init() {}

  public func buildActions(
    repos: [RepoDefinition],
    commands: [CommandDefinition],
    configuredActions: [ActionDefinition],
    layouts: [LayoutDefinition],
    bundles: [BundleDefinition]
  ) -> [ActionDefinition] {
    var actionsByID = Dictionary(uniqueKeysWithValues: configuredActions.map { ($0.id, $0) })

    for repo in repos {
      let id = "repo.\(repo.key).open"
      actionsByID[id] = actionsByID[id] ?? ActionDefinition(
        id: id,
        label: "Open \(repo.label)",
        description: "Open or focus the \(repo.label) tmux workspace.",
        type: .repoOpen,
        risk: .safe,
        confirmation: .none,
        repoKey: repo.key,
        role: .coding
      )
    }

    for command in commands {
      let id = "command.\(command.id).run"
      actionsByID[id] = actionsByID[id] ?? ActionDefinition(
        id: id,
        label: command.label,
        description: command.description,
        type: .commandRun,
        risk: command.risk,
        confirmation: command.confirmation,
        repoKey: command.repoKey,
        commandID: command.id,
        role: command.role,
        enabled: command.confirmation != .blocked
      )
    }

    for layout in layouts {
      let id = "layout.\(layout.id).apply"
      actionsByID[id] = actionsByID[id] ?? ActionDefinition(
        id: id,
        label: layout.label,
        description: layout.description,
        type: .layout,
        risk: .safe,
        confirmation: .none,
        layoutID: layout.id
      )
    }

    for bundle in bundles {
      let id = "bundle.\(bundle.id).run"
      let expanded = riskForBundle(bundle, actionsByID: actionsByID)
      actionsByID[id] = actionsByID[id] ?? ActionDefinition(
        id: id,
        label: bundle.label,
        description: bundle.description,
        type: .bundle,
        risk: expanded.risk,
        confirmation: expanded.confirmation,
        bundleID: bundle.id,
        enabled: expanded.confirmation != .blocked
      )
    }

    return actionsByID.values.sorted { $0.id < $1.id }
  }

  private func riskForBundle(
    _ bundle: BundleDefinition,
    actionsByID: [String: ActionDefinition]
  ) -> (risk: RiskTier, confirmation: ConfirmationPolicy) {
    var risk = RiskTier.safe
    var confirmation = ConfirmationPolicy.none

    for actionID in bundle.actionIDs {
      guard let action = actionsByID[actionID] else {
        return (.unclassified, .blocked)
      }
      risk = maxRisk(risk, action.risk)
      confirmation = maxConfirmation(confirmation, action.confirmation)
    }

    return (risk, confirmation)
  }

  private func maxRisk(_ lhs: RiskTier, _ rhs: RiskTier) -> RiskTier {
    riskRank(lhs) >= riskRank(rhs) ? lhs : rhs
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

  private func maxConfirmation(
    _ lhs: ConfirmationPolicy,
    _ rhs: ConfirmationPolicy
  ) -> ConfirmationPolicy {
    confirmationRank(lhs) >= confirmationRank(rhs) ? lhs : rhs
  }

  private func confirmationRank(_ confirmation: ConfirmationPolicy) -> Int {
    switch confirmation {
    case .none: 0
    case .review: 1
    case .typed: 2
    case .blocked: 3
    }
  }
}
