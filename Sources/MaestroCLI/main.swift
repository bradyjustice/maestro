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
    } catch let error as PaletteConfigError {
      writeHumanError(error.localizedDescription)
      return 1
    } catch {
      writeHumanError(error.localizedDescription)
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
    case "button":
      try runButton(args)
    default:
      throw CLIError(message: "Unknown command: \(command)", code: "unknown_command", exitCode: 2, json: args.contains("--json"))
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
      let loaded = try loadUncheckedConfig()
      let validation = PaletteValidator().validate(loaded.config)
      if json {
        writeJSON(ConfigValidateOutput(
          configPath: loaded.fileURL.path,
          validation: validation
        ))
      } else if validation.ok {
        print("palette.json OK")
      } else {
        for issue in validation.issues {
          print("\(issue.code): \(issue.message)")
        }
      }
      if !validation.ok {
        throw CLIError(message: "palette.json validation failed.", code: "invalid_config", exitCode: 1, json: json, alreadyWritten: true)
      }
    default:
      throw CLIError(message: "Unknown config subcommand: \(subcommand)", code: "unknown_config_subcommand", exitCode: 2, json: json)
    }
  }

  private func runButton(_ arguments: [String]) throws {
    var args = arguments
    let json = consumeFlag("--json", from: &args)
    let dryRun = consumeFlag("--dry-run", from: &args)

    guard let subcommand = args.first else {
      throw CLIError(message: "Missing button subcommand.", code: "missing_button_subcommand", exitCode: 2, json: json)
    }
    args.removeFirst()

    switch subcommand {
    case "list":
      guard !dryRun else {
        throw CLIError(message: "--dry-run is only valid with button run.", code: "unexpected_arguments", exitCode: 2, json: json)
      }
      guard args.isEmpty else {
        throw CLIError(message: "Unexpected button list arguments: \(args.joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
      }
      let loaded = try loadConfig()
      if json {
        writeJSON(loaded.config.buttons)
      } else {
        for button in loaded.config.buttons {
          print("\(button.id)\t\(button.kind.rawValue)\t\(button.target)\t\(button.label)")
        }
      }
    case "run":
      guard let buttonID = args.first else {
        throw CLIError(message: "Missing button id.", code: "missing_button", exitCode: 2, json: json)
      }
      guard args.count == 1 else {
        throw CLIError(message: "Unexpected button run arguments: \(args.dropFirst().joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
      }

      let loaded = try loadConfig()
      let runtime = PaletteRuntime(
        config: loaded.config,
        configDirectory: loaded.fileURL.deletingLastPathComponent(),
        environment: environment
      )

      if dryRun {
        let plan = try runtime.buttonPlan(id: buttonID)
        if json {
          writeJSON(plan)
        } else {
          printButtonPlan(plan)
        }
        return
      }

      let result = try runtime.runButton(id: buttonID, confirmation: NativePaletteConfirmation())
      if json {
        writeJSON(result)
      } else {
        print(result.message)
      }
      if !result.ok {
        throw CLIError(message: result.message, code: "button_blocked", exitCode: 1, json: json, alreadyWritten: true)
      }
    default:
      throw CLIError(message: "Unknown button subcommand: \(subcommand)", code: "unknown_button_subcommand", exitCode: 2, json: json)
    }
  }

  private func loadUncheckedConfig() throws -> (config: PaletteConfig, fileURL: URL) {
    let fileURL = MaestroPaths.defaultConfigFile(environment: environment)
    let data = try Data(contentsOf: fileURL)
    let config = try MaestroJSON.decoder.decode(PaletteConfig.self, from: data)
    return (config, fileURL)
  }

  private func loadConfig() throws -> (config: PaletteConfig, fileURL: URL) {
    let loaded = try loadUncheckedConfig()
    let validation = PaletteValidator().validate(loaded.config)
    guard validation.ok else {
      throw PaletteConfigError.invalidConfig(validation.issues)
    }
    return loaded
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

func printButtonPlan(_ plan: CommandButtonPlan) {
  print("\(plan.buttonID)")
  print("  target: \(plan.target.tmuxPaneTarget)")
  if let displayCommand = plan.displayCommand {
    print("  command: \(displayCommand)")
  } else {
    print("  command: C-c")
  }
  print("  tmux: \(plan.tmuxCommand.argv.joined(separator: " "))")
}

func printHelp() {
  print(
    """
    Maestro

    Usage:
      maestro config validate [--json]
      maestro button list [--json]
      maestro button run <button-id> [--dry-run] [--json]

    Configuration:
      maestro/config/palette.json
    """
  )
}

