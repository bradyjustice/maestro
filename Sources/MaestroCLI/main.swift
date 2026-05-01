import Darwin
import Foundation
import MaestroAutomation
import MaestroCore

@main
struct MaestroCLI {
  static func main() {
    do {
      try Command().run(arguments: Array(CommandLine.arguments.dropFirst()))
    } catch let error as CLIError {
      error.write()
      exit(error.exitCode)
    } catch let error as JSONError {
      writeJSON(error)
      exit(1)
    } catch {
      writeHumanError(error.localizedDescription)
      exit(1)
    }
  }
}

struct Command {
  let environment: [String: String]

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    self.environment = environment
  }

  func run(arguments: [String]) throws {
    var args = arguments
    if args.isEmpty || args.first == "-h" || args.first == "--help" || args.first == "help" {
      printHelp()
      return
    }

    let command = args.removeFirst()
    switch command {
    case "repo":
      try runRepo(args)
    case "command":
      try runCommandCatalog(args)
    case "action":
      try runActions(args)
    case "diagnostics", "doctor":
      try runDiagnostics(args)
    default:
      throw CLIError(message: "Unknown command: \(command)", code: "unknown_command", exitCode: 2, json: args.contains("--json"))
    }
  }

  private func runRepo(_ arguments: [String]) throws {
    var args = arguments
    let json = consumeFlag("--json", from: &args)
    let dryRun = consumeFlag("--dry-run", from: &args)

    guard let subcommand = args.first else {
      throw CLIError(message: "Missing repo subcommand.", code: "missing_repo_subcommand", exitCode: 2, json: json)
    }
    args.removeFirst()

    let catalog = try loadCatalog()
    switch subcommand {
    case "list":
      guard args.isEmpty else {
        throw CLIError(message: "Unexpected repo list arguments: \(args.joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
      }
      if json {
        writeJSON(catalog.repos)
      } else {
        for repo in catalog.repos {
          print("\(repo.key)\t\(repo.label)")
        }
      }
    case "open":
      guard let repoKey = args.first else {
        throw CLIError(message: "Missing repo key.", code: "missing_repo", exitCode: 2, json: json)
      }
      guard args.count == 1 else {
        throw CLIError(message: "Unexpected repo open arguments: \(args.dropFirst().joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
      }
      guard let repo = catalog.repos.first(where: { $0.key == repoKey }) else {
        throw CLIError(message: "Unknown repo: \(repoKey)", code: "unknown_repo", exitCode: 1, json: json)
      }
      let resolver = RepoPathResolver(environment: environment)
      let plan = RepoOpenPlan(repo: repo, resolvedPath: resolver.resolve(repo.path), inTmux: environment["TMUX"]?.isEmpty == false)
      if json || dryRun {
        writeJSON(plan)
        return
      }
      try RepoOpenExecutor(environment: environment).open(plan)
    default:
      throw CLIError(message: "Unknown repo subcommand: \(subcommand)", code: "unknown_repo_subcommand", exitCode: 2, json: json)
    }
  }

  private func runCommandCatalog(_ arguments: [String]) throws {
    var args = arguments
    let json = consumeFlag("--json", from: &args)

    guard let subcommand = args.first else {
      throw CLIError(message: "Missing command subcommand.", code: "missing_command_subcommand", exitCode: 2, json: json)
    }
    args.removeFirst()

    switch subcommand {
    case "list":
      var repoFilter: String?
      while !args.isEmpty {
        let token = args.removeFirst()
        switch token {
        case "--repo":
          guard let repo = args.first else {
            throw CLIError(message: "Missing value for --repo.", code: "missing_repo_filter", exitCode: 2, json: json)
          }
          repoFilter = repo
          args.removeFirst()
        default:
          throw CLIError(message: "Unexpected command list argument: \(token)", code: "unexpected_arguments", exitCode: 2, json: json)
        }
      }

      let catalog = try loadCatalog()
      let commands = catalog.commands.filter { repoFilter == nil || $0.repoKey == repoFilter }
      if json {
        writeJSON(commands)
      } else {
        for command in commands {
          let repo = command.repoKey ?? "-"
          print("\(command.id)\t\(repo)\t\(command.risk.rawValue)\t\(command.label)")
        }
      }
    default:
      throw CLIError(message: "Unknown command subcommand: \(subcommand)", code: "unknown_command_subcommand", exitCode: 2, json: json)
    }
  }

  private func runActions(_ arguments: [String]) throws {
    var args = arguments
    let json = consumeFlag("--json", from: &args)

    guard let subcommand = args.first else {
      throw CLIError(message: "Missing action subcommand.", code: "missing_action_subcommand", exitCode: 2, json: json)
    }
    args.removeFirst()

    switch subcommand {
    case "list":
      guard args.isEmpty else {
        throw CLIError(message: "Unexpected action list arguments: \(args.joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
      }
      let catalog = try loadCatalog()
      if json {
        writeJSON(catalog.actions)
      } else {
        for action in catalog.actions {
          let enabled = action.enabled ? "enabled" : "blocked"
          print("\(action.id)\t\(action.type.rawValue)\t\(action.risk.rawValue)\t\(enabled)\t\(action.label)")
        }
      }
    default:
      throw CLIError(message: "Unknown action subcommand: \(subcommand)", code: "unknown_action_subcommand", exitCode: 2, json: json)
    }
  }

  private func runDiagnostics(_ arguments: [String]) throws {
    var args = arguments
    let json = consumeFlag("--json", from: &args)
    guard args.isEmpty else {
      throw CLIError(message: "Unexpected diagnostics arguments: \(args.joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
    }

    let catalog = try loadCatalog()
    let automation = NativeMacAutomation().permissionSnapshot(promptForAccessibility: false)
    let diagnostics = DiagnosticsReport(
      configDirectory: MaestroPaths.defaultConfigDirectory(environment: environment).path,
      stateDirectory: MaestroPaths.defaultStateDirectory(environment: environment).path,
      repoCount: catalog.repos.count,
      commandCount: catalog.commands.count,
      actionCount: catalog.actions.count,
      accessibilityTrusted: automation.accessibilityTrusted,
      appleEventsAvailable: automation.appleEventsAvailable,
      automationNotes: automation.notes
    )

    if json {
      writeJSON(diagnostics)
    } else {
      print("Config: \(diagnostics.configDirectory)")
      print("State: \(diagnostics.stateDirectory)")
      print("Repos: \(diagnostics.repoCount)")
      print("Commands: \(diagnostics.commandCount)")
      print("Actions: \(diagnostics.actionCount)")
      print("Accessibility: \(diagnostics.accessibilityTrusted ? "trusted" : "not trusted")")
      print("Apple Events: \(diagnostics.appleEventsAvailable ? "available" : "unavailable")")
    }
  }

  private func loadCatalog() throws -> CatalogBundle {
    try CatalogLoader(
      configDirectory: MaestroPaths.defaultConfigDirectory(environment: environment),
      pathResolver: RepoPathResolver(environment: environment)
    ).load()
  }
}

struct DiagnosticsReport: Codable, Equatable {
  var configDirectory: String
  var stateDirectory: String
  var repoCount: Int
  var commandCount: Int
  var actionCount: Int
  var accessibilityTrusted: Bool
  var appleEventsAvailable: Bool
  var automationNotes: [String]
}

struct CLIError: Error {
  var message: String
  var code: String
  var exitCode: Int32
  var json: Bool

  func write() {
    if json {
      writeJSON(JSONError(error: message, code: code))
    } else {
      writeHumanError(message)
    }
  }
}

@discardableResult
func consumeFlag(_ flag: String, from args: inout [String]) -> Bool {
  guard let index = args.firstIndex(of: flag) else {
    return false
  }
  args.remove(at: index)
  return true
}

func writeJSON<T: Encodable>(_ value: T) {
  do {
    let data = try MaestroJSON.encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  } catch {
    writeHumanError("Could not encode JSON output: \(error.localizedDescription)")
  }
}

func writeHumanError(_ message: String) {
  FileHandle.standardError.write(Data("maestro: \(message)\n".utf8))
}

func printHelp() {
  print(
    """
    Usage:
      maestro repo list [--json]
      maestro repo open <repo> [--json] [--dry-run]
      maestro command list [--repo <repo>] [--json]
      maestro action list [--json]
      maestro diagnostics [--json]
    """
  )
}
