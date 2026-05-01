import Foundation

public struct CommandCatalogBuilder {
  public var pathResolver: RepoPathResolver
  public var riskPolicy: RiskPolicy
  public var fileManager: FileManager

  public init(
    pathResolver: RepoPathResolver = RepoPathResolver(),
    riskPolicy: RiskPolicy = RiskPolicy(),
    fileManager: FileManager = .default
  ) {
    self.pathResolver = pathResolver
    self.riskPolicy = riskPolicy
    self.fileManager = fileManager
  }

  public func buildCommands(
    repos: [RepoDefinition],
    configuredCommands: [CommandDefinition]
  ) -> [CommandDefinition] {
    var commandsByID = Dictionary(uniqueKeysWithValues: configuredCommands.map { ($0.id, $0) })

    for repo in repos {
      let repoPath = pathResolver.resolve(repo.path)
      for script in discoverPackageScripts(at: repoPath) {
        let id = "\(repo.key).\(script.name)"
        guard commandsByID[id] == nil else {
          continue
        }

        let family = riskPolicy.family(for: script.name, body: script.body)
        let risk = riskPolicy.classifyPackageScript(name: script.name, body: script.body)
        let confirmation: ConfirmationPolicy = risk == .safe ? .none : .blocked
        let command = CommandDefinition(
          id: id,
          repoKey: repo.key,
          script: script.name,
          argv: ["npm", "run", script.name],
          family: family,
          risk: risk,
          environment: riskPolicy.environment(for: risk, scriptName: script.name, body: script.body),
          role: riskPolicy.role(for: family),
          behavior: riskPolicy.behavior(for: family),
          confirmation: confirmation,
          label: "\(repo.label) \(script.name)",
          description: script.body,
          source: "package.json"
        )
        commandsByID[id] = command
      }
    }

    return commandsByID.values.sorted { $0.id < $1.id }
  }

  public func discoverPackageScripts(at repoPath: String) -> [PackageScript] {
    let packageURL = URL(fileURLWithPath: repoPath).appendingPathComponent("package.json")
    guard fileManager.fileExists(atPath: packageURL.path),
          let data = try? Data(contentsOf: packageURL),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let scripts = object["scripts"] as? [String: String]
    else {
      return []
    }

    return scripts
      .map { PackageScript(name: $0.key, body: $0.value) }
      .sorted { $0.name < $1.name }
  }
}

public struct PackageScript: Equatable, Sendable {
  public var name: String
  public var body: String

  public init(name: String, body: String) {
    self.name = name
    self.body = body
  }
}
