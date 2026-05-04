import Foundation

public enum WorkspaceConfigConstants {
  public static let schemaVersion = 3
  public static let repoID = "workspace"
  public static let layoutID = "workspace"
  public static let terminalHostID = "main"
  public static let paneTemplateID = "single"
  public static let appZoneID = "apps"
  public static let browserID = "browser"
  public static let vsCodeID = "vscode"
}

public struct WorkspaceConfig: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var workspace: WorkspaceDefinition
  public var browser: WorkspaceAppSettings
  public var vsCode: WorkspaceAppSettings

  public init(
    schemaVersion: Int,
    workspace: WorkspaceDefinition,
    browser: WorkspaceAppSettings,
    vsCode: WorkspaceAppSettings
  ) {
    self.schemaVersion = schemaVersion
    self.workspace = workspace
    self.browser = browser
    self.vsCode = vsCode
  }
}

public struct WorkspaceDefinition: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var path: String

  public init(id: String, label: String, path: String) {
    self.id = id
    self.label = label
    self.path = path
  }
}

public struct WorkspaceAppSettings: Codable, Equatable, Sendable {
  public var label: String
  public var bundleID: String?
  public var useSystemDefaultBrowser: Bool
  public var defaultURL: String?

  public init(
    label: String,
    bundleID: String? = nil,
    useSystemDefaultBrowser: Bool = false,
    defaultURL: String? = nil
  ) {
    self.label = label
    self.bundleID = bundleID
    self.useSystemDefaultBrowser = useSystemDefaultBrowser
    self.defaultURL = defaultURL
  }

  private enum CodingKeys: String, CodingKey {
    case label
    case bundleID
    case useSystemDefaultBrowser
    case defaultURL
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.label = try container.decode(String.self, forKey: .label)
    self.bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
    self.useSystemDefaultBrowser = try container.decodeIfPresent(Bool.self, forKey: .useSystemDefaultBrowser) ?? false
    self.defaultURL = try container.decodeIfPresent(String.self, forKey: .defaultURL)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(label, forKey: .label)
    try container.encodeIfPresent(bundleID, forKey: .bundleID)
    if useSystemDefaultBrowser {
      try container.encode(useSystemDefaultBrowser, forKey: .useSystemDefaultBrowser)
    }
    try container.encodeIfPresent(defaultURL, forKey: .defaultURL)
  }
}

public struct LoadedWorkspaceConfig: Equatable, Sendable {
  public var config: WorkspaceConfig
  public var fileURL: URL

  public init(config: WorkspaceConfig, fileURL: URL) {
    self.config = config
    self.fileURL = fileURL
  }
}

public struct WorkspaceConfigLoader {
  public var fileManager: FileManager
  public var environment: [String: String]

  public init(
    fileManager: FileManager = .default,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.fileManager = fileManager
    self.environment = environment
  }

  public func load(fileURL: URL? = nil) throws -> LoadedWorkspaceConfig {
    let loaded = try loadUnchecked(fileURL: fileURL)
    let validation = WorkspaceConfigValidator().validate(loaded.config)
    guard validation.ok else {
      throw WorkspaceConfigError.invalidConfig(validation.issues)
    }
    return loaded
  }

  public func loadUnchecked(fileURL: URL? = nil) throws -> LoadedWorkspaceConfig {
    let url = fileURL ?? MaestroPaths.defaultWorkspaceConfigFile(
      environment: environment,
      fileManager: fileManager
    )
    let data = try Data(contentsOf: url)
    let config = try MaestroJSON.decoder.decode(WorkspaceConfig.self, from: data)
    return LoadedWorkspaceConfig(config: config, fileURL: url)
  }
}

public enum WorkspaceConfigError: Error, LocalizedError, Equatable {
  case invalidConfig([PaletteValidationIssue])
  case unsupportedSchema(Int)

  public var errorDescription: String? {
    switch self {
    case let .invalidConfig(issues):
      return issues.map(\.message).joined(separator: " ")
    case let .unsupportedSchema(version):
      return "Unsupported workspace schemaVersion: \(version)"
    }
  }
}

public struct WorkspaceConfigValidator {
  public init() {}

  public func validate(_ config: WorkspaceConfig) -> PaletteValidationResult {
    var issues: [PaletteValidationIssue] = []

    if config.schemaVersion != WorkspaceConfigConstants.schemaVersion {
      issues.append(issue("unsupported_schema", "workspace.json schemaVersion must be 3."))
    }

    if config.workspace.id.trimmedForWorkspaceValidation.isEmpty {
      issues.append(issue("empty_workspace_id", "Workspace id must not be empty."))
    }
    if config.workspace.label.trimmedForWorkspaceValidation.isEmpty {
      issues.append(issue("empty_workspace_label", "Workspace label must not be empty."))
    }
    if config.workspace.path.trimmedForWorkspaceValidation.isEmpty {
      issues.append(issue("empty_workspace_path", "Workspace path must not be empty."))
    }

    validateApp(config.browser, id: WorkspaceConfigConstants.browserID, role: .browser, issues: &issues)
    validateApp(config.vsCode, id: WorkspaceConfigConstants.vsCodeID, role: .editor, issues: &issues)

    if issues.isEmpty {
      let internalConfig = WorkspaceCommandCenterAdapter().commandCenterConfig(from: config)
      let internalValidation = CommandCenterValidator().validate(internalConfig)
      for internalIssue in internalValidation.issues {
        issues.append(issue("internal_\(internalIssue.code)", internalIssue.message))
      }
    }

    return PaletteValidationResult(issues: issues)
  }

  private func validateApp(
    _ app: WorkspaceAppSettings,
    id: String,
    role: AppTargetRole,
    issues: inout [PaletteValidationIssue]
  ) {
    if app.label.trimmedForWorkspaceValidation.isEmpty {
      issues.append(issue("empty_\(id)_label", "\(appDisplayName(id)) label must not be empty."))
    }

    let bundleID = app.bundleID?.trimmedForWorkspaceValidation ?? ""
    if app.useSystemDefaultBrowser {
      if role != .browser {
        issues.append(issue("invalid_\(id)_default_browser", "\(appDisplayName(id)) cannot use the system default browser."))
      }
      if !bundleID.isEmpty {
        issues.append(issue("ambiguous_\(id)_resolution", "\(appDisplayName(id)) must not define both bundleID and useSystemDefaultBrowser."))
      }
      let defaultURL = app.defaultURL?.trimmedForWorkspaceValidation ?? ""
      if defaultURL.isEmpty {
        issues.append(issue("missing_\(id)_default_url", "\(appDisplayName(id)) must define defaultURL when using the system default browser."))
      } else if URL(string: defaultURL)?.scheme?.isEmpty ?? true {
        issues.append(issue("invalid_\(id)_default_url", "\(appDisplayName(id)) defaultURL must be a valid URL."))
      }
      return
    }

    if bundleID.isEmpty {
      issues.append(issue("empty_\(id)_bundle_id", "\(appDisplayName(id)) must define a bundle ID."))
    }
  }

  private func appDisplayName(_ id: String) -> String {
    id == WorkspaceConfigConstants.vsCodeID ? "VS Code" : "Browser"
  }

  private func issue(_ code: String, _ message: String) -> PaletteValidationIssue {
    PaletteValidationIssue(code: code, message: message)
  }
}

public struct WorkspacePathResolver {
  public var configDirectory: URL
  public var environment: [String: String]

  public init(
    configDirectory: URL,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.configDirectory = configDirectory
    self.environment = environment
  }

  public func resolveWorkspacePath(_ config: WorkspaceConfig) -> String {
    CommandCenterPathResolver(configDirectory: configDirectory, environment: environment)
      .resolvePath(config.workspace.path, relativeTo: configDirectory)
  }
}

public struct WorkspaceCommandCenterAdapter {
  public init() {}

  public func commandCenterConfig(from workspaceConfig: WorkspaceConfig) -> CommandCenterConfig {
    CommandCenterConfig(
      schemaVersion: 2,
      workspace: CommandWorkspace(
        id: workspaceConfig.workspace.id,
        label: workspaceConfig.workspace.label
      ),
      repos: [
        CommandRepo(
          id: WorkspaceConfigConstants.repoID,
          label: workspaceConfig.workspace.label,
          path: workspaceConfig.workspace.path
        )
      ],
      appTargets: [
        appTarget(
          id: WorkspaceConfigConstants.browserID,
          settings: workspaceConfig.browser,
          role: .browser
        ),
        appTarget(
          id: WorkspaceConfigConstants.vsCodeID,
          settings: workspaceConfig.vsCode,
          role: .editor
        )
      ],
      paneTemplates: [
        PaneTemplate(
          id: WorkspaceConfigConstants.paneTemplateID,
          label: "Workspace Shell",
          slots: [
            PaneSlot(
              id: "main",
              label: workspaceConfig.workspace.label,
              role: "shell",
              unit: PercentRect(x: 0, y: 0, width: 1, height: 1),
              repoID: WorkspaceConfigConstants.repoID
            )
          ]
        )
      ],
      screenLayouts: [
        ScreenLayout(
          id: WorkspaceConfigConstants.layoutID,
          label: workspaceConfig.workspace.label,
          terminalHosts: [
            TerminalHost(
              id: WorkspaceConfigConstants.terminalHostID,
              label: "Terminal",
              repoID: WorkspaceConfigConstants.repoID,
              paneTemplateID: WorkspaceConfigConstants.paneTemplateID,
              frame: PercentRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)
            )
          ],
          appZones: [
            AppZone(
              id: WorkspaceConfigConstants.appZoneID,
              label: "Browser and VS Code",
              frame: PercentRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1),
              appTargetIDs: [
                WorkspaceConfigConstants.browserID,
                WorkspaceConfigConstants.vsCodeID
              ]
            )
          ]
        )
      ],
      actions: [],
      sections: []
    )
  }

  private func appTarget(
    id: String,
    settings: WorkspaceAppSettings,
    role: AppTargetRole
  ) -> AppTarget {
    AppTarget(
      id: id,
      label: settings.label,
      bundleID: settings.bundleID?.trimmedForWorkspaceValidation.nilIfEmptyForWorkspaceValidation,
      useSystemDefaultBrowser: settings.useSystemDefaultBrowser,
      role: role,
      defaultURL: settings.defaultURL?.trimmedForWorkspaceValidation.nilIfEmptyForWorkspaceValidation
    )
  }
}

public struct ResolvedWorkspaceSummary: Codable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var path: String

  public init(id: String, label: String, path: String) {
    self.id = id
    self.label = label
    self.path = path
  }
}

public struct WorkspaceTerminalArrangePlan: Codable, Equatable, Sendable {
  public var label: String
  public var sessionName: String
  public var windowName: String
  public var frame: LayoutRect
  public var status: CommandCenterSurfaceStatus
  public var ownershipDecision: CommandCenterWindowOwnershipDecision
  public var window: TerminalWindowSnapshot?

  public init(
    label: String,
    sessionName: String,
    windowName: String,
    frame: LayoutRect,
    status: CommandCenterSurfaceStatus,
    ownershipDecision: CommandCenterWindowOwnershipDecision,
    window: TerminalWindowSnapshot? = nil
  ) {
    self.label = label
    self.sessionName = sessionName
    self.windowName = windowName
    self.frame = frame
    self.status = status
    self.ownershipDecision = ownershipDecision
    self.window = window
  }
}

public struct WorkspaceAppArrangePlan: Codable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var bundleID: String?
  public var useSystemDefaultBrowser: Bool
  public var frame: LayoutRect

  public init(
    id: String,
    label: String,
    bundleID: String?,
    useSystemDefaultBrowser: Bool,
    frame: LayoutRect
  ) {
    self.id = id
    self.label = label
    self.bundleID = bundleID
    self.useSystemDefaultBrowser = useSystemDefaultBrowser
    self.frame = frame
  }
}

public struct WorkspaceAppAreaArrangePlan: Codable, Equatable, Sendable {
  public var label: String
  public var frame: LayoutRect
  public var apps: [WorkspaceAppArrangePlan]

  public init(label: String, frame: LayoutRect, apps: [WorkspaceAppArrangePlan]) {
    self.label = label
    self.frame = frame
    self.apps = apps
  }
}

public struct WorkspaceArrangePlan: Codable, Equatable, Sendable {
  public var workspace: ResolvedWorkspaceSummary
  public var screen: LayoutScreen
  public var terminal: WorkspaceTerminalArrangePlan
  public var appArea: WorkspaceAppAreaArrangePlan

  public init(
    workspace: ResolvedWorkspaceSummary,
    screen: LayoutScreen,
    terminal: WorkspaceTerminalArrangePlan,
    appArea: WorkspaceAppAreaArrangePlan
  ) {
    self.workspace = workspace
    self.screen = screen
    self.terminal = terminal
    self.appArea = appArea
  }
}

public struct WorkspaceArrangePlanBuilder {
  public init() {}

  public func build(
    workspaceConfig: WorkspaceConfig,
    configDirectory: URL,
    environment: [String: String],
    layoutPlan: CommandCenterLayoutPlan,
    internalConfig: CommandCenterConfig
  ) throws -> WorkspaceArrangePlan {
    guard let terminalHost = layoutPlan.terminalHosts.first else {
      throw CommandCenterConfigError.missingTerminalHost(WorkspaceConfigConstants.terminalHostID)
    }
    guard let appZone = layoutPlan.appZones.first else {
      throw CommandCenterConfigError.missingScreenLayout(WorkspaceConfigConstants.layoutID)
    }

    let appTargetsByID = Dictionary(uniqueKeysWithValues: internalConfig.appTargets.map { ($0.id, $0) })
    let apps = appZone.appTargetIDs.compactMap { appTargetID -> WorkspaceAppArrangePlan? in
      guard let appTarget = appTargetsByID[appTargetID] else {
        return nil
      }
      return WorkspaceAppArrangePlan(
        id: appTarget.id,
        label: appTarget.label,
        bundleID: appTarget.bundleID,
        useSystemDefaultBrowser: appTarget.useSystemDefaultBrowser,
        frame: appZone.frame
      )
    }

    return WorkspaceArrangePlan(
      workspace: ResolvedWorkspaceSummary(
        id: workspaceConfig.workspace.id,
        label: workspaceConfig.workspace.label,
        path: WorkspacePathResolver(configDirectory: configDirectory, environment: environment)
          .resolveWorkspacePath(workspaceConfig)
      ),
      screen: layoutPlan.screen,
      terminal: WorkspaceTerminalArrangePlan(
        label: terminalHost.label,
        sessionName: terminalHost.sessionName,
        windowName: terminalHost.windowName,
        frame: terminalHost.frame,
        status: terminalHost.status,
        ownershipDecision: terminalHost.ownershipDecision,
        window: terminalHost.window
      ),
      appArea: WorkspaceAppAreaArrangePlan(
        label: appZone.label,
        frame: appZone.frame,
        apps: apps
      )
    )
  }
}

private extension String {
  var trimmedForWorkspaceValidation: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var nilIfEmptyForWorkspaceValidation: String? {
    isEmpty ? nil : self
  }
}
