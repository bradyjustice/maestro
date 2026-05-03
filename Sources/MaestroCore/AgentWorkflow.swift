import Foundation

public struct AgentStartPlan: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var taskID: String
  public var repoName: String
  public var repoPath: String
  public var worktreePath: String
  public var branch: String
  public var baseRef: String
  public var recordPath: String
  public var launchSkipped: Bool
  public var promptProvided: Bool
  public var tmuxSession: String?
  public var tmuxWindow: String?

  public init(
    schemaVersion: Int = 1,
    taskID: String,
    repoName: String,
    repoPath: String,
    worktreePath: String,
    branch: String,
    baseRef: String,
    recordPath: String,
    launchSkipped: Bool,
    promptProvided: Bool,
    tmuxSession: String? = nil,
    tmuxWindow: String? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.taskID = taskID
    self.repoName = repoName
    self.repoPath = repoPath
    self.worktreePath = worktreePath
    self.branch = branch
    self.baseRef = baseRef
    self.recordPath = recordPath
    self.launchSkipped = launchSkipped
    self.promptProvided = promptProvided
    self.tmuxSession = tmuxSession
    self.tmuxWindow = tmuxWindow
  }
}

public struct AgentStartResult: Codable, Equatable, Sendable {
  public var ok: Bool
  public var plan: AgentStartPlan
  public var snapshot: AgentTaskSnapshot
  public var warnings: [String]
  public var message: String

  public init(
    ok: Bool = true,
    plan: AgentStartPlan,
    snapshot: AgentTaskSnapshot,
    warnings: [String] = [],
    message: String
  ) {
    self.ok = ok
    self.plan = plan
    self.snapshot = snapshot
    self.warnings = warnings
    self.message = message
  }
}

public struct AgentMarkResult: Codable, Equatable, Sendable {
  public var ok: Bool
  public var snapshot: AgentTaskSnapshot
  public var message: String

  public init(ok: Bool = true, snapshot: AgentTaskSnapshot, message: String) {
    self.ok = ok
    self.snapshot = snapshot
    self.message = message
  }
}

public struct AgentReviewResult: Codable, Equatable, Sendable {
  public var ok: Bool
  public var snapshot: AgentTaskSnapshot
  public var artifactPath: String
  public var checkCommand: String?
  public var checkExit: Int?
  public var reviewExit: Int
  public var message: String

  public init(
    ok: Bool,
    snapshot: AgentTaskSnapshot,
    artifactPath: String,
    checkCommand: String? = nil,
    checkExit: Int? = nil,
    reviewExit: Int,
    message: String
  ) {
    self.ok = ok
    self.snapshot = snapshot
    self.artifactPath = artifactPath
    self.checkCommand = checkCommand
    self.checkExit = checkExit
    self.reviewExit = reviewExit
    self.message = message
  }
}

public struct AgentCleanPlan: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var snapshot: AgentTaskSnapshot
  public var force: Bool
  public var dirty: Bool
  public var worktreeExists: Bool
  public var requiresExactConfirmation: Bool
  public var exactConfirmation: String
  public var prompt: String

  public init(
    schemaVersion: Int = 1,
    snapshot: AgentTaskSnapshot,
    force: Bool,
    dirty: Bool,
    worktreeExists: Bool,
    requiresExactConfirmation: Bool,
    exactConfirmation: String,
    prompt: String
  ) {
    self.schemaVersion = schemaVersion
    self.snapshot = snapshot
    self.force = force
    self.dirty = dirty
    self.worktreeExists = worktreeExists
    self.requiresExactConfirmation = requiresExactConfirmation
    self.exactConfirmation = exactConfirmation
    self.prompt = prompt
  }
}

public enum AgentCleanConfirmation: Equatable, Sendable {
  case none
  case yes
  case exact(String)
  case trustedCleanOnly
}

public struct AgentCleanResult: Codable, Equatable, Sendable {
  public var ok: Bool
  public var snapshot: AgentTaskSnapshot
  public var archivedPath: String
  public var removedWorktree: Bool
  public var message: String

  public init(
    ok: Bool = true,
    snapshot: AgentTaskSnapshot,
    archivedPath: String,
    removedWorktree: Bool,
    message: String
  ) {
    self.ok = ok
    self.snapshot = snapshot
    self.archivedPath = archivedPath
    self.removedWorktree = removedWorktree
    self.message = message
  }
}

public struct AgentTmuxPlan: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var taskID: String
  public var session: String
  public var window: String?
  public var target: String
  public var commands: [TmuxCommand]

  public init(
    schemaVersion: Int = 1,
    taskID: String,
    session: String,
    window: String? = nil,
    target: String,
    commands: [TmuxCommand]
  ) {
    self.schemaVersion = schemaVersion
    self.taskID = taskID
    self.session = session
    self.window = window
    self.target = target
    self.commands = commands
  }
}

public struct AgentTmuxResult: Codable, Equatable, Sendable {
  public var ok: Bool
  public var plan: AgentTmuxPlan
  public var message: String

  public init(ok: Bool = true, plan: AgentTmuxPlan, message: String) {
    self.ok = ok
    self.plan = plan
    self.message = message
  }
}

public enum AgentWorkflowError: Error, LocalizedError, Equatable, Sendable {
  case invalidSlug(String)
  case repoNotFound(String)
  case notGitRepo(String)
  case baseRefMissing(String, String)
  case branchExists(String)
  case worktreeExists(String)
  case recordExists(String)
  case missingWorktree(String)
  case cleanStateRefusal(String, String)
  case cleanConfirmationRequired(String)
  case cleanConfirmationMismatch(String)
  case missingTmuxTarget(String)
  case noCheckCommand(String)
  case unsafeCheckCommand(String)
  case commandFailed(String, Int32)
  case executableMissing(String)

  public var errorDescription: String? {
    switch self {
    case let .invalidSlug(slug):
      return "Task slug must use letters, numbers, dots, underscores, or hyphens: \(slug)"
    case let .repoNotFound(repo):
      return "Repo not found: \(repo)"
    case let .notGitRepo(path):
      return "Not a git repo: \(path)"
    case let .baseRefMissing(repo, baseRef):
      return "Base ref not found in \(repo): \(baseRef)"
    case let .branchExists(branch):
      return "Branch already exists: \(branch)"
    case let .worktreeExists(path):
      return "Worktree path already exists: \(path)"
    case let .recordExists(taskID):
      return "Agent record already exists: \(taskID)"
    case let .missingWorktree(path):
      return "Worktree not found: \(path)"
    case let .cleanStateRefusal(taskID, state):
      return "Refusing to clean \(taskID) in state '\(state)'. Mark merged/abandoned first or rerun with --force."
    case let .cleanConfirmationRequired(prompt):
      return prompt
    case let .cleanConfirmationMismatch(expected):
      return "Confirmation did not match \(expected)."
    case let .missingTmuxTarget(taskID):
      return "Agent task has no tmux target: \(taskID)"
    case let .noCheckCommand(repoName):
      return "No check command found for \(repoName)."
    case let .unsafeCheckCommand(commandID):
      return "Check command is not a safe local foreground command: \(commandID)"
    case let .commandFailed(label, status):
      return "\(label) failed with status \(status)."
    case let .executableMissing(executable):
      return "\(executable) is required."
    }
  }
}

public enum AgentSlugValidator {
  public static func validate(_ slug: String) throws {
    guard slug.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil else {
      throw AgentWorkflowError.invalidSlug(slug)
    }
  }
}

