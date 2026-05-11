import Foundation

public struct LoadedCommandCenterConfig: Equatable, Sendable {
  public var config: CommandCenterConfig
  public var fileURL: URL
  public var migratedFromSchemaVersion: Int?

  public init(
    config: CommandCenterConfig,
    fileURL: URL,
    migratedFromSchemaVersion: Int? = nil
  ) {
    self.config = config
    self.fileURL = fileURL
    self.migratedFromSchemaVersion = migratedFromSchemaVersion
  }
}

public struct CommandCenterConfigLoader {
  public var fileManager: FileManager
  public var environment: [String: String]

  public init(
    fileManager: FileManager = .default,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.fileManager = fileManager
    self.environment = environment
  }

  public func load(fileURL: URL? = nil) throws -> LoadedCommandCenterConfig {
    let loaded = try loadUnchecked(fileURL: fileURL)
    let validation = CommandCenterValidator().validate(loaded.config)
    guard validation.ok else {
      throw CommandCenterConfigError.invalidConfig(validation.issues)
    }
    return loaded
  }

  public func loadUnchecked(fileURL: URL? = nil) throws -> LoadedCommandCenterConfig {
    let url = fileURL ?? MaestroPaths.defaultConfigFile(environment: environment, fileManager: fileManager)
    let data = try Data(contentsOf: url)
    let probe = try MaestroJSON.decoder.decode(SchemaProbe.self, from: data)
    let schemaVersion = probe.schemaVersion ?? 1

    switch schemaVersion {
    case 1:
      let legacy = try MaestroJSON.decoder.decode(PaletteConfig.self, from: data)
      return LoadedCommandCenterConfig(
        config: CommandCenterMigrator().migrate(legacy),
        fileURL: url,
        migratedFromSchemaVersion: 1
      )
    case 2:
      let config = try MaestroJSON.decoder.decode(CommandCenterConfig.self, from: data)
      return LoadedCommandCenterConfig(config: config, fileURL: url)
    default:
      throw CommandCenterConfigError.unsupportedSchema(schemaVersion)
    }
  }
}

private struct SchemaProbe: Decodable {
  var schemaVersion: Int?
}

public struct CommandCenterMigrator {
  public init() {}

  public func migrate(_ legacy: PaletteConfig) -> CommandCenterConfig {
    let repoByTarget = legacyTargetRepos(legacy)
    let repos = legacy.targets.compactMap { repoByTarget[$0.id] }
    let singleTemplate = PaneTemplate(
      id: "legacy.single",
      label: "Single Pane",
      slots: [
        PaneSlot(
          id: "main",
          label: "Main",
          role: "main",
          unit: PercentRect(x: 0, y: 0, width: 1, height: 1)
        )
      ]
    )

    let layouts = legacy.layouts.map { layout in
      let region = legacy.regions.first { $0.id == layout.region }
      let hosts = layout.slots.map { slot in
        let target = legacy.targets.first { $0.id == slot.target }
        return TerminalHost(
          id: slot.target,
          label: target?.label ?? slot.target,
          repoID: slot.target,
          paneTemplateID: singleTemplate.id,
          frame: combinedFrame(region: region?.container, slot: slot.unit),
          sessionStrategy: .perHost
        )
      }
      return ScreenLayout(id: layout.id, label: layout.label, terminalHosts: hosts)
    }

    let actions = legacy.buttons.map { button in
      CommandCenterAction(
        id: button.id,
        label: button.label,
        kind: button.kind == .command ? .shellArgv : .stop,
        hostID: button.target,
        slotID: "main",
        argv: button.argv
      )
    }

    let sections = legacy.sections.map {
      CommandCenterSection(id: $0.id, label: $0.label, actionIDs: $0.buttonIDs)
    }

    let profiles = legacy.profiles?.map {
      CommandCenterProfile(
        id: $0.id,
        label: $0.label,
        layoutIDs: $0.layoutIDs,
        appTargetIDs: [],
        actionSectionIDs: $0.sectionIDs
      )
    }

    return CommandCenterConfig(
      schemaVersion: 2,
      workspace: CommandWorkspace(id: "legacy", label: "Legacy Palette"),
      repos: repos,
      appTargets: [],
      paneTemplates: [singleTemplate],
      screenLayouts: layouts,
      actions: actions,
      sections: sections,
      profiles: profiles
    )
  }

  private func legacyTargetRepos(_ legacy: PaletteConfig) -> [String: CommandRepo] {
    var repos: [String: CommandRepo] = [:]
    for target in legacy.targets {
      guard let root = legacy.roots.first(where: { $0.id == target.root }) else {
        continue
      }
      repos[target.id] = CommandRepo(
        id: target.id,
        label: target.label,
        path: join(root: root.path, target: target.path)
      )
    }
    return repos
  }

  private func join(root: String, target: String) -> String {
    guard !target.isEmpty else {
      return root
    }
    if root.hasSuffix("/") {
      return root + target
    }
    return root + "/" + target
  }

  private func combinedFrame(region: PercentRect?, slot: PercentRect) -> PercentRect {
    let base = region ?? PercentRect(x: 0, y: 0, width: 1, height: 1)
    return PercentRect(
      x: base.x + (base.width * slot.x),
      y: base.y + (base.height * slot.y),
      width: base.width * slot.width,
      height: base.height * slot.height
    )
  }
}

public struct CommandCenterValidator {
  public init() {}

  public func validate(_ config: CommandCenterConfig) -> PaletteValidationResult {
    var issues: [PaletteValidationIssue] = []

    if config.schemaVersion != 2 {
      issues.append(issue("unsupported_schema", "palette.json schemaVersion must be 2."))
    }

    validateUnique([config.workspace.id], "workspace", &issues)
    validateUnique(config.repos.map(\.id), "repo", &issues)
    validateUnique(config.appTargets.map(\.id), "app_target", &issues)
    validateUnique(config.paneTemplates.map(\.id), "pane_template", &issues)
    validateUnique(config.terminalProfiles?.map(\.id) ?? [], "terminal_profile", &issues)
    validateUnique(config.screenLayouts.map(\.id), "screen_layout", &issues)
    validateUnique(config.actions.map(\.id), "action", &issues)
    validateUnique(config.sections.map(\.id), "section", &issues)
    validateUnique(config.profiles?.map(\.id) ?? [], "profile", &issues)

    let repoIDs = Set(config.repos.map(\.id))
    let appTargetIDs = Set(config.appTargets.map(\.id))
    let templateIDs = Set(config.paneTemplates.map(\.id))
    let terminalProfileIDs = Set(config.terminalProfiles?.map(\.id) ?? [])
    let layoutIDs = Set(config.screenLayouts.map(\.id))
    let actionIDs = Set(config.actions.map(\.id))
    let sectionIDs = Set(config.sections.map(\.id))
    var actionSlotIDsByHostID: [String: Set<String>] = [:]

    if config.workspace.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(issue("empty_workspace_id", "Workspace id must not be empty."))
    }
    if config.repos.isEmpty {
      issues.append(issue("missing_repos", "Command center config must define at least one repo."))
    }
    if config.paneTemplates.isEmpty {
      issues.append(issue("missing_pane_templates", "Command center config must define at least one pane template."))
    }
    if config.screenLayouts.isEmpty {
      issues.append(issue("missing_screen_layouts", "Command center config must define at least one screen layout."))
    }

    for repo in config.repos where repo.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(issue("empty_repo_path", "Repo \(repo.id) must define a path."))
    }

    for appTarget in config.appTargets {
      let bundleID = appTarget.bundleID?.trimmingCharacters(in: .whitespacesAndNewlines)
      if appTarget.useSystemDefaultBrowser {
        if appTarget.role != .browser {
          issues.append(issue("invalid_default_browser_target_role", "App target \(appTarget.id) can use the system default browser only when its role is browser."))
        }
        if let bundleID, !bundleID.isEmpty {
          issues.append(issue("ambiguous_app_target_browser_resolution", "App target \(appTarget.id) must not define both bundleID and useSystemDefaultBrowser."))
        }
        let defaultURL = appTarget.defaultURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        if defaultURL?.isEmpty ?? true {
          issues.append(issue("missing_default_browser_url", "App target \(appTarget.id) must define defaultURL when using the system default browser."))
        } else if let defaultURL,
                  !(URL(string: defaultURL)?.scheme?.isEmpty == false) {
          issues.append(issue("invalid_default_browser_url", "App target \(appTarget.id) defaultURL must be a valid URL."))
        }
      } else if bundleID?.isEmpty ?? true {
        issues.append(issue("empty_app_bundle_id", "App target \(appTarget.id) must define a bundle ID."))
      }
    }

    for template in config.paneTemplates {
      if template.slots.isEmpty {
        issues.append(issue("empty_pane_template", "Pane template \(template.id) must define at least one slot."))
      }
      validateUnique(template.slots.map(\.id), "pane_slot_in_\(template.id)", &issues)
      for slot in template.slots {
        if !slot.unit.isInsideUnitSpace {
          issues.append(issue("invalid_pane_slot_unit", "Pane template \(template.id) slot \(slot.id) unit must fit inside its host."))
        }
        if let repoID = slot.repoID, !repoIDs.contains(repoID) {
          issues.append(issue("unknown_pane_slot_repo", "Pane template \(template.id) slot \(slot.id) references unknown repo \(repoID)."))
        }
      }
    }

    for profile in config.terminalProfiles ?? [] {
      if !repoIDs.contains(profile.repoID) {
        issues.append(issue("unknown_terminal_profile_repo", "Terminal profile \(profile.id) references unknown repo \(profile.repoID)."))
      }
      if !templateIDs.contains(profile.paneTemplateID) {
        issues.append(issue("unknown_terminal_profile_template", "Terminal profile \(profile.id) references unknown pane template \(profile.paneTemplateID)."))
      }
      if let template = config.paneTemplates.first(where: { $0.id == profile.paneTemplateID }) {
        let slotIDs = Set(template.slots.map(\.id))
        validateUnique(profile.startupCommands.map(\.slotID), "terminal_profile_startup_slot_in_\(profile.id)", &issues)
        for startup in profile.startupCommands {
          if startup.argv.isEmpty {
            issues.append(issue("empty_terminal_profile_startup_argv", "Terminal profile \(profile.id) startup command for slot \(startup.slotID) must define argv."))
          }
          if !slotIDs.contains(startup.slotID) {
            issues.append(issue("unknown_terminal_profile_startup_slot", "Terminal profile \(profile.id) startup command references unknown slot \(startup.slotID)."))
          }
        }
      }
    }

    for layout in config.screenLayouts {
      if layout.terminalHosts.isEmpty && layout.appZones.isEmpty {
        issues.append(issue("empty_screen_layout", "Screen layout \(layout.id) must define a terminal host or app zone."))
      }
      validateUnique(layout.terminalHosts.map(\.id), "terminal_host_in_\(layout.id)", &issues)
      validateUnique(layout.terminalHosts.map(\.effectiveTerminalProfileID), "terminal_profile_in_\(layout.id)", &issues)
      validateUnique(layout.appZones.map(\.id), "app_zone_in_\(layout.id)", &issues)

      for host in layout.terminalHosts {
        if let profileID = host.terminalProfileID {
          if !terminalProfileIDs.contains(profileID) {
            issues.append(issue("unknown_terminal_host_profile", "Terminal host \(host.id) references unknown terminal profile \(profileID)."))
          }
        } else if host.repoID == nil || host.paneTemplateID == nil {
          issues.append(issue("missing_terminal_host_profile", "Terminal host \(host.id) must define terminalProfileID or legacy repoID and paneTemplateID."))
        }
        if let repoID = host.repoID, !repoIDs.contains(repoID) {
          issues.append(issue("unknown_terminal_host_repo", "Terminal host \(host.id) references unknown repo \(repoID)."))
        }
        if let paneTemplateID = host.paneTemplateID, !templateIDs.contains(paneTemplateID) {
          issues.append(issue("unknown_terminal_host_template", "Terminal host \(host.id) references unknown pane template \(paneTemplateID)."))
        }
        if !host.frame.isInsideUnitSpace {
          issues.append(issue("invalid_terminal_host_frame", "Terminal host \(host.id) frame must fit inside percentage space."))
        }
        registerActionSlots(for: host, in: config, slotIDsByHostID: &actionSlotIDsByHostID)
      }

      for zone in layout.appZones {
        if !zone.frame.isInsideUnitSpace {
          issues.append(issue("invalid_app_zone_frame", "App zone \(zone.id) frame must fit inside percentage space."))
        }
        if zone.appTargetIDs.isEmpty {
          issues.append(issue("empty_app_zone_targets", "App zone \(zone.id) must reference at least one app target."))
        }
        for appTargetID in zone.appTargetIDs where !appTargetIDs.contains(appTargetID) {
          issues.append(issue("unknown_app_zone_target", "App zone \(zone.id) references unknown app target \(appTargetID)."))
        }
      }
    }

    let hostIDs = Set(config.screenLayouts.flatMap { layout in
      layout.terminalHosts.flatMap { host in
        [host.id, host.effectiveTerminalProfileID]
      }
    })
    for action in config.actions {
      switch action.kind {
      case .shellArgv:
        if action.argv?.isEmpty ?? true {
          issues.append(issue("empty_action_argv", "Shell action \(action.id) must define argv."))
        }
        validatePaneActionTarget(action, hostIDs: hostIDs, slotIDsByHostID: actionSlotIDsByHostID, issues: &issues)
      case .stop, .codexPrompt:
        validatePaneActionTarget(action, hostIDs: hostIDs, slotIDsByHostID: actionSlotIDsByHostID, issues: &issues)
      case .openURL:
        if action.url?.isEmpty ?? true {
          issues.append(issue("empty_action_url", "Open URL action \(action.id) must define url."))
        }
        validateOptionalAppTarget(action, appTargetIDs: appTargetIDs, issues: &issues)
      case .openRepoInEditor:
        if let repoID = action.repoID {
          if !repoIDs.contains(repoID) {
            issues.append(issue("unknown_action_repo", "Action \(action.id) references unknown repo \(repoID)."))
          }
        } else {
          issues.append(issue("missing_action_repo", "Action \(action.id) must define repoID."))
        }
        if action.appTargetID == nil {
          issues.append(issue("missing_action_app_target", "Action \(action.id) must define appTargetID."))
        }
        validateOptionalAppTarget(action, appTargetIDs: appTargetIDs, issues: &issues)
      case .focusSurface:
        let hasHost = action.hostID.map { hostIDs.contains($0) } ?? false
        let hasApp = action.appTargetID.map { appTargetIDs.contains($0) } ?? false
        if !hasHost && !hasApp {
          issues.append(issue("missing_focus_surface", "Focus action \(action.id) must reference a terminal host or app target."))
        }
        if let hostID = action.hostID, !hostIDs.contains(hostID) {
          issues.append(issue("unknown_action_host", "Action \(action.id) references unknown terminal host \(hostID)."))
        }
        validateOptionalAppTarget(action, appTargetIDs: appTargetIDs, issues: &issues)
      }
    }

    for section in config.sections {
      validateUnique(section.actionIDs, "section_action_in_\(section.id)", &issues)
      for actionID in section.actionIDs where !actionIDs.contains(actionID) {
        issues.append(issue("unknown_section_action", "Section \(section.id) references unknown action \(actionID)."))
      }
    }

    for profile in config.profiles ?? [] {
      validateUnique(profile.layoutIDs, "profile_layout_in_\(profile.id)", &issues)
      validateUnique(profile.appTargetIDs, "profile_app_target_in_\(profile.id)", &issues)
      validateUnique(profile.actionSectionIDs, "profile_section_in_\(profile.id)", &issues)
      for layoutID in profile.layoutIDs where !layoutIDs.contains(layoutID) {
        issues.append(issue("unknown_profile_layout", "Profile \(profile.id) references unknown layout \(layoutID)."))
      }
      for appTargetID in profile.appTargetIDs where !appTargetIDs.contains(appTargetID) {
        issues.append(issue("unknown_profile_app_target", "Profile \(profile.id) references unknown app target \(appTargetID)."))
      }
      for sectionID in profile.actionSectionIDs where !sectionIDs.contains(sectionID) {
        issues.append(issue("unknown_profile_section", "Profile \(profile.id) references unknown section \(sectionID)."))
      }
    }

    return PaletteValidationResult(issues: issues)
  }

  private func validatePaneActionTarget(
    _ action: CommandCenterAction,
    hostIDs: Set<String>,
    slotIDsByHostID: [String: Set<String>],
    issues: inout [PaletteValidationIssue]
  ) {
    guard let hostID = action.hostID, let slotID = action.slotID, !slotID.isEmpty else {
      issues.append(issue("missing_action_pane_target", "Action \(action.id) must define hostID and slotID."))
      return
    }
    if !hostIDs.contains(hostID) {
      issues.append(issue("unknown_action_host", "Action \(action.id) references unknown terminal host \(hostID)."))
      return
    }
    if !(slotIDsByHostID[hostID]?.contains(slotID) ?? false) {
      issues.append(issue("unknown_action_slot", "Action \(action.id) references unknown slot \(slotID) on terminal host \(hostID)."))
    }
  }

  private func registerActionSlots(
    for host: TerminalHost,
    in config: CommandCenterConfig,
    slotIDsByHostID: inout [String: Set<String>]
  ) {
    let profile = try? CommandCenterTerminalProfileResolver().profile(for: host, in: config)
    let templateID = profile?.paneTemplateID ?? host.paneTemplateID
    guard let templateID,
          let template = config.paneTemplates.first(where: { $0.id == templateID }) else {
      return
    }

    let slotIDs = Set(template.slots.map(\.id))
    for hostID in Set([host.id, host.effectiveTerminalProfileID, profile?.id].compactMap { $0 }) {
      slotIDsByHostID[hostID, default: []].formUnion(slotIDs)
    }
  }

  private func validateOptionalAppTarget(
    _ action: CommandCenterAction,
    appTargetIDs: Set<String>,
    issues: inout [PaletteValidationIssue]
  ) {
    if let appTargetID = action.appTargetID, !appTargetIDs.contains(appTargetID) {
      issues.append(issue("unknown_action_app_target", "Action \(action.id) references unknown app target \(appTargetID)."))
    }
  }

  private func validateUnique(_ ids: [String], _ label: String, _ issues: inout [PaletteValidationIssue]) {
    var seen = Set<String>()
    for id in ids {
      if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(issue("empty_\(label)_id", "\(label.replacingOccurrences(of: "_", with: " ").capitalized) IDs must not be empty."))
      } else if !seen.insert(id).inserted {
        issues.append(issue("duplicate_\(label)_id", "Duplicate \(label.replacingOccurrences(of: "_", with: " ")) id: \(id)."))
      }
    }
  }

  private func issue(_ code: String, _ message: String) -> PaletteValidationIssue {
    PaletteValidationIssue(code: code, message: message)
  }
}

public struct CommandCenterPathResolver {
  public var configDirectory: URL
  public var environment: [String: String]

  public init(
    configDirectory: URL,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.configDirectory = configDirectory
    self.environment = environment
  }

  public func resolve(repo: CommandRepo) -> String {
    resolvePath(repo.path, relativeTo: configDirectory)
  }

  public func resolvePath(_ path: String, relativeTo base: URL) -> String {
    let expanded = expandHome(path, environment: environment)
    if expanded.isEmpty {
      return base.standardizedFileURL.path
    }
    if expanded.hasPrefix("/") {
      return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }
    return base.appendingPathComponent(expanded).standardizedFileURL.path
  }
}
