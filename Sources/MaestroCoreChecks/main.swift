import Foundation
import MaestroCore

@main
struct MaestroCoreChecks {
  static func main() throws {
    try checkedInCatalogLoads()
    try repoPathResolverPreservesCurrentWorkOverrides()
    try repoOpenPlanMatchesCompatibilityWindows()
    try riskPolicyBlocksUnknownRiskyScripts()
    try discoveredRiskyScriptsStayBlockedUntilConfigured()
    print("Maestro core checks passed.")
  }

  private static func checkedInCatalogLoads() throws {
    let loader = CatalogLoader(
      configDirectory: repoRoot().appendingPathComponent("maestro/config"),
      pathResolver: RepoPathResolver(environment: ["HOME": "/Users/example"])
    )

    let catalog = try loader.load()

    try expectEqual(catalog.repos.map(\.key), [
      "node",
      "account",
      "admin",
      "plan",
      "board",
      "website",
      "email",
      "ux",
      "tools",
      "resume"
    ], "repo catalog order")
    try expect(catalog.actions.contains { $0.id == "repo.account.open" }, "account open action exists")
    try expect(catalog.actions.contains { $0.id == "bundle.node.cockpit.run" }, "node cockpit bundle action exists")
  }

  private static func repoPathResolverPreservesCurrentWorkOverrides() throws {
    let resolver = RepoPathResolver(environment: [
      "HOME": "/Users/example",
      "WORK_NODE_ROOT": "/tmp/node",
      "WORK_TOOLS_ROOT": "/tmp/maestro",
      "WORK_RESUME_ROOT": "/tmp/resume"
    ])

    try expectEqual(resolver.resolve(RepoPath(root: .node, relative: "node_account")), "/tmp/node/node_account", "node root override")
    try expectEqual(resolver.resolve(RepoPath(root: .tools)), "/tmp/maestro", "tools root override")
    try expectEqual(resolver.resolve(RepoPath(root: .resume)), "/tmp/resume", "resume root override")
  }

  private static func repoOpenPlanMatchesCompatibilityWindows() throws {
    let repo = RepoDefinition(
      key: "tools",
      label: "maestro",
      path: RepoPath(root: .tools),
      tmuxSession: "tools",
      defaultWindows: ["Coding", "shell"]
    )

    let plan = RepoOpenPlan(repo: repo, resolvedPath: "/tmp/maestro", inTmux: true)

    try expectEqual(plan.iTermTitle, "work:tools", "iTerm title")
    try expectEqual(plan.createCommands.map(\.arguments), [
      ["new-session", "-d", "-s", "tools", "-n", "Coding", "-c", "/tmp/maestro"],
      ["new-window", "-t", "tools:", "-n", "shell", "-c", "/tmp/maestro"],
      ["select-window", "-t", "tools:Coding"]
    ], "repo-open tmux plan")
    try expectEqual(plan.focusCommand.arguments, ["switch-client", "-t", "tools"], "tmux focus in existing session")
  }

  private static func riskPolicyBlocksUnknownRiskyScripts() throws {
    let policy = RiskPolicy()

    try expectEqual(policy.classifyPackageScript(name: "dev", body: "vite"), .safe, "dev risk")
    try expectEqual(policy.confirmation(for: .safe), .none, "safe confirmation")
    try expectEqual(policy.classifyPackageScript(name: "deploy", body: "wrangler deploy"), .remote, "deploy risk")
    try expectEqual(policy.confirmation(for: .remote), .review, "remote confirmation")
    try expectEqual(policy.classifyPackageScript(name: "deploy:prod", body: "wrangler deploy --env production"), .production, "prod risk")
    try expectEqual(policy.confirmation(for: .production), .typed, "prod confirmation")
    try expectEqual(policy.classifyPackageScript(name: "reset", body: "rm -rf .wrangler/state"), .destructive, "destructive risk")
    try expectEqual(policy.confirmation(for: .destructive), .typed, "destructive confirmation")
    try expectEqual(policy.classifyPackageScript(name: "seed", body: "node scripts/seed.js"), .unclassified, "unknown script risk")
    try expectEqual(policy.confirmation(for: .unclassified), .blocked, "unclassified confirmation")
  }

  private static func discoveredRiskyScriptsStayBlockedUntilConfigured() throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("maestro-core-checks-\(UUID().uuidString)")
    let repoURL = tempRoot.appendingPathComponent("node_website")
    try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
    let package = """
    {
      "scripts": {
        "dev": "vite",
        "deploy:prod": "wrangler deploy --env production"
      }
    }
    """
    try package.write(to: repoURL.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
    defer {
      try? FileManager.default.removeItem(at: tempRoot)
    }

    let repo = RepoDefinition(
      key: "website",
      label: "node_website",
      path: RepoPath(root: .node, relative: "node_website"),
      tmuxSession: "website",
      defaultWindows: ["coding1", "shell"]
    )
    let builder = CommandCatalogBuilder(
      pathResolver: RepoPathResolver(environment: ["WORK_NODE_ROOT": tempRoot.path])
    )

    let commands = builder.buildCommands(repos: [repo], configuredCommands: [])
    let dev = try require(commands.first { $0.id == "website.dev" }, "discovered dev command")
    let deploy = try require(commands.first { $0.id == "website.deploy:prod" }, "discovered deploy command")

    try expectEqual(dev.confirmation, .none, "safe discovered command confirmation")
    try expectEqual(deploy.risk, .production, "risky discovered command detected risk")
    try expectEqual(deploy.confirmation, .blocked, "risky discovered command remains blocked")
  }

  private static func repoRoot() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    while url.lastPathComponent != "Sources" {
      url.deleteLastPathComponent()
    }
    return url.deletingLastPathComponent()
  }

  private static func expect(_ condition: Bool, _ message: String) throws {
    guard condition else {
      throw CheckFailure(message)
    }
  }

  private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
      throw CheckFailure("\(message): expected \(expected), got \(actual)")
    }
  }

  private static func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
      throw CheckFailure("missing \(message)")
    }
    return value
  }
}

struct CheckFailure: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}
