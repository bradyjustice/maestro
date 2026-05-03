import Foundation

public enum MaestroPaths {
  public static func defaultConfigFile(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
    executableURL: URL? = Bundle.main.executableURL,
    fileManager: FileManager = .default
  ) -> URL {
    if let explicitFile = nonEmpty(environment["MAESTRO_CONFIG_FILE"]) {
      return URL(fileURLWithPath: expandHome(explicitFile, environment: environment))
    }

    if let explicitDirectory = nonEmpty(environment["MAESTRO_CONFIG_DIR"]) {
      return URL(fileURLWithPath: expandHome(explicitDirectory, environment: environment))
        .appendingPathComponent("palette.json")
    }

    if let found = findUp(from: currentDirectory, relativePath: "maestro/config/palette.json", fileManager: fileManager) {
      return found
    }

    if let executableURL,
       let found = findUp(from: executableURL.deletingLastPathComponent(), relativePath: "maestro/config/palette.json", fileManager: fileManager) {
      return found
    }

    return currentDirectory.appendingPathComponent("maestro/config/palette.json")
  }

  private static func findUp(from start: URL, relativePath: String, fileManager: FileManager) -> URL? {
    var cursor = start.standardizedFileURL
    while true {
      let candidate = cursor.appendingPathComponent(relativePath)
      if fileManager.fileExists(atPath: candidate.path) {
        return candidate
      }
      let parent = cursor.deletingLastPathComponent()
      if parent.path == cursor.path {
        return nil
      }
      cursor = parent
    }
  }
}

public struct PaletteConfigLoader {
  public var fileManager: FileManager
  public var environment: [String: String]

  public init(
    fileManager: FileManager = .default,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.fileManager = fileManager
    self.environment = environment
  }

  public func load(fileURL: URL? = nil) throws -> PaletteConfig {
    let url = fileURL ?? MaestroPaths.defaultConfigFile(environment: environment, fileManager: fileManager)
    let data = try Data(contentsOf: url)
    let config = try MaestroJSON.decoder.decode(PaletteConfig.self, from: data)
    let validation = PaletteValidator().validate(config)
    guard validation.ok else {
      throw PaletteConfigError.invalidConfig(validation.issues)
    }
    return config
  }
}

public struct PalettePathResolver {
  public var configDirectory: URL
  public var environment: [String: String]

  public init(
    configDirectory: URL,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.configDirectory = configDirectory
    self.environment = environment
  }

  public func resolve(root: ConfigRoot) -> String {
    resolvePath(root.path, relativeTo: configDirectory)
  }

  public func resolve(target: TerminalTarget, in config: PaletteConfig) throws -> ResolvedTerminalTarget {
    guard let root = config.roots.first(where: { $0.id == target.root }) else {
      throw PaletteConfigError.missingRoot(target.root)
    }
    let rootPath = resolve(root: root)
    let cwd = resolvePath(target.path, relativeTo: URL(fileURLWithPath: rootPath))
    return ResolvedTerminalTarget(
      id: target.id,
      label: target.label,
      session: target.session,
      window: target.window,
      pane: target.pane,
      cwd: cwd
    )
  }

  public func resolvedTargets(in config: PaletteConfig) throws -> [ResolvedTerminalTarget] {
    try config.targets.map { try resolve(target: $0, in: config) }
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

public struct PaletteValidator {
  public init() {}

  public func validate(_ config: PaletteConfig) -> PaletteValidationResult {
    var issues: [PaletteValidationIssue] = []

    if config.schemaVersion != 1 {
      issues.append(issue("unsupported_schema", "palette.json schemaVersion must be 1."))
    }

    validateUnique(config.roots.map(\.id), "root", &issues)
    validateUnique(config.targets.map(\.id), "target", &issues)
    validateUnique(config.regions.map(\.id), "region", &issues)
    validateUnique(config.layouts.map(\.id), "layout", &issues)
    validateUnique(config.buttons.map(\.id), "button", &issues)
    validateUnique(config.sections.map(\.id), "section", &issues)

    let rootIDs = Set(config.roots.map(\.id))
    let targetIDs = Set(config.targets.map(\.id))
    let regionIDs = Set(config.regions.map(\.id))
    let buttonIDs = Set(config.buttons.map(\.id))

    if config.roots.isEmpty {
      issues.append(issue("missing_roots", "palette.json must define at least one root."))
    }
    if config.targets.isEmpty {
      issues.append(issue("missing_targets", "palette.json must define at least one terminal target."))
    }

    for root in config.roots where root.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(issue("empty_root_path", "Root \(root.id) must define a path."))
    }

    for target in config.targets {
      if target.session.isEmpty {
        issues.append(issue("empty_target_session", "Target \(target.id) must define a tmux session."))
      }
      if target.window.isEmpty {
        issues.append(issue("empty_target_window", "Target \(target.id) must define a tmux window."))
      }
      if target.pane < 0 {
        issues.append(issue("invalid_target_pane", "Target \(target.id) pane must be zero or greater."))
      }
      if !rootIDs.contains(target.root) {
        issues.append(issue("unknown_target_root", "Target \(target.id) references unknown root \(target.root)."))
      }
    }

    for region in config.regions where !region.container.isInsideUnitSpace {
      issues.append(issue("invalid_region_container", "Region \(region.id) container must fit inside percentage space."))
    }

    for layout in config.layouts {
      if !regionIDs.contains(layout.region) {
        issues.append(issue("unknown_layout_region", "Layout \(layout.id) references unknown region \(layout.region)."))
      }
      if layout.slots.isEmpty {
        issues.append(issue("empty_layout", "Layout \(layout.id) must define at least one slot."))
      }
      validateUnique(layout.slots.map(\.id), "layout slot in \(layout.id)", &issues)
      for slot in layout.slots {
        if !targetIDs.contains(slot.target) {
          issues.append(issue("unknown_layout_target", "Layout \(layout.id) slot \(slot.id) references unknown target \(slot.target)."))
        }
        if !slot.unit.isInsideUnitSpace {
          issues.append(issue("invalid_slot_unit", "Layout \(layout.id) slot \(slot.id) unit must fit inside its region."))
        }
      }
    }

    for button in config.buttons {
      if !targetIDs.contains(button.target) {
        issues.append(issue("unknown_button_target", "Button \(button.id) references unknown target \(button.target)."))
      }
      switch button.kind {
      case .command:
        if button.argv?.isEmpty ?? true {
          issues.append(issue("empty_button_argv", "Command button \(button.id) must define argv."))
        }
      case .stop:
        if button.argv != nil {
          issues.append(issue("stop_button_argv", "Stop button \(button.id) must not define argv."))
        }
      }
    }

    for section in config.sections {
      for buttonID in section.buttonIDs where !buttonIDs.contains(buttonID) {
        issues.append(issue("unknown_section_button", "Section \(section.id) references unknown button \(buttonID)."))
      }
    }

    return PaletteValidationResult(issues: issues)
  }

  private func validateUnique(_ ids: [String], _ label: String, _ issues: inout [PaletteValidationIssue]) {
    var seen = Set<String>()
    for id in ids {
      if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(issue("empty_\(label.replacingOccurrences(of: " ", with: "_"))_id", "\(label.capitalized) IDs must not be empty."))
      } else if !seen.insert(id).inserted {
        issues.append(issue("duplicate_\(label.replacingOccurrences(of: " ", with: "_"))_id", "Duplicate \(label) id: \(id)."))
      }
    }
  }

  private func issue(_ code: String, _ message: String) -> PaletteValidationIssue {
    PaletteValidationIssue(code: code, message: message)
  }
}

public func expandHome(_ path: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
  guard path == "~" || path.hasPrefix("~/") else {
    return path
  }
  let home = nonEmpty(environment["HOME"]) ?? NSHomeDirectory()
  if path == "~" {
    return home
  }
  return home + "/" + String(path.dropFirst(2))
}

public func nonEmpty(_ value: String?) -> String? {
  guard let value, !value.isEmpty else {
    return nil
  }
  return value
}

