import Darwin
import Foundation
import MaestroAutomation
import MaestroCore

@main
struct MaestroCLI {
  static func main() {
    let exitCode = Command().run(arguments: Array(CommandLine.arguments.dropFirst()))
    exit(exitCode)
  }
}

struct Command {
  var environment: [String: String]

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    self.environment = environment
  }

  func run(arguments: [String]) -> Int32 {
    do {
      try runOrThrow(arguments: arguments)
      return 0
    } catch let error as CLIError {
      error.write()
      return error.exitCode
    } catch {
      if arguments.contains("--json") {
        writeJSON(JSONError(code: "command_failed", message: error.localizedDescription))
      } else {
        writeHumanError(error.localizedDescription)
      }
      return 1
    }
  }

  private func runOrThrow(arguments: [String]) throws {
    var args = arguments
    if args.isEmpty || args.first == "-h" || args.first == "--help" || args.first == "help" {
      printHelp()
      return
    }

    let command = args.removeFirst()
    switch command {
    case "config":
      try runConfig(args)
    case "arrange":
      try runArrange(args)
    default:
      throw CLIError(
        message: "Unknown command: \(command)",
        code: "unknown_command",
        exitCode: 2,
        json: args.contains("--json")
      )
    }
  }

  private func runConfig(_ arguments: [String]) throws {
    var args = arguments
    let json = consumeFlag("--json", from: &args)

    guard let subcommand = args.first else {
      throw CLIError(message: "Missing config subcommand.", code: "missing_config_subcommand", exitCode: 2, json: json)
    }
    args.removeFirst()

    switch subcommand {
    case "validate":
      guard args.isEmpty else {
        throw CLIError(message: "Unexpected config validate arguments: \(args.joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
      }
      let loaded = try loadUncheckedWorkspaceConfig()
      let validation = WorkspaceConfigValidator().validate(loaded.config)
      if json {
        writeJSON(ConfigValidateOutput(configPath: loaded.fileURL.path, validation: validation))
      } else if validation.ok {
        print("workspace.json OK")
      } else {
        for issue in validation.issues {
          print("\(issue.code): \(issue.message)")
        }
      }
      if !validation.ok {
        throw CLIError(message: "workspace.json validation failed.", code: "invalid_config", exitCode: 1, json: json, alreadyWritten: true)
      }
    default:
      throw CLIError(message: "Unknown config subcommand: \(subcommand)", code: "unknown_config_subcommand", exitCode: 2, json: json)
    }
  }

  private func runArrange(_ arguments: [String]) throws {
    var args = arguments
    let json = consumeFlag("--json", from: &args)
    let dryRun = consumeFlag("--dry-run", from: &args)

    guard args.isEmpty else {
      throw CLIError(message: "Unexpected arrange arguments: \(args.joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
    }

    let loaded = try loadWorkspaceConfig()
    let runtime = workspaceRuntime(loaded)
    let plan = dryRun ? try runtime.dryRunArrangePlan() : try runtime.arrange()
    if json {
      writeJSON(plan)
    } else {
      printArrangePlan(plan, dryRun: dryRun)
    }
  }

  private func loadUncheckedWorkspaceConfig() throws -> LoadedWorkspaceConfig {
    try WorkspaceConfigLoader(environment: environment).loadUnchecked()
  }

  private func loadWorkspaceConfig() throws -> LoadedWorkspaceConfig {
    try WorkspaceConfigLoader(environment: environment).load()
  }

  private func workspaceRuntime(_ loaded: LoadedWorkspaceConfig) -> WorkspaceRuntime {
    let diagnostics = MaestroDiagnostics(options: MaestroDebugOptions(environment: environment))
    return WorkspaceRuntime(
      config: loaded.config,
      configDirectory: loaded.fileURL.deletingLastPathComponent(),
      environment: environment,
      tmux: TmuxController(diagnostics: diagnostics),
      windows: NativeMacAutomation(diagnostics: diagnostics),
      diagnostics: diagnostics
    )
  }
}

struct ConfigValidateOutput: Codable {
  var configPath: String
  var validation: PaletteValidationResult
}

struct CLIError: Error {
  var message: String
  var code: String
  var exitCode: Int32
  var json: Bool
  var alreadyWritten: Bool

  init(
    message: String,
    code: String,
    exitCode: Int32,
    json: Bool,
    alreadyWritten: Bool = false
  ) {
    self.message = message
    self.code = code
    self.exitCode = exitCode
    self.json = json
    self.alreadyWritten = alreadyWritten
  }

  func write() {
    guard !alreadyWritten else {
      return
    }
    if json {
      writeJSON(JSONError(code: code, message: message))
    } else {
      writeHumanError(message)
    }
  }
}

struct JSONError: Codable {
  var ok = false
  var code: String
  var message: String
}

func consumeFlag(_ flag: String, from args: inout [String]) -> Bool {
  if let index = args.firstIndex(of: flag) {
    args.remove(at: index)
    return true
  }
  return false
}

func writeJSON<T: Encodable>(_ value: T) {
  do {
    let data = try MaestroJSON.encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  } catch {
    writeHumanError(error.localizedDescription)
  }
}

func writeHumanError(_ message: String) {
  FileHandle.standardError.write(Data("maestro: \(message)\n".utf8))
}

func printArrangePlan(_ plan: WorkspaceArrangePlan, dryRun: Bool) {
  print("\(dryRun ? "Would arrange" : "Arranged") \(plan.workspace.label)")
  print("  workspace: \(plan.workspace.path)")
  print("  terminal: \(frameSummary(plan.terminal.frame)) \(plan.terminal.sessionName):\(plan.terminal.windowName)")
  print("  apps: \(frameSummary(plan.appArea.frame)) \(plan.appArea.apps.map(\.label).joined(separator: ", "))")
}

func frameSummary(_ frame: LayoutRect) -> String {
  "\(Int(frame.x)),\(Int(frame.y)) \(Int(frame.width))x\(Int(frame.height))"
}

func printHelp() {
  print(
    """
    Maestro

    Usage:
      maestro config validate [--json]
      maestro arrange [--dry-run] [--json]

    Configuration:
      maestro/config/workspace.json
    """
  )
}
