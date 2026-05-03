import AppKit
import MaestroAutomation
import MaestroCore
import SwiftUI

@main
struct MaestroPaletteApp: App {
  @NSApplicationDelegateAdaptor(PaletteAppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

@MainActor
final class PaletteAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var window: NSWindow?
  private let defaultsKeyX = "MaestroPaletteWindowX"
  private let defaultsKeyY = "MaestroPaletteWindowY"

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    showPalette()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func windowDidMove(_ notification: Notification) {
    guard let frame = window?.frame else {
      return
    }
    UserDefaults.standard.set(frame.origin.x, forKey: defaultsKeyX)
    UserDefaults.standard.set(frame.origin.y, forKey: defaultsKeyY)
  }

  private func showPalette() {
    let model = PaletteViewModel()
    model.load()

    let content = PaletteView(model: model)
    let size = NSSize(width: 340, height: 560)
    let origin = savedOrigin(defaultSize: size)
    let window = NSWindow(
      contentRect: NSRect(origin: origin, size: size),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "Maestro"
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentView = NSHostingView(rootView: content)
    window.minSize = NSSize(width: 300, height: 420)
    window.standardWindowButton(.zoomButton)?.isHidden = true
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    self.window = window
  }

  private func savedOrigin(defaultSize: NSSize) -> NSPoint {
    let defaults = UserDefaults.standard
    let hasSaved = defaults.object(forKey: defaultsKeyX) != nil && defaults.object(forKey: defaultsKeyY) != nil
    if hasSaved {
      return NSPoint(x: defaults.double(forKey: defaultsKeyX), y: defaults.double(forKey: defaultsKeyY))
    }

    guard let screen = NSScreen.main else {
      return NSPoint(x: 80, y: 80)
    }
    return NSPoint(
      x: screen.visibleFrame.maxX - defaultSize.width - 24,
      y: screen.visibleFrame.maxY - defaultSize.height - 24
    )
  }
}

@MainActor
final class PaletteViewModel: ObservableObject {
  @Published var config: PaletteConfig?
  @Published var loadError: String?
  @Published var statusByID: [String: PaletteActionStatus] = [:]
  @Published var isRunning: Set<String> = []

  private var configFileURL: URL?

  func load() {
    do {
      let fileURL = MaestroPaths.defaultConfigFile()
      let data = try Data(contentsOf: fileURL)
      let config = try MaestroJSON.decoder.decode(PaletteConfig.self, from: data)
      let validation = PaletteValidator().validate(config)
      guard validation.ok else {
        throw PaletteConfigError.invalidConfig(validation.issues)
      }
      let configChanged = self.config != config
      self.config = config
      self.configFileURL = fileURL
      self.loadError = nil
      if configChanged {
        self.statusByID = [:]
        self.isRunning = []
      }
    } catch {
      self.config = nil
      self.configFileURL = nil
      self.loadError = error.localizedDescription
    }
  }

  func applyLayout(_ layout: TerminalLayout) {
    run(id: layout.id, role: .layout) { runtime in
      _ = try runtime.applyLayout(id: layout.id)
      return .succeeded
    }
  }

  func focusTarget(_ target: TerminalTarget) {
    run(id: target.id, role: .target) { runtime in
      try runtime.focusTarget(id: target.id)
      return .succeeded
    }
  }

  func runButton(_ button: CommandButton) {
    let role = PaletteActionRole(buttonKind: button.kind)
    run(id: button.id, role: role) { runtime in
      let result = try runtime.runButton(id: button.id, confirmation: PaletteAppConfirmation())
      return result.ok ? .succeeded : .canceled
    }
  }

  private func run(
    id: String,
    role: PaletteActionRole,
    operation: @escaping @Sendable (PaletteRuntime) throws -> PaletteRunOutcome
  ) {
    guard let config, let configFileURL else {
      statusByID[id] = .failed(detail: "Palette configuration is not loaded.")
      return
    }

    statusByID[id] = .running(role: role)
    isRunning.insert(id)
    let runtime = PaletteRuntime(
      config: config,
      configDirectory: configFileURL.deletingLastPathComponent()
    )

    Task.detached {
      do {
        let outcome = try operation(runtime)
        await MainActor.run {
          switch outcome {
          case .succeeded:
            self.statusByID[id] = .succeeded(role: role)
          case .canceled:
            self.statusByID[id] = .canceled()
          }
          self.isRunning.remove(id)
        }
      } catch {
        await MainActor.run {
          self.statusByID[id] = .failed(detail: error.localizedDescription)
          self.isRunning.remove(id)
        }
      }
    }
  }
}

enum PaletteActionRole: Equatable, Sendable {
  case layout
  case target
  case command
  case stop

  init(buttonKind: CommandButtonKind) {
    switch buttonKind {
    case .command:
      self = .command
    case .stop:
      self = .stop
    }
  }

  var runningMessage: String {
    switch self {
    case .layout:
      return "Arranging"
    case .target:
      return "Opening"
    case .command:
      return "Sending"
    case .stop:
      return "Stopping"
    }
  }

  var successMessage: String {
    switch self {
    case .layout:
      return "Arranged"
    case .target:
      return "Ready"
    case .command:
      return "Sent"
    case .stop:
      return "Stopped"
    }
  }

  var idleSystemImage: String {
    switch self {
    case .layout:
      return "rectangle.3.group"
    case .target:
      return "terminal"
    case .command:
      return "play.fill"
    case .stop:
      return "stop.fill"
    }
  }

  var isDestructive: Bool {
    self == .stop
  }
}

enum PaletteActionPhase: Equatable, Sendable {
  case idle
  case running
  case succeeded
  case canceled
  case failed
}

struct PaletteActionStatus: Equatable, Sendable {
  var phase: PaletteActionPhase
  var message: String
  var detail: String?

  static func running(role: PaletteActionRole) -> PaletteActionStatus {
    PaletteActionStatus(phase: .running, message: role.runningMessage, detail: nil)
  }

  static func succeeded(role: PaletteActionRole) -> PaletteActionStatus {
    PaletteActionStatus(phase: .succeeded, message: role.successMessage, detail: nil)
  }

  static func canceled() -> PaletteActionStatus {
    PaletteActionStatus(phase: .canceled, message: "Canceled", detail: nil)
  }

  static func failed(detail: String?) -> PaletteActionStatus {
    PaletteActionStatus(phase: .failed, message: "Needs attention", detail: detail)
  }
}

private enum PaletteRunOutcome: Sendable {
  case succeeded
  case canceled
}

final class PaletteAppConfirmation: PaletteConfirmationProviding {
  init() {}

  func confirmBusy(target: ResolvedTerminalTarget, command: String, currentCommand: String) -> Bool {
    let displayCommand = command.isEmpty ? "this command" : command
    return ask(
      title: "Pane Busy",
      message: "\(target.label) is running \(currentCommand).\n\nSend \(displayCommand) anyway?",
      primary: "Send"
    )
  }

  func confirmStop(target: ResolvedTerminalTarget) -> Bool {
    ask(
      title: "Stop \(target.label)?",
      message: "Send Control-C to \(target.session):\(target.window).\(target.pane)?",
      primary: "Stop"
    )
  }

  private func ask(title: String, message: String, primary: String) -> Bool {
    let run = {
      MainActor.assumeIsolated {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: primary)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
      }
    }

    if Thread.isMainThread {
      return run()
    }
    return DispatchQueue.main.sync(execute: run)
  }
}

struct PaletteView: View {
  @ObservedObject var model: PaletteViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header

      if let loadError = model.loadError {
        PaletteLoadErrorView(detail: loadError) {
          model.load()
        }
      } else if let config = model.config {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            PaletteSection(title: "Layouts") {
              buttonGrid(config.layouts) { layout in
                PaletteActionButton(
                  title: layout.label,
                  role: .layout,
                  status: model.statusByID[layout.id],
                  running: model.isRunning.contains(layout.id),
                  help: "Arrange \(layout.label)"
                ) {
                  model.applyLayout(layout)
                }
              }
            }

            PaletteSection(title: "Targets") {
              buttonGrid(config.targets) { target in
                PaletteActionButton(
                  title: target.label,
                  role: .target,
                  status: model.statusByID[target.id],
                  running: model.isRunning.contains(target.id),
                  help: "Open or focus \(target.label)"
                ) {
                  model.focusTarget(target)
                }
              }
            }

            let commandButtons = config.buttons.filter { $0.kind == .command }
            PaletteSection(title: "Commands") {
              buttonGrid(commandButtons) { button in
                PaletteActionButton(
                  title: button.label,
                  role: .command,
                  status: model.statusByID[button.id],
                  running: model.isRunning.contains(button.id),
                  help: commandHelp(for: button)
                ) {
                  model.runButton(button)
                }
              }
            }

            let stopButtons = config.buttons.filter { $0.kind == .stop }
            PaletteSection(title: "Stop") {
              buttonGrid(stopButtons) { button in
                PaletteActionButton(
                  title: button.label,
                  role: .stop,
                  status: model.statusByID[button.id],
                  running: model.isRunning.contains(button.id),
                  help: "Send Control-C to \(button.label)"
                ) {
                  model.runButton(button)
                }
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }
      }
    }
    .padding(14)
    .frame(minWidth: 300, idealWidth: 340, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    HStack {
      Text("Maestro")
        .font(.headline)
      Spacer()
      Button {
        model.load()
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.borderless)
      .help("Reload palette config")
    }
  }

  private func commandHelp(for button: CommandButton) -> String {
    guard let argv = button.argv, !argv.isEmpty else {
      return "Run \(button.label)"
    }
    return "Run \(ShellCommandRenderer.render(argv))"
  }

  private func buttonGrid<Data: RandomAccessCollection, Content: View>(
    _ data: Data,
    @ViewBuilder content: @escaping (Data.Element) -> Content
  ) -> some View where Data.Element: Identifiable {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
      ForEach(data) { item in
        content(item)
      }
    }
  }
}

struct PaletteSection<Content: View>: View {
  var title: String
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct PaletteLoadErrorView: View {
  var detail: String
  var reload: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .frame(width: 18)

      VStack(alignment: .leading, spacing: 8) {
        Text("Palette config could not load")
          .font(.callout)
          .fontWeight(.semibold)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        Button(action: reload) {
          Label("Reload", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Reload palette config")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(10)
    .background(Color.orange.opacity(0.08))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .stroke(Color.orange.opacity(0.18), lineWidth: 1)
    )
  }
}

struct PaletteActionButton: View {
  var title: String
  var role: PaletteActionRole
  var status: PaletteActionStatus?
  var running: Bool
  var help: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Image(systemName: systemImage)
            .frame(width: 16)
            .foregroundStyle(iconColor)
          Text(title)
            .font(.callout)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .truncationMode(.tail)
            .layoutPriority(1)
          Spacer(minLength: 0)
        }
        if let status {
          Text(status.message)
            .font(.caption2)
            .foregroundStyle(statusColor)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .truncationMode(.tail)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(backgroundColor)
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .stroke(borderColor, lineWidth: 1)
    )
    .disabled(running)
    .help(effectiveHelp)
  }

  private var phase: PaletteActionPhase {
    if running {
      return .running
    }
    return status?.phase ?? .idle
  }

  private var systemImage: String {
    switch phase {
    case .running:
      return "hourglass"
    case .failed:
      return "exclamationmark.triangle.fill"
    case .idle, .succeeded, .canceled:
      return role.idleSystemImage
    }
  }

  private var iconColor: Color {
    switch phase {
    case .failed:
      return .orange
    case .running:
      return role.isDestructive ? .red : .accentColor
    case .succeeded:
      return .green
    case .canceled:
      return .secondary
    case .idle:
      return role.isDestructive ? .red : .accentColor
    }
  }

  private var statusColor: Color {
    switch phase {
    case .failed:
      return .orange
    case .succeeded:
      return .green
    case .running:
      return role.isDestructive ? .red : .accentColor
    case .canceled, .idle:
      return .secondary
    }
  }

  private var backgroundColor: Color {
    switch phase {
    case .failed:
      return Color.orange.opacity(0.10)
    case .succeeded:
      return Color.green.opacity(0.07)
    case .running:
      return (role.isDestructive ? Color.red : Color.accentColor).opacity(0.10)
    case .canceled:
      return Color(nsColor: .controlBackgroundColor)
    case .idle:
      return role.isDestructive ? Color.red.opacity(0.10) : Color(nsColor: .controlBackgroundColor)
    }
  }

  private var borderColor: Color {
    switch phase {
    case .failed:
      return Color.orange.opacity(0.35)
    case .succeeded:
      return Color.green.opacity(0.28)
    case .running:
      return (role.isDestructive ? Color.red : Color.accentColor).opacity(0.32)
    case .canceled:
      return Color(nsColor: .separatorColor).opacity(0.45)
    case .idle:
      return role.isDestructive ? Color.red.opacity(0.28) : Color(nsColor: .separatorColor).opacity(0.45)
    }
  }

  private var effectiveHelp: String {
    if phase == .failed, let detail = status?.detail, !detail.isEmpty {
      return detail
    }
    return help
  }
}
