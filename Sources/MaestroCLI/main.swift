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
    case "layout":
      try runLayout(args)
    case "action":
      try runAction(args)
    case "pane":
      try runPane(args)
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
      let loaded = try loadUncheckedCommandCenterConfig()
      let validation = CommandCenterValidator().validate(loaded.config)
      if json {
        writeJSON(ConfigValidateOutput(
          configPath: loaded.fileURL.path,
          validation: validation,
          migratedFromSchemaVersion: loaded.migratedFromSchemaVersion
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

  private func runLayout(_ arguments: [String]) throws {
    var args = arguments
    let json = consumeFlag("--json", from: &args)
    let dryRun = consumeFlag("--dry-run", from: &args)

    guard let subcommand = args.first else {
      throw CLIError(message: "Missing layout subcommand.", code: "missing_layout_subcommand", exitCode: 2, json: json)
    }
    args.removeFirst()

    switch subcommand {
    case "list":
      guard !dryRun else {
        throw CLIError(message: "--dry-run is only valid with layout apply.", code: "unexpected_arguments", exitCode: 2, json: json)
      }
      guard args.isEmpty else {
        throw CLIError(message: "Unexpected layout list arguments: \(args.joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
      }
      let loaded = try loadCommandCenterConfig()
      if json {
        writeJSON(loaded.config.screenLayouts)
      } else {
        for layout in loaded.config.screenLayouts {
          print("\(layout.id)\t\(layout.terminalHosts.count) hosts\t\(layout.appZones.count) app zones\t\(layout.label)")
        }
      }
    case "apply":
      guard let layoutID = args.first else {
        throw CLIError(message: "Missing layout id.", code: "missing_layout", exitCode: 2, json: json)
      }
      guard args.count == 1 else {
        throw CLIError(message: "Unexpected layout apply arguments: \(args.dropFirst().joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
      }
      let loaded = try loadCommandCenterConfig()
      let runtime = commandCenterRuntime(loaded)
      let plan = dryRun ? try runtime.dryRunLayoutPlan(id: layoutID) : try runtime.applyLayout(id: layoutID)
      if json {
        writeJSON(plan)
      } else {
        printLayoutPlan(plan, dryRun: dryRun)
      }
    default:
      throw CLIError(message: "Unknown layout subcommand: \(subcommand)", code: "unknown_layout_subcommand", exitCode: 2, json: json)
    }
  }

  private func runAction(_ arguments: [String]) throws {
    var args = arguments
    let json = consumeFlag("--json", from: &args)
    let dryRun = consumeFlag("--dry-run", from: &args)

    guard let subcommand = args.first else {
      throw CLIError(message: "Missing action subcommand.", code: "missing_action_subcommand", exitCode: 2, json: json)
    }
    args.removeFirst()

    switch subcommand {
    case "list":
      guard !dryRun else {
        throw CLIError(message: "--dry-run is only valid with action run.", code: "unexpected_arguments", exitCode: 2, json: json)
      }
      guard args.isEmpty else {
        throw CLIError(message: "Unexpected action list arguments: \(args.joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
      }
      let loaded = try loadCommandCenterConfig()
      if json {
        writeJSON(loaded.config.actions)
      } else {
        for action in loaded.config.actions {
          print("\(action.id)\t\(action.kind.rawValue)\t\(action.label)")
        }
      }
    case "run":
      guard let actionID = args.first else {
        throw CLIError(message: "Missing action id.", code: "missing_action", exitCode: 2, json: json)
      }
      guard args.count == 1 else {
        throw CLIError(message: "Unexpected action run arguments: \(args.dropFirst().joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
      }
      let loaded = try loadCommandCenterConfig()
      let runtime = commandCenterRuntime(loaded)
      if dryRun {
        let plan = try runtime.actionPlan(id: actionID)
        if json {
          writeJSON(plan)
        } else {
          printActionPlan(plan)
        }
        return
      }

      let result = try runtime.runAction(id: actionID, confirmation: NativeCommandCenterConfirmation())
      if json {
        writeJSON(result)
      } else {
        print(result.message)
      }
      if !result.ok {
        throw CLIError(message: result.message, code: "action_blocked", exitCode: 1, json: json, alreadyWritten: true)
      }
    default:
      throw CLIError(message: "Unknown action subcommand: \(subcommand)", code: "unknown_action_subcommand", exitCode: 2, json: json)
    }
  }

  private func runPane(_ arguments: [String]) throws {
    var args = arguments
    let json = consumeFlag("--json", from: &args)
    let dryRun = consumeFlag("--dry-run", from: &args)
    let layoutID = consumeOption("--layout", from: &args)

    guard let subcommand = args.first else {
      throw CLIError(message: "Missing pane subcommand.", code: "missing_pane_subcommand", exitCode: 2, json: json)
    }
    args.removeFirst()

    let loaded = try loadCommandCenterConfig()
    let runtime = commandCenterRuntime(loaded)

    switch subcommand {
    case "list":
      guard args.isEmpty else {
        throw CLIError(message: "Unexpected pane list arguments: \(args.joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
      }
      if dryRun {
        let bindings = try runtime.configuredPaneBindings(layoutID: layoutID)
        if json {
          writeJSON(bindings)
        } else {
          printPaneBindings(bindings)
        }
      } else {
        let panes = try runtime.livePaneList(layoutID: layoutID)
        if json {
          writeJSON(panes)
        } else {
          for pane in panes {
            print("\(pane.sessionName):\(pane.windowName).\(pane.paneIndex)\t\(pane.slotID ?? "-")\t\(pane.currentCommand)")
          }
        }
      }
    case "swap", "move":
      guard args.count == 2 else {
        throw CLIError(message: "Usage: maestro pane \(subcommand) <host.slot> <host.slot> [--dry-run] [--json]", code: "unexpected_arguments", exitCode: 2, json: json)
      }
      let source = try CommandCenterPaneRef(parse: args[0])
      let destination = try CommandCenterPaneRef(parse: args[1])
      let kind: CommandCenterPaneOperationKind = subcommand == "swap" ? .swap : .move
      let plan = dryRun
        ? try runtime.paneOperationPlan(kind: kind, source: source, destination: destination, layoutID: layoutID)
        : try runtime.runPaneOperation(kind: kind, source: source, destination: destination, layoutID: layoutID)
      if json {
        writeJSON(plan)
      } else {
        printPaneOperationPlan(plan, dryRun: dryRun)
      }
    default:
      throw CLIError(message: "Unknown pane subcommand: \(subcommand)", code: "unknown_pane_subcommand", exitCode: 2, json: json)
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
      let loaded = try loadCommandCenterConfig()
      let aliases = loaded.config.actions.filter { $0.kind == .shellArgv || $0.kind == .stop }
      if json {
        writeJSON(aliases.map(ButtonAliasListItem.init(action:)))
      } else {
        for action in aliases {
          print("\(action.id)\t\(buttonKind(for: action).rawValue)\t\(action.hostID ?? "-")\t\(action.label)")
        }
      }
    case "run":
      guard let buttonID = args.first else {
        throw CLIError(message: "Missing button id.", code: "missing_button", exitCode: 2, json: json)
      }
      guard args.count == 1 else {
        throw CLIError(message: "Unexpected button run arguments: \(args.dropFirst().joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
      }

      let loaded = try loadCommandCenterConfig()
      let runtime = commandCenterRuntime(loaded)
      guard let aliasAction = loaded.config.actions.first(where: { $0.id == buttonID }),
            aliasAction.kind == .shellArgv || aliasAction.kind == .stop else {
        throw CLIError(message: "Unknown button: \(buttonID)", code: "missing_button", exitCode: 2, json: json)
      }

      if dryRun {
        let plan = ButtonAliasPlan(actionPlan: try runtime.actionPlan(id: buttonID))
        if json {
          writeJSON(plan)
        } else {
          printButtonAliasPlan(plan)
        }
        return
      }

      let result = try runtime.runAction(id: buttonID, confirmation: NativeCommandCenterConfirmation())
      if json {
        writeJSON(ButtonAliasRunResult(result: result, buttonID: buttonID))
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

  private func loadUncheckedCommandCenterConfig() throws -> LoadedCommandCenterConfig {
    try CommandCenterConfigLoader(environment: environment).loadUnchecked()
  }

  private func loadCommandCenterConfig() throws -> LoadedCommandCenterConfig {
    try CommandCenterConfigLoader(environment: environment).load()
  }

  private func commandCenterRuntime(_ loaded: LoadedCommandCenterConfig) -> CommandCenterRuntime {
    let diagnostics = MaestroDiagnostics(options: MaestroDebugOptions(environment: environment))
    return CommandCenterRuntime(
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
  var migratedFromSchemaVersion: Int?
}

struct ButtonAliasListItem: Codable {
  var id: String
  var label: String
  var kind: CommandButtonKind
  var hostID: String?
  var slotID: String?

  init(action: CommandCenterAction) {
    self.id = action.id
    self.label = action.label
    self.kind = action.kind == .stop ? .stop : .command
    self.hostID = action.hostID
    self.slotID = action.slotID
  }
}

struct ButtonAliasPlan: Codable {
  var buttonID: String
  var label: String
  var kind: CommandButtonKind
  var targetPane: String?
  var displayCommand: String?
  var tmuxCommand: TmuxCommand?

  init(actionPlan: CommandCenterActionPlan) {
    self.buttonID = actionPlan.actionID
    self.label = actionPlan.label
    self.kind = actionPlan.kind == .stop ? .stop : .command
    self.targetPane = actionPlan.targetPane
    self.displayCommand = actionPlan.displayCommand
    self.tmuxCommand = actionPlan.tmuxCommand
  }
}

struct ButtonAliasRunResult: Codable {
  var ok: Bool
  var buttonID: String
  var status: CommandCenterRunStatus
  var message: String

  init(result: CommandCenterRunResult, buttonID: String) {
    self.ok = result.ok
    self.buttonID = buttonID
    self.status = result.status
    self.message = result.message
  }
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

func consumeOption(_ name: String, from args: inout [String]) -> String? {
  guard let index = args.firstIndex(of: name),
        args.indices.contains(index + 1) else {
    return nil
  }
  let value = args[index + 1]
  args.remove(at: index + 1)
  args.remove(at: index)
  return value
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

func printLayoutPlan(_ plan: CommandCenterLayoutPlan, dryRun: Bool) {
  print("\(dryRun ? "Would apply" : "Applied") \(plan.layoutID)")
  for host in plan.terminalHosts {
    print("  host \(host.hostID): \(Int(host.frame.x)),\(Int(host.frame.y)) \(Int(host.frame.width))x\(Int(host.frame.height)) \(host.sessionName)")
  }
  for zone in plan.appZones {
    print("  app zone \(zone.zoneID): \(zone.appTargetIDs.joined(separator: ","))")
  }
}

func printActionPlan(_ plan: CommandCenterActionPlan) {
  print("\(plan.actionID)")
  if let targetPane = plan.targetPane {
    print("  target: \(targetPane)")
  }
  if let displayCommand = plan.displayCommand {
    print("  command: \(displayCommand)")
  }
  if let url = plan.url {
    print("  url: \(url)")
  }
  if let repoPath = plan.repoPath {
    print("  repo: \(repoPath)")
  }
  if let tmuxCommand = plan.tmuxCommand {
    print("  tmux: \(tmuxCommand.argv.joined(separator: " "))")
  }
}

func printPaneBindings(_ bindings: [CommandCenterPaneBinding]) {
  for binding in bindings {
    print("\(binding.hostID).\(binding.slotID)\t\(binding.role)\t\(binding.paneTarget)")
  }
}

func printPaneOperationPlan(_ plan: CommandCenterPaneOperationPlan, dryRun: Bool) {
  print("\(dryRun ? "Would \(plan.kind.rawValue)" : plan.kind.rawValue) \(plan.source.display) -> \(plan.destination.display)")
  for command in plan.commands {
    print("  \(command.argv.joined(separator: " "))")
  }
}

func printButtonAliasPlan(_ plan: ButtonAliasPlan) {
  print("\(plan.buttonID)")
  if let targetPane = plan.targetPane {
    print("  target: \(targetPane)")
  }
  if let displayCommand = plan.displayCommand {
    print("  command: \(displayCommand)")
  } else {
    print("  command: C-c")
  }
  if let tmuxCommand = plan.tmuxCommand {
    print("  tmux: \(tmuxCommand.argv.joined(separator: " "))")
  }
}

func buttonKind(for action: CommandCenterAction) -> CommandButtonKind {
  action.kind == .stop ? .stop : .command
}

func printHelp() {
  print(
    """
    Maestro

    Usage:
      maestro config validate [--json]
      maestro layout list [--json]
      maestro layout apply <layout-id> [--dry-run] [--json]
      maestro action list [--json]
      maestro action run <action-id> [--dry-run] [--json]
      maestro pane list [--layout <layout-id>] [--dry-run] [--json]
      maestro pane swap <host.slot> <host.slot> [--layout <layout-id>] [--dry-run] [--json]
      maestro pane move <host.slot> <host.slot> [--layout <layout-id>] [--dry-run] [--json]
      maestro button list [--json]
      maestro button run <button-id> [--dry-run] [--json]

    Configuration:
      maestro/config/palette.json
    """
  )
}
