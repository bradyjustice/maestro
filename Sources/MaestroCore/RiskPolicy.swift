import Foundation

public struct RiskPolicy: Sendable {
  public init() {}

  public func classifyPackageScript(name: String, body: String) -> RiskTier {
    let text = "\(name) \(body)".lowercased()

    if containsAny(text, ["rm -rf", "reset", "drop ", "truncate", "destroy", "delete-prod", "wipe"]) {
      return .destructive
    }

    if containsAny(text, ["prod", "production"]) {
      return .production
    }

    if containsAny(text, ["deploy", "wrangler deploy", "cloudflare", "remote", "migrate", "migration"]) {
      return .remote
    }

    if safeLocalScriptNames.contains(name) {
      return .safe
    }

    return .unclassified
  }

  public func confirmation(for risk: RiskTier) -> ConfirmationPolicy {
    switch risk {
    case .safe:
      return .none
    case .remote:
      return .review
    case .production, .destructive:
      return .typed
    case .unclassified:
      return .blocked
    }
  }

  public func environment(for risk: RiskTier, scriptName: String, body: String) -> EnvironmentTarget {
    let text = "\(scriptName) \(body)".lowercased()
    if risk == .production || text.contains("prod") || text.contains("production") {
      return .production
    }
    if text.contains("staging") {
      return .staging
    }
    if risk == .remote {
      return .remote
    }
    if risk == .unclassified {
      return .unknown
    }
    return .local
  }

  public func family(for scriptName: String, body: String) -> CommandFamily {
    let text = "\(scriptName) \(body)".lowercased()
    if scriptName == "dev" || scriptName.hasPrefix("dev:") {
      return .dev
    }
    if scriptName == "check" || scriptName.hasPrefix("check:") {
      return .check
    }
    if scriptName == "test" || scriptName.hasPrefix("test:") {
      return .test
    }
    if scriptName == "build" || scriptName.hasPrefix("build:") {
      return .build
    }
    if scriptName == "preview" || scriptName.hasPrefix("preview:") {
      return .preview
    }
    if text.contains("deploy") {
      return .deploy
    }
    if text.contains("migrate") || text.contains("migration") {
      return .migration
    }
    if text.contains("content") {
      return .content
    }
    return .other
  }

  public func role(for family: CommandFamily) -> TmuxRole {
    switch family {
    case .dev:
      return .devServer
    case .check, .test:
      return .check
    case .build:
      return .build
    case .preview:
      return .preview
    case .deploy:
      return .deploy
    case .migration:
      return .migration
    case .status:
      return .status
    case .shell:
      return .shell
    case .agent:
      return .agent
    case .content, .other:
      return .shell
    }
  }

  public func behavior(for family: CommandFamily) -> CommandBehavior {
    switch family {
    case .dev, .preview:
      return .singleton
    case .agent:
      return .longRunning
    case .check, .test, .build, .deploy, .migration, .content, .status, .shell, .other:
      return .foreground
    }
  }

  private var safeLocalScriptNames: Set<String> {
    [
      "dev",
      "check",
      "test",
      "test:unit",
      "test:watch",
      "build",
      "preview",
      "lint",
      "format",
      "typecheck",
      "start",
      "status"
    ]
  }

  private func containsAny(_ text: String, _ needles: [String]) -> Bool {
    needles.contains { text.contains($0) }
  }
}
