import Foundation
import MaestroAutomation
import MaestroCore

@main
struct MaestroCoreChecks {
  static func main() throws {
    try checkedInWorkspaceLoadsAndValidates()
    try workspaceValidationRejectsBrokenConfig()
    try workspacePathResolutionUsesConfigDirectory()
    try workspaceAdapterBuildsOneHostArrangement()
    try workspaceDryRunPlanIsSimpleAndStable()
    try workspaceArrangeToleratesMissingAppWindows()
    print("Maestro core checks passed.")
  }

  private static func checkedInWorkspaceLoadsAndValidates() throws {
    let loaded = try checkedInLoadedWorkspace()
    let validation = WorkspaceConfigValidator().validate(loaded.config)
    try expect(validation.ok, "checked-in workspace config validates")
    try expectEqual(loaded.config.schemaVersion, 3, "checked-in schema version")
    try expectEqual(loaded.config.workspace.id, "maestro", "workspace id")
    try expectEqual(loaded.config.workspace.path, "../..", "workspace path")
    try expect(loaded.config.browser.useSystemDefaultBrowser, "browser uses system default browser")
    try expectEqual(loaded.config.vsCode.bundleID, "com.microsoft.VSCode", "VS Code bundle id")
  }

  private static func workspaceValidationRejectsBrokenConfig() throws {
    var config = try checkedInWorkspace()
    config.schemaVersion = 2
    config.workspace.path = ""
    config.browser.defaultURL = nil
    config.vsCode.bundleID = ""

    let codes = WorkspaceConfigValidator().validate(config).issues.map(\.code)
    try expect(codes.contains("unsupported_schema"), "schema v3 is required")
    try expect(codes.contains("empty_workspace_path"), "workspace path is required")
    try expect(codes.contains("missing_browser_default_url"), "default browser requires a URL for app resolution")
    try expect(codes.contains("empty_vscode_bundle_id"), "VS Code bundle id is required")
  }

  private static func workspacePathResolutionUsesConfigDirectory() throws {
    let loaded = try checkedInLoadedWorkspace()
    let resolved = WorkspacePathResolver(configDirectory: loaded.fileURL.deletingLastPathComponent())
      .resolveWorkspacePath(loaded.config)
    try expectEqual(resolved, repoRoot().path, "workspace path resolves relative to maestro/config")

    var config = loaded.config
    config.workspace.path = "~/Code/maestro"
    let homeResolved = WorkspacePathResolver(
      configDirectory: loaded.fileURL.deletingLastPathComponent(),
      environment: ["HOME": "/Users/example"]
    ).resolveWorkspacePath(config)
    try expectEqual(homeResolved, "/Users/example/Code/maestro", "workspace path expands home")
  }

  private static func workspaceAdapterBuildsOneHostArrangement() throws {
    let workspace = try checkedInWorkspace()
    let internalConfig = WorkspaceCommandCenterAdapter().commandCenterConfig(from: workspace)
    let validation = CommandCenterValidator().validate(internalConfig)
    try expect(validation.ok, "internal command-center config validates")
    try expectEqual(internalConfig.actions.count, 0, "workspace sliver defines no actions")
    try expectEqual(internalConfig.screenLayouts.count, 1, "workspace sliver defines one layout")

    let layout = try require(internalConfig.screenLayouts.first, "workspace layout")
    try expectEqual(layout.id, WorkspaceConfigConstants.layoutID, "internal layout id")
    try expectEqual(layout.terminalHosts.count, 1, "internal layout has one terminal host")
    try expectEqual(layout.appZones.count, 1, "internal layout has one app zone")

    let plan = try CommandCenterLayoutPlanner().plan(
      layout: layout,
      config: internalConfig,
      screen: representativeScreen()
    )
    let terminal = try require(plan.terminalHosts.first, "terminal host plan")
    let appZone = try require(plan.appZones.first, "app zone plan")
    try expectEqual(terminal.frame, LayoutRect(x: 0, y: 0, width: 480, height: 900), "terminal occupies left third")
    try expectEqual(terminal.slots.count, 1, "terminal has one pane")
    try expectEqual(terminal.slots[0].frame, terminal.frame, "single pane fills terminal")
    try expectEqual(terminal.sessionName, "maestro_maestro_main", "tmux session name")
    try expectEqual(appZone.frame, LayoutRect(x: 480, y: 0, width: 960, height: 900), "apps occupy right two-thirds")
    try expectEqual(appZone.appTargetIDs, ["browser", "vscode"], "browser and VS Code share app area")
  }

  private static func workspaceDryRunPlanIsSimpleAndStable() throws {
    let loaded = try checkedInLoadedWorkspace()
    let plan = try WorkspaceRuntime(
      config: loaded.config,
      configDirectory: loaded.fileURL.deletingLastPathComponent()
    ).dryRunArrangePlan(screen: representativeScreen())

    try expectEqual(plan.workspace.id, "maestro", "dry-run workspace id")
    try expectEqual(plan.workspace.path, repoRoot().path, "dry-run resolved workspace path")
    try expectEqual(plan.terminal.sessionName, "maestro_maestro_main", "dry-run terminal session")
    try expectEqual(plan.terminal.frame, LayoutRect(x: 0, y: 0, width: 480, height: 900), "dry-run terminal frame")
    try expectEqual(plan.appArea.frame, LayoutRect(x: 480, y: 0, width: 960, height: 900), "dry-run app area frame")
    try expectEqual(plan.appArea.apps.map(\.label), ["Browser", "VS Code"], "dry-run apps")

    let encoded = String(data: try MaestroJSON.encoder.encode(plan), encoding: .utf8) ?? ""
    try expect(encoded.contains("\"sessionName\" : \"maestro_maestro_main\""), "arrange JSON includes session name")
    try expect(!encoded.contains("actionID"), "arrange JSON does not expose action plans")
  }

  private static func workspaceArrangeToleratesMissingAppWindows() throws {
    let loaded = try checkedInLoadedWorkspace()
    let runner = RecordingRunner()
    let windows = FakeWorkspaceAutomation(createdWindowID: "created-main")
    windows.appMoveOutcomesByTargetID["browser"] = .noFrontWindow
    windows.appMoveOutcomesByTargetID["vscode"] = .applicationNotFound

    let plan = try WorkspaceRuntime(
      config: loaded.config,
      configDirectory: loaded.fileURL.deletingLastPathComponent(),
      tmux: TmuxController(runner: runner),
      windows: windows,
      stateStore: temporaryStateStore()
    ).arrange()

    try expectEqual(plan.terminal.window?.id, "created-main", "arrange creates tracked terminal window")
    try expectEqual(windows.createdHostIDs, ["main"], "arrange creates one terminal host window")
    try expectEqual(windows.movedAppTargetIDs, ["browser", "vscode"], "arrange attempts existing app targets")
    try expect(runner.calls.contains {
      $0 == ["tmux", "new-session", "-d", "-s", "maestro_maestro_main", "-n", "main", "-c", repoRoot().path]
    }, "arrange creates tmux session at workspace path")
    try expect(!runner.calls.contains { $0.contains("send-keys") }, "arrange sends no dev command")
  }

  private static func checkedInLoadedWorkspace() throws -> LoadedWorkspaceConfig {
    try WorkspaceConfigLoader().load(fileURL: repoRoot().appendingPathComponent("maestro/config/workspace.json"))
  }

  private static func checkedInWorkspace() throws -> WorkspaceConfig {
    try checkedInLoadedWorkspace().config
  }

  private static func representativeScreen() -> LayoutScreen {
    LayoutScreen(
      id: "display",
      name: "Display",
      frame: LayoutRect(x: 0, y: 0, width: 1440, height: 900),
      visibleFrame: LayoutRect(x: 0, y: 0, width: 1440, height: 900)
    )
  }

  private static func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .standardizedFileURL
  }

  private static func temporaryStateStore() -> CommandCenterStateStore {
    let stateURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("maestro-core-checks-\(UUID().uuidString)")
    return CommandCenterStateStore(environment: ["MAESTRO_STATE_DIR": stateURL.path])
  }
}

final class RecordingRunner: CommandRunning, @unchecked Sendable {
  var calls: [[String]] = []

  func run(executable: String, arguments: [String]) throws -> ProcessRunResult {
    let call = [executable] + arguments
    calls.append(call)

    switch arguments.first {
    case "has-session":
      return ProcessRunResult(status: 1, stdout: "", stderr: "")
    case "list-windows", "list-panes":
      return ProcessRunResult(status: 1, stdout: "", stderr: "")
    default:
      return ProcessRunResult(status: 0, stdout: "", stderr: "")
    }
  }
}

final class FakeWorkspaceAutomation: CommandCenterWindowAutomation, @unchecked Sendable {
  var taggedWindows: [TerminalWindowSnapshot]
  var createdWindowID: String
  var createdHostIDs: [String] = []
  var movedFramesByWindowID: [String: LayoutRect] = [:]
  var movedAppTargetIDs: [String] = []
  var appMoveOutcomesByTargetID: [String: CommandCenterWindowMoveOutcome] = [:]

  init(
    taggedWindows: [TerminalWindowSnapshot] = [],
    createdWindowID: String = "created-window"
  ) {
    self.taggedWindows = taggedWindows
    self.createdWindowID = createdWindowID
  }

  func activeScreen() -> LayoutScreen {
    LayoutScreen(
      id: "display",
      name: "Display",
      frame: LayoutRect(x: 0, y: 0, width: 1440, height: 900),
      visibleFrame: LayoutRect(x: 0, y: 0, width: 1440, height: 900)
    )
  }

  func taggedTerminalHostWindows() throws -> [TerminalWindowSnapshot] {
    taggedWindows
  }

  func createTerminalHostWindow(
    for host: ResolvedTerminalHost,
    attachCommand: String
  ) throws -> TerminalWindowSnapshot {
    createdHostIDs.append(host.id)
    let snapshot = TerminalWindowSnapshot(id: createdWindowID, targetID: host.id)
    taggedWindows.append(snapshot)
    return snapshot
  }

  func focusTerminalHostWindow(hostID: String) throws {}

  func focusTerminalHostWindow(windowID: String) throws {}

  func moveTerminalHostWindows(_ framesByHostID: [String: LayoutRect]) throws {}

  func moveTerminalHostWindowsByWindowID(
    _ framesByWindowID: [String: LayoutRect]
  ) throws -> [CommandCenterTerminalWindowMoveReport] {
    movedFramesByWindowID.merge(framesByWindowID) { _, new in new }
    return framesByWindowID.map { windowID, frame in
      CommandCenterTerminalWindowMoveReport(windowID: windowID, frame: frame, outcome: .moved)
    }
  }

  func focusApp(_ appTarget: AppTarget) throws {}

  func openURL(_ url: String, appTarget: AppTarget?) throws {}

  func openRepo(path: String, appTarget: AppTarget) throws {}

  func moveAppWindows(
    _ framesByAppTargetID: [String: LayoutRect],
    appTargets: [AppTarget]
  ) throws -> [CommandCenterAppWindowMoveReport] {
    movedAppTargetIDs = appTargets.map(\.id)
    return appTargets.compactMap { appTarget in
      guard let frame = framesByAppTargetID[appTarget.id] else {
        return nil
      }
      return CommandCenterAppWindowMoveReport(
        appTargetID: appTarget.id,
        bundleID: appTarget.bundleID,
        frame: frame,
        outcome: appMoveOutcomesByTargetID[appTarget.id] ?? .moved
      )
    }
  }
}

struct CheckFailure: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  if !condition() {
    throw CheckFailure(message)
  }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
  if actual != expected {
    throw CheckFailure("\(message): expected \(expected), got \(actual)")
  }
}

func require<T>(_ value: T?, _ message: String) throws -> T {
  guard let value else {
    throw CheckFailure(message)
  }
  return value
}
