import Foundation
import MaestroCore

@main
struct MaestroCoreChecks {
  static func main() throws {
    try checkedInCatalogLoads()
    try repoPathResolverPreservesCurrentWorkOverrides()
    try stateDirectoryResolutionMatchesCompatibilityRules()
    try repoOpenPlanMatchesCompatibilityWindows()
    try riskPolicyBlocksUnknownRiskyScripts()
    try discoveredRiskyScriptsStayBlockedUntilConfigured()
    try catalogValidationReportsFailures()
    try jsonErrorEncodingStaysStable()
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
    try expect(catalog.validation.ok, "checked-in catalog validates")
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

  private static func stateDirectoryResolutionMatchesCompatibilityRules() throws {
    try expectEqual(
      MaestroPaths.defaultStateDirectory(environment: [
        "HOME": "/Users/example",
        "MAESTRO_STATE_DIR": "~/custom-state",
        "XDG_STATE_HOME": "/tmp/xdg-state"
      ]).path,
      "/Users/example/custom-state",
      "MAESTRO_STATE_DIR wins and expands tilde"
    )
    try expectEqual(
      MaestroPaths.defaultStateDirectory(environment: [
        "HOME": "/Users/example",
        "XDG_STATE_HOME": "/tmp/xdg-state"
      ]).path,
      "/tmp/xdg-state/local-tools/maestro",
      "XDG state directory"
    )
    try expectEqual(
      MaestroPaths.defaultStateDirectory(environment: ["HOME": "/Users/example"]).path,
      "/Users/example/.local/state/local-tools/maestro",
      "fallback state directory"
    )
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

  private static func catalogValidationReportsFailures() throws {
    let repo = RepoDefinition(
      key: "account",
      label: "node_account",
      path: RepoPath(root: .node, relative: "node_account"),
      tmuxSession: "account",
      defaultWindows: ["coding1"],
      roles: [
        "coding": "coding1",
        "bogus": "ghost"
      ]
    )
    let duplicateRepo = RepoDefinition(
      key: "account",
      label: "duplicate",
      path: RepoPath(root: .node, relative: "duplicate"),
      tmuxSession: "duplicate",
      defaultWindows: []
    )
    let configuredCommand = CommandDefinition(
      id: "account.dev",
      repoKey: "missing",
      family: .dev,
      risk: .safe,
      environment: .local,
      role: .devServer,
      behavior: .singleton,
      confirmation: .none,
      label: "Account Dev",
      description: "Run dev."
    )
    let duplicateConfiguredCommand = CommandDefinition(
      id: "account.dev",
      repoKey: "account",
      family: .dev,
      risk: .safe,
      environment: .local,
      role: .devServer,
      behavior: .singleton,
      confirmation: .none,
      label: "Duplicate Account Dev",
      description: "Run dev."
    )
    let discoveredRiskyCommand = CommandDefinition(
      id: "account.deploy:prod",
      repoKey: "account",
      script: "deploy:prod",
      argv: ["npm", "run", "deploy:prod"],
      family: .deploy,
      risk: .production,
      environment: .production,
      role: .deploy,
      behavior: .foreground,
      confirmation: .none,
      label: "Deploy Prod",
      description: "wrangler deploy --env production",
      source: "package.json"
    )
    let layout = LayoutDefinition(
      id: "terminal.quad",
      label: "Terminal Quad",
      description: "Test layout.",
      slots: [
        LayoutSlot(id: "slot", app: "iTerm", role: "terminal", unit: "left"),
        LayoutSlot(id: "slot", app: "iTerm", role: "terminal", unit: "right")
      ]
    )
    let action = ActionDefinition(
      id: "bad.action",
      label: "Bad Action",
      description: "Invalid references.",
      type: .commandRun,
      repoKey: "missing",
      commandID: "missing.command",
      layoutID: "missing.layout",
      bundleID: "missing.bundle"
    )
    let duplicateAction = ActionDefinition(
      id: "bad.action",
      label: "Duplicate Action",
      description: "Invalid references.",
      type: .repoOpen
    )
    let bundle = BundleDefinition(
      id: "bad.bundle",
      label: "Bad Bundle",
      description: "Invalid action references.",
      actionIDs: ["missing.action", "missing.action"]
    )
    let catalog = CatalogBundle(
      repos: [repo, duplicateRepo],
      configuredCommands: [configuredCommand, duplicateConfiguredCommand],
      commands: [configuredCommand, configuredCommand, discoveredRiskyCommand],
      configuredActions: [action, duplicateAction],
      actions: [action, duplicateAction],
      layouts: [layout, layout],
      bundles: [bundle, bundle]
    )

    let report = CatalogValidator().validate(catalog)
    let codes = Set(report.errors.map(\.code))

    try expect(!report.ok, "invalid catalog reports not ok")
    try expect(codes.contains("duplicate_repo_id"), "duplicate repo id reported")
    try expect(codes.contains("duplicate_configured_command_id"), "duplicate configured command id reported")
    try expect(codes.contains("duplicate_command_id"), "duplicate command id reported")
    try expect(codes.contains("duplicate_configured_action_id"), "duplicate configured action id reported")
    try expect(codes.contains("duplicate_action_id"), "duplicate action id reported")
    try expect(codes.contains("duplicate_layout_id"), "duplicate layout id reported")
    try expect(codes.contains("duplicate_bundle_id"), "duplicate bundle id reported")
    try expect(codes.contains("repo_missing_default_windows"), "empty repo windows reported")
    try expect(codes.contains("invalid_repo_role"), "invalid repo role reported")
    try expect(codes.contains("unknown_repo_role_window"), "unknown role window reported")
    try expect(codes.contains("unknown_command_repo"), "unknown command repo reported")
    try expect(codes.contains("discovered_risky_command_unblocked"), "unblocked discovered risky command reported")
    try expect(codes.contains("unknown_action_repo"), "unknown action repo reported")
    try expect(codes.contains("unknown_action_command"), "unknown action command reported")
    try expect(codes.contains("unknown_action_layout"), "unknown action layout reported")
    try expect(codes.contains("unknown_action_bundle"), "unknown action bundle reported")
    try expect(codes.contains("missing_action_repo"), "missing action repo reported")
    try expect(codes.contains("duplicate_layout_slot_id"), "duplicate layout slot reported")
    try expect(codes.contains("duplicate_bundle_action_id"), "duplicate bundle action reported")
    try expect(codes.contains("unknown_bundle_action"), "unknown bundle action reported")
  }

  private static func jsonErrorEncodingStaysStable() throws {
    let error = JSONError(error: "Human readable message", code: "stable_error_code")
    let data = try MaestroJSON.encoder.encode(error)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw CheckFailure("JSON error did not encode as an object")
    }

    try expectEqual(object["ok"] as? Bool, false, "JSON error ok field")
    try expectEqual(object["error"] as? String, "Human readable message", "JSON error message")
    try expectEqual(object["code"] as? String, "stable_error_code", "JSON error code")
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
