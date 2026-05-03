import Foundation
import MaestroAutomation
import MaestroCore

@main
struct MaestroCoreChecks {
  static func main() throws {
    try checkedInPaletteLoadsAndValidates()
    try rootAndTargetPathsResolve()
    try percentageContainersCoverStarterRegions()
    try stackAndQuadFramesResolveForStarterRegions()
    try taggedWindowPlanningIgnoresUnmanagedWindows()
    try tmuxCreationPlansAreDeterministic()
    try argvRenderingAndSendKeysPlanning()
    try busyPaneBlocksWithoutConfirmationAndSendsWithConfirmation()
    try stopButtonsRequireConfirmation()
    try dryRunJSONEncodesCommandPlan()
    print("Maestro core checks passed.")
  }

  private static func checkedInPaletteLoadsAndValidates() throws {
    let config = try checkedInConfig()
    let validation = PaletteValidator().validate(config)
    try expect(validation.ok, "checked-in palette validates")
    try expectEqual(config.targets.map(\.id), ["website", "account", "admin", "shell"], "starter target order")
    try expect(config.layouts.contains { $0.id == "quad.left-third" }, "starter quad left-third layout exists")
    try expect(config.buttons.contains { $0.id == "website.dev" }, "starter website dev button exists")
    try expect(config.buttons.contains { $0.id == "account.check" }, "starter account check button exists")
  }

  private static func rootAndTargetPathsResolve() throws {
    let config = PaletteConfig(
      schemaVersion: 1,
      roots: [
        ConfigRoot(id: "home", path: "~/Code"),
        ConfigRoot(id: "relative", path: "../..")
      ],
      targets: [
        TerminalTarget(
          id: "sample",
          label: "Sample",
          session: "node-dev",
          window: "sample",
          pane: 0,
          root: "home",
          path: "project"
        ),
        TerminalTarget(
          id: "tool",
          label: "Tool",
          session: "node-dev",
          window: "tool",
          pane: 0,
          root: "relative",
          path: ""
        )
      ],
      regions: [],
      layouts: [],
      buttons: [],
      sections: []
    )
    let resolver = PalettePathResolver(
      configDirectory: URL(fileURLWithPath: "/tmp/repo/maestro/config"),
      environment: ["HOME": "/Users/example"]
    )
    let sample = try resolver.resolve(target: config.targets[0], in: config)
    let tool = try resolver.resolve(target: config.targets[1], in: config)
    try expectEqual(sample.cwd, "/Users/example/Code/project", "tilde root and relative target path")
    try expectEqual(tool.cwd, "/tmp/repo", "relative root path")
  }

  private static func percentageContainersCoverStarterRegions() throws {
    let config = try checkedInConfig()
    let screen = representativeScreen()
    let full = try plan("stack.full", in: config, screen: screen)
    let half = try plan("stack.left-half", in: config, screen: screen)
    let third = try plan("stack.left-third", in: config, screen: screen)

    try expectEqual(full.container, LayoutRect(x: 0, y: 0, width: 1440, height: 900), "full region")
    try expectEqual(half.container, LayoutRect(x: 0, y: 0, width: 720, height: 900), "left-half region")
    try expectEqual(third.container, LayoutRect(x: 0, y: 0, width: 480, height: 900), "left-third region")
  }

  private static func stackAndQuadFramesResolveForStarterRegions() throws {
    let config = try checkedInConfig()
    let screen = representativeScreen()
    let stack = try plan("stack.left-half", in: config, screen: screen)
    try expectEqual(stack.slots[0].frame, LayoutRect(x: 0, y: 0, width: 720, height: 450), "stack top half")
    try expectEqual(stack.slots[1].frame, LayoutRect(x: 0, y: 450, width: 720, height: 450), "stack bottom half")
    try expectEqual(stack.slots.map(\.targetID), ["website", "shell"], "stack target mapping")

    let quad = try plan("quad.left-third", in: config, screen: screen)
    try expectEqual(quad.slots[0].frame, LayoutRect(x: 0, y: 0, width: 240, height: 450), "quad top-left third")
    try expectEqual(quad.slots[1].frame, LayoutRect(x: 240, y: 0, width: 240, height: 450), "quad top-right third")
    try expectEqual(quad.slots[2].frame, LayoutRect(x: 0, y: 450, width: 240, height: 450), "quad bottom-left third")
    try expectEqual(quad.slots[3].frame, LayoutRect(x: 240, y: 450, width: 240, height: 450), "quad bottom-right third")
    try expectEqual(quad.slots.map(\.targetID), ["website", "account", "admin", "shell"], "quad target mapping")
  }

  private static func taggedWindowPlanningIgnoresUnmanagedWindows() throws {
    let config = try checkedInConfig()
    let screen = representativeScreen()
    let layout = try require(config.layouts.first { $0.id == "stack.full" }, "stack.full layout")
    let windows = [
      TerminalWindowSnapshot(id: "managed-website", targetID: "website"),
      TerminalWindowSnapshot(id: "unmanaged", targetID: nil),
      TerminalWindowSnapshot(id: "other-target", targetID: "account")
    ]
    let plan = try PaletteLayoutPlanner().plan(
      layout: layout,
      config: config,
      screen: screen,
      windows: windows
    )
    try expectEqual(plan.slots[0].status, .matched, "website slot matched")
    try expectEqual(plan.slots[1].status, .missingWindow, "shell slot missing")
    try expectEqual(plan.unmanagedWindowCount, 0, "unmanaged and out-of-layout windows ignored")
  }

  private static func tmuxCreationPlansAreDeterministic() throws {
    let target = ResolvedTerminalTarget(
      id: "website",
      label: "Website",
      session: "node-dev",
      window: "website",
      pane: 0,
      cwd: "/repo/node_website"
    )
    let missingSession = TmuxPlanner().ensureTargetPlan(
      target: target,
      sessionExists: false,
      windowExists: false
    )
    try expectEqual(missingSession.commands.map(\.arguments), [
      ["new-session", "-d", "-s", "node-dev", "-n", "website", "-c", "/repo/node_website"],
      ["select-window", "-t", "node-dev:website"]
    ], "missing session tmux plan")

    let missingWindow = TmuxPlanner().ensureTargetPlan(
      target: target,
      sessionExists: true,
      windowExists: false
    )
    try expectEqual(missingWindow.commands.map(\.arguments), [
      ["new-window", "-t", "node-dev:", "-n", "website", "-c", "/repo/node_website"],
      ["select-window", "-t", "node-dev:website"]
    ], "missing window tmux plan")
  }

  private static func argvRenderingAndSendKeysPlanning() throws {
    try expectEqual(
      ShellCommandRenderer.render(["npm", "run", "dev"]),
      "npm run dev",
      "simple argv rendering"
    )
    try expectEqual(
      ShellCommandRenderer.render(["npm", "run", "script with space", "it's-ok"]),
      "npm run 'script with space' 'it'\\''s-ok'",
      "quoted argv rendering"
    )

    let config = try checkedInConfig()
    let runtime = runtimeForChecks(config: config, runner: RecordingRunner())
    let plan = try runtime.buttonPlan(id: "website.dev")
    try expectEqual(plan.displayCommand, "npm run dev", "button display command")
    try expectEqual(
      plan.tmuxCommand.arguments,
      ["send-keys", "-t", "node-dev:website.0", "npm run dev", "C-m"],
      "button send-keys command"
    )
  }

  private static func busyPaneBlocksWithoutConfirmationAndSendsWithConfirmation() throws {
    let config = try checkedInConfig()
    let runner = RecordingRunner()
    runner.result(stdout: "node\n", for: ["tmux", "display-message", "-p", "-t", "node-dev:website.0", "#{pane_current_command}"])
    let blocked = try runtimeForChecks(config: config, runner: runner)
      .runButton(id: "website.dev", confirmation: DenyPaletteConfirmation())
    try expectEqual(blocked.status, .blocked, "busy pane denied status")
    try expect(!runner.calls.contains { $0 == ["tmux", "send-keys", "-t", "node-dev:website.0", "npm run dev", "C-m"] }, "busy denied does not send command")

    let allowedRunner = RecordingRunner()
    allowedRunner.result(stdout: "node\n", for: ["tmux", "display-message", "-p", "-t", "node-dev:website.0", "#{pane_current_command}"])
    let sent = try runtimeForChecks(config: config, runner: allowedRunner)
      .runButton(id: "website.dev", confirmation: AllowPaletteConfirmation())
    try expectEqual(sent.status, .sent, "busy pane confirmation sends")
    try expect(allowedRunner.calls.contains { $0 == ["tmux", "send-keys", "-t", "node-dev:website.0", "npm run dev", "C-m"] }, "busy allowed sends command")
  }

  private static func stopButtonsRequireConfirmation() throws {
    let config = try checkedInConfig()
    let deniedRunner = RecordingRunner()
    let denied = try runtimeForChecks(config: config, runner: deniedRunner)
      .runButton(id: "website.stop", confirmation: DenyPaletteConfirmation())
    try expectEqual(denied.status, .blocked, "stop denied status")
    try expect(deniedRunner.calls.isEmpty, "stop denied does not call tmux")

    let allowedRunner = RecordingRunner()
    let sent = try runtimeForChecks(config: config, runner: allowedRunner)
      .runButton(id: "website.stop", confirmation: AllowPaletteConfirmation())
    try expectEqual(sent.status, .sent, "stop confirmed sends")
    try expectEqual(allowedRunner.calls, [
      ["tmux", "send-keys", "-t", "node-dev:website.0", "C-c"]
    ], "stop sends C-c")
  }

  private static func dryRunJSONEncodesCommandPlan() throws {
    let config = try checkedInConfig()
    let runtime = runtimeForChecks(config: config, runner: RecordingRunner())
    let plan = try runtime.buttonPlan(id: "account.check")
    let output = String(data: try MaestroJSON.encoder.encode(plan), encoding: .utf8) ?? ""
    try expect(output.contains("\"buttonID\" : \"account.check\""), "dry-run JSON includes button id")
    try expect(output.contains("\"displayCommand\" : \"npm run check\""), "dry-run JSON includes rendered command")
    try expect(output.contains("\"targetPane\" : \"node-dev:account.0\""), "dry-run JSON includes target pane")
  }

  private static func checkedInConfig() throws -> PaletteConfig {
    let url = repoRoot().appendingPathComponent("maestro/config/palette.json")
    let data = try Data(contentsOf: url)
    return try MaestroJSON.decoder.decode(PaletteConfig.self, from: data)
  }

  private static func plan(_ id: String, in config: PaletteConfig, screen: LayoutScreen) throws -> PaletteLayoutPlan {
    let layout = try require(config.layouts.first { $0.id == id }, "\(id) layout")
    return try PaletteLayoutPlanner().plan(layout: layout, config: config, screen: screen)
  }

  private static func runtimeForChecks(config: PaletteConfig, runner: RecordingRunner) -> PaletteRuntime {
    PaletteRuntime(
      config: config,
      configDirectory: repoRoot().appendingPathComponent("maestro/config"),
      tmux: TmuxController(runner: runner),
      windows: FakeWindowAutomation()
    )
  }

  private static func representativeScreen() -> LayoutScreen {
    LayoutScreen(
      id: "screen",
      name: "Screen",
      frame: LayoutRect(x: 0, y: 0, width: 1440, height: 900),
      visibleFrame: LayoutRect(x: 0, y: 0, width: 1440, height: 900)
    )
  }

  private static func repoRoot() -> URL {
    var cursor = URL(fileURLWithPath: #filePath)
    while cursor.path != "/" {
      if FileManager.default.fileExists(atPath: cursor.appendingPathComponent("Package.swift").path) {
        return cursor
      }
      cursor.deleteLastPathComponent()
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  }

  private static func expect(_ condition: Bool, _ message: String) throws {
    guard condition else {
      throw CheckFailure(message)
    }
  }

  private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    guard actual == expected else {
      throw CheckFailure("\(message): expected \(expected), got \(actual)")
    }
  }

  private static func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else {
      throw CheckFailure("Missing \(message)")
    }
    return value
  }
}

struct CheckFailure: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}

final class RecordingRunner: CommandRunning, @unchecked Sendable {
  private var scripted: [String: ProcessRunResult] = [:]
  private let separator = "\u{1f}"
  var calls: [[String]] = []

  func result(
    status: Int32 = 0,
    stdout: String = "",
    stderr: String = "",
    for argv: [String]
  ) {
    scripted[key(argv)] = ProcessRunResult(status: status, stdout: stdout, stderr: stderr)
  }

  func run(executable: String, arguments: [String]) throws -> ProcessRunResult {
    let argv = [executable] + arguments
    calls.append(argv)
    return scripted[key(argv)] ?? ProcessRunResult(status: 0, stdout: "", stderr: "")
  }

  private func key(_ argv: [String]) -> String {
    argv.joined(separator: separator)
  }
}

struct FakeWindowAutomation: PaletteWindowAutomation {
  func activeScreen() -> LayoutScreen {
    LayoutScreen(
      id: "screen",
      name: "Screen",
      frame: LayoutRect(x: 0, y: 0, width: 1440, height: 900),
      visibleFrame: LayoutRect(x: 0, y: 0, width: 1440, height: 900)
    )
  }

  func taggedTerminalWindows() throws -> [TerminalWindowSnapshot] {
    []
  }

  func createTerminalWindow(for target: ResolvedTerminalTarget, attachCommand: String) throws {}

  func focusTerminalWindow(targetID: String) throws {}

  func moveTerminalWindows(_ framesByTargetID: [String: LayoutRect]) throws {}
}
