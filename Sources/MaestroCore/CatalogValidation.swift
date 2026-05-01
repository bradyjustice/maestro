import Foundation

public struct CatalogValidationIssue: Codable, Equatable, Sendable {
  public var code: String
  public var message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

public struct CatalogValidationReport: Codable, Equatable, Sendable {
  public var ok: Bool
  public var errors: [CatalogValidationIssue]
  public var warnings: [CatalogValidationIssue]

  public init(
    errors: [CatalogValidationIssue] = [],
    warnings: [CatalogValidationIssue] = []
  ) {
    self.ok = errors.isEmpty
    self.errors = errors
    self.warnings = warnings
  }
}

public struct CatalogValidator: Sendable {
  public init() {}

  public func validate(_ catalog: CatalogBundle) -> CatalogValidationReport {
    var errors: [CatalogValidationIssue] = []
    let warnings: [CatalogValidationIssue] = []

    appendDuplicateErrors(
      values: catalog.repos.map(\.key),
      code: "duplicate_repo_id",
      label: "repo",
      to: &errors
    )
    appendDuplicateErrors(
      values: catalog.configuredCommands.map(\.id),
      code: "duplicate_configured_command_id",
      label: "configured command",
      to: &errors
    )
    appendDuplicateErrors(
      values: catalog.commands.map(\.id),
      code: "duplicate_command_id",
      label: "command",
      to: &errors
    )
    appendDuplicateErrors(
      values: catalog.configuredActions.map(\.id),
      code: "duplicate_configured_action_id",
      label: "configured action",
      to: &errors
    )
    appendDuplicateErrors(
      values: catalog.actions.map(\.id),
      code: "duplicate_action_id",
      label: "action",
      to: &errors
    )
    appendDuplicateErrors(
      values: catalog.layouts.map(\.id),
      code: "duplicate_layout_id",
      label: "layout",
      to: &errors
    )
    appendDuplicateErrors(
      values: catalog.bundles.map(\.id),
      code: "duplicate_bundle_id",
      label: "bundle",
      to: &errors
    )

    let repoKeys = Set(catalog.repos.map(\.key))
    let commandIDs = Set(catalog.commands.map(\.id))
    let actionIDs = Set(catalog.actions.map(\.id))
    let layoutIDs = Set(catalog.layouts.map(\.id))
    let bundleIDs = Set(catalog.bundles.map(\.id))

    validateRepos(catalog.repos, errors: &errors)
    validateCommands(catalog.commands, repoKeys: repoKeys, errors: &errors)
    validateActions(
      catalog.actions,
      repoKeys: repoKeys,
      commandIDs: commandIDs,
      layoutIDs: layoutIDs,
      bundleIDs: bundleIDs,
      errors: &errors
    )
    validateLayouts(catalog.layouts, errors: &errors)
    validateBundles(catalog.bundles, actionIDs: actionIDs, errors: &errors)

    return CatalogValidationReport(errors: errors, warnings: warnings)
  }

  private func validateRepos(
    _ repos: [RepoDefinition],
    errors: inout [CatalogValidationIssue]
  ) {
    for repo in repos {
      if repo.defaultWindows.isEmpty {
        errors.append(issue(
          "repo_missing_default_windows",
          "Repo \(repo.key) must define at least one default window."
        ))
      }

      for (role, window) in repo.roles.sorted(by: { $0.key < $1.key }) {
        if TmuxRole(rawValue: role) == nil {
          errors.append(issue(
            "invalid_repo_role",
            "Repo \(repo.key) uses unknown role \(role)."
          ))
        }
        if !repo.defaultWindows.contains(window) {
          errors.append(issue(
            "unknown_repo_role_window",
            "Repo \(repo.key) role \(role) references unknown window \(window)."
          ))
        }
      }
    }
  }

  private func validateCommands(
    _ commands: [CommandDefinition],
    repoKeys: Set<String>,
    errors: inout [CatalogValidationIssue]
  ) {
    for command in commands {
      if let repoKey = command.repoKey, !repoKeys.contains(repoKey) {
        errors.append(issue(
          "unknown_command_repo",
          "Command \(command.id) references unknown repo \(repoKey)."
        ))
      }

      if command.source == "package.json",
         command.risk != .safe,
         command.confirmation != .blocked {
        errors.append(issue(
          "discovered_risky_command_unblocked",
          "Discovered command \(command.id) must stay blocked unless it is explicitly configured."
        ))
      }
    }
  }

  private func validateActions(
    _ actions: [ActionDefinition],
    repoKeys: Set<String>,
    commandIDs: Set<String>,
    layoutIDs: Set<String>,
    bundleIDs: Set<String>,
    errors: inout [CatalogValidationIssue]
  ) {
    for action in actions {
      if let repoKey = action.repoKey, !repoKeys.contains(repoKey) {
        errors.append(issue(
          "unknown_action_repo",
          "Action \(action.id) references unknown repo \(repoKey)."
        ))
      }
      if let commandID = action.commandID, !commandIDs.contains(commandID) {
        errors.append(issue(
          "unknown_action_command",
          "Action \(action.id) references unknown command \(commandID)."
        ))
      }
      if let layoutID = action.layoutID, !layoutIDs.contains(layoutID) {
        errors.append(issue(
          "unknown_action_layout",
          "Action \(action.id) references unknown layout \(layoutID)."
        ))
      }
      if let bundleID = action.bundleID, !bundleIDs.contains(bundleID) {
        errors.append(issue(
          "unknown_action_bundle",
          "Action \(action.id) references unknown bundle \(bundleID)."
        ))
      }

      switch action.type {
      case .repoOpen where action.repoKey == nil:
        errors.append(issue("missing_action_repo", "Repo-open action \(action.id) must reference a repo."))
      case .commandRun where action.commandID == nil:
        errors.append(issue("missing_action_command", "Command action \(action.id) must reference a command."))
      case .layout where action.layoutID == nil:
        errors.append(issue("missing_action_layout", "Layout action \(action.id) must reference a layout."))
      case .bundle where action.bundleID == nil:
        errors.append(issue("missing_action_bundle", "Bundle action \(action.id) must reference a bundle."))
      case .repoOpen, .commandRun, .agent, .layout, .bundle:
        break
      }
    }
  }

  private func validateLayouts(
    _ layouts: [LayoutDefinition],
    errors: inout [CatalogValidationIssue]
  ) {
    for layout in layouts {
      appendDuplicateErrors(
        values: layout.slots.map(\.id),
        code: "duplicate_layout_slot_id",
        label: "layout \(layout.id) slot",
        to: &errors
      )
    }
  }

  private func validateBundles(
    _ bundles: [BundleDefinition],
    actionIDs: Set<String>,
    errors: inout [CatalogValidationIssue]
  ) {
    for bundle in bundles {
      appendDuplicateErrors(
        values: bundle.actionIDs,
        code: "duplicate_bundle_action_id",
        label: "bundle \(bundle.id) action",
        to: &errors
      )

      for actionID in bundle.actionIDs where !actionIDs.contains(actionID) {
        errors.append(issue(
          "unknown_bundle_action",
          "Bundle \(bundle.id) references unknown action \(actionID)."
        ))
      }
    }
  }

  private func appendDuplicateErrors(
    values: [String],
    code: String,
    label: String,
    to errors: inout [CatalogValidationIssue]
  ) {
    for value in duplicateValues(values) {
      errors.append(issue(code, "Duplicate \(label) id: \(value)."))
    }
  }

  private func duplicateValues(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var reported = Set<String>()
    var duplicates: [String] = []

    for value in values {
      if seen.insert(value).inserted {
        continue
      }
      if reported.insert(value).inserted {
        duplicates.append(value)
      }
    }

    return duplicates
  }

  private func issue(_ code: String, _ message: String) -> CatalogValidationIssue {
    CatalogValidationIssue(code: code, message: message)
  }
}
