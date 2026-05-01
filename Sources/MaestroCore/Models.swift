import Foundation

public enum RepoRoot: String, Codable, CaseIterable, Sendable {
  case node
  case tools
  case resume
  case absolute
}

public struct RepoPath: Codable, Equatable, Sendable {
  public var root: RepoRoot
  public var relative: String

  public init(root: RepoRoot, relative: String = "") {
    self.root = root
    self.relative = relative
  }
}

public enum TmuxRole: String, Codable, CaseIterable, Sendable {
  case coding
  case devServer = "dev-server"
  case preview
  case check
  case build
  case deploy
  case migration
  case shell
  case agent
  case status
}

public struct RepoDefinition: Codable, Identifiable, Equatable, Sendable {
  public var id: String { key }

  public var key: String
  public var label: String
  public var path: RepoPath
  public var tmuxSession: String
  public var defaultWindows: [String]
  public var roles: [String: String]
  public var layoutHint: String?

  public init(
    key: String,
    label: String,
    path: RepoPath,
    tmuxSession: String,
    defaultWindows: [String],
    roles: [String: String] = [:],
    layoutHint: String? = nil
  ) {
    self.key = key
    self.label = label
    self.path = path
    self.tmuxSession = tmuxSession
    self.defaultWindows = defaultWindows
    self.roles = roles
    self.layoutHint = layoutHint
  }
}

public enum CommandFamily: String, Codable, CaseIterable, Sendable {
  case dev
  case check
  case test
  case build
  case preview
  case deploy
  case migration
  case content
  case status
  case shell
  case agent
  case other
}

public enum RiskTier: String, Codable, CaseIterable, Sendable {
  case safe
  case remote
  case production
  case destructive
  case unclassified
}

public enum EnvironmentTarget: String, Codable, CaseIterable, Sendable {
  case local
  case staging
  case production
  case remote
  case unknown
}

public enum CommandBehavior: String, Codable, CaseIterable, Sendable {
  case foreground
  case longRunning = "long-running"
  case singleton
  case repeatable
}

public enum ConfirmationPolicy: String, Codable, CaseIterable, Sendable {
  case none
  case review
  case typed
  case blocked
}

public struct CommandDefinition: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var repoKey: String?
  public var script: String?
  public var argv: [String]?
  public var family: CommandFamily
  public var risk: RiskTier
  public var environment: EnvironmentTarget
  public var role: TmuxRole
  public var behavior: CommandBehavior
  public var confirmation: ConfirmationPolicy
  public var label: String
  public var description: String
  public var source: String

  public init(
    id: String,
    repoKey: String? = nil,
    script: String? = nil,
    argv: [String]? = nil,
    family: CommandFamily,
    risk: RiskTier,
    environment: EnvironmentTarget,
    role: TmuxRole,
    behavior: CommandBehavior,
    confirmation: ConfirmationPolicy,
    label: String,
    description: String,
    source: String = "config"
  ) {
    self.id = id
    self.repoKey = repoKey
    self.script = script
    self.argv = argv
    self.family = family
    self.risk = risk
    self.environment = environment
    self.role = role
    self.behavior = behavior
    self.confirmation = confirmation
    self.label = label
    self.description = description
    self.source = source
  }
}

public enum ActionType: String, Codable, CaseIterable, Sendable {
  case repoOpen = "repo-open"
  case commandRun = "command-run"
  case agent
  case layout
  case bundle
}

public struct ActionDefinition: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var description: String
  public var type: ActionType
  public var risk: RiskTier
  public var confirmation: ConfirmationPolicy
  public var repoKey: String?
  public var commandID: String?
  public var layoutID: String?
  public var bundleID: String?
  public var role: TmuxRole?
  public var enabled: Bool

  public init(
    id: String,
    label: String,
    description: String,
    type: ActionType,
    risk: RiskTier = .safe,
    confirmation: ConfirmationPolicy = .none,
    repoKey: String? = nil,
    commandID: String? = nil,
    layoutID: String? = nil,
    bundleID: String? = nil,
    role: TmuxRole? = nil,
    enabled: Bool = true
  ) {
    self.id = id
    self.label = label
    self.description = description
    self.type = type
    self.risk = risk
    self.confirmation = confirmation
    self.repoKey = repoKey
    self.commandID = commandID
    self.layoutID = layoutID
    self.bundleID = bundleID
    self.role = role
    self.enabled = enabled
  }
}

public struct LayoutSlot: Codable, Equatable, Sendable {
  public var id: String
  public var app: String
  public var role: String
  public var unit: String

  public init(id: String, app: String, role: String, unit: String) {
    self.id = id
    self.app = app
    self.role = role
    self.unit = unit
  }
}

public struct LayoutDefinition: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var description: String
  public var slots: [LayoutSlot]

  public init(id: String, label: String, description: String, slots: [LayoutSlot]) {
    self.id = id
    self.label = label
    self.description = description
    self.slots = slots
  }
}

public struct BundleDefinition: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var description: String
  public var actionIDs: [String]

  public init(id: String, label: String, description: String, actionIDs: [String]) {
    self.id = id
    self.label = label
    self.description = description
    self.actionIDs = actionIDs
  }
}

public enum AgentState: String, Codable, CaseIterable, Sendable {
  case queued
  case running
  case needsInput = "needs-input"
  case review
  case merged
  case abandoned
}

public struct AgentTaskRecord: Codable, Identifiable, Equatable, Sendable {
  public var schemaVersion: Int
  public var id: String
  public var repoName: String
  public var repoPath: String
  public var worktreePath: String
  public var branch: String
  public var baseRef: String
  public var state: AgentState
  public var note: String?
  public var checkExit: Int?
  public var reviewExit: Int?
  public var reviewArtifact: String?
  public var tmuxSession: String?
  public var tmuxWindow: String?
  public var createdAt: Date
  public var updatedAt: Date
  public var cleanedAt: Date?

  public init(
    schemaVersion: Int = 1,
    id: String,
    repoName: String,
    repoPath: String,
    worktreePath: String,
    branch: String,
    baseRef: String = "main",
    state: AgentState,
    note: String? = nil,
    checkExit: Int? = nil,
    reviewExit: Int? = nil,
    reviewArtifact: String? = nil,
    tmuxSession: String? = nil,
    tmuxWindow: String? = nil,
    createdAt: Date,
    updatedAt: Date,
    cleanedAt: Date? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.repoName = repoName
    self.repoPath = repoPath
    self.worktreePath = worktreePath
    self.branch = branch
    self.baseRef = baseRef
    self.state = state
    self.note = note
    self.checkExit = checkExit
    self.reviewExit = reviewExit
    self.reviewArtifact = reviewArtifact
    self.tmuxSession = tmuxSession
    self.tmuxWindow = tmuxWindow
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.cleanedAt = cleanedAt
  }
}

public struct AuditEvent: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var schemaVersion: Int
  public var timestamp: Date
  public var actionID: String
  public var actor: String
  public var target: String
  public var risk: RiskTier
  public var outcome: String
  public var message: String?

  public init(
    id: UUID = UUID(),
    schemaVersion: Int = 1,
    timestamp: Date,
    actionID: String,
    actor: String,
    target: String,
    risk: RiskTier,
    outcome: String,
    message: String? = nil
  ) {
    self.id = id
    self.schemaVersion = schemaVersion
    self.timestamp = timestamp
    self.actionID = actionID
    self.actor = actor
    self.target = target
    self.risk = risk
    self.outcome = outcome
    self.message = message
  }
}

public struct JSONError: Codable, Error, Equatable, Sendable {
  public var ok: Bool
  public var error: String
  public var code: String

  public init(error: String, code: String) {
    self.ok = false
    self.error = error
    self.code = code
  }
}

public struct RepoCatalogDocument: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var repos: [RepoDefinition]
}

public struct CommandCatalogDocument: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var commands: [CommandDefinition]
}

public struct ActionCatalogDocument: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var actions: [ActionDefinition]
}

public struct LayoutCatalogDocument: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var layouts: [LayoutDefinition]
}

public struct BundleCatalogDocument: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var bundles: [BundleDefinition]
}
