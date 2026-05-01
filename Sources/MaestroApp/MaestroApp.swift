import MaestroAutomation
import MaestroCore
import SwiftUI

@main
struct MaestroNativeApp: App {
  var body: some Scene {
    WindowGroup {
      DashboardView()
        .frame(minWidth: 1080, minHeight: 720)
    }
    .windowStyle(.titleBar)
  }
}

@MainActor
final class DashboardModel: ObservableObject {
  @Published var repos: [RepoDefinition] = []
  @Published var actions: [ActionDefinition] = []
  @Published var commands: [CommandDefinition] = []
  @Published var layouts: [LayoutDefinition] = []
  @Published var bundles: [BundleDefinition] = []
  @Published var permissionSnapshot = AutomationPermissionSnapshot(
    accessibilityTrusted: false,
    appleEventsAvailable: false
  )
  @Published var selectedRepoID: String?
  @Published var selectedActionID: String?
  @Published var selectedLayoutID: String?
  @Published var selectedScreenSelection = LayoutScreenSelection.active
  @Published var layoutPlan: LayoutPlan?
  @Published var layoutPlanError: String?
  @Published var layoutApplyMessage: String?
  @Published var loadError: String?

  private let pathResolver = RepoPathResolver()
  private let automation = NativeMacAutomation()

  var selectedRepo: RepoDefinition? {
    repos.first { $0.id == selectedRepoID } ?? repos.first
  }

  var selectedAction: ActionDefinition? {
    actions.first { $0.id == selectedActionID } ?? actions.first
  }

  var selectedLayout: LayoutDefinition? {
    layouts.first { $0.id == selectedLayoutID } ?? layouts.first
  }

  func load() {
    do {
      let catalog = try CatalogLoader().load()
      repos = catalog.repos
      actions = catalog.actions
      commands = catalog.commands
      layouts = catalog.layouts
      bundles = catalog.bundles
      selectedRepoID = repos.first?.id
      selectedActionID = actions.first?.id
      selectedLayoutID = layouts.first?.id
      refreshPermissions(promptForAccessibility: false)
      refreshLayoutPlan()
      loadError = nil
    } catch {
      repos = []
      actions = []
      commands = []
      layouts = []
      bundles = []
      layoutPlan = nil
      loadError = error.localizedDescription
    }
  }

  func selectLayout(_ layout: LayoutDefinition) {
    selectedLayoutID = layout.id
    refreshLayoutPlan()
  }

  func refreshPermissions(promptForAccessibility: Bool = false) {
    permissionSnapshot = automation.permissionSnapshot(promptForAccessibility: promptForAccessibility)
  }

  func refreshLayoutPlan() {
    guard let layout = selectedLayout else {
      layoutPlan = nil
      layoutPlanError = nil
      return
    }

    do {
      layoutPlan = try automation.planLayout(layout, screenSelection: selectedScreenSelection)
      layoutPlanError = nil
    } catch {
      layoutPlan = nil
      layoutPlanError = error.localizedDescription
    }
  }

  func applySelectedLayout() {
    refreshPermissions(promptForAccessibility: false)
    guard permissionSnapshot.accessibilityTrusted else {
      layoutApplyMessage = permissionSnapshot.accessibilityRecovery.message
      return
    }
    guard let layoutPlan else {
      refreshLayoutPlan()
      layoutApplyMessage = layoutPlanError
      return
    }

    do {
      let result = try automation.applyLayout(layoutPlan)
      layoutApplyMessage = "Moved \(result.movedWindowCount) window(s), skipped \(result.skippedSlotCount) slot(s)."
      refreshLayoutPlan()
    } catch {
      layoutApplyMessage = error.localizedDescription
    }
  }

  func resolvedPath(for repo: RepoDefinition) -> String {
    pathResolver.resolve(repo.path)
  }
}

struct DashboardView: View {
  @StateObject private var model = DashboardModel()

  var body: some View {
    NavigationSplitView {
      Sidebar(model: model)
    } content: {
      Overview(model: model)
    } detail: {
      DetailPane(model: model)
    }
    .navigationTitle("Maestro")
    .task {
      model.load()
    }
  }
}

struct Sidebar: View {
  @ObservedObject var model: DashboardModel

  var body: some View {
    List(selection: $model.selectedRepoID) {
      Section("Repos") {
        ForEach(model.repos) { repo in
          Label(repo.label, systemImage: "folder")
            .tag(repo.id)
        }
      }

      Section("Layouts") {
        ForEach(model.layouts) { layout in
          Button {
            model.selectLayout(layout)
          } label: {
            Label(layout.label, systemImage: layout.id == model.selectedLayoutID ? "rectangle.3.group.fill" : "rectangle.3.group")
          }
          .buttonStyle(.plain)
        }
      }

      Section("Bundles") {
        ForEach(model.bundles) { bundle in
          Label(bundle.label, systemImage: "square.stack.3d.up")
        }
      }
    }
    .listStyle(.sidebar)
  }
}

struct Overview: View {
  @ObservedObject var model: DashboardModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if let loadError = model.loadError {
          StatusCard(
            title: "Catalog",
            value: "Unavailable",
            systemImage: "exclamationmark.triangle",
            detail: loadError,
            tone: .warning
          )
        }

        LazyVGrid(
          columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
          ],
          spacing: 12
        ) {
          StatusCard(
            title: "Accessibility",
            value: model.permissionSnapshot.accessibilityRecovery.title,
            systemImage: "accessibility",
            detail: model.permissionSnapshot.accessibilityRecovery.message,
            tone: model.permissionSnapshot.accessibilityTrusted ? .good : .warning
          )
          StatusCard(
            title: "Automation",
            value: model.permissionSnapshot.automationRecovery.title,
            systemImage: "applescript",
            detail: model.permissionSnapshot.automationRecovery.message,
            tone: model.permissionSnapshot.appleEventsAvailable ? .good : .warning
          )
          StatusCard(
            title: "Catalog",
            value: "\(model.repos.count) repos",
            systemImage: "list.bullet.rectangle",
            detail: "\(model.actions.count) actions, \(model.commands.count) commands",
            tone: .neutral
          )
        }

        SectionHeader(title: "Layouts", systemImage: "rectangle.3.group")
        LayoutPlanPanel(model: model)

        SectionHeader(title: "Actions", systemImage: "bolt")
        ActionList(model: model)

        SectionHeader(title: "Agents", systemImage: "person.crop.rectangle.stack")
        AgentEmptyState()
      }
      .padding(20)
    }
  }
}

struct ActionList: View {
  @ObservedObject var model: DashboardModel

  var body: some View {
    VStack(spacing: 0) {
      ForEach(model.actions.prefix(12)) { action in
        Button {
          model.selectedActionID = action.id
        } label: {
          HStack(spacing: 12) {
            Image(systemName: icon(for: action.type))
              .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
              Text(action.label)
                .font(.body)
              Text(action.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            RiskBadge(risk: action.risk, enabled: action.enabled)
          }
          .contentShape(Rectangle())
          .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        Divider()
      }
    }
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func icon(for type: ActionType) -> String {
    switch type {
    case .repoOpen:
      return "folder"
    case .commandRun:
      return "terminal"
    case .agent:
      return "person.crop.rectangle.stack"
    case .layout:
      return "rectangle.3.group"
    case .bundle:
      return "square.stack.3d.up"
    }
  }
}

struct DetailPane: View {
  @ObservedObject var model: DashboardModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        if let repo = model.selectedRepo {
          DetailSection(title: repo.label, systemImage: "folder") {
            DetailRow(label: "Key", value: repo.key)
            DetailRow(label: "Path", value: model.resolvedPath(for: repo))
            DetailRow(label: "tmux", value: repo.tmuxSession)
            DetailRow(label: "Windows", value: repo.defaultWindows.joined(separator: ", "))
            DetailRow(label: "Layout", value: repo.layoutHint ?? "Default")
          }
        }

        if let action = model.selectedAction {
          DetailSection(title: action.label, systemImage: "bolt") {
            DetailRow(label: "ID", value: action.id)
            DetailRow(label: "Type", value: action.type.rawValue)
            DetailRow(label: "Risk", value: action.risk.rawValue)
            DetailRow(label: "Confirmation", value: action.confirmation.rawValue)
            DetailRow(label: "State", value: action.enabled ? "Enabled" : "Blocked")
          }
        }

        if let layout = model.selectedLayout {
          DetailSection(title: layout.label, systemImage: "rectangle.3.group") {
            DetailRow(label: "ID", value: layout.id)
            DetailRow(label: "Description", value: layout.description)
            DetailRow(label: "Slots", value: "\(layout.slots.count)")
            if let plan = model.layoutPlan {
              DetailRow(label: "Screen", value: plan.screen.name)
              DetailRow(label: "Targets", value: "\(plan.moveCount) matched, \(plan.slots.count - plan.moveCount) missing")
            }
          }
        }
      }
      .padding(20)
    }
  }
}

struct LayoutPlanPanel: View {
  @ObservedObject var model: DashboardModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Picker("Screen", selection: $model.selectedScreenSelection) {
          Text("Active").tag(LayoutScreenSelection.active)
          Text("Main").tag(LayoutScreenSelection.main)
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
        .onChange(of: model.selectedScreenSelection) {
          model.refreshLayoutPlan()
        }

        Button {
          model.refreshLayoutPlan()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }

        Spacer()

        if !model.permissionSnapshot.accessibilityTrusted {
          Button {
            model.refreshPermissions(promptForAccessibility: true)
            model.refreshLayoutPlan()
          } label: {
            Label("Request Access", systemImage: "lock.open")
          }
        }

        Button {
          model.applySelectedLayout()
        } label: {
          Label("Apply Layout", systemImage: "rectangle.3.group")
        }
        .disabled(!model.permissionSnapshot.accessibilityTrusted || model.layoutPlan?.moveCount == 0)
      }

      if let error = model.layoutPlanError {
        Text(error)
          .font(.caption)
          .foregroundStyle(.orange)
      }

      if let message = model.layoutApplyMessage {
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let plan = model.layoutPlan {
        VStack(spacing: 0) {
          ForEach(plan.slots, id: \.slotID) { slot in
            LayoutSlotPlanRow(slot: slot)
            Divider()
          }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        if !plan.issues.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(plan.issues, id: \.code) { issue in
              Text(issue.message)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
  }
}

struct LayoutSlotPlanRow: View {
  var slot: LayoutPlanSlot

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: slot.status == .matched ? "checkmark.circle" : "circle.dashed")
        .foregroundStyle(slot.status == .matched ? .green : .secondary)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 3) {
        Text(slot.slotID)
          .font(.body)
        Text(frameText)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text(slot.window?.appName ?? slot.app)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }

  private var frameText: String {
    "\(slot.unit)  \(Int(slot.frame.x)),\(Int(slot.frame.y))  \(Int(slot.frame.width))x\(Int(slot.frame.height))"
  }
}

struct DetailSection<Content: View>: View {
  var title: String
  var systemImage: String
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeader(title: title, systemImage: systemImage)
      VStack(spacing: 8) {
        content
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(nsColor: .controlBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }
}

struct DetailRow: View {
  var label: String
  var value: String

  var body: some View {
    HStack(alignment: .top) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 90, alignment: .leading)
      Text(value)
        .font(.body.monospaced())
        .textSelection(.enabled)
      Spacer(minLength: 0)
    }
  }
}

struct StatusCard: View {
  enum Tone {
    case good
    case warning
    case neutral
  }

  var title: String
  var value: String
  var systemImage: String
  var detail: String
  var tone: Tone

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: systemImage)
          .foregroundStyle(color)
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
      }
      Text(value)
        .font(.headline)
      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var color: Color {
    switch tone {
    case .good:
      return .green
    case .warning:
      return .orange
    case .neutral:
      return .secondary
    }
  }
}

struct RiskBadge: View {
  var risk: RiskTier
  var enabled: Bool

  var body: some View {
    Text(enabled ? risk.rawValue : "blocked")
      .font(.caption.weight(.medium))
      .foregroundStyle(foreground)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(background)
      .clipShape(Capsule())
  }

  private var foreground: Color {
    enabled ? .primary : .secondary
  }

  private var background: Color {
    switch risk {
    case .safe:
      return Color.green.opacity(0.16)
    case .remote:
      return Color.blue.opacity(0.16)
    case .production:
      return Color.orange.opacity(0.18)
    case .destructive:
      return Color.red.opacity(0.18)
    case .unclassified:
      return Color.gray.opacity(0.18)
    }
  }
}

struct SectionHeader: View {
  var title: String
  var systemImage: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
      Text(title)
        .font(.headline)
      Spacer()
    }
  }
}

struct AgentEmptyState: View {
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "tray")
        .foregroundStyle(.secondary)
      Text("No native agent records loaded")
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(14)
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
