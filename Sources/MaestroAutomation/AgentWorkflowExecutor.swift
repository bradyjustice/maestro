import Foundation
import MaestroCore

public struct AgentWorkflowExecutor {
  public var store: AgentStateStore
  public var catalog: CatalogBundle?
  public var environment: [String: String]
  public var fileManager: FileManager
  public var runner: ForegroundCommandRunning
  public var tmuxRunner: CommandRunning

  public init(
    store: AgentStateStore? = nil,
    catalog: CatalogBundle? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default,
    runner: ForegroundCommandRunning = ProcessForegroundCommandRunner(),
    tmuxRunner: CommandRunning = ProcessCommandRunner()
  ) {
    self.environment = environment
    self.fileManager = fileManager
    self.store = store ?? AgentStateStore(
      stateDirectory: MaestroPaths.defaultStateDirectory(environment: environment),
      environment: environment,
      fileManager: fileManager
    )
    self.catalog = catalog
    self.runner = runner
    self.tmuxRunner = tmuxRunner
  }

  public func start(
    repoArgument: String,
    taskSlug: String,
    prompt: String?
  ) throws -> AgentStartResult {
    try AgentSlugValidator.validate(taskSlug)
    try fileManager.createDirectory(
      at: worktreeRootURL(),
      withIntermediateDirectories: true
    )

    let repoPath = try resolveRepo(repoArgument)
    let repoName = URL(fileURLWithPath: repoPath).lastPathComponent
    let baseRef = nonEmpty(environment["AGENT_BASE_REF"]) ?? "main"
    let dateSlug = Self.dateSlug(Date())
    let branch = "agent/\(dateSlug)-\(taskSlug)"
    let taskID = "\(repoName)-\(dateSlug)-\(taskSlug)"
    let worktreePath = worktreeRootURL().appendingPathComponent(taskID).path
    let recordPath = store.activeRecordURL(for: taskID).path
    let launchSkipped = environment["AGENT_START_NO_LAUNCH"] == "1"
    let tmuxSession = launchSkipped ? nil : (nonEmpty(environment["AGENT_TMUX_SESSION"]) ?? "agents")
    let tmuxWindow = launchSkipped ? nil : "agent:\(taskSlug) - running - \(dateSlug)-\(taskSlug)"

    if !launchSkipped {
      guard executablePath("tmux") != nil else {
        throw AgentWorkflowError.executableMissing("tmux")
      }
      guard executablePath("codex") != nil else {
        throw AgentWorkflowError.executableMissing("codex")
      }
    }

    try validateStart(
      repoPath: repoPath,
      repoName: repoName,
      baseRef: baseRef,
      branch: branch,
      taskID: taskID,
      worktreePath: worktreePath
    )

    var warnings: [String] = []
    let sourceStatus = try run(ForegroundCommand(
      executable: "git",
      arguments: ["-C", repoPath, "status", "--short"]
    ))
    if !sourceStatus.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      warnings.append("Source checkout has uncommitted changes; new worktree still starts from \(baseRef).")
    }

    let add = try run(ForegroundCommand(
      executable: "git",
      arguments: ["-C", repoPath, "worktree", "add", "-b", branch, worktreePath, baseRef]
    ))
    guard add.status == 0 else {
      throw AgentWorkflowError.commandFailed("git worktree add", add.status)
    }

    let now = Date()
    let record = AgentTaskRecord(
      id: taskID,
      repoName: repoName,
      repoPath: repoPath,
      worktreePath: worktreePath,
      branch: branch,
      baseRef: baseRef,
      state: launchSkipped ? .queued : .running,
      note: launchSkipped ? "Worktree created; launch skipped by AGENT_START_NO_LAUNCH" : "Started by maestro agent start",
      tmuxSession: tmuxSession,
      tmuxWindow: tmuxWindow,
      createdAt: now,
      updatedAt: now
    )
    try store.writeActive(record)

    if !launchSkipped {
      try launchCodex(
        worktreePath: worktreePath,
        prompt: prompt,
        tmuxSession: tmuxSession ?? "agents",
        tmuxWindow: tmuxWindow ?? taskID
      )
    }

    let snapshot = AgentTaskSnapshot(
      source: .swift,
      archived: false,
      recordPath: recordPath,
      record: record,
      reviewArtifactAvailable: false
    )
    let plan = AgentStartPlan(
      taskID: taskID,
      repoName: repoName,
      repoPath: repoPath,
      worktreePath: worktreePath,
      branch: branch,
      baseRef: baseRef,
      recordPath: recordPath,
      launchSkipped: launchSkipped,
      promptProvided: nonEmpty(prompt) != nil,
      tmuxSession: tmuxSession,
      tmuxWindow: tmuxWindow
    )

    return AgentStartResult(
      plan: plan,
      snapshot: snapshot,
      warnings: warnings,
      message: launchSkipped ? "Created queued agent task \(taskID)." : "Started agent task \(taskID)."
    )
  }

  public func mark(
    taskQuery: String,
    state: AgentState,
    note: String?
  ) throws -> AgentMarkResult {
    let snapshot = try store.task(matching: taskQuery, includeArchived: false)
    var record = snapshot.record
    record.state = state
    if let note = nonEmpty(note) {
      record.note = note
    }
    record.updatedAt = Date()

    let updated = try store.update(snapshot, with: record)
    return AgentMarkResult(snapshot: updated, message: "Updated \(record.id): \(record.state.rawValue)")
  }

  public func review(taskQuery: String) throws -> AgentReviewResult {
    let snapshot = try store.task(matching: taskQuery, includeArchived: false)
    let record = snapshot.record
    guard fileManager.fileExists(atPath: record.worktreePath) else {
      throw AgentWorkflowError.missingWorktree(record.worktreePath)
    }
    guard executablePath("codex") != nil else {
      throw AgentWorkflowError.executableMissing("codex")
    }

    let artifactURL = try reviewArtifactURL(for: snapshot)
    try fileManager.createDirectory(
      at: artifactURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    var body = reviewHeader(for: record)
    let checkCommand = try checkCommand(for: record)
    var checkExit: Int?
    if let checkCommand {
      body += "Command: `\(ActionExecutionPlanner.commandLine(from: checkCommand.argv ?? []))`\n\n"
      body += "```text\n"
      try append(body, to: artifactURL)
      let result = try run(ForegroundCommand(
        executable: checkCommand.argv?[0] ?? "",
        arguments: Array((checkCommand.argv ?? []).dropFirst()),
        currentDirectoryPath: record.worktreePath,
        environment: environment
      ))
      checkExit = Int(result.status)
      try append(result.output, to: artifactURL)
      try append("```\n\nExit: `\(result.status)`\n\n", to: artifactURL)
    } else {
      body += "No check command found.\n\n"
      try append(body, to: artifactURL)
    }

    try append(
      "## Codex Review\n\nCommand: `codex review --uncommitted`\n\n```text\n",
      to: artifactURL
    )
    let review = try run(ForegroundCommand(
      executable: executablePath("codex") ?? "codex",
      arguments: ["review", "--uncommitted"],
      currentDirectoryPath: record.worktreePath,
      environment: scrubbedEnvironment()
    ))
    try append(review.output, to: artifactURL)
    try append("```\n\nExit: `\(review.status)`\n", to: artifactURL)

    let ok = (checkExit ?? 0) == 0 && review.status == 0
    var updatedRecord = record
    updatedRecord.reviewArtifact = artifactURL.path
    updatedRecord.checkExit = checkExit
    updatedRecord.reviewExit = Int(review.status)
    updatedRecord.state = ok ? .review : .needsInput
    updatedRecord.note = ok ? "Review artifact ready" : "Review or check failed; inspect artifact"
    updatedRecord.updatedAt = Date()
    let updated = try store.update(snapshot, with: updatedRecord)

    return AgentReviewResult(
      ok: ok,
      snapshot: updated,
      artifactPath: artifactURL.path,
      checkCommand: checkCommand?.argv.map(ActionExecutionPlanner.commandLine(from:)),
      checkExit: checkExit,
      reviewExit: Int(review.status),
      message: ok ? "Review artifact ready: \(artifactURL.path)" : "Review or check failed: \(artifactURL.path)"
    )
  }

  public func cleanPlan(taskQuery: String, force: Bool) throws -> AgentCleanPlan {
    let snapshot = try store.task(matching: taskQuery, includeArchived: false)
    let record = snapshot.record
    if !force && record.state != .merged && record.state != .abandoned {
      throw AgentWorkflowError.cleanStateRefusal(record.id, record.state.rawValue)
    }

    var isDirectory: ObjCBool = false
    let worktreeExists = fileManager.fileExists(atPath: record.worktreePath, isDirectory: &isDirectory)
      && isDirectory.boolValue
    let dirty: Bool
    if worktreeExists {
      let status = try run(ForegroundCommand(
        executable: "git",
        arguments: ["-C", record.worktreePath, "status", "--porcelain"]
      ))
      dirty = !status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    } else {
      dirty = false
    }

    let exact = "remove \(record.id)"
    let requiresExact = force || dirty
    return AgentCleanPlan(
      snapshot: snapshot,
      force: force,
      dirty: dirty,
      worktreeExists: worktreeExists,
      requiresExactConfirmation: requiresExact,
      exactConfirmation: exact,
      prompt: requiresExact
        ? "This can discard local worktree changes for \(record.id)."
        : "Remove clean worktree for \(record.id)?"
    )
  }

  public func clean(
    plan: AgentCleanPlan,
    confirmation: AgentCleanConfirmation
  ) throws -> AgentCleanResult {
    try validateCleanConfirmation(plan: plan, confirmation: confirmation)

    let record = plan.snapshot.record
    var removedWorktree = false
    if plan.worktreeExists {
      var arguments = ["-C", record.repoPath, "worktree", "remove"]
      if plan.force || plan.dirty {
        arguments.append("--force")
      }
      arguments.append(record.worktreePath)
      let removal = try run(ForegroundCommand(executable: "git", arguments: arguments))
      guard removal.status == 0 else {
        throw AgentWorkflowError.commandFailed("git worktree remove", removal.status)
      }
      removedWorktree = true
    }

    var archivedRecord = record
    archivedRecord.updatedAt = Date()
    archivedRecord.cleanedAt = archivedRecord.updatedAt
    if archivedRecord.note?.isEmpty ?? true {
      archivedRecord.note = "Cleaned by maestro agent clean"
    }
    let archived = try store.archive(plan.snapshot, with: archivedRecord)

    return AgentCleanResult(
      snapshot: archived,
      archivedPath: archived.recordPath,
      removedWorktree: removedWorktree,
      message: "Archived registry: \(archived.recordPath)"
    )
  }

  public func attachPlan(taskQuery: String) throws -> AgentTmuxPlan {
    try tmuxPlan(taskQuery: taskQuery)
  }

  public func focusPlan(taskQuery: String) throws -> AgentTmuxPlan {
    try tmuxPlan(taskQuery: taskQuery)
  }

  public func attach(taskQuery: String) throws -> AgentTmuxResult {
    let plan = try attachPlan(taskQuery: taskQuery)
    try run(plan)
    return AgentTmuxResult(plan: plan, message: "Attached \(plan.target).")
  }

  public func focus(taskQuery: String) throws -> AgentTmuxResult {
    let plan = try focusPlan(taskQuery: taskQuery)
    try run(plan)
    return AgentTmuxResult(plan: plan, message: "Focused \(plan.target).")
  }

  private func validateStart(
    repoPath: String,
    repoName: String,
    baseRef: String,
    branch: String,
    taskID: String,
    worktreePath: String
  ) throws {
    let base = try run(ForegroundCommand(
      executable: "git",
      arguments: ["-C", repoPath, "rev-parse", "--verify", "\(baseRef)^{commit}"]
    ))
    guard base.status == 0 else {
      throw AgentWorkflowError.baseRefMissing(repoName, baseRef)
    }

    let branchCheck = try run(ForegroundCommand(
      executable: "git",
      arguments: ["-C", repoPath, "show-ref", "--verify", "--quiet", "refs/heads/\(branch)"]
    ))
    guard branchCheck.status != 0 else {
      throw AgentWorkflowError.branchExists(branch)
    }

    if fileManager.fileExists(atPath: worktreePath) {
      throw AgentWorkflowError.worktreeExists(worktreePath)
    }
    if store.activeRecordExists(taskID: taskID) {
      throw AgentWorkflowError.recordExists(taskID)
    }
  }

  private func resolveRepo(_ repoArgument: String) throws -> String {
    let candidate: String
    if repoArgument.hasPrefix("/") || repoArgument.hasPrefix("~") || repoArgument.contains("/") {
      candidate = MaestroPaths.expandTilde(repoArgument, environment: environment)
    } else {
      candidate = URL(fileURLWithPath: agentNodeRoot()).appendingPathComponent(repoArgument).path
    }

    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory),
          isDirectory.boolValue else {
      throw AgentWorkflowError.repoNotFound(repoArgument)
    }

    let root = try run(ForegroundCommand(
      executable: "git",
      arguments: ["-C", candidate, "rev-parse", "--show-toplevel"]
    ))
    guard root.status == 0 else {
      throw AgentWorkflowError.notGitRepo(candidate)
    }
    return root.output.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func launchCodex(
    worktreePath: String,
    prompt: String?,
    tmuxSession: String,
    tmuxWindow: String
  ) throws {
    guard executablePath("tmux") != nil else {
      throw AgentWorkflowError.executableMissing("tmux")
    }
    guard let codex = executablePath("codex") else {
      throw AgentWorkflowError.executableMissing("codex")
    }

    let commandString = shellCommandLine(from: codexLaunchArguments(codex: codex, worktreePath: worktreePath, prompt: prompt))
    let commands: [TmuxCommand]
    if nonEmpty(environment["TMUX"]) != nil {
      commands = [
        TmuxCommand(arguments: ["new-window", "-n", tmuxWindow, "-c", worktreePath, commandString])
      ]
    } else {
      let hasSession = try tmuxRunner.run(TmuxCommand(arguments: ["has-session", "-t", tmuxSession]))
      var planned: [TmuxCommand] = []
      if hasSession != 0 {
        planned.append(TmuxCommand(arguments: ["new-session", "-d", "-s", tmuxSession, "-n", "agent-status", "agent-status; exec $SHELL -l"]))
      }
      planned.append(TmuxCommand(arguments: ["new-window", "-t", "\(tmuxSession):", "-n", tmuxWindow, "-c", worktreePath, commandString]))
      commands = planned
    }

    for command in commands {
      let status = try tmuxRunner.run(command)
      guard status == 0 else {
        throw AgentWorkflowError.commandFailed("tmux", status)
      }
    }
  }

  private func codexLaunchArguments(codex: String, worktreePath: String, prompt: String?) -> [String] {
    var arguments: [String] = []
    if environment["AGENT_INHERIT_SECRETS"] != "1" {
      arguments.append("env")
      for secret in Self.secretEnvironmentKeys {
        arguments += ["-u", secret]
      }
    }
    arguments += [
      codex,
      "--cd",
      worktreePath,
      "--sandbox",
      "workspace-write",
      "--ask-for-approval",
      "on-request"
    ]
    if let prompt = nonEmpty(prompt) {
      arguments.append(prompt)
    }
    return arguments
  }

  private func reviewArtifactURL(for snapshot: AgentTaskSnapshot) throws -> URL {
    let root = snapshot.source == .legacy ? store.legacyReviewsDirectory : store.swiftReviewsDirectory
    let stamp = Self.reviewStamp(Date())
    return root.appendingPathComponent("\(snapshot.record.id)-\(stamp).md")
  }

  private func reviewHeader(for record: AgentTaskRecord) -> String {
    """
    # Agent Review: \(record.id)

    - Repo: `\(record.repoName)`
    - Branch: `\(record.branch)`
    - Worktree: `\(record.worktreePath)`
    - Base: `\(record.baseRef)`
    - Started: `\(ISO8601DateFormatter().string(from: Date()))`

    ## Diff Stat

    Committed branch diff:

    ```text
    \(diffStat(arguments: ["diff", "--stat", "\(record.baseRef)...HEAD"], worktreePath: record.worktreePath))
    ```

    Uncommitted diff:

    ```text
    \(diffStat(arguments: ["diff", "--stat"], worktreePath: record.worktreePath))
    ```

    ## Repo Check

    """
  }

  private func diffStat(arguments: [String], worktreePath: String) -> String {
    let result = try? runner.run(ForegroundCommand(
      executable: "git",
      arguments: ["-C", worktreePath] + arguments
    ))
    return result?.output ?? ""
  }

  private func checkCommand(for record: AgentTaskRecord) throws -> CommandDefinition? {
    guard let catalog else {
      return nil
    }
    guard let repo = matchingRepo(for: record, in: catalog) else {
      return nil
    }

    if let exact = catalog.commands.first(where: { $0.id == "\(repo.key).check" }) {
      guard isSafeForegroundCheck(exact) else {
        throw AgentWorkflowError.unsafeCheckCommand(exact.id)
      }
      return exact
    }

    let checks = catalog.commands.filter { command in
      command.repoKey == repo.key && command.family == .check
    }
    guard let command = checks.first else {
      return nil
    }
    guard isSafeForegroundCheck(command) else {
      throw AgentWorkflowError.unsafeCheckCommand(command.id)
    }
    return command
  }

  private func matchingRepo(
    for record: AgentTaskRecord,
    in catalog: CatalogBundle
  ) -> RepoDefinition? {
    catalog.repos.first { repo in
      repo.key == record.repoName
        || repo.label == record.repoName
        || URL(fileURLWithPath: path(for: repo)).standardizedFileURL.path == URL(fileURLWithPath: record.repoPath).standardizedFileURL.path
        || URL(fileURLWithPath: path(for: repo)).lastPathComponent == record.repoName
    }
  }

  private func path(for repo: RepoDefinition) -> String {
    RepoPathResolver(environment: environment).resolve(repo.path)
  }

  private func isSafeForegroundCheck(_ command: CommandDefinition) -> Bool {
    command.risk == .safe
      && command.environment == .local
      && command.confirmation == .none
      && command.behavior == .foreground
      && command.argv?.isEmpty == false
  }

  private func validateCleanConfirmation(
    plan: AgentCleanPlan,
    confirmation: AgentCleanConfirmation
  ) throws {
    if plan.requiresExactConfirmation {
      guard case let .exact(value) = confirmation else {
        throw AgentWorkflowError.cleanConfirmationRequired(plan.prompt)
      }
      guard value == plan.exactConfirmation else {
        throw AgentWorkflowError.cleanConfirmationMismatch(plan.exactConfirmation)
      }
      return
    }

    switch confirmation {
    case .yes, .trustedCleanOnly, .exact:
      return
    case .none:
      throw AgentWorkflowError.cleanConfirmationRequired(plan.prompt)
    }
  }

  private func tmuxPlan(taskQuery: String) throws -> AgentTmuxPlan {
    let snapshot = try store.task(matching: taskQuery, includeArchived: false)
    let record = snapshot.record
    guard let session = nonEmpty(record.tmuxSession) else {
      throw AgentWorkflowError.missingTmuxTarget(record.id)
    }
    let window = nonEmpty(record.tmuxWindow)
    let target = window.map { "\(session):\($0)" } ?? session
    let command = TmuxCommand(arguments: nonEmpty(environment["TMUX"]) != nil
      ? ["switch-client", "-t", target]
      : ["attach-session", "-t", target])
    return AgentTmuxPlan(
      taskID: record.id,
      session: session,
      window: window,
      target: target,
      commands: [command]
    )
  }

  private func run(_ plan: AgentTmuxPlan) throws {
    for command in plan.commands {
      let status = try tmuxRunner.run(command)
      guard status == 0 else {
        throw AgentWorkflowError.commandFailed("tmux", status)
      }
    }
  }

  private func run(_ command: ForegroundCommand) throws -> ForegroundCommandResult {
    try runner.run(command)
  }

  private func append(_ text: String, to url: URL) throws {
    if !fileManager.fileExists(atPath: url.path) {
      fileManager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
    }
    let handle = try FileHandle(forWritingTo: url)
    defer {
      try? handle.close()
    }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
    try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  private func scrubbedEnvironment() -> [String: String] {
    guard environment["AGENT_INHERIT_SECRETS"] != "1" else {
      return environment
    }
    var scrubbed = environment
    for key in Self.secretEnvironmentKeys {
      scrubbed.removeValue(forKey: key)
    }
    return scrubbed
  }

  private func executablePath(_ executable: String) -> String? {
    if executable.contains("/") {
      return fileManager.isExecutableFile(atPath: executable) ? executable : nil
    }
    let path = environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    for directory in path.split(separator: ":") {
      let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(executable).path
      if fileManager.isExecutableFile(atPath: candidate) {
        return candidate
      }
    }
    return nil
  }

  private func worktreeRootURL() -> URL {
    if let override = nonEmpty(environment["AGENT_WORKTREE_ROOT"]) {
      return URL(fileURLWithPath: MaestroPaths.expandTilde(override, environment: environment))
    }
    return URL(fileURLWithPath: agentNodeRoot()).appendingPathComponent("_agent-worktrees")
  }

  private func agentNodeRoot() -> String {
    MaestroPaths.expandTilde(
      nonEmpty(environment["AGENT_NODE_ROOT"]) ?? "~/Documents/Coding/node",
      environment: environment
    )
  }

  private func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else {
      return nil
    }
    return value
  }

  private static func dateSlug(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd"
    return formatter.string(from: date)
  }

  private static func reviewStamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: date)
  }

  private func shellCommandLine(from argv: [String]) -> String {
    argv.map(shellQuote).joined(separator: " ")
  }

  private func shellQuote(_ value: String) -> String {
    guard !value.isEmpty else {
      return "''"
    }
    if value.range(of: #"^[A-Za-z0-9_@%+=:,./-]+$"#, options: .regularExpression) != nil {
      return value
    }
    return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
  }

  private static let secretEnvironmentKeys = [
    "CLOUDFLARE_API_TOKEN",
    "CLOUDFLARE_ACCOUNT_ID",
    "CF_API_TOKEN",
    "HOME_ASSISTANT_TOKEN",
    "GITHUB_TOKEN",
    "GH_TOKEN",
    "NPM_TOKEN",
    "OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_SESSION_TOKEN",
    "GOOGLE_APPLICATION_CREDENTIALS"
  ]
}
