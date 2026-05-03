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
  @Published var statusByID: [String: String] = [:]
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
      self.config = config
      self.configFileURL = fileURL
      self.loadError = nil
    } catch {
      self.config = nil
      self.configFileURL = nil
      self.loadError = error.localizedDescription
    }
  }

  func applyLayout(_ layout: TerminalLayout) {
    run(id: layout.id) { runtime in
      _ = try runtime.applyLayout(id: layout.id)
      return "sent"
    }
  }

  func focusTarget(_ target: TerminalTarget) {
    run(id: target.id) { runtime in
      try runtime.focusTarget(id: target.id)
      return "sent"
    }
  }

  func runButton(_ button: CommandButton) {
    run(id: button.id) { runtime in
      let result = try runtime.runButton(id: button.id, confirmation: NativePaletteConfirmation())
      return result.message
    }
  }

  private func run(id: String, operation: @escaping @Sendable (PaletteRuntime) throws -> String) {
    guard let config, let configFileURL else {
      statusByID[id] = "blocked"
      return
    }

    statusByID[id] = "sending"
    isRunning.insert(id)
    let runtime = PaletteRuntime(
      config: config,
      configDirectory: configFileURL.deletingLastPathComponent()
    )

    Task.detached {
      do {
        let message = try operation(runtime)
        await MainActor.run {
          self.statusByID[id] = message
          self.isRunning.remove(id)
        }
      } catch {
        await MainActor.run {
          self.statusByID[id] = "blocked"
          self.isRunning.remove(id)
        }
      }
    }
  }
}

struct PaletteView: View {
  @ObservedObject var model: PaletteViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header

      if let loadError = model.loadError {
        Text(loadError)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else if let config = model.config {
        PaletteSection(title: "Layouts") {
          buttonGrid(config.layouts) { layout in
            PaletteActionButton(
              title: layout.label,
              systemImage: "rectangle.3.group",
              status: model.statusByID[layout.id],
              running: model.isRunning.contains(layout.id)
            ) {
              model.applyLayout(layout)
            }
          }
        }

        PaletteSection(title: "Targets") {
          buttonGrid(config.targets) { target in
            PaletteActionButton(
              title: target.label,
              systemImage: "terminal",
              status: model.statusByID[target.id],
              running: model.isRunning.contains(target.id)
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
              systemImage: "play.fill",
              status: model.statusByID[button.id],
              running: model.isRunning.contains(button.id)
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
              systemImage: "stop.fill",
              destructive: true,
              status: model.statusByID[button.id],
              running: model.isRunning.contains(button.id)
            ) {
              model.runButton(button)
            }
          }
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
      .help("Reload")
    }
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
  }
}

struct PaletteActionButton: View {
  var title: String
  var systemImage: String
  var destructive = false
  var status: String?
  var running: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Image(systemName: running ? "hourglass" : systemImage)
            .frame(width: 16)
          Text(title)
            .font(.callout)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
          Spacer(minLength: 0)
        }
        if let status {
          Text(status)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(destructive ? Color.red.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
    )
    .disabled(running)
  }
}

