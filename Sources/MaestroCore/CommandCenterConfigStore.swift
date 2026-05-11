import Foundation

public struct CommandCenterConfigSaveResult: Equatable, Sendable {
  public var fileURL: URL
  public var backupURL: URL?
  public var validation: PaletteValidationResult

  public init(
    fileURL: URL,
    backupURL: URL? = nil,
    validation: PaletteValidationResult
  ) {
    self.fileURL = fileURL
    self.backupURL = backupURL
    self.validation = validation
  }
}

public struct CommandCenterConfigStore {
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
    try CommandCenterConfigLoader(fileManager: fileManager, environment: environment)
      .load(fileURL: fileURL)
  }

  public func validate(_ config: CommandCenterConfig) -> PaletteValidationResult {
    CommandCenterValidator().validate(config)
  }

  public func save(_ config: CommandCenterConfig, to fileURL: URL) throws -> CommandCenterConfigSaveResult {
    let validation = validate(config)
    guard validation.ok else {
      throw CommandCenterConfigError.invalidConfig(validation.issues)
    }

    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try MaestroJSON.encoder.encode(config)
    try data.write(to: fileURL, options: .atomic)

    return CommandCenterConfigSaveResult(
      fileURL: fileURL,
      backupURL: nil,
      validation: validation
    )
  }
}

public enum CommandCenterConfigReferenceTarget: Equatable, Sendable {
  case repo(String)
  case paneTemplate(String)
  case terminalProfile(String)
  case screenLayout(String)
  case action(String)
}

public struct CommandCenterConfigReference: Identifiable, Equatable, Sendable {
  public var sourceKind: String
  public var sourceID: String
  public var field: String
  public var detail: String

  public init(
    sourceKind: String,
    sourceID: String,
    field: String,
    detail: String
  ) {
    self.sourceKind = sourceKind
    self.sourceID = sourceID
    self.field = field
    self.detail = detail
  }

  public var id: String {
    "\(sourceKind):\(sourceID):\(field):\(detail)"
  }
}

public struct CommandCenterConfigReferenceInspector {
  public init() {}

  public func references(
    to target: CommandCenterConfigReferenceTarget,
    in config: CommandCenterConfig
  ) -> [CommandCenterConfigReference] {
    switch target {
    case let .repo(id):
      return repoReferences(id, in: config)
    case let .paneTemplate(id):
      return paneTemplateReferences(id, in: config)
    case let .terminalProfile(id):
      return terminalProfileReferences(id, in: config)
    case let .screenLayout(id):
      return screenLayoutReferences(id, in: config)
    case let .action(id):
      return actionReferences(id, in: config)
    }
  }

  private func repoReferences(_ id: String, in config: CommandCenterConfig) -> [CommandCenterConfigReference] {
    var references: [CommandCenterConfigReference] = []

    for template in config.paneTemplates {
      for slot in template.slots where slot.repoID == id {
        references.append(reference(
          "Pane Template",
          template.id,
          "slot repo",
          "\(slot.id) uses \(id)"
        ))
      }
    }

    for profile in config.terminalProfiles ?? [] where profile.repoID == id {
      references.append(reference("Terminal Profile", profile.id, "repoID", "uses \(id)"))
    }

    for layout in config.screenLayouts {
      for host in layout.terminalHosts where host.repoID == id {
        references.append(reference("Screen Layout", layout.id, "host repo", "\(host.id) uses \(id)"))
      }
    }

    for action in config.actions where action.repoID == id {
      references.append(reference("Action", action.id, "repoID", "uses \(id)"))
    }

    return references
  }

  private func paneTemplateReferences(_ id: String, in config: CommandCenterConfig) -> [CommandCenterConfigReference] {
    var references: [CommandCenterConfigReference] = []

    for profile in config.terminalProfiles ?? [] where profile.paneTemplateID == id {
      references.append(reference("Terminal Profile", profile.id, "paneTemplateID", "uses \(id)"))
    }

    for layout in config.screenLayouts {
      for host in layout.terminalHosts where host.paneTemplateID == id {
        references.append(reference("Screen Layout", layout.id, "host template", "\(host.id) uses \(id)"))
      }
    }

    return references
  }

  private func terminalProfileReferences(_ id: String, in config: CommandCenterConfig) -> [CommandCenterConfigReference] {
    var references: [CommandCenterConfigReference] = []

    for layout in config.screenLayouts {
      for host in layout.terminalHosts where host.terminalProfileID == id {
        references.append(reference("Screen Layout", layout.id, "terminalProfileID", "\(host.id) uses \(id)"))
      }
    }

    return references
  }

  private func screenLayoutReferences(_ id: String, in config: CommandCenterConfig) -> [CommandCenterConfigReference] {
    var references: [CommandCenterConfigReference] = []

    for profile in config.profiles ?? [] where profile.layoutIDs.contains(id) {
      references.append(reference("Profile", profile.id, "layoutIDs", "includes \(id)"))
    }

    return references
  }

  private func actionReferences(_ id: String, in config: CommandCenterConfig) -> [CommandCenterConfigReference] {
    var references: [CommandCenterConfigReference] = []

    for section in config.sections where section.actionIDs.contains(id) {
      references.append(reference("Section", section.id, "actionIDs", "includes \(id)"))
    }

    return references
  }

  private func reference(
    _ sourceKind: String,
    _ sourceID: String,
    _ field: String,
    _ detail: String
  ) -> CommandCenterConfigReference {
    CommandCenterConfigReference(
      sourceKind: sourceKind,
      sourceID: sourceID,
      field: field,
      detail: detail
    )
  }
}
