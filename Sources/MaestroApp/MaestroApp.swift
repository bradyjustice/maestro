import AppKit
import MaestroAutomation
import MaestroCore
import SwiftUI

@main
struct MaestroCommandCenterApp: App {
  @NSApplicationDelegateAdaptor(CommandCenterAppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

@MainActor
final class CommandCenterAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var window: NSWindow?
  private let defaultsKeyX = "MaestroCommandCenterWindowX"
  private let defaultsKeyY = "MaestroCommandCenterWindowY"

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    showCommandCenter()
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

  private func showCommandCenter() {
    let model = CommandCenterViewModel()
    model.load()

    let size = NSSize(width: 980, height: 620)
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
    window.contentView = NSHostingView(rootView: CommandCenterView(model: model))
    window.minSize = NSSize(width: 820, height: 520)
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
final class CommandCenterViewModel: ObservableObject {
  @Published var config: CommandCenterConfig?
  @Published var loadError: String?
  @Published var selectedProfileID: String?
  @Published var selectedLayoutID: String?
  @Published var selectedMode: CommandCenterMode = .map
  @Published var statusByID: [String: CommandCenterActionStatus] = [:]
  @Published var isRunning: Set<String> = []
  @Published var lastMessage = "Idle"
  @Published var migratedFromSchemaVersion: Int?

  private var configFileURL: URL?
  private let defaultsKeyProfile = "MaestroCommandCenterActiveProfileID"
  private let defaultsKeyLayout = "MaestroCommandCenterActiveLayoutID"
  private let environment: [String: String]
  let diagnostics: MaestroDiagnostics

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    self.environment = environment
    self.diagnostics = MaestroDiagnostics(options: MaestroDebugOptions(environment: environment))
  }

  var visibleConfig: CommandCenterProfileResolution? {
    guard let config else {
      return nil
    }
    return CommandCenterProfileResolver().resolve(config: config, activeProfileID: selectedProfileID)
  }

  var selectedLayout: ScreenLayout? {
    guard let config else {
      return nil
    }
    let visibleLayouts = visibleConfig?.layouts ?? config.screenLayouts
    if let selectedLayoutID,
       let layout = visibleLayouts.first(where: { $0.id == selectedLayoutID }) {
      return layout
    }
    return visibleLayouts.first
  }

  func load() {
    diagnostics.emit(
      level: .info,
      component: "command_center.view_model",
      name: "config.load.start",
      message: "Loading command center config"
    )
    do {
      let loaded = try CommandCenterConfigLoader(environment: environment).load()
      let configChanged = config != loaded.config
      config = loaded.config
      configFileURL = loaded.fileURL
      migratedFromSchemaVersion = loaded.migratedFromSchemaVersion
      loadError = nil
      reconcileSelection(for: loaded.config)
      if configChanged {
        statusByID = [:]
        isRunning = []
      }
      lastMessage = loaded.migratedFromSchemaVersion == nil ? "Config loaded" : "Legacy config migrated"
      diagnostics.emit(
        level: .info,
        component: "command_center.view_model",
        name: "config.load.success",
        message: "Loaded command center config",
        context: [
          "workspace_id": loaded.config.workspace.id,
          "schema_version": String(loaded.config.schemaVersion),
          "layout_count": String(loaded.config.screenLayouts.count),
          "action_count": String(loaded.config.actions.count),
          "migrated_from_schema_version": loaded.migratedFromSchemaVersion.map(String.init) ?? ""
        ]
      )
    } catch {
      config = nil
      configFileURL = nil
      selectedProfileID = nil
      selectedLayoutID = nil
      migratedFromSchemaVersion = nil
      loadError = error.localizedDescription
      lastMessage = "Config error"
      diagnostics.emit(
        level: .error,
        component: "command_center.view_model",
        name: "config.load.failure",
        message: "Command center config load failed",
        context: MaestroDiagnostics.safeErrorContext(error)
      )
    }
  }

  func selectProfile(id: String) {
    guard let config,
          let profile = CommandCenterProfileResolver().selectedProfile(in: config, activeProfileID: id) else {
      selectedProfileID = nil
      UserDefaults.standard.removeObject(forKey: defaultsKeyProfile)
      diagnostics.emit(
        level: .warning,
        component: "command_center.view_model",
        name: "profile.select.failure",
        message: "Profile selection failed",
        context: ["profile_id": id]
      )
      return
    }
    selectedProfileID = profile.id
    UserDefaults.standard.set(profile.id, forKey: defaultsKeyProfile)
    reconcileLayout(for: config)
    diagnostics.emit(
      level: .info,
      component: "command_center.view_model",
      name: "profile.select.success",
      message: "Selected profile",
      context: ["profile_id": profile.id]
    )
  }

  func selectLayout(id: String) {
    selectedLayoutID = id
    UserDefaults.standard.set(id, forKey: defaultsKeyLayout)
    diagnostics.emit(
      level: .info,
      component: "command_center.view_model",
      name: "layout.select.success",
      message: "Selected layout",
      context: ["layout_id": id]
    )
  }

  func applySelectedLayout() {
    guard let layout = selectedLayout else {
      return
    }
    run(id: layout.id, role: .layout) { runtime in
      _ = try runtime.applyLayout(id: layout.id)
      return .succeeded("Applied \(layout.label)")
    }
  }

  func runAction(_ action: CommandCenterAction) {
    let layoutID = selectedLayoutID
    run(id: action.id, role: .action(action.kind)) { runtime in
      let result = try runtime.runAction(id: action.id, layoutID: layoutID, confirmation: NativeCommandCenterConfirmation())
      return result.ok ? .succeeded(result.message) : .canceled(result.message)
    }
  }

  private func run(
    id: String,
    role: CommandCenterActionRole,
    operation: @escaping @Sendable (CommandCenterRuntime) throws -> CommandCenterRunOutcome
  ) {
    guard let config, let configFileURL else {
      statusByID[id] = .failed("Configuration is not loaded.")
      lastMessage = "Configuration is not loaded."
      return
    }

    statusByID[id] = .running(role)
    isRunning.insert(id)
    lastMessage = role.runningMessage
    let runtime = CommandCenterRuntime(
      config: config,
      configDirectory: configFileURL.deletingLastPathComponent(),
      environment: environment,
      tmux: TmuxController(diagnostics: diagnostics),
      windows: NativeMacAutomation(diagnostics: diagnostics),
      diagnostics: diagnostics
    )

    Task.detached {
      do {
        let outcome = try operation(runtime)
        await MainActor.run {
          switch outcome {
          case let .succeeded(message):
            self.statusByID[id] = .succeeded(role, message: message)
            self.lastMessage = message
          case let .canceled(message):
            self.statusByID[id] = .canceled(message)
            self.lastMessage = message
          }
          self.isRunning.remove(id)
        }
      } catch {
        await MainActor.run {
          self.statusByID[id] = .failed(error.localizedDescription)
          self.lastMessage = error.localizedDescription
          self.isRunning.remove(id)
        }
      }
    }
  }

  private func reconcileSelection(for config: CommandCenterConfig) {
    let resolver = CommandCenterProfileResolver()
    if let profile = resolver.selectedProfile(
      in: config,
      activeProfileID: selectedProfileID ?? UserDefaults.standard.string(forKey: defaultsKeyProfile)
    ) {
      selectedProfileID = profile.id
      UserDefaults.standard.set(profile.id, forKey: defaultsKeyProfile)
    } else {
      selectedProfileID = nil
      UserDefaults.standard.removeObject(forKey: defaultsKeyProfile)
    }
    reconcileLayout(for: config)
  }

  private func reconcileLayout(for config: CommandCenterConfig) {
    let visibleLayouts = visibleConfig?.layouts ?? config.screenLayouts
    let saved = selectedLayoutID ?? UserDefaults.standard.string(forKey: defaultsKeyLayout)
    if let saved, visibleLayouts.contains(where: { $0.id == saved }) {
      selectedLayoutID = saved
      UserDefaults.standard.set(saved, forKey: defaultsKeyLayout)
      return
    }
    selectedLayoutID = visibleLayouts.first?.id
    if let selectedLayoutID {
      UserDefaults.standard.set(selectedLayoutID, forKey: defaultsKeyLayout)
    }
  }
}

enum CommandCenterMode: String, CaseIterable, Identifiable {
  case map = "Map"
  case settings = "Settings"

  var id: String { rawValue }
  var systemImage: String {
    switch self {
    case .map:
      return "rectangle.3.group"
    case .settings:
      return "slider.horizontal.3"
    }
  }
}

enum CommandCenterActionRole: Equatable, Sendable {
  case layout
  case action(CommandCenterActionKind)

  var runningMessage: String {
    switch self {
    case .layout:
      return "Arranging layout"
    case let .action(kind):
      switch kind {
      case .shellArgv, .codexPrompt:
        return "Sending command"
      case .stop:
        return "Stopping pane"
      case .openURL, .openRepoInEditor:
        return "Opening"
      case .focusSurface:
        return "Focusing"
      }
    }
  }

  var systemImage: String {
    switch self {
    case .layout:
      return "rectangle.3.group"
    case let .action(kind):
      switch kind {
      case .shellArgv:
        return "play.fill"
      case .stop:
        return "stop.fill"
      case .openURL:
        return "safari"
      case .openRepoInEditor:
        return "curlybraces"
      case .focusSurface:
        return "scope"
      case .codexPrompt:
        return "text.cursor"
      }
    }
  }

  var isDestructive: Bool {
    if case let .action(kind) = self {
      return kind == .stop
    }
    return false
  }
}

enum CommandCenterActionPhase: Equatable, Sendable {
  case idle
  case running
  case succeeded
  case canceled
  case failed
}

struct CommandCenterActionStatus: Equatable, Sendable {
  var phase: CommandCenterActionPhase
  var message: String

  static func running(_ role: CommandCenterActionRole) -> CommandCenterActionStatus {
    CommandCenterActionStatus(phase: .running, message: role.runningMessage)
  }

  static func succeeded(_ role: CommandCenterActionRole, message: String) -> CommandCenterActionStatus {
    CommandCenterActionStatus(phase: .succeeded, message: message.isEmpty ? "Done" : message)
  }

  static func canceled(_ message: String) -> CommandCenterActionStatus {
    CommandCenterActionStatus(phase: .canceled, message: message.isEmpty ? "Canceled" : message)
  }

  static func failed(_ message: String) -> CommandCenterActionStatus {
    CommandCenterActionStatus(phase: .failed, message: message)
  }
}

private enum CommandCenterRunOutcome: Sendable {
  case succeeded(String)
  case canceled(String)
}

struct CommandCenterView: View {
  @ObservedObject var model: CommandCenterViewModel

  var body: some View {
    VStack(spacing: 0) {
      if let loadError = model.loadError {
        CommandCenterLoadErrorView(detail: loadError) {
          model.load()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let config = model.config, let visible = model.visibleConfig {
        HStack(spacing: 0) {
          leftRail(config: config, visible: visible)
          Divider()
          centerSurface(config: config)
          Divider()
          inspector(config: config, visible: visible)
        }
        Divider()
        statusStrip(config: config)
      }
    }
    .frame(minWidth: 820, minHeight: 520)
    .background(.regularMaterial)
  }

  private func leftRail(config: CommandCenterConfig, visible: CommandCenterProfileResolution) -> some View {
    VStack(alignment: .leading, spacing: 12) {
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

      if let profiles = config.profiles, !profiles.isEmpty {
        Picker("Profile", selection: Binding<String>(
          get: { model.selectedProfileID ?? profiles[0].id },
          set: { model.selectProfile(id: $0) }
        )) {
          ForEach(profiles) { profile in
            Text(profile.label).tag(profile.id)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
      }

      Picker("Mode", selection: $model.selectedMode) {
        ForEach(CommandCenterMode.allCases) { mode in
          Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      Text("Layouts")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)

      ScrollView {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(visible.layouts) { layout in
            RailButton(
              title: layout.label,
              subtitle: "\(layout.terminalHosts.count) host\(layout.terminalHosts.count == 1 ? "" : "s")",
              systemImage: "rectangle.split.3x1",
              selected: model.selectedLayoutID == layout.id
            ) {
              model.selectLayout(id: layout.id)
            }
          }
        }
      }

      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(width: 210, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor).opacity(0.42))
  }

  @ViewBuilder
  private func centerSurface(config: CommandCenterConfig) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if model.selectedMode == .map {
        VStack(alignment: .leading, spacing: 14) {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(model.selectedLayout?.label ?? "Layout")
                .font(.title3)
                .fontWeight(.semibold)
              Text(config.workspace.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
              model.applySelectedLayout()
            } label: {
              Label("Apply", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(model.selectedLayout == nil || model.isRunning.contains(model.selectedLayoutID ?? ""))
          }
          if let layout = model.selectedLayout {
            ScreenMapView(layout: layout, config: config)
          }
        }
        .padding(16)
      } else {
        SettingsTabs(config: config)
          .padding(12)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(nsColor: .textBackgroundColor).opacity(0.24))
  }

  private func inspector(config: CommandCenterConfig, visible: CommandCenterProfileResolution) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if let layout = model.selectedLayout {
          InspectorSection(title: "Layout") {
            InspectorRow(label: "ID", value: layout.id)
            InspectorRow(label: "Terminal Hosts", value: "\(layout.terminalHosts.count)")
            InspectorRow(label: "App Zones", value: "\(layout.appZones.count)")
          }

          InspectorSection(title: "Hosts") {
            ForEach(layout.terminalHosts) { host in
              let template = config.paneTemplates.first { $0.id == host.paneTemplateID }
              InspectorRow(label: host.label, value: template?.label ?? host.paneTemplateID)
            }
          }
        }

        ForEach(visible.sections) { section in
          let actions = actions(in: section, config: config)
          if !actions.isEmpty {
            InspectorSection(title: section.label) {
              VStack(spacing: 7) {
                ForEach(actions) { action in
                  ActionRowButton(
                    action: action,
                    status: model.statusByID[action.id],
                    running: model.isRunning.contains(action.id)
                  ) {
                    model.runAction(action)
                  }
                }
              }
            }
          }
        }
      }
      .padding(12)
    }
    .frame(width: 270, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor).opacity(0.38))
  }

  private func statusStrip(config: CommandCenterConfig) -> some View {
    HStack(spacing: 12) {
      Label(model.selectedLayoutID ?? "No layout", systemImage: "rectangle.3.group")
      if let layout = model.selectedLayout {
        let sessions = layout.terminalHosts
          .map { CommandCenterTmuxNaming.sessionName(workspaceID: config.workspace.id, hostID: $0.id) }
          .joined(separator: ", ")
        Label(sessions.isEmpty ? "No terminal sessions" : sessions, systemImage: "terminal")
      }
      if let migrated = model.migratedFromSchemaVersion {
        Label("Migrated v\(migrated)", systemImage: "arrow.triangle.2.circlepath")
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

  private func actions(in section: CommandCenterSection, config: CommandCenterConfig) -> [CommandCenterAction] {
    var byID: [String: CommandCenterAction] = [:]
    for action in config.actions where byID[action.id] == nil {
      byID[action.id] = action
    }
    return section.actionIDs.compactMap { byID[$0] }
  }
}

struct RailButton: View {
  var title: String
  var subtitle: String
  var systemImage: String
  var selected: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .frame(width: 18)
        VStack(alignment: .leading, spacing: 1) {
          Text(title)
            .lineLimit(1)
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(selected ? Color.accentColor.opacity(0.14) : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }
}

struct ScreenMapView: View {
  var layout: ScreenLayout
  var config: CommandCenterConfig

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)

        ForEach(layout.appZones) { zone in
          ZoneRect(rect: zone.frame, in: size) {
            VStack(alignment: .leading, spacing: 5) {
              Label(zone.label, systemImage: "macwindow")
                .font(.caption)
                .fontWeight(.semibold)
              ForEach(zone.appTargetIDs, id: \.self) { appID in
                Text(config.appTargets.first { $0.id == appID }?.label ?? appID)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          }
          .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
          .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
          )
        }

        ForEach(layout.terminalHosts) { host in
          ZoneRect(rect: host.frame, in: size) {
            TerminalHostPreview(host: host, config: config)
          }
          .background(Color.accentColor.opacity(0.13))
          .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
          )
        }
      }
    }
    .aspectRatio(16 / 10, contentMode: .fit)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

struct ZoneRect<Content: View>: View {
  var rect: PercentRect
  var size: CGSize
  @ViewBuilder var content: Content

  init(rect: PercentRect, in size: CGSize, @ViewBuilder content: () -> Content) {
    self.rect = rect
    self.size = size
    self.content = content()
  }

  var body: some View {
    content
      .frame(width: max(1, size.width * rect.width), height: max(1, size.height * rect.height), alignment: .topLeading)
      .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
      .position(x: size.width * (rect.x + rect.width / 2), y: size.height * (rect.y + rect.height / 2))
  }
}

struct TerminalHostPreview: View {
  var host: TerminalHost
  var config: CommandCenterConfig

  var body: some View {
    GeometryReader { proxy in
      let template = config.paneTemplates.first { $0.id == host.paneTemplateID }
      ZStack(alignment: .topLeading) {
        VStack(alignment: .leading, spacing: 3) {
          Label(host.label, systemImage: "terminal")
            .font(.caption)
            .fontWeight(.semibold)
          Text(CommandCenterTmuxNaming.sessionName(workspaceID: config.workspace.id, hostID: host.id))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(8)
        .zIndex(2)

        if let template {
          ForEach(template.slots) { slot in
            ZoneRect(rect: slot.unit, in: proxy.size) {
              VStack(alignment: .leading, spacing: 3) {
                Text(slot.label)
                  .font(.caption)
                  .fontWeight(.medium)
                Text(slot.role)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
              .padding(7)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.32))
            .overlay(
              RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
            )
          }
        }
      }
    }
  }
}

struct ActionRowButton: View {
  var action: CommandCenterAction
  var status: CommandCenterActionStatus?
  var running: Bool
  var run: () -> Void

  var body: some View {
    Button(action: run) {
      HStack(spacing: 8) {
        Image(systemName: role.systemImage)
          .frame(width: 18)
          .foregroundStyle(iconColor)
        VStack(alignment: .leading, spacing: 2) {
          Text(action.label)
            .lineLimit(1)
          Text(status?.message ?? action.kind.rawValue)
            .font(.caption2)
            .foregroundStyle(statusColor)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .frame(maxWidth: .infinity, alignment: .leading)
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
  }

  private var role: CommandCenterActionRole {
    .action(action.kind)
  }

  private var phase: CommandCenterActionPhase {
    running ? .running : status?.phase ?? .idle
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
    case .canceled, .idle:
      return role.isDestructive ? Color.red.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.7)
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
    case .canceled, .idle:
      return role.isDestructive ? Color.red.opacity(0.25) : Color(nsColor: .separatorColor).opacity(0.45)
    }
  }
}

struct InspectorSection<Content: View>: View {
  var title: String
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(title)
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct InspectorRow: View {
  var label: String
  var value: String

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(label)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .font(.caption)
  }
}

struct SettingsTabs: View {
  var config: CommandCenterConfig

  var body: some View {
    TabView {
      SettingsList(title: "Repos", rows: config.repos.map { ($0.label, $0.path) })
        .tabItem { Label("Repos", systemImage: "folder") }
      SettingsList(title: "Apps", rows: config.appTargets.map { ($0.label, $0.bundleID) })
        .tabItem { Label("Apps", systemImage: "app") }
      SettingsList(title: "Pane Templates", rows: config.paneTemplates.map { ($0.label, "\($0.slots.count) slots") })
        .tabItem { Label("Pane Templates", systemImage: "rectangle.split.2x1") }
      SettingsList(title: "Screen Layouts", rows: config.screenLayouts.map { ($0.label, "\($0.terminalHosts.count) hosts, \($0.appZones.count) app zones") })
        .tabItem { Label("Screen Layouts", systemImage: "rectangle.3.group") }
      SettingsList(title: "Actions", rows: config.actions.map { ($0.label, $0.kind.rawValue) })
        .tabItem { Label("Actions", systemImage: "bolt") }
    }
  }
}

struct SettingsList: View {
  var title: String
  var rows: [(String, String)]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.title3)
        .fontWeight(.semibold)
      List(rows, id: \.0) { row in
        HStack {
          Text(row.0)
          Spacer()
          Text(row.1)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    }
  }
}

struct CommandCenterLoadErrorView: View {
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
