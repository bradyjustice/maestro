import Foundation

public struct MaestroPaths: Sendable {
  public static let defaultStateSuffix = "local-tools/maestro"

  public static func defaultConfigDirectory(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) -> URL {
    if let override = environment["MAESTRO_CONFIG_DIR"], !override.isEmpty {
      return URL(fileURLWithPath: expandTilde(override, environment: environment))
    }

    let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
    if let found = findUp(from: cwd, relativePath: "maestro/config", fileManager: fileManager) {
      return found
    }

    if let executable = CommandLine.arguments.first, !executable.isEmpty {
      let executableURL = URL(fileURLWithPath: executable).deletingLastPathComponent()
      if let found = findUp(from: executableURL, relativePath: "maestro/config", fileManager: fileManager) {
        return found
      }
    }

    return cwd.appendingPathComponent("maestro/config")
  }

  public static func defaultStateDirectory(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> URL {
    if let override = environment["MAESTRO_STATE_DIR"], !override.isEmpty {
      return URL(fileURLWithPath: expandTilde(override, environment: environment))
    }

    if let xdgStateHome = environment["XDG_STATE_HOME"], !xdgStateHome.isEmpty {
      return URL(fileURLWithPath: expandTilde(xdgStateHome, environment: environment))
        .appendingPathComponent(defaultStateSuffix)
    }

    let home = environment["HOME"] ?? NSHomeDirectory()
    return URL(fileURLWithPath: expandTilde(home, environment: environment))
      .appendingPathComponent(".local/state")
      .appendingPathComponent(defaultStateSuffix)
  }

  public static func expandTilde(
    _ path: String,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String {
    if path == "~" {
      return environment["HOME"] ?? NSHomeDirectory()
    }
    if path.hasPrefix("~/") {
      let home = environment["HOME"] ?? NSHomeDirectory()
      return home + "/" + String(path.dropFirst(2))
    }
    return path
  }

  private static func findUp(
    from start: URL,
    relativePath: String,
    fileManager: FileManager
  ) -> URL? {
    var current = start.standardizedFileURL

    while true {
      let candidate = current.appendingPathComponent(relativePath)
      if fileManager.fileExists(atPath: candidate.path) {
        return candidate
      }

      let parent = current.deletingLastPathComponent()
      if parent.path == current.path {
        return nil
      }
      current = parent
    }
  }
}

public struct RepoPathResolver: Sendable {
  public var environment: [String: String]

  public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    self.environment = environment
  }

  public func resolve(_ repoPath: RepoPath) -> String {
    switch repoPath.root {
    case .node:
      return join(base: root(env: "WORK_NODE_ROOT", fallback: "~/Documents/Coding/node"), relative: repoPath.relative)
    case .tools:
      return join(base: root(env: "WORK_TOOLS_ROOT", fallback: "~/Documents/Coding/maestro"), relative: repoPath.relative)
    case .resume:
      return join(base: root(env: "WORK_RESUME_ROOT", fallback: "~/Documents/Coding/resume"), relative: repoPath.relative)
    case .absolute:
      return MaestroPaths.expandTilde(repoPath.relative, environment: environment)
    }
  }

  private func root(env: String, fallback: String) -> String {
    MaestroPaths.expandTilde(environment[env].flatMap { $0.isEmpty ? nil : $0 } ?? fallback, environment: environment)
  }

  private func join(base: String, relative: String) -> String {
    guard !relative.isEmpty else {
      return base
    }
    return URL(fileURLWithPath: base).appendingPathComponent(relative).path
  }
}
