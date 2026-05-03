import Foundation
import MaestroAutomation
import MaestroCore

@main
struct MaestroCoreChecks {
  static func main() throws {
    try checkedInCatalogLoads()
    try repoPathResolverPreservesCurrentWorkOverrides()
    try stateDirectoryResolutionMatchesCompatibilityRules()
    try agentStateStorePathsResolveCompatibilityLocations()
    try agentTaskRecordJSONRoundTripsAndValidatesState()
    try legacyAgentEnvRecordsNormalizeWithoutPrompts()
    try agentStateStoreWritesPrivateAtomicRecords()
    try agentSlugValidationMatchesCompatibility()
    try agentStateStoreUpdatesAndArchivesLegacyRecords()
    try agentReviewWritesArtifactAndUpdatesSwiftRecord()
    try agentCleanPlanRefusesActiveTasksAndRequiresExactForDirtyWorktrees()
    try agentTmuxPlansTargetWindows()
    try invalidLegacyAgentStateFailsValidation()
    try repoOpenPlanMatchesCompatibilityWindows()
    try workDevTargetSelectionMatchesCompatibility()
    try workDevPlanMatchesCompatibilityCommands()
    try layoutPlanningCoversRepresentativeScreens()
    try layoutPlanningReportsPermissionMissing()
    try layoutPlannerFiltersUnmanagedWindows()
    try itermResolverFallsBackToKnownBundlePath()
    try itermProvisioningTargetsOnlyMissingTerminalSlots()
    try actionExecutionRuntimeBlocksLayoutWhenAutomationUnavailable()
    try actionExecutionReportsCreatedLayoutWindows()
    try riskPolicyBlocksUnknownRiskyScripts()
    try discoveredRiskyScriptsStayBlockedUntilConfigured()
    try actionExecutionExpandsBundlesDeterministically()
    try actionExecutionCommandEligibilityIsExplicit()
    try actionExecutionAgentStatusIsExecutable()
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

  private static func agentStateStorePathsResolveCompatibilityLocations() throws {
    let stateDirectory = URL(fileURLWithPath: "/tmp/maestro-state")
    let explicitRegistry = AgentStateStore(
      stateDirectory: stateDirectory,
      environment: [
        "HOME": "/Users/example",
        "AGENT_REGISTRY_DIR": "~/agent-registry"
      ]
    )
    try expectEqual(
      explicitRegistry.activeDirectory.path,
      "/tmp/maestro-state/agents/active",
      "swift active agent state directory"
    )
    try expectEqual(
      explicitRegistry.archiveDirectory.path,
      "/tmp/maestro-state/agents/archive",
      "swift archived agent state directory"
    )
    try expectEqual(
      explicitRegistry.legacyRegistryDirectory.path,
      "/Users/example/agent-registry",
      "explicit legacy registry directory"
    )

    let worktreeRegistry = AgentStateStore(
      stateDirectory: stateDirectory,
      environment: [
        "HOME": "/Users/example",
        "AGENT_WORKTREE_ROOT": "~/worktrees"
      ]
    )
    try expectEqual(
      worktreeRegistry.legacyRegistryDirectory.path,
      "/Users/example/worktrees/_registry",
      "legacy registry from worktree root"
    )

    let defaultRegistry = AgentStateStore(
      stateDirectory: stateDirectory,
      environment: ["HOME": "/Users/example"]
    )
    try expectEqual(
      defaultRegistry.legacyRegistryDirectory.path,
      "/Users/example/Documents/Coding/node/_agent-worktrees/_registry",
      "default legacy registry directory"
    )
  }

  private static func agentTaskRecordJSONRoundTripsAndValidatesState() throws {
    let record = sampleAgentRecord(state: .needsInput)
    let data = try MaestroJSON.encoder.encode(record)
    let decoded = try MaestroJSON.decoder.decode(AgentTaskRecord.self, from: data)
    try expectEqual(decoded, record, "agent task record round-trip")

    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw CheckFailure("agent task record did not encode as an object")
    }
    try expectEqual(object["schemaVersion"] as? Int, 1, "agent schema version")
    try expectEqual(object["state"] as? String, "needs-input", "agent lifecycle state encoding")
    try expect(object["prompt"] == nil, "agent records do not encode prompts")

    let invalid = Data(
      """
      {
        "schemaVersion": 1,
        "id": "bad",
        "repoName": "sample",
        "repoPath": "/tmp/sample",
        "worktreePath": "/tmp/worktree",
        "branch": "agent/bad",
        "baseRef": "main",
        "state": "blocked",
        "createdAt": "1970-01-01T00:00:00Z",
        "updatedAt": "1970-01-01T00:00:00Z"
      }
      """.utf8
    )
    do {
      _ = try MaestroJSON.decoder.decode(AgentTaskRecord.self, from: invalid)
      throw CheckFailure("expected invalid agent lifecycle state to fail decoding")
    } catch is DecodingError {
      // Expected.
    }
  }

  private static func legacyAgentEnvRecordsNormalizeWithoutPrompts() throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("maestro-agent-legacy-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: tempRoot)
    }

    let registry = tempRoot.appendingPathComponent("_registry")
    let reviews = registry.appendingPathComponent("reviews")
    try FileManager.default.createDirectory(at: reviews, withIntermediateDirectories: true)
    let artifact = reviews.appendingPathComponent("sample-review.md")
    try "review".write(to: artifact, atomically: true, encoding: .utf8)

    let recordFile = registry.appendingPathComponent("sample-20260101-task.env")
    let legacy = """
    task_id=sample-20260101-task
    repo_name=node_account
    repo_path=/tmp/node/node_account
    worktree_path=/tmp/worktrees/sample\\ task
    branch=agent/20260101-task
    base_ref=main
    state=review
    created_at=2026-01-01T00:00:00Z
    updated_at=2026-01-01T00:05:00Z
    prompt=super-secret-prompt
    note=Review\\ ready
    review_artifact=\(artifact.path)
    check_exit=0
    review_exit=0
    tmux_session=agents
    tmux_window=agent:task\\ -\\ running
    cleaned_at=''
    """
    try legacy.write(to: recordFile, atomically: true, encoding: .utf8)
    let before = try FileManager.default.attributesOfItem(atPath: recordFile.path)[.modificationDate] as? Date

    let store = AgentStateStore(
      stateDirectory: tempRoot.appendingPathComponent("state"),
      environment: ["AGENT_REGISTRY_DIR": registry.path]
    )
    let tasks = try store.list()
    try expectEqual(tasks.count, 1, "legacy agent task count")
    let task = try require(tasks.first, "legacy task")
    try expectEqual(task.source, .legacy, "legacy task source")
    try expectEqual(task.record.id, "sample-20260101-task", "legacy task id")
    try expectEqual(task.record.state, .review, "legacy task state")
    try expectEqual(task.record.worktreePath, "/tmp/worktrees/sample task", "legacy shell escaped path")
    try expectEqual(task.record.note, "Review ready", "legacy shell escaped note")
    try expectEqual(task.record.tmuxWindow, "agent:task - running", "legacy tmux window")
    try expectEqual(task.reviewArtifactAvailable, true, "legacy review artifact availability")

    let output = String(data: try MaestroJSON.encoder.encode(AgentTaskList(stateDirectory: store.stateDirectory.path, tasks: tasks)), encoding: .utf8) ?? ""
    try expect(!output.contains("super-secret-prompt"), "legacy prompt is redacted from normalized JSON")
    try expect(!output.contains("prompt"), "normalized JSON has no prompt key")

    let after = try FileManager.default.attributesOfItem(atPath: recordFile.path)[.modificationDate] as? Date
    try expectEqual(after, before, "legacy status read does not modify registry file")
  }

  private static func agentStateStoreWritesPrivateAtomicRecords() throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("maestro-agent-write-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: tempRoot)
    }

    let store = AgentStateStore(stateDirectory: tempRoot, environment: [:])
    let record = sampleAgentRecord(state: .running)
    try store.writeActive(record)

    let recordURL = store.activeDirectory.appendingPathComponent("\(record.id).json")
    try expect(FileManager.default.fileExists(atPath: recordURL.path), "swift agent record exists")
    let firstDecode = try MaestroJSON.decoder.decode(AgentTaskRecord.self, from: Data(contentsOf: recordURL))
    try expectEqual(firstDecode, record, "written agent record decodes")
    try expectEqual(filePermissions(recordURL), 0o600, "swift agent record permissions")

    var updated = record
    updated.state = .review
    updated.updatedAt = Date(timeIntervalSince1970: 60)
    try store.writeActive(updated)
    let secondDecode = try MaestroJSON.decoder.decode(AgentTaskRecord.self, from: Data(contentsOf: recordURL))
    try expectEqual(secondDecode, updated, "rewritten agent record decodes")
    try expectEqual(filePermissions(recordURL), 0o600, "rewritten agent record permissions")

    let files = try FileManager.default.contentsOfDirectory(atPath: store.activeDirectory.path)
    try expectEqual(files, ["\(record.id).json"], "atomic write leaves only final record")
  }

  private static func agentSlugValidationMatchesCompatibility() throws {
    try AgentSlugValidator.validate("task.slug_1-alpha")
    do {
      try AgentSlugValidator.validate("../nope")
      throw CheckFailure("expected invalid agent slug to fail")
    } catch let error as AgentWorkflowError {
      try expectEqual(error, .invalidSlug("../nope"), "invalid slug error")
    }
  }

  private static func agentStateStoreUpdatesAndArchivesLegacyRecords() throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("maestro-agent-legacy-update-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: tempRoot)
    }

    let registry = tempRoot.appendingPathComponent("_registry")
    try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
    let recordFile = registry.appendingPathComponent("sample-20260101-task.env")
    try """
    task_id=sample-20260101-task
    repo_name=sample
    repo_path=/tmp/sample
    worktree_path=/tmp/worktrees/sample
    branch=agent/20260101-task
    base_ref=main
    state=running
    created_at=2026-01-01T00:00:00Z
    updated_at=2026-01-01T00:00:00Z
    prompt=legacy-secret
    """.write(to: recordFile, atomically: true, encoding: .utf8)

    let store = AgentStateStore(
      stateDirectory: tempRoot.appendingPathComponent("state"),
      environment: ["AGENT_REGISTRY_DIR": registry.path]
    )
    let snapshot = try store.task(matching: "sample-20260101-task", includeArchived: false)
    var record = snapshot.record
    record.state = .abandoned
    record.note = "Done"
    record.updatedAt = Date(timeIntervalSince1970: 60)
    let updated = try store.update(snapshot, with: record)

    try expectEqual(updated.source, .legacy, "updated legacy source")
    let updatedText = try String(contentsOf: recordFile, encoding: .utf8)
    try expect(updatedText.contains("state='abandoned'"), "legacy update writes state")
    try expect(updatedText.contains("note='Done'"), "legacy update writes note")
    try expect(!updatedText.contains("legacy-secret"), "legacy update does not serialize prompt")

    record.cleanedAt = Date(timeIntervalSince1970: 120)
    let archived = try store.archive(updated, with: record)
    try expectEqual(archived.archived, true, "legacy archive snapshot is archived")
    try expect(!FileManager.default.fileExists(atPath: recordFile.path), "legacy active file moved")
    try expect(
      FileManager.default.fileExists(atPath: registry.appendingPathComponent("archive/sample-20260101-task.env").path),
      "legacy archive file exists"
    )
  }

  private static func agentReviewWritesArtifactAndUpdatesSwiftRecord() throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("maestro-agent-review-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: tempRoot)
    }

    let repo = tempRoot.appendingPathComponent("sample")
    let worktree = tempRoot.appendingPathComponent("worktree")
    let fakeBin = tempRoot.appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
    let codex = fakeBin.appendingPathComponent("codex")
    try "#!/usr/bin/env bash\n".write(to: codex, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)

    let store = AgentStateStore(
      stateDirectory: tempRoot.appendingPathComponent("state"),
      environment: ["PATH": fakeBin.path]
    )
    let record = AgentTaskRecord(
      id: "sample-20260101-task",
      repoName: "sample",
      repoPath: repo.path,
      worktreePath: worktree.path,
      branch: "agent/20260101-task",
      state: .running,
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 0)
    )
    try store.writeActive(record)

    let repoDefinition = RepoDefinition(
      key: "sample",
      label: "sample",
      path: RepoPath(root: .absolute, relative: repo.path),
      tmuxSession: "sample",
      defaultWindows: ["coding"]
    )
    let check = CommandDefinition(
      id: "sample.check",
      repoKey: "sample",
      argv: ["fake-check"],
      family: .check,
      risk: .safe,
      environment: .local,
      role: .check,
      behavior: .foreground,
      confirmation: .none,
      label: "Sample Check",
      description: "Run check."
    )
    let catalog = CatalogBundle(
      repos: [repoDefinition],
      configuredCommands: [check],
      commands: [check],
      configuredActions: [],
      actions: [],
      layouts: [],
      bundles: []
    )
    let runner = FakeForegroundCommandRunner { command in
      if command.executable == "fake-check" {
        return ForegroundCommandResult(status: 0, output: "check ok\n")
      }
      if command.executable.hasSuffix("/codex") {
        return ForegroundCommandResult(status: 0, output: "review ok\n")
      }
      return ForegroundCommandResult(status: 0, output: "diff stat\n")
    }

    let result = try AgentWorkflowExecutor(
      store: store,
      catalog: catalog,
      environment: ["PATH": fakeBin.path],
      runner: runner
    ).review(taskQuery: record.id)

    try expect(result.ok, "agent review succeeds")
    try expectEqual(result.snapshot.record.state, .review, "review updates state")
    try expectEqual(result.snapshot.record.checkExit, 0, "review records check exit")
    try expectEqual(result.snapshot.record.reviewExit, 0, "review records codex exit")
    let artifact = try String(contentsOfFile: result.artifactPath, encoding: .utf8)
    try expect(artifact.contains("Command: `fake-check`"), "review artifact records check argv")
    try expect(artifact.contains("No check command found") == false, "review artifact uses catalog check")
    try expect(artifact.contains("```text\nreview ok"), "review artifact opens codex output fence on its own line")
    try expect(!artifact.contains("eval"), "review artifact does not mention shell eval")
  }

  private static func agentCleanPlanRefusesActiveTasksAndRequiresExactForDirtyWorktrees() throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("maestro-agent-clean-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: tempRoot)
    }
    let worktree = tempRoot.appendingPathComponent("worktree")
    try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
    let store = AgentStateStore(stateDirectory: tempRoot.appendingPathComponent("state"), environment: [:])
    var record = sampleAgentRecord(state: .running)
    record.worktreePath = worktree.path
    try store.writeActive(record)
    let runner = FakeForegroundCommandRunner { _ in
      ForegroundCommandResult(status: 0, output: " M README.md\n")
    }
    let executor = AgentWorkflowExecutor(store: store, environment: [:], runner: runner)

    do {
      _ = try executor.cleanPlan(taskQuery: record.id, force: false)
      throw CheckFailure("expected active task clean to fail")
    } catch let error as AgentWorkflowError {
      try expectEqual(error, .cleanStateRefusal(record.id, "running"), "clean state refusal")
    }

    let snapshot = try store.task(matching: record.id, includeArchived: false)
    record.state = .abandoned
    _ = try store.update(snapshot, with: record)
    let plan = try executor.cleanPlan(taskQuery: record.id, force: false)
    try expect(plan.dirty, "dirty worktree detected")
    try expect(plan.requiresExactConfirmation, "dirty cleanup requires exact confirmation")
    do {
      _ = try executor.clean(plan: plan, confirmation: .yes)
      throw CheckFailure("expected dirty clean without exact confirmation to fail")
    } catch let error as AgentWorkflowError {
      try expectEqual(error, .cleanConfirmationRequired(plan.prompt), "dirty clean confirmation required")
    }
  }

  private static func agentTmuxPlansTargetWindows() throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("maestro-agent-tmux-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: tempRoot)
    }
    let store = AgentStateStore(stateDirectory: tempRoot, environment: [:])
    try store.writeActive(sampleAgentRecord(state: .running))

    let plan = try AgentWorkflowExecutor(
      store: store,
      environment: ["TMUX": "1"]
    ).attachPlan(taskQuery: "sample-20260101-task")

    try expectEqual(plan.target, "agents:agent:task - running", "agent tmux target includes window")
    try expectEqual(plan.commands.map(\.arguments), [
      ["switch-client", "-t", "agents:agent:task - running"]
    ], "agent attach/focus target command")
  }

  private static func invalidLegacyAgentStateFailsValidation() throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("maestro-agent-invalid-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: tempRoot)
    }

    let registry = tempRoot.appendingPathComponent("_registry")
    try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
    try """
    task_id=sample-invalid
    repo_name=sample
    state=blocked
    created_at=2026-01-01T00:00:00Z
    updated_at=2026-01-01T00:00:00Z
    """.write(to: registry.appendingPathComponent("sample-invalid.env"), atomically: true, encoding: .utf8)

    let store = AgentStateStore(
      stateDirectory: tempRoot.appendingPathComponent("state"),
      environment: ["AGENT_REGISTRY_DIR": registry.path]
    )
    do {
      _ = try store.list()
      throw CheckFailure("expected invalid legacy agent state to fail")
    } catch let error as AgentStateStoreError {
      guard case let .invalidLegacyRecord(path, reason) = error else {
        throw CheckFailure("unexpected invalid legacy state error: \(error)")
      }
      try expect(path.hasSuffix("/_registry/sample-invalid.env"), "invalid legacy state path")
      try expectEqual(reason, "Unknown state: blocked", "invalid legacy state reason")
    }
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

  private static func itermResolverFallsBackToKnownBundlePath() throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("maestro-core-checks-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: tempRoot)
    }

    let appURL = tempRoot.appendingPathComponent("iTerm.app")
    let contentsURL = appURL.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>CFBundleIdentifier</key>
      <string>com.googlecode.iterm2</string>
    </dict>
    </plist>
    """
    try plist.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

    let resolution = ItermApplicationResolver(
      knownBundlePaths: [appURL.path],
      homeDirectory: tempRoot.path
    ).resolve(launchServicesURL: nil)

    try expect(resolution.installed, "iTerm fallback resolver finds known bundle path")
    try expect(!resolution.launchServicesReady, "iTerm fallback resolver keeps Launch Services status separate")
    try expect(resolution.knownBundlePathFound, "iTerm fallback resolver reports known path")
    try expectEqual(resolution.applicationURL?.path, appURL.path, "iTerm fallback application path")
  }

  private static func itermProvisioningTargetsOnlyMissingTerminalSlots() throws {
    let plan = try LayoutPlanner().plan(
      layout: codingWorkspaceLayout(),
      screen: testScreen(id: "main", width: 1920, height: 1080),
      windows: [
        testWindow(id: "code", appName: "Code", bundleIdentifier: "com.microsoft.VSCode", title: "Code")
      ]
    )

    let missingItermSlots = ItermWindowProvisioning.missingItermSlots(in: plan)

    try expectEqual(missingItermSlots.map(\.slotID), ["terminal"], "only missing iTerm slots are provisioned")
    try expect(plan.canExecute, "layout with missing iTerm slot is executable when inventory is available")
  }

  private static func actionExecutionRuntimeBlocksLayoutWhenAutomationUnavailable() throws {
    let layout = terminalStackLayout()
    let action = ActionDefinition(
      id: "layout.terminal.stack.apply",
      label: "Terminal Stack",
      description: "Apply terminal stack.",
      type: .layout,
      layoutID: layout.id
    )
    let catalog = catalogWith(layout: layout, action: action)
    let fakeAutomation = FakeLayoutAutomation(
      readiness: LayoutRuntimeReadinessSnapshot(
        ready: false,
        accessibilityTrusted: false,
        appleEventsAvailable: true,
        iTermInstalled: true,
        iTermWindowCreationAvailable: true,
        blockedReasons: ["Accessibility missing."]
      )
    )

    let plan = try ActionExecutionExecutor(
      catalog: catalog,
      layoutAutomation: fakeAutomation,
      auditLog: ActionAuditLog(stateDirectory: FileManager.default.temporaryDirectory)
    ).plan(actionID: action.id)

    try expect(!plan.runnable, "runtime layout readiness blocks action plans")
    try expectEqual(plan.steps.first?.blockedReason, "Accessibility missing.", "runtime blocked reason")
    try expect(plan.blockedReasons.contains { $0.contains("Accessibility missing.") }, "runtime blocked reason is visible at plan level")
  }

  private static func actionExecutionReportsCreatedLayoutWindows() throws {
    let tempRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("maestro-core-checks-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: tempRoot)
    }

    let layout = terminalStackLayout()
    let action = ActionDefinition(
      id: "layout.terminal.stack.apply",
      label: "Terminal Stack",
      description: "Apply terminal stack.",
      type: .layout,
      layoutID: layout.id
    )
    let catalog = catalogWith(layout: layout, action: action)
    let fakeAutomation = FakeLayoutAutomation(
      readiness: LayoutRuntimeReadinessSnapshot(
        ready: true,
        accessibilityTrusted: true,
        appleEventsAvailable: true,
        iTermInstalled: true,
        iTermWindowCreationAvailable: true
      ),
      result: LayoutApplicationResult(
        ok: true,
        layoutID: layout.id,
        movedWindowCount: 2,
        createdWindowCount: 2,
        skippedSlotCount: 0
      )
    )

    let result = try ActionExecutionExecutor(
      catalog: catalog,
      layoutAutomation: fakeAutomation,
      auditLog: ActionAuditLog(stateDirectory: tempRoot)
    ).run(actionID: action.id)

    let step = try require(result.steps.first, "layout execution step result")
    try expect(result.ok, "layout execution with created windows succeeds")
    try expect(step.message.contains("created 2 window(s)"), "layout execution reports created window count")
    try expect(step.message.contains("moved 2 window(s)"), "layout execution reports moved window count")
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

  private static func actionExecutionAgentStatusIsExecutable() throws {
    let catalog = try checkedInCatalog()
    let planner = ActionExecutionPlanner(
      catalog: catalog,
      pathResolver: RepoPathResolver(environment: ["HOME": "/Users/example"]),
      environment: ["TMUX": "1"]
    )

    let statusPlan = try planner.plan(actionID: "agent.status.show")
    let statusStep = try require(statusPlan.steps.first, "agent status action step")
    let agentCommandPlan = try require(statusStep.agentCommandPlan, "agent status command plan")
    try expect(statusPlan.runnable, "agent status action is runnable")
    try expectEqual(agentCommandPlan.argv, ["agent-status"], "agent status argv")

    let plan = try planner.plan(actionID: "bundle.agent.reviewLoop.run")

    try expect(plan.runnable, "agent review loop bundle is runnable at catalog-planning time")
    try expectEqual(plan.steps.map(\.actionID), [
      "agent.status.show",
      "layout.terminal.stack.apply"
    ], "agent review loop expansion order")
    try expect(
      !plan.blockedReasons.contains { $0.contains("Agent action execution is not supported") },
      "agent review loop no longer reports unsupported agent execution"
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

  private static func sampleAgentRecord(state: AgentState) -> AgentTaskRecord {
    AgentTaskRecord(
      id: "sample-20260101-task",
      repoName: "sample",
      repoPath: "/tmp/sample",
      worktreePath: "/tmp/worktrees/sample-20260101-task",
      branch: "agent/20260101-task",
      baseRef: "main",
      state: state,
      note: "Review ready",
      checkExit: 0,
      reviewExit: 0,
      reviewArtifact: "/tmp/reviews/sample.md",
      tmuxSession: "agents",
      tmuxWindow: "agent:task - running",
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 0)
    )
  }

  private static func filePermissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let permissions = attributes[.posixPermissions] as? NSNumber else {
      throw CheckFailure("missing file permissions for \(url.path)")
    }
    return permissions.intValue & 0o777
  }

  private static func catalogWith(
    layout: LayoutDefinition,
    action: ActionDefinition
  ) -> CatalogBundle {
    CatalogBundle(
      repos: [],
      configuredCommands: [],
      commands: [],
      configuredActions: [action],
      actions: [action],
      layouts: [layout],
      bundles: []
    )
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

private struct FakeLayoutAutomation: LayoutAutomation, LayoutRuntimeReadinessProviding {
  var readiness: LayoutRuntimeReadinessSnapshot
  var result: LayoutApplicationResult

  init(
    readiness: LayoutRuntimeReadinessSnapshot,
    result: LayoutApplicationResult = LayoutApplicationResult(
      ok: true,
      layoutID: "terminal.stack",
      movedWindowCount: 0,
      skippedSlotCount: 0
    )
  ) {
    self.readiness = readiness
    self.result = result
  }

  func planLayout(
    _ layout: LayoutDefinition,
    screenSelection: LayoutScreenSelection
  ) throws -> LayoutPlan {
    try LayoutPlanner().plan(
      layout: layout,
      screen: LayoutScreen(
        id: "fake",
        name: "Fake",
        frame: LayoutRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: LayoutRect(x: 0, y: 24, width: 1920, height: 1032),
        isMain: true,
        isActive: true
      ),
      windows: []
    )
  }

  func applyLayout(_ plan: LayoutPlan) throws -> LayoutApplicationResult {
    result
  }

  func layoutReadiness(
    for layout: LayoutDefinition,
    promptForAccessibility: Bool
  ) -> LayoutRuntimeReadinessSnapshot {
    readiness
  }
}

private struct FakeForegroundCommandRunner: ForegroundCommandRunning {
  var handler: (ForegroundCommand) -> ForegroundCommandResult

  init(_ handler: @escaping (ForegroundCommand) -> ForegroundCommandResult) {
    self.handler = handler
  }

  func run(_ command: ForegroundCommand) throws -> ForegroundCommandResult {
    handler(command)
  }
}

struct CheckFailure: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}
