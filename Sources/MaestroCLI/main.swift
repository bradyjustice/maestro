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
    case "agent":
      try runAgents(args)
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
      let catalog = try loadCatalog()
      if json {
        writeJSON(catalog.actions)
      } else {
        for action in catalog.actions {
          let enabled = action.enabled ? "enabled" : "blocked"
          print("\(action.id)\t\(action.type.rawValue)\t\(action.risk.rawValue)\t\(enabled)\t\(action.label)")
        }
      }
    case "run":
      guard let actionID = args.first else {
        throw CLIError(message: "Missing action id.", code: "missing_action", exitCode: 2, json: json)
      }
      guard args.count == 1 else {
        throw CLIError(message: "Unexpected action run arguments: \(args.dropFirst().joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
      }

      let catalog = try loadCatalog()
      let executor = ActionExecutionExecutor(
        catalog: catalog,
        environment: environment,
        screenSelection: .active
      )
      let plan = try executor.plan(actionID: actionID)
      if dryRun {
        if json {
          writeJSON(plan)
        } else {
          printActionPlan(plan)
        }
        return
      }

      let result = try executor.run(plan: plan)
      if json {
        writeJSON(result)
        if !result.ok {
          exit(1)
        }
      } else if result.ok {
        print(result.message)
      } else {
        throw CLIError(message: result.message, code: "action_run_failed", exitCode: 1, json: false, prefixed: false)
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
      let readiness = automation.layoutReadiness(for: layout, promptForAccessibility: false)
      guard readiness.ready else {
        let message = readiness.blockedReasons.isEmpty
          ? "Native layout automation is unavailable."
          : readiness.blockedReasons.joined(separator: " ")
        throw CLIError(
          message: message,
          code: readiness.accessibilityTrusted ? "layout_runtime_unavailable" : "accessibility_permission_missing",
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
          print("Applied \(layout.label): created \(result.createdWindowCount) window(s), moved \(result.movedWindowCount) window(s), skipped \(result.skippedSlotCount) slot(s)")
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
    let nativeLayoutReadiness = catalog.layouts.first(where: ItermWindowProvisioning.layoutUsesIterm).map {
      nativeAutomation.layoutReadiness(for: $0, promptForAccessibility: false)
    } ?? LayoutRuntimeReadinessSnapshot(
      ready: automation.accessibilityTrusted,
      accessibilityTrusted: automation.accessibilityTrusted,
      appleEventsAvailable: automation.appleEventsAvailable,
      iTermInstalled: true,
      iTermWindowCreationAvailable: true,
      blockedReasons: automation.accessibilityTrusted ? [] : [automation.accessibilityRecovery.message]
    )
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
      nativeLayoutReadiness: nativeLayoutReadiness,
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
      print("Launch Services: \(diagnostics.iTerm.launchServicesReady ? "ready" : "missing iTerm registration")")
      print("Native Layouts: \(diagnostics.nativeLayoutReadiness.ready ? "ready" : "blocked")")
    }
  }

  private func runAgents(_ arguments: [String]) throws {
    var args = arguments
    let json = consumeFlag("--json", from: &args)

    guard let subcommand = args.first else {
      throw CLIError(message: "Missing agent subcommand.", code: "missing_agent_subcommand", exitCode: 2, json: json)
    }
    args.removeFirst()

    let store = AgentStateStore(
      stateDirectory: MaestroPaths.defaultStateDirectory(environment: environment),
      environment: environment
    )
    let executor = AgentWorkflowExecutor(
      store: store,
      catalog: try? loadCatalog(),
      environment: environment
    )

    do {
      switch subcommand {
      case "start":
        guard args.count >= 2 else {
          throw CLIError(message: "Missing agent start arguments.", code: "missing_agent_start_arguments", exitCode: 2, json: json)
        }
        let repo = args.removeFirst()
        let taskSlug = args.removeFirst()
        let prompt = args.isEmpty ? nil : args.joined(separator: " ")
        let result = try executor.start(repoArgument: repo, taskSlug: taskSlug, prompt: prompt)
        if json {
          writeJSON(result)
        } else {
          printAgentStart(result)
        }
      case "status":
        guard args.isEmpty else {
          throw CLIError(message: "Unexpected agent status arguments: \(args.joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
        }
        let tasks = try store.list(includeArchived: false)
        if json {
          writeJSON(AgentTaskList(stateDirectory: store.stateDirectory.path, tasks: tasks))
        } else {
          printAgentStatus(tasks, stateDirectory: store.stateDirectory.path)
        }
      case "show":
        guard let query = args.first else {
          throw CLIError(message: "Missing agent task id.", code: "missing_agent_task", exitCode: 2, json: json)
        }
        guard args.count == 1 else {
          throw CLIError(message: "Unexpected agent show arguments: \(args.dropFirst().joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
        }
        let task = try store.task(matching: query, includeArchived: true)
        if json {
          writeJSON(task)
        } else {
          printAgentTask(task)
        }
      case "review":
        guard let query = args.first else {
          throw CLIError(message: "Missing agent task id.", code: "missing_agent_task", exitCode: 2, json: json)
        }
        guard args.count == 1 else {
          throw CLIError(message: "Unexpected agent review arguments: \(args.dropFirst().joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
        }
        let result = try executor.review(taskQuery: query)
        if json {
          writeJSON(result)
        } else {
          printAgentReview(result)
        }
        if !result.ok {
          exit(1)
        }
      case "mark":
        guard args.count >= 2 else {
          throw CLIError(message: "Missing agent mark arguments.", code: "missing_agent_mark_arguments", exitCode: 2, json: json)
        }
        let query = args.removeFirst()
        let stateValue = args.removeFirst()
        guard let state = AgentState(rawValue: stateValue) else {
          throw CLIError(message: "Invalid agent state: \(stateValue)", code: "invalid_agent_state", exitCode: 2, json: json)
        }
        let note = args.isEmpty ? nil : args.joined(separator: " ")
        let result = try executor.mark(taskQuery: query, state: state, note: note)
        if json {
          writeJSON(result)
        } else {
          print(result.message)
          if let note = result.snapshot.record.note, !note.isEmpty {
            print("Note: \(note)")
          }
        }
      case "clean":
        let force = consumeFlag("--force", from: &args)
        guard let query = args.first else {
          throw CLIError(message: "Missing agent task id.", code: "missing_agent_task", exitCode: 2, json: json)
        }
        guard args.count == 1 else {
          throw CLIError(message: "Unexpected agent clean arguments: \(args.dropFirst().joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
        }
        let plan = try executor.cleanPlan(taskQuery: query, force: force)
        let confirmation = try readAgentCleanConfirmation(plan: plan, json: json)
        let result = try executor.clean(plan: plan, confirmation: confirmation)
        if json {
          writeJSON(result)
        } else {
          print(result.message)
        }
      case "attach":
        guard let query = args.first else {
          throw CLIError(message: "Missing agent task id.", code: "missing_agent_task", exitCode: 2, json: json)
        }
        guard args.count == 1 else {
          throw CLIError(message: "Unexpected agent attach arguments: \(args.dropFirst().joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
        }
        let result = try executor.attach(taskQuery: query)
        if json {
          writeJSON(result)
        } else {
          print(result.message)
        }
      case "focus":
        guard let query = args.first else {
          throw CLIError(message: "Missing agent task id.", code: "missing_agent_task", exitCode: 2, json: json)
        }
        guard args.count == 1 else {
          throw CLIError(message: "Unexpected agent focus arguments: \(args.dropFirst().joined(separator: " "))", code: "unexpected_arguments", exitCode: 2, json: json)
        }
        let result = try executor.focus(taskQuery: query)
        if json {
          writeJSON(result)
        } else {
          print(result.message)
        }
      default:
        throw CLIError(message: "Unknown agent subcommand: \(subcommand)", code: "unknown_agent_subcommand", exitCode: 2, json: json)
      }
    } catch let error as AgentStateStoreError {
      throw CLIError(message: error.localizedDescription, code: "agent_state_error", exitCode: 1, json: json)
    } catch let error as AgentWorkflowError {
      throw CLIError(message: error.localizedDescription, code: "agent_workflow_error", exitCode: 1, json: json)
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
  var nativeLayoutReadiness: LayoutRuntimeReadinessSnapshot
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
      maestro action run <action-id> [--json] [--dry-run]
      maestro work dev <target...> [--json] [--dry-run]
      maestro layout list [--json]
      maestro layout plan <layout> [--screen active|main] [--json]
      maestro layout apply <layout> [--screen active|main] [--json]
      maestro agent start <repo|repo-path> <task-slug> [prompt] [--json]
      maestro agent status [--json]
      maestro agent show <task-id> [--json]
      maestro agent review <task-id> [--json]
      maestro agent mark <task-id> <queued|running|needs-input|review|merged|abandoned> [note] [--json]
      maestro agent clean [--force] <task-id> [--json]
      maestro agent attach <task-id>
      maestro agent focus <task-id>
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

func printActionPlan(_ plan: ActionExecutionPlan) {
  let state = plan.runnable ? "runnable" : "blocked"
  print("\(plan.actionID)\t\(state)\t\(plan.label)")
  for step in plan.steps {
    let stepState = step.runnable ? "ready" : "blocked"
    print("\(step.index + 1).\t\(step.actionID)\t\(stepState)\t\(step.label)")
    if let reason = step.blockedReason {
      print("  reason: \(reason)")
    }
    if let commandPlan = step.commandRunPlan {
      print("  tmux: \(commandPlan.tmuxPane)")
      print("  command: \(commandPlan.displayCommand)")
    }
    if let agentPlan = step.agentCommandPlan {
      print("  command: \(agentPlan.displayCommand)")
    }
  }
  if plan.steps.isEmpty {
    for reason in plan.blockedReasons {
      print("blocked: \(reason)")
    }
  }
}

func printAgentStatus(_ tasks: [AgentTaskSnapshot], stateDirectory: String) {
  guard !tasks.isEmpty else {
    print("No active agent tasks.")
    print("State: \(stateDirectory)")
    return
  }

  print(agentStatusLine(task: "TASK", state: "STATE", repo: "REPO", branch: "BRANCH", review: "REVIEW", source: "SOURCE", worktree: "WORKTREE"))
  print(agentStatusLine(task: "----", state: "-----", repo: "----", branch: "------", review: "------", source: "------", worktree: "--------"))
  for task in tasks {
    let record = task.record
    print(agentStatusLine(
      task: trunc(record.id, width: 36),
      state: trunc(record.state.rawValue, width: 12),
      repo: trunc(record.repoName, width: 16),
      branch: trunc(record.branch, width: 28),
      review: task.reviewArtifactAvailable ? "yes" : "no",
      source: task.source.rawValue,
      worktree: record.worktreePath
    ))
  }
}

func printAgentStart(_ result: AgentStartResult) {
  let record = result.snapshot.record
  for warning in result.warnings {
    FileHandle.standardError.write(Data("agent: warning: \(warning)\n".utf8))
  }
  print("Task: \(record.id)")
  print("Repo: \(record.repoPath)")
  print("Branch: \(record.branch)")
  print("Worktree: \(record.worktreePath)")
  print("Registry: \(result.snapshot.recordPath)")
  if result.plan.launchSkipped {
    print("Launch: skipped by AGENT_START_NO_LAUNCH")
  } else {
    print("tmux: \(record.tmuxSession ?? "") / \(record.tmuxWindow ?? "")")
  }
}

func printAgentReview(_ result: AgentReviewResult) {
  print("Review artifact: \(result.artifactPath)")
  if let checkExit = result.checkExit {
    print("Check exit: \(checkExit)")
  } else {
    print("Check exit: none")
  }
  print("Codex review exit: \(result.reviewExit)")
  print("State: \(result.snapshot.record.state.rawValue)")
}

func printAgentTask(_ task: AgentTaskSnapshot) {
  let record = task.record
  print("Task: \(record.id)")
  print("Source: \(task.source.rawValue)\(task.archived ? " archived" : "")")
  print("State: \(record.state.rawValue)")
  print("Repo: \(record.repoName)")
  print("Repo path: \(record.repoPath)")
  print("Branch: \(record.branch)")
  print("Base: \(record.baseRef)")
  print("Worktree: \(record.worktreePath)")
  if let tmuxSession = record.tmuxSession, !tmuxSession.isEmpty {
    print("tmux session: \(tmuxSession)")
  }
  if let tmuxWindow = record.tmuxWindow, !tmuxWindow.isEmpty {
    print("tmux window: \(tmuxWindow)")
  }
  print("Created: \(MaestroJSONDateFormatter.string(from: record.createdAt))")
  print("Updated: \(MaestroJSONDateFormatter.string(from: record.updatedAt))")
  if let cleanedAt = record.cleanedAt {
    print("Cleaned: \(MaestroJSONDateFormatter.string(from: cleanedAt))")
  }
  if let note = record.note, !note.isEmpty {
    print("Note: \(note)")
  }
  if let checkExit = record.checkExit {
    print("Check exit: \(checkExit)")
  }
  if let reviewExit = record.reviewExit {
    print("Review exit: \(reviewExit)")
  }
  if let reviewArtifact = record.reviewArtifact, !reviewArtifact.isEmpty {
    print("Review artifact: \(task.reviewArtifactAvailable ? reviewArtifact : "\(reviewArtifact) (missing)")")
  } else {
    print("Review artifact: none")
  }
  print("Record: \(task.recordPath)")
}

func readAgentCleanConfirmation(
  plan: AgentCleanPlan,
  json: Bool
) throws -> AgentCleanConfirmation {
  if plan.requiresExactConfirmation {
    FileHandle.standardError.write(Data("\(plan.prompt)\nType \"\(plan.exactConfirmation)\" to continue: ".utf8))
    guard let answer = readLine() else {
      throw CLIError(message: "Missing cleanup confirmation.", code: "missing_cleanup_confirmation", exitCode: 1, json: json)
    }
    return .exact(answer)
  }

  FileHandle.standardError.write(Data("\(plan.prompt) [y/N] ".utf8))
  guard let answer = readLine() else {
    throw CLIError(message: "Missing cleanup confirmation.", code: "missing_cleanup_confirmation", exitCode: 1, json: json)
  }
  switch answer {
  case "y", "Y", "yes", "YES":
    return .yes
  default:
    throw CLIError(message: "aborted", code: "cleanup_aborted", exitCode: 1, json: json)
  }
}

func trunc(_ value: String, width: Int) -> String {
  guard value.count > width else {
    return value
  }
  return String(value.prefix(max(0, width - 1))) + "~"
}

func padded(_ value: String, width: Int) -> String {
  let clipped = trunc(value, width: width)
  guard clipped.count < width else {
    return clipped
  }
  return clipped + String(repeating: " ", count: width - clipped.count)
}

func agentStatusLine(
  task: String,
  state: String,
  repo: String,
  branch: String,
  review: String,
  source: String,
  worktree: String
) -> String {
  [
    padded(task, width: 36),
    padded(state, width: 12),
    padded(repo, width: 16),
    padded(branch, width: 28),
    padded(review, width: 8),
    padded(source, width: 8),
    worktree
  ].joined(separator: " ")
}

enum MaestroJSONDateFormatter {
  static func string(from date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }
}
