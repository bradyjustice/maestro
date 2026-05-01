import Foundation

public struct TmuxCommand: Codable, Equatable, Sendable {
  public var executable: String
  public var arguments: [String]

  public init(executable: String = "tmux", arguments: [String]) {
    self.executable = executable
    self.arguments = arguments
  }
}

public struct RepoOpenPlan: Codable, Equatable, Sendable {
  public var repo: RepoDefinition
  public var resolvedPath: String
  public var iTermTitle: String
  public var createCommands: [TmuxCommand]
  public var focusCommand: TmuxCommand

  public init(repo: RepoDefinition, resolvedPath: String, inTmux: Bool) {
    self.repo = repo
    self.resolvedPath = resolvedPath
    self.iTermTitle = "work:\(repo.key)"
    self.createCommands = Self.createCommands(repo: repo, resolvedPath: resolvedPath)
    self.focusCommand = TmuxCommand(arguments: inTmux ? ["switch-client", "-t", repo.tmuxSession] : ["attach-session", "-t", repo.tmuxSession])
  }

  private static func createCommands(repo: RepoDefinition, resolvedPath: String) -> [TmuxCommand] {
    guard let firstWindow = repo.defaultWindows.first else {
      return []
    }

    var commands = [
      TmuxCommand(arguments: ["new-session", "-d", "-s", repo.tmuxSession, "-n", firstWindow, "-c", resolvedPath])
    ]

    for window in repo.defaultWindows.dropFirst() {
      commands.append(TmuxCommand(arguments: ["new-window", "-t", "\(repo.tmuxSession):", "-n", window, "-c", resolvedPath]))
    }

    commands.append(TmuxCommand(arguments: ["select-window", "-t", "\(repo.tmuxSession):\(firstWindow)"]))
    return commands
  }
}
