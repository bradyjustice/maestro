import Foundation

public struct CatalogBundle: Equatable, Sendable {
  public var repos: [RepoDefinition]
  public var configuredCommands: [CommandDefinition]
  public var commands: [CommandDefinition]
  public var configuredActions: [ActionDefinition]
  public var actions: [ActionDefinition]
  public var layouts: [LayoutDefinition]
  public var bundles: [BundleDefinition]

  public init(
    repos: [RepoDefinition],
    configuredCommands: [CommandDefinition],
    commands: [CommandDefinition],
    configuredActions: [ActionDefinition],
    actions: [ActionDefinition],
    layouts: [LayoutDefinition],
    bundles: [BundleDefinition]
  ) {
    self.repos = repos
    self.configuredCommands = configuredCommands
    self.commands = commands
    self.configuredActions = configuredActions
    self.actions = actions
    self.layouts = layouts
    self.bundles = bundles
  }
}

public struct CatalogLoader {
  public var configDirectory: URL
  public var pathResolver: RepoPathResolver
  public var fileManager: FileManager

  public init(
    configDirectory: URL = MaestroPaths.defaultConfigDirectory(),
    pathResolver: RepoPathResolver = RepoPathResolver(),
    fileManager: FileManager = .default
  ) {
    self.configDirectory = configDirectory
    self.pathResolver = pathResolver
    self.fileManager = fileManager
  }

  public func load() throws -> CatalogBundle {
    let repos = try loadDocument("repos.json", as: RepoCatalogDocument.self).repos
    let configuredCommands = try loadDocument("commands.json", as: CommandCatalogDocument.self).commands
    let configuredActions = try loadDocument("actions.json", as: ActionCatalogDocument.self).actions
    let layouts = try loadDocument("layouts.json", as: LayoutCatalogDocument.self).layouts
    let bundles = try loadDocument("bundles.json", as: BundleCatalogDocument.self).bundles
    let commands = CommandCatalogBuilder(
      pathResolver: pathResolver,
      fileManager: fileManager
    ).buildCommands(repos: repos, configuredCommands: configuredCommands)
    let actions = ActionRegistry().buildActions(
      repos: repos,
      commands: commands,
      configuredActions: configuredActions,
      layouts: layouts,
      bundles: bundles
    )

    return CatalogBundle(
      repos: repos,
      configuredCommands: configuredCommands,
      commands: commands,
      configuredActions: configuredActions,
      actions: actions,
      layouts: layouts,
      bundles: bundles
    )
  }

  public func loadDocument<T: Decodable>(_ filename: String, as type: T.Type) throws -> T {
    let url = configDirectory.appendingPathComponent(filename)
    do {
      let data = try Data(contentsOf: url)
      return try MaestroJSON.decoder.decode(T.self, from: data)
    } catch let error as DecodingError {
      throw CatalogError.invalidJSON(path: url.path, reason: String(describing: error))
    } catch {
      throw CatalogError.unreadable(path: url.path, reason: error.localizedDescription)
    }
  }
}

public enum CatalogError: Error, LocalizedError, Equatable, Sendable {
  case unreadable(path: String, reason: String)
  case invalidJSON(path: String, reason: String)
  case missingRepo(String)
  case missingCommand(String)
  case missingAction(String)

  public var errorDescription: String? {
    switch self {
    case let .unreadable(path, reason):
      return "Cannot read catalog at \(path): \(reason)"
    case let .invalidJSON(path, reason):
      return "Invalid catalog JSON at \(path): \(reason)"
    case let .missingRepo(key):
      return "Unknown repo: \(key)"
    case let .missingCommand(id):
      return "Unknown command: \(id)"
    case let .missingAction(id):
      return "Unknown action: \(id)"
    }
  }
}

public enum MaestroJSON {
  public static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  public static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
