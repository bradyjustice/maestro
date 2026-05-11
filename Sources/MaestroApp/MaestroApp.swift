import AppKit
import MaestroAutomation
import MaestroCore
import SwiftUI

@main
struct MaestroWorkspaceApp: App {
  @NSApplicationDelegateAdaptor(WorkspaceAppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

@MainActor
final class WorkspaceAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var window: NSWindow?
  private let defaultsKeyX = "MaestroWorkspaceWindowX"
  private let defaultsKeyY = "MaestroWorkspaceWindowY"

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    showWorkspace()
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

  private func showWorkspace() {
    let model = WorkspaceViewModel()
    model.load()

    let size = NSSize(width: 760, height: 460)
    let window = NSWindow(
      contentRect: NSRect(origin: savedOrigin(defaultSize: size), size: size),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "Maestro"
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentView = NSHostingView(rootView: WorkspaceView(model: model))
    window.minSize = NSSize(width: 640, height: 380)
    window.standardWindowButton(.zoomButton)?.isHidden = true
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    self.window = window
  }

  private func savedOrigin(defaultSize: NSSize) -> NSPoint {
    let defaults = UserDefaults.standard
    if defaults.object(forKey: defaultsKeyX) != nil && defaults.object(forKey: defaultsKeyY) != nil {
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
final class WorkspaceViewModel: ObservableObject {
  @Published var config: WorkspaceConfig?
  @Published var plan: WorkspaceArrangePlan?
  @Published var validationResult = PaletteValidationResult(issues: [])
  @Published var loadError: String?
  @Published var isArranging = false
  @Published var lastMessage = "Idle"

  private var configFileURL: URL?
  private let environment: [String: String]
  let diagnostics: MaestroDiagnostics

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    self.environment = environment
    self.diagnostics = MaestroDiagnostics(options: MaestroDebugOptions(environment: environment))
  }

  func load() {
    do {
      let loaded = try WorkspaceConfigLoader(environment: environment).loadUnchecked()
      let validation = WorkspaceConfigValidator().validate(loaded.config)
      config = loaded.config
      configFileURL = loaded.fileURL
      validationResult = validation
      loadError = validation.ok ? nil : validation.issues.map(\.message).joined(separator: " ")
      plan = validation.ok ? try dryRunPlan(config: loaded.config, fileURL: loaded.fileURL) : nil
      lastMessage = validation.ok ? "Workspace loaded" : "Config error"
      diagnostics.emit(
        level: validation.ok ? .info : .warning,
        component: "workspace.view_model",
        name: validation.ok ? "config.load.success" : "config.load.invalid",
        message: validation.ok ? "Loaded workspace config" : "Workspace config is invalid",
        context: [
          "workspace_id": loaded.config.workspace.id,
          "schema_version": String(loaded.config.schemaVersion)
        ]
      )
    } catch {
      config = nil
      configFileURL = nil
      validationResult = PaletteValidationResult(issues: [])
      plan = nil
      loadError = error.localizedDescription
      lastMessage = "Config error"
      diagnostics.emit(
        level: .error,
        component: "workspace.view_model",
        name: "config.load.failure",
        message: "Workspace config load failed",
        context: MaestroDiagnostics.safeErrorContext(error)
      )
    }
  }

  func arrange() {
    guard let config, let configFileURL, validationResult.ok else {
      lastMessage = "Configuration is not ready"
      return
    }

    isArranging = true
    lastMessage = "Arranging workspace"
    let diagnostics = diagnostics
    let environment = environment
    let configDirectory = configFileURL.deletingLastPathComponent()

    Task.detached {
      let runtime = WorkspaceRuntime(
        config: config,
        configDirectory: configDirectory,
        environment: environment,
        tmux: TmuxController(diagnostics: diagnostics),
        windows: NativeMacAutomation(diagnostics: diagnostics),
        diagnostics: diagnostics
      )
      do {
        let appliedPlan = try runtime.arrange()
        await MainActor.run {
          self.plan = appliedPlan
          self.isArranging = false
          self.lastMessage = "Workspace arranged"
        }
      } catch {
        await MainActor.run {
          self.isArranging = false
          self.lastMessage = error.localizedDescription
        }
      }
    }
  }

  private func dryRunPlan(config: WorkspaceConfig, fileURL: URL) throws -> WorkspaceArrangePlan {
    try WorkspaceRuntime(
      config: config,
      configDirectory: fileURL.deletingLastPathComponent(),
      environment: environment,
      diagnostics: diagnostics
    ).dryRunArrangePlan()
  }
}

struct WorkspaceView: View {
  @ObservedObject var model: WorkspaceViewModel

  var body: some View {
    VStack(spacing: 0) {
      if let loadError = model.loadError, model.plan == nil {
        WorkspaceLoadErrorView(detail: loadError) {
          model.load()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        VStack(alignment: .leading, spacing: 16) {
          header
          if let plan = model.plan {
            WorkspacePreview(plan: plan)
          }
          validationFooter
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      Divider()
      statusStrip
    }
    .frame(minWidth: 640, minHeight: 380)
    .background(.regularMaterial)
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(model.config?.workspace.label ?? "Maestro")
          .font(.title2)
          .fontWeight(.semibold)
        if let path = model.plan?.workspace.path {
          Text(path)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      Spacer()
      Button {
        model.load()
      } label: {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.borderless)
      .help("Reload")

      Button {
        model.arrange()
      } label: {
        Label(model.isArranging ? "Arranging" : "Arrange Workspace", systemImage: "rectangle.3.group")
      }
      .buttonStyle(.borderedProminent)
      .disabled(model.isArranging || !model.validationResult.ok)
    }
  }

  @ViewBuilder
  private var validationFooter: some View {
    if !model.validationResult.ok {
      VStack(alignment: .leading, spacing: 5) {
        Label("\(model.validationResult.issues.count) blocking issue\(model.validationResult.issues.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        ForEach(Array(model.validationResult.issues.prefix(4).enumerated()), id: \.offset) { _, issue in
          Text(issue.message)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      .font(.caption)
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
  }

  private var statusStrip: some View {
    HStack(spacing: 12) {
      if let plan = model.plan {
        Label(plan.terminal.sessionName, systemImage: "terminal")
        Label(plan.appArea.apps.map(\.label).joined(separator: ", "), systemImage: "macwindow")
      }
      if model.diagnostics.isEnabled {
        Label("Debug", systemImage: "record.circle")
      }
      Spacer()
      Text(model.lastMessage)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
  }
}

struct WorkspacePreview: View {
  var plan: WorkspaceArrangePlan

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)

        PreviewZone(rect: PercentRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1), size: size) {
          VStack(alignment: .leading, spacing: 6) {
            Label("iTerm", systemImage: "terminal")
              .font(.caption)
              .fontWeight(.semibold)
            Text(plan.terminal.sessionName)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          .padding(9)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color.accentColor.opacity(0.13))
        .overlay(
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
        )

        PreviewZone(rect: PercentRect(x: 1.0 / 3.0, y: 0, width: 2.0 / 3.0, height: 1), size: size) {
          VStack(alignment: .leading, spacing: 8) {
            Label(plan.appArea.label, systemImage: "macwindow")
              .font(.caption)
              .fontWeight(.semibold)
            ForEach(plan.appArea.apps, id: \.id) { app in
              Text(app.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .padding(9)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.78))
        .overlay(
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        )
      }
    }
    .aspectRatio(16 / 9, contentMode: .fit)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

struct PreviewZone<Content: View>: View {
  var rect: PercentRect
  var size: CGSize
  @ViewBuilder var content: Content

  var body: some View {
    content
      .frame(width: max(1, size.width * rect.width), height: max(1, size.height * rect.height), alignment: .topLeading)
      .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
      .position(x: size.width * (rect.x + rect.width / 2), y: size.height * (rect.y + rect.height / 2))
  }
}

struct WorkspaceLoadErrorView: View {
  var detail: String
  var reload: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Maestro could not load", systemImage: "exclamationmark.triangle.fill")
        .font(.headline)
        .foregroundStyle(.orange)
      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button(action: reload) {
        Label("Reload", systemImage: "arrow.clockwise")
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
    .padding(18)
    .frame(maxWidth: 420, alignment: .leading)
  }
}
