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
    case "work":
      try runWork(args)
    case "layout":
      try runLayouts(args)
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

  private func runWork(_ arguments: [String]) throws {
    var args = arguments
    let json = consumeFlag("--json", from: &args)
    let dryRun = consumeFlag("--dry-run", from: &args)

    guard let subcommand = args.first else {
      throw CLIError(message: "Missing work subcommand.", code: "missing_work_subcommand", exitCode: 2, json: json)
    }
    args.removeFirst()

    switch subcommand {
    case "dev":
      do {
        let targets = try WorkDevPlan.targets(from: args)
        let plan = try WorkDevPlan(
          targets: targets,
          pathResolver: RepoPathResolver(environment: environment),
          inTmux: environment["TMUX"]?.isEmpty == false
        )

        if json || dryRun {
          writeJSON(plan)
          return
        }

        try WorkDevExecutor(environment: environment).open(plan)
      } catch let error as WorkDevPlanError {
        let message = json ? error.localizedDescription : "\(error.localizedDescription)\n\n\(workUsage())"
        throw CLIError(
          message: message,
          code: error.code,
          exitCode: 1,
          json: json,
          prefixed: false
        )
      } catch let error as WorkDevExecutionError {
        throw CLIError(
          message: error.localizedDescription,
          code: error.code,
          exitCode: 1,
          json: json,
          prefixed: false
        )
      }
    default:
      throw CLIError(message: "Unknown work subcommand: \(subcommand)", code: "unknown_work_subcommand", exitCode: 2, json: json)
    }
  }

  private func runLayouts(_ arguments: [String]) throws {
    var args = arguments
    let json = consumeFlag("--json", from: &args)

    guard let subcommand = args.first else {
      throw CLIError(message: "Missing layout subcommand.", code: "missing_layout_subcommand", exitCode: 2, json: json)
    }
    args.removeFirst()

    switch subcommand {
    case "list":
      guard args.isEmpty else {
        throw CLIError(message: "Unexpected layout list arguments: \(args.joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
      }
      let layouts = try loadCatalog().layouts
      if json {
        writeJSON(layouts)
      } else {
        for layout in layouts {
          print("\(layout.id)\t\(layout.label)\t\(layout.slots.count) slots")
        }
      }
    case "plan":
      let screenSelection = try consumeScreenSelection(from: &args, json: json)
      guard let layoutID = args.first else {
        throw CLIError(message: "Missing layout id.", code: "missing_layout", exitCode: 2, json: json)
      }
      guard args.count == 1 else {
        throw CLIError(message: "Unexpected layout plan arguments: \(args.dropFirst().joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
      }
      let layout = try findLayout(layoutID, json: json)
      let automation = NativeMacAutomation()
      let permissions = automation.permissionSnapshot(promptForAccessibility: false)
      do {
        let output = try LayoutPlanOutput(
          plan: automation.planLayout(layout, screenSelection: screenSelection),
          permissions: permissions,
          iTerm: automation.iTermReadiness()
        )
        if json {
          writeJSON(output)
        } else {
          printLayoutPlan(output.plan)
        }
      } catch let error as NativeMacAutomationError {
        throw CLIError(message: error.localizedDescription, code: error.code, exitCode: 1, json: json)
      } catch let error as LayoutPlanError {
        throw CLIError(message: error.localizedDescription, code: error.code, exitCode: 1, json: json)
      }
    case "apply":
      let screenSelection = try consumeScreenSelection(from: &args, json: json)
      guard let layoutID = args.first else {
        throw CLIError(message: "Missing layout id.", code: "missing_layout", exitCode: 2, json: json)
      }
      guard args.count == 1 else {
        throw CLIError(message: "Unexpected layout apply arguments: \(args.dropFirst().joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
      }

      let layout = try findLayout(layoutID, json: json)
      let automation = NativeMacAutomation()
      let permissions = automation.permissionSnapshot(promptForAccessibility: false)
      guard permissions.accessibilityTrusted else {
        throw CLIError(
          message: permissions.accessibilityRecovery.message,
          code: "accessibility_permission_missing",
          exitCode: 1,
          json: json
        )
      }

      do {
        let plan = try automation.planLayout(layout, screenSelection: screenSelection)
        let result = try automation.applyLayout(plan)
        let output = LayoutApplyOutput(plan: plan, permissions: permissions, result: result)
        if json {
          writeJSON(output)
        } else {
          print("Applied \(layout.label): moved \(result.movedWindowCount) window(s), skipped \(result.skippedSlotCount) slot(s)")
        }
      } catch let error as NativeMacAutomationError {
        throw CLIError(message: error.localizedDescription, code: error.code, exitCode: 1, json: json)
      } catch let error as LayoutPlanError {
        throw CLIError(message: error.localizedDescription, code: error.code, exitCode: 1, json: json)
      }
    default:
      throw CLIError(message: "Unknown layout subcommand: \(subcommand)", code: "unknown_layout_subcommand", exitCode: 2, json: json)
    }
  }

  private func runDiagnostics(_ arguments: [String]) throws {
    var args = arguments
    let json = consumeFlag("--json", from: &args)
    guard args.isEmpty else {
      throw CLIError(message: "Unexpected diagnostics arguments: \(args.joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
    }

    let catalog = try loadCatalog()
    let nativeAutomation = NativeMacAutomation()
    let automation = nativeAutomation.permissionSnapshot(promptForAccessibility: false)
    let screens = nativeAutomation.screens()
    let diagnostics = DiagnosticsReport(
      configDirectory: MaestroPaths.defaultConfigDirectory(environment: environment).path,
      stateDirectory: MaestroPaths.defaultStateDirectory(environment: environment).path,
      repoCount: catalog.repos.count,
      commandCount: catalog.commands.count,
      actionCount: catalog.actions.count,
      layoutCount: catalog.layouts.count,
      validation: catalog.validation,
      accessibilityTrusted: automation.accessibilityTrusted,
      appleEventsAvailable: automation.appleEventsAvailable,
      accessibilityState: automation.accessibilityState,
      automationState: automation.automationState,
      accessibilityRecovery: automation.accessibilityRecovery,
      automationRecovery: automation.automationRecovery,
      automationNotes: automation.notes,
      screenCount: screens.count,
      screens: screens,
      iTerm: nativeAutomation.iTermReadiness()
    )

    if json {
      writeJSON(diagnostics)
    } else {
      print("Config: \(diagnostics.configDirectory)")
      print("State: \(diagnostics.stateDirectory)")
      print("Repos: \(diagnostics.repoCount)")
      print("Commands: \(diagnostics.commandCount)")
      print("Actions: \(diagnostics.actionCount)")
      print("Layouts: \(diagnostics.layoutCount)")
      print("Accessibility: \(diagnostics.accessibilityTrusted ? "trusted" : "not trusted")")
      print("Apple Events: \(diagnostics.appleEventsAvailable ? "available" : "unavailable")")
      print("Screens: \(diagnostics.screenCount)")
      print("iTerm: \(diagnostics.iTerm.installed ? "installed" : "missing")")
    }
  }

  private func loadCatalog() throws -> CatalogBundle {
    try CatalogLoader(
      configDirectory: MaestroPaths.defaultConfigDirectory(environment: environment),
      pathResolver: RepoPathResolver(environment: environment)
    ).load()
  }

  private func findLayout(_ layoutID: String, json: Bool) throws -> LayoutDefinition {
    let catalog = try loadCatalog()
    guard let layout = catalog.layouts.first(where: { $0.id == layoutID }) else {
      throw CLIError(message: "Unknown layout: \(layoutID)", code: "unknown_layout", exitCode: 1, json: json)
    }
    return layout
  }
}

struct DiagnosticsReport: Codable, Equatable {
  var configDirectory: String
  var stateDirectory: String
  var repoCount: Int
  var commandCount: Int
  var actionCount: Int
  var layoutCount: Int
  var validation: CatalogValidationReport
  var accessibilityTrusted: Bool
  var appleEventsAvailable: Bool
  var accessibilityState: PermissionRecoveryState
  var automationState: PermissionRecoveryState
  var accessibilityRecovery: PermissionRecovery
  var automationRecovery: PermissionRecovery
  var automationNotes: [String]
  var screenCount: Int
  var screens: [LayoutScreen]
  var iTerm: ItermReadinessSnapshot
}

struct LayoutPlanOutput: Codable, Equatable {
  var plan: LayoutPlan
  var permissions: AutomationPermissionSnapshot
  var iTerm: ItermReadinessSnapshot
}

struct LayoutApplyOutput: Codable, Equatable {
  var plan: LayoutPlan
  var permissions: AutomationPermissionSnapshot
  var result: LayoutApplicationResult
}

struct CLIError: Error {
  var message: String
  var code: String
  var exitCode: Int32
  var json: Bool
  var prefixed: Bool = true

  func write() {
    if json {
      writeJSON(JSONError(error: message, code: code))
    } else if prefixed {
      writeHumanError(message)
    } else {
      FileHandle.standardError.write(Data("\(message)\n".utf8))
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

func consumeScreenSelection(
  from args: inout [String],
  json: Bool
) throws -> LayoutScreenSelection {
  guard let index = args.firstIndex(of: "--screen") else {
    return .active
  }
  let valueIndex = args.index(after: index)
  guard valueIndex < args.endIndex else {
    throw CLIError(message: "Missing value for --screen.", code: "missing_screen_selection", exitCode: 2, json: json)
  }
  let value = args[valueIndex]
  guard let selection = LayoutScreenSelection(rawValue: value) else {
    throw CLIError(message: "Unknown screen selection: \(value)", code: "unknown_screen_selection", exitCode: 2, json: json)
  }
  args.remove(at: valueIndex)
  args.remove(at: index)
  return selection
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

func printLayoutPlan(_ plan: LayoutPlan) {
  print("\(plan.label) on \(plan.screen.name)")
  for slot in plan.slots {
    let frame = slot.frame
    let target = slot.window.map { "\($0.appName): \($0.title)" } ?? "no matching window"
    print("\(slot.slotID)\t\(slot.unit)\t\(Int(frame.x)),\(Int(frame.y)) \(Int(frame.width))x\(Int(frame.height))\t\(target)")
  }
  if !plan.issues.isEmpty {
    for issue in plan.issues {
      print("note: \(issue.message)")
    }
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
      maestro work dev <target...> [--json] [--dry-run]
      maestro layout list [--json]
      maestro layout plan <layout> [--screen active|main] [--json]
      maestro layout apply <layout> [--screen active|main] [--json]
      maestro diagnostics [--json]
    """
  )
}

func workUsage() -> String {
  """
  Usage:
    work <repo>
    work dev <target...>

  Repos:
    node      node
    account   node_account
    admin     node_admin
    plan      node_plan
    board     node_board
    website   node_website
    email     node_email
    tools     maestro
    resume    resume
    ux        node_ux

  Dev targets:
    all       website + account + admin
    website   node_website
    account   node_account
    admin     node_admin
    shell     shell pane in node root
  """
}
