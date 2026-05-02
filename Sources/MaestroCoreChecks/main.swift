import Foundation
import MaestroCore

@main
struct MaestroCoreChecks {
  static func main() throws {
    try checkedInCatalogLoads()
    try repoPathResolverPreservesCurrentWorkOverrides()
    try stateDirectoryResolutionMatchesCompatibilityRules()
    try repoOpenPlanMatchesCompatibilityWindows()
    try workDevTargetSelectionMatchesCompatibility()
    try workDevPlanMatchesCompatibilityCommands()
    try layoutPlanningCoversRepresentativeScreens()
    try layoutPlanningReportsPermissionMissing()
    try layoutPlannerFiltersUnmanagedWindows()
    try riskPolicyBlocksUnknownRiskyScripts()
    try discoveredRiskyScriptsStayBlockedUntilConfigured()
    try actionExecutionExpandsBundlesDeterministically()
    try actionExecutionCommandEligibilityIsExplicit()
    try actionExecutionReportsBlockedBundleReasons()
    try actionAuditLogWritesJSONLines()
    try catalogValidationReportsFailures()
    try jsonErrorEncodingStaysStable()
    print("Maestro core checks passed.")
  }

  private static func checkedInCatalogLoads() throws {
    let catalog = try checkedInCatalog()

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
    try expect(catalog.layouts.contains { $0.id == "terminal.six-up" }, "terminal six-up layout exists")
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

  private static func workDevTargetSelectionMatchesCompatibility() throws {
    try expectEqual(
      try WorkDevPlan.targets(from: ["website", "account"]),
      [.website, .account],
      "explicit work dev target order"
    )
    try expectEqual(
      try WorkDevPlan.targets(from: ["all", "shell"]),
      [.website, .account, .admin, .shell],
      "all target expansion with shell"
    )
    try expectEqual(
      try WorkDevPlan.targets(from: ["admin", "website"]),
      [.website, .admin],
      "compatibility target ordering"
    )

    do {
      _ = try WorkDevPlan.targets(from: [])
      throw CheckFailure("expected missing work dev targets to fail")
    } catch let error as WorkDevPlanError {
      try expectEqual(error, .missingTargets, "missing dev targets error")
    }

    do {
      _ = try WorkDevPlan.targets(from: ["shell"])
      throw CheckFailure("expected shell-only work dev targets to fail")
    } catch let error as WorkDevPlanError {
      try expectEqual(error, .invalidTargets, "shell-only dev targets error")
    }

    do {
      _ = try WorkDevPlan.targets(from: ["nope"])
      throw CheckFailure("expected invalid work dev targets to fail")
    } catch let error as WorkDevPlanError {
      try expectEqual(error, .invalidTargets, "invalid dev targets error")
    }
  }

  private static func workDevPlanMatchesCompatibilityCommands() throws {
    let plan = try WorkDevPlan(
      targets: [.website, .account, .admin, .shell],
      pathResolver: RepoPathResolver(environment: ["WORK_NODE_ROOT": "/tmp/node"]),
      inTmux: true
    )

    try expectEqual(plan.session, "node-dev", "work dev session")
    try expectEqual(plan.window, "dev", "work dev window")
    try expectEqual(plan.iTermTitle, "work:node-dev", "work dev iTerm title")
    try expectEqual(plan.targets.map(\.resolvedPath), [
      "/tmp/node/node_website",
      "/tmp/node/node_account",
      "/tmp/node/node_admin",
      "/tmp/node"
    ], "work dev target paths")
    try expectEqual(plan.targets.map(\.paneIndex), [0, 1, 2, 3], "work dev pane indexes")
    try expectEqual(plan.targets.map(\.runsDevServer), [true, true, true, false], "work dev server flags")
    try expectEqual(plan.hasSessionCommand.arguments, ["has-session", "-t", "node-dev"], "work dev has-session command")
    try expectEqual(plan.killExistingSessionCommand.arguments, ["kill-session", "-t", "node-dev"], "work dev kill-session command")
    try expectEqual(
      plan.createSessionCommand.arguments,
      ["new-session", "-d", "-s", "node-dev", "-n", "dev", "-c", "/tmp/node/node_website"],
      "work dev new-session command"
    )
    try expectEqual(
      plan.remainOnExitCommand.arguments,
      ["set-window-option", "-t", "node-dev:dev", "remain-on-exit", "on"],
      "work dev remain-on-exit command"
    )
    try expectEqual(plan.paneCommands.map(\.arguments), [
      ["send-keys", "-t", "node-dev:dev.0", "npm run dev", "C-m"],
      ["split-window", "-t", "node-dev:dev", "-c", "/tmp/node/node_account"],
      ["send-keys", "-t", "node-dev:dev.1", "npm run dev", "C-m"],
      ["split-window", "-t", "node-dev:dev", "-c", "/tmp/node/node_admin"],
      ["send-keys", "-t", "node-dev:dev.2", "npm run dev", "C-m"],
      ["split-window", "-t", "node-dev:dev", "-c", "/tmp/node"]
    ], "work dev pane commands")
    try expectEqual(plan.layoutCommands.map(\.arguments), [
      ["select-layout", "-t", "node-dev:dev", "tiled"],
      ["select-pane", "-t", "node-dev:dev.0"]
    ], "work dev layout commands")
    try expectEqual(plan.focusCommand.arguments, ["switch-client", "-t", "node-dev"], "work dev tmux focus")
  }

  private static func layoutPlanningCoversRepresentativeScreens() throws {
    let layouts = [
      terminalStackLayout(),
      terminalQuadLayout(),
      terminalSixUpLayout(),
      codingWorkspaceLayout()
    ]
    let screens = [
      testScreen(id: "laptop", width: 1512, height: 982),
      testScreen(id: "external-16x9", width: 1920, height: 1080),
      testScreen(id: "ultrawide", width: 3440, height: 1440),
      testScreen(id: "tv", width: 3840, height: 2160)
    ]
    let windows = [
      testWindow(id: "iterm-1", appName: "iTerm2", bundleIdentifier: "com.googlecode.iterm2", title: "One"),
      testWindow(id: "iterm-2", appName: "iTerm2", bundleIdentifier: "com.googlecode.iterm2", title: "Two"),
      testWindow(id: "iterm-3", appName: "iTerm2", bundleIdentifier: "com.googlecode.iterm2", title: "Three"),
      testWindow(id: "iterm-4", appName: "iTerm2", bundleIdentifier: "com.googlecode.iterm2", title: "Four"),
      testWindow(id: "iterm-5", appName: "iTerm2", bundleIdentifier: "com.googlecode.iterm2", title: "Five"),
      testWindow(id: "iterm-6", appName: "iTerm2", bundleIdentifier: "com.googlecode.iterm2", title: "Six"),
      testWindow(id: "code", appName: "Code", bundleIdentifier: "com.microsoft.VSCode", title: "Code"),
      testWindow(id: "safari", appName: "Safari", bundleIdentifier: "com.apple.Safari", title: "Safari")
    ]

    for screen in screens {
      for layout in layouts {
        let plan = try LayoutPlanner().plan(layout: layout, screen: screen, windows: windows)
        try expectEqual(plan.slots.count, layout.slots.count, "\(layout.id) slot count on \(screen.id)")
        for slot in plan.slots {
          try expect(slot.frame.width > 0, "\(layout.id) \(slot.slotID) width on \(screen.id)")
          try expect(slot.frame.height > 0, "\(layout.id) \(slot.slotID) height on \(screen.id)")
          try expect(screen.visibleFrame.contains(slot.frame), "\(layout.id) \(slot.slotID) stays inside \(screen.id)")
        }
      }
    }
  }

  private static func layoutPlanningReportsPermissionMissing() throws {
    let plan = try LayoutPlanner().plan(
      layout: terminalQuadLayout(),
      screen: testScreen(id: "main", width: 1920, height: 1080),
      windows: [],
      inventoryStatus: .accessibilityPermissionMissing
    )

    try expectEqual(plan.inventoryStatus, .accessibilityPermissionMissing, "layout permission inventory status")
    try expect(plan.issues.contains { $0.code == "accessibility-permission-missing" }, "layout permission issue")
    try expect(plan.slots.allSatisfy { $0.status == .missingWindow }, "layout slots stay inspectable without inventory")
  }

  private static func layoutPlannerFiltersUnmanagedWindows() throws {
    let plan = try LayoutPlanner().plan(
      layout: terminalStackLayout(),
      screen: testScreen(id: "main", width: 1920, height: 1080),
      windows: [
        testWindow(id: "iterm-1", appName: "iTerm2", bundleIdentifier: "com.googlecode.iterm2", title: "One"),
        testWindow(id: "iterm-2", appName: "iTerm2", bundleIdentifier: "com.googlecode.iterm2", title: "Two"),
        testWindow(id: "iterm-3", appName: "iTerm2", bundleIdentifier: "com.googlecode.iterm2", title: "Three"),
        testWindow(id: "safari", appName: "Safari", bundleIdentifier: "com.apple.Safari", title: "Safari")
      ]
    )

    try expectEqual(plan.moveCount, 2, "terminal stack only targets two windows")
    try expectEqual(plan.unmanagedWindowCount, 2, "unmanaged window count includes extra target and unrelated app")
    try expectEqual(plan.unmanagedTargetWindows.map(\.id), ["iterm-3"], "only extra targeted app window is reported")
    try expect(!plan.slots.contains { $0.window?.id == "safari" }, "unrelated app is not assigned to a terminal slot")
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

  private static func actionExecutionExpandsBundlesDeterministically() throws {
    let catalog = try checkedInCatalog()
    let planner = ActionExecutionPlanner(
      catalog: catalog,
      pathResolver: RepoPathResolver(environment: ["HOME": "/Users/example"]),
      environment: ["TMUX": "1"]
    )

    let plan = try planner.plan(actionID: "bundle.backend.cockpit.run")

    try expect(plan.runnable, "backend cockpit bundle is runnable")
    try expectEqual(plan.steps.map(\.actionID), [
      "repo.account.open",
      "repo.admin.open",
      "command.account.dev.run",
      "command.admin.dev.run",
      "layout.terminal.quad.apply"
    ], "backend cockpit expansion order")
    try expectEqual(plan.steps.map(\.id), [
      "1.repo.account.open",
      "2.repo.admin.open",
      "3.command.account.dev.run",
      "4.command.admin.dev.run",
      "5.layout.terminal.quad.apply"
    ], "backend cockpit deterministic step ids")
  }

  private static func actionExecutionCommandEligibilityIsExplicit() throws {
    let catalog = try checkedInCatalog()
    let planner = ActionExecutionPlanner(
      catalog: catalog,
      pathResolver: RepoPathResolver(environment: ["HOME": "/Users/example"]),
      environment: ["TMUX": "1"]
    )

    let devPlan = try planner.plan(actionID: "command.account.dev.run")
    let devStep = try require(devPlan.steps.first, "account dev action step")
    let commandPlan = try require(devStep.commandRunPlan, "account dev command run plan")
    try expect(devPlan.runnable, "safe singleton command is runnable")
    try expectEqual(commandPlan.argv, ["npm", "run", "dev"], "safe command argv")
    try expectEqual(commandPlan.displayCommand, "npm run dev", "safe command display")
    try expectEqual(commandPlan.tmuxPane, "account:dev.0", "safe command tmux target")
    try expectEqual(commandPlan.tmuxCommands.map(\.arguments), [
      ["select-window", "-t", "account:dev"],
      ["send-keys", "-t", "account:dev.0", "npm run dev", "C-m"]
    ], "safe command tmux commands")

    let checkPlan = try planner.plan(actionID: "command.account.check.run")
    try expect(!checkPlan.runnable, "foreground command is blocked until supported")
    try expect(
      checkPlan.blockedReasons.contains { $0.contains("Unsupported command behavior: foreground.") },
      "unsupported behavior reason is visible"
    )
  }

  private static func actionExecutionReportsBlockedBundleReasons() throws {
    let catalog = try checkedInCatalog()
    let planner = ActionExecutionPlanner(
      catalog: catalog,
      pathResolver: RepoPathResolver(environment: ["HOME": "/Users/example"]),
      environment: ["TMUX": "1"]
    )

    let plan = try planner.plan(actionID: "bundle.agent.reviewLoop.run")

    try expect(!plan.runnable, "agent review loop bundle is blocked")
    try expectEqual(plan.steps.map(\.actionID), [
      "agent.status.show",
      "layout.terminal.stack.apply"
    ], "blocked bundle remains inspectable")
    try expect(
      plan.blockedReasons.contains { $0.contains("Agent action execution is not supported") },
      "blocked bundle explains unsupported agent"
    )
  }

  private static func actionAuditLogWritesJSONLines() throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("maestro-core-checks-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: tempRoot)
    }

    let log = ActionAuditLog(stateDirectory: tempRoot)
    let event = AuditEvent(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      timestamp: Date(timeIntervalSince1970: 0),
      actionID: "bundle.backend.cockpit.run",
      actor: "check",
      target: "bundle:bundle.backend.cockpit.run",
      risk: .safe,
      outcome: "started",
      message: "Started Backend Cockpit."
    )

    try log.append(event)
    let text = try String(contentsOf: log.fileURL, encoding: .utf8)
    let lines = text.split(separator: "\n")
    try expectEqual(lines.count, 1, "audit log writes one JSONL line")
    let decoded = try MaestroJSON.decoder.decode(AuditEvent.self, from: Data(lines[0].utf8))
    try expectEqual(decoded, event, "audit log event round-trips")
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
        LayoutSlot(id: "slot", app: "iTerm", role: "terminal", unit: "right"),
        LayoutSlot(id: "bad-slot", app: "iTerm", role: "terminal", unit: "bogus")
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
    try expect(codes.contains("unknown_layout_unit"), "unknown layout unit reported")
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

  private static func checkedInCatalog() throws -> CatalogBundle {
    try CatalogLoader(
      configDirectory: repoRoot().appendingPathComponent("maestro/config"),
      pathResolver: RepoPathResolver(environment: ["HOME": "/Users/example"])
    ).load()
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

  private static func terminalStackLayout() -> LayoutDefinition {
    LayoutDefinition(
      id: "terminal.stack",
      label: "Terminal Stack",
      description: "Stack terminals.",
      slots: [
        LayoutSlot(id: "top", app: "iTerm", role: "terminal", unit: "top-half"),
        LayoutSlot(id: "bottom", app: "iTerm", role: "terminal", unit: "bottom-half")
      ]
    )
  }

  private static func terminalQuadLayout() -> LayoutDefinition {
    LayoutDefinition(
      id: "terminal.quad",
      label: "Terminal Quad",
      description: "Quad terminals.",
      slots: [
        LayoutSlot(id: "top-left", app: "iTerm", role: "terminal", unit: "top-left"),
        LayoutSlot(id: "top-right", app: "iTerm", role: "terminal", unit: "top-right"),
        LayoutSlot(id: "bottom-left", app: "iTerm", role: "terminal", unit: "bottom-left"),
        LayoutSlot(id: "bottom-right", app: "iTerm", role: "terminal", unit: "bottom-right")
      ]
    )
  }

  private static func terminalSixUpLayout() -> LayoutDefinition {
    LayoutDefinition(
      id: "terminal.six-up",
      label: "Terminal Six-Up",
      description: "Six terminals.",
      slots: [
        LayoutSlot(id: "top-left", app: "iTerm", role: "terminal", unit: "top-left-third"),
        LayoutSlot(id: "top-center", app: "iTerm", role: "terminal", unit: "top-center-third"),
        LayoutSlot(id: "top-right", app: "iTerm", role: "terminal", unit: "top-right-third"),
        LayoutSlot(id: "bottom-left", app: "iTerm", role: "terminal", unit: "bottom-left-third"),
        LayoutSlot(id: "bottom-center", app: "iTerm", role: "terminal", unit: "bottom-center-third"),
        LayoutSlot(id: "bottom-right", app: "iTerm", role: "terminal", unit: "bottom-right-third")
      ]
    )
  }

  private static func codingWorkspaceLayout() -> LayoutDefinition {
    LayoutDefinition(
      id: "coding.workspace",
      label: "Coding Workspace",
      description: "Coding workspace.",
      slots: [
        LayoutSlot(id: "editor", app: "Visual Studio Code", role: "editor", unit: "left-two-thirds"),
        LayoutSlot(id: "terminal", app: "iTerm", role: "terminal", unit: "right-third"),
        LayoutSlot(id: "browser", app: "Safari", role: "browser", unit: "center")
      ]
    )
  }

  private static func testScreen(id: String, width: Double, height: Double) -> LayoutScreen {
    LayoutScreen(
      id: id,
      name: id,
      frame: LayoutRect(x: 0, y: 0, width: width, height: height),
      visibleFrame: LayoutRect(x: 0, y: 24, width: width, height: height - 48),
      isMain: id == "main",
      isActive: true
    )
  }

  private static func testWindow(
    id: String,
    appName: String,
    bundleIdentifier: String?,
    title: String
  ) -> WindowSnapshot {
    WindowSnapshot(
      id: id,
      appName: appName,
      bundleIdentifier: bundleIdentifier,
      processIdentifier: 1,
      title: title,
      frame: LayoutRect(x: 0, y: 0, width: 100, height: 100)
    )
  }
}

struct CheckFailure: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}
