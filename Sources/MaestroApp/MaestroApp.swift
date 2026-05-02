import MaestroAutomation
import MaestroCore
import SwiftUI

struct DashboardActionAvailability: Equatable {
  var canRun: Bool
  var reason: String

  static let runnable = DashboardActionAvailability(canRun: true, reason: "")
}

enum DashboardActionStatus: Equatable {
  case running(String)
  case succeeded(String)
  case failed(String)

  var message: String {
    switch self {
    case let .running(message), let .succeeded(message), let .failed(message):
      return message
    }
  }

  var systemImage: String {
    switch self {
    case .running:
      return "hourglass"
    case .succeeded:
      return "checkmark.circle.fill"
    case .failed:
      return "exclamationmark.triangle.fill"
    }
  }

  var foreground: Color {
    switch self {
    case .running:
      return .secondary
    case .succeeded:
      return .green
    case .failed:
      return .orange
    }
  }
}

enum DashboardActionError: Error, LocalizedError {
  case unavailable(String)

  var errorDescription: String? {
    switch self {
    case let .unavailable(message):
      return message
    }
  }
}

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
  @Published var agentTasks: [AgentTaskSnapshot] = []
  @Published var permissionSnapshot = AutomationPermissionSnapshot(
    accessibilityTrusted: false,
    appleEventsAvailable: false
  )
  @Published var iTermReadiness = ItermReadinessSnapshot(
    installed: false,
    running: false
  )
  @Published var selectedRepoID: String?
  @Published var selectedActionID: String?
  @Published var selectedLayoutID: String?
  @Published var selectedAgentTaskID: String?
  @Published var selectedScreenSelection = LayoutScreenSelection.active
  @Published var layoutPlan: LayoutPlan?
  @Published var layoutPlanError: String?
  @Published var layoutApplyMessage: String?
  @Published var actionStatuses: [String: DashboardActionStatus] = [:]
  @Published var actionStepStatuses: [String: [String: DashboardActionStatus]] = [:]
  @Published var runningActionID: String?
  @Published var loadError: String?
  @Published var agentLoadError: String?

  private let pathResolver = RepoPathResolver()
  private let environment = ProcessInfo.processInfo.environment
  private let automation = NativeMacAutomation()
  private var catalog: CatalogBundle?

  var selectedRepo: RepoDefinition? {
    repos.first { $0.id == selectedRepoID } ?? repos.first
  }

  var selectedAction: ActionDefinition? {
    actions.first { $0.id == selectedActionID } ?? actions.first
  }

  var selectedLayout: LayoutDefinition? {
    layouts.first { $0.id == selectedLayoutID } ?? layouts.first
  }

  var selectedAgentTask: AgentTaskSnapshot? {
    agentTasks.first { $0.id == selectedAgentTaskID } ?? agentTasks.first
  }

  func load() {
    do {
      let catalog = try CatalogLoader().load()
      self.catalog = catalog
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
      refreshAgents()
      loadError = nil
    } catch {
      repos = []
      actions = []
      commands = []
      layouts = []
      bundles = []
      agentTasks = []
      self.catalog = nil
      layoutPlan = nil
      loadError = error.localizedDescription
    }
  }

  func selectLayout(_ layout: LayoutDefinition) {
    selectedLayoutID = layout.id
    refreshLayoutPlan()
  }

  func repo(for action: ActionDefinition) -> RepoDefinition? {
    guard let repoKey = action.repoKey else {
      return nil
    }
    return repos.first { $0.key == repoKey }
  }

  func command(for action: ActionDefinition) -> CommandDefinition? {
    guard let commandID = action.commandID else {
      return nil
    }
    return commands.first { $0.id == commandID }
  }

  func layout(for action: ActionDefinition) -> LayoutDefinition? {
    guard let layoutID = action.layoutID else {
      return nil
    }
    return layouts.first { $0.id == layoutID }
  }

  func bundle(for action: ActionDefinition) -> BundleDefinition? {
    guard let bundleID = action.bundleID else {
      return nil
    }
    return bundles.first { $0.id == bundleID }
  }

  func executionPlan(for action: ActionDefinition) -> ActionExecutionPlan? {
    guard let catalog else {
      return nil
    }
    return try? ActionExecutionExecutor(
      catalog: catalog,
      environment: environment,
      pathResolver: pathResolver,
      layoutAutomation: automation,
      screenSelection: selectedScreenSelection
    ).plan(actionID: action.id)
  }

  func layoutAvailability(for layout: LayoutDefinition) -> DashboardActionAvailability {
    let readiness = automation.layoutReadiness(for: layout, promptForAccessibility: false)
    guard readiness.ready else {
      return DashboardActionAvailability(
        canRun: false,
        reason: readiness.blockedReasons.first ?? "Native layout automation is unavailable."
      )
    }

    guard let plan = layout.id == selectedLayoutID ? layoutPlan : try? automation.planLayout(layout, screenSelection: selectedScreenSelection) else {
      return DashboardActionAvailability(canRun: false, reason: layoutPlanError ?? "Unable to plan this layout.")
    }
    guard plan.canExecute else {
      return DashboardActionAvailability(
        canRun: false,
        reason: "No matching windows can be moved and no missing iTerm windows can be created for this layout."
      )
    }
    return .runnable
  }

  func actionAvailability(for action: ActionDefinition) -> DashboardActionAvailability {
    guard let plan = executionPlan(for: action) else {
      return DashboardActionAvailability(canRun: false, reason: "Unable to plan this action.")
    }
    guard plan.runnable else {
      return DashboardActionAvailability(
        canRun: false,
        reason: plan.blockedReasons.first ?? "This action has blocked steps."
      )
    }
    return .runnable
  }

  func expectedBehavior(for action: ActionDefinition) -> String {
    if let plan = executionPlan(for: action) {
      if action.type == .bundle {
        return "Run \(plan.steps.count) expanded action step(s) in order, stopping on the first failure."
      }
      if let commandPlan = plan.steps.first?.commandRunPlan {
        return "Open \(commandPlan.repoKey), select tmux target \(commandPlan.tmuxPane), and send \(commandPlan.displayCommand)."
      }
    }

    switch action.type {
    case .repoOpen:
      guard let repo = repo(for: action) else {
        return "Open or focus the configured repo tmux workspace."
      }
      return "Open or focus tmux session \(repo.tmuxSession), creating \(repo.defaultWindows.joined(separator: ", ")) if needed."
    case .layout:
      guard let layout = layout(for: action) else {
        return "Select and apply the configured layout."
      }
      return "Select \(layout.label), create missing iTerm windows when needed, and apply matched windows."
    case .commandRun:
      return "Run the command if it is safe, local, modeled with argv, and uses a supported tmux behavior."
    case .agent:
      return "Agent execution is visible in bundles but is not supported yet."
    case .bundle:
      return "Run the expanded bundle steps in order."
    }
  }

  func runAction(_ action: ActionDefinition) {
    selectedActionID = action.id

    let availability = actionAvailability(for: action)
    guard availability.canRun else {
      actionStatuses[action.id] = .failed(availability.reason)
      return
    }

    guard let catalog, let plan = executionPlan(for: action) else {
      actionStatuses[action.id] = .failed("Unable to plan this action.")
      return
    }

    let executionEnvironment = environment
    let screenSelection = selectedScreenSelection
    runningActionID = action.id
    actionStatuses[action.id] = .running("Running \(action.label)...")
    actionStepStatuses[action.id] = Dictionary(
      uniqueKeysWithValues: plan.steps.map { ($0.id, DashboardActionStatus.running("Queued.")) }
    )

    Task {
      let execution = await Task.detached(priority: .userInitiated) { () -> (result: ActionExecutionResult?, error: String?) in
        do {
          let executor = ActionExecutionExecutor(
            catalog: catalog,
            environment: executionEnvironment,
            screenSelection: screenSelection
          )
          return (try executor.run(plan: plan), nil)
        } catch {
          return (nil, error.localizedDescription)
        }
      }.value

      if let result = execution.result {
        actionStatuses[action.id] = result.ok ? .succeeded(result.message) : .failed(result.message)
        actionStepStatuses[action.id] = stepStatuses(from: result)
        if result.plan.steps.contains(where: { $0.type == .layout }) {
          refreshPermissions(promptForAccessibility: false)
          refreshLayoutPlan()
        }
      } else if let message = execution.error {
        actionStatuses[action.id] = .failed(message)
      }
      runningActionID = nil
    }
  }

  func refreshPermissions(promptForAccessibility: Bool = false) {
    permissionSnapshot = automation.permissionSnapshot(promptForAccessibility: promptForAccessibility)
    iTermReadiness = automation.iTermReadiness()
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

  func refreshAgents() {
    do {
      let store = AgentStateStore(environment: environment)
      agentTasks = try store.list(includeArchived: false)
      if let selectedAgentTaskID, !agentTasks.contains(where: { $0.id == selectedAgentTaskID }) {
        self.selectedAgentTaskID = agentTasks.first?.id
      } else if selectedAgentTaskID == nil {
        selectedAgentTaskID = agentTasks.first?.id
      }
      agentLoadError = nil
    } catch {
      agentTasks = []
      selectedAgentTaskID = nil
      agentLoadError = error.localizedDescription
    }
  }

  func applySelectedLayout() {
    guard let layout = selectedLayout else {
      layoutApplyMessage = "No layout is selected."
      return
    }

    do {
      layoutApplyMessage = try applyLayout(layout)
    } catch {
      layoutApplyMessage = error.localizedDescription
    }
  }

  private func runRepoOpenAction(_ action: ActionDefinition) {
    guard let repo = repo(for: action) else {
      actionStatuses[action.id] = .failed("The configured repo target is not in the catalog.")
      return
    }

    let resolvedPath = pathResolver.resolve(repo.path)
    let plan = RepoOpenPlan(
      repo: repo,
      resolvedPath: resolvedPath,
      inTmux: environment["TMUX"]?.isEmpty == false
    )
    let executorEnvironment = environment

    runningActionID = action.id
    actionStatuses[action.id] = .running("Opening \(repo.label)...")

    Task {
      let result = await Task.detached(priority: .userInitiated) { () -> (success: Bool, message: String) in
        do {
          try RepoOpenExecutor(environment: executorEnvironment).open(plan)
          return (true, "Opened \(repo.label) in tmux session \(repo.tmuxSession).")
        } catch {
          return (false, error.localizedDescription)
        }
      }.value

      if result.success {
        actionStatuses[action.id] = .succeeded(result.message)
      } else {
        actionStatuses[action.id] = .failed(result.message)
      }
      runningActionID = nil
    }
  }

  private func runLayoutAction(_ action: ActionDefinition) {
    guard let layout = layout(for: action) else {
      actionStatuses[action.id] = .failed("The configured layout target is not in the catalog.")
      return
    }

    selectedLayoutID = layout.id
    runningActionID = action.id
    actionStatuses[action.id] = .running("Applying \(layout.label)...")

    do {
      let message = try applyLayout(layout)
      actionStatuses[action.id] = .succeeded(message)
    } catch {
      let message = error.localizedDescription
      layoutApplyMessage = message
      actionStatuses[action.id] = .failed(message)
    }
    runningActionID = nil
  }

  private func applyLayout(_ layout: LayoutDefinition) throws -> String {
    selectedLayoutID = layout.id
    refreshPermissions(promptForAccessibility: false)
    let readiness = automation.layoutReadiness(for: layout, promptForAccessibility: false)
    guard readiness.ready else {
      throw DashboardActionError.unavailable(
        readiness.blockedReasons.first ?? "Native layout automation is unavailable."
      )
    }

    refreshLayoutPlan()
    guard let layoutPlan else {
      throw DashboardActionError.unavailable(layoutPlanError ?? "Unable to plan layout.")
    }
    guard layoutPlan.canExecute else {
      throw DashboardActionError.unavailable("No matching windows can be moved and no missing iTerm windows can be created for this layout.")
    }

    let result = try automation.applyLayout(layoutPlan)
    let message = "Applied \(layout.label): created \(result.createdWindowCount) window(s), moved \(result.movedWindowCount) window(s), skipped \(result.skippedSlotCount) slot(s)."
    layoutApplyMessage = message
    refreshLayoutPlan()
    return message
  }

  func resolvedPath(for repo: RepoDefinition) -> String {
    pathResolver.resolve(repo.path)
  }

  private func stepStatuses(from result: ActionExecutionResult) -> [String: DashboardActionStatus] {
    Dictionary(uniqueKeysWithValues: result.steps.map { step in
      let status: DashboardActionStatus
      switch step.outcome {
      case .succeeded:
        status = .succeeded(step.message)
      case .failed:
        status = .failed(step.message)
      case .skipped:
        status = .failed(step.message)
      }
      return (step.id, status)
    })
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
            title: "iTerm",
            value: model.iTermReadiness.installed ? "Installed" : "Missing",
            systemImage: "macwindow",
            detail: model.iTermReadiness.notes.first ?? (model.iTermReadiness.launchServicesReady ? "Launch Services can resolve iTerm." : "Found app fallback is required."),
            tone: model.iTermReadiness.installed ? .good : .warning
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
        AgentList(model: model)
      }
      .padding(20)
    }
  }
}

struct ActionList: View {
  @ObservedObject var model: DashboardModel

  var body: some View {
    VStack(spacing: 0) {
      ForEach(model.actions) { action in
        ActionRow(model: model, action: action)
      }
    }
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

struct ActionRow: View {
  @ObservedObject var model: DashboardModel
  var action: ActionDefinition

  private var availability: DashboardActionAvailability {
    model.actionAvailability(for: action)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
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
        }
        .buttonStyle(.plain)

        actionStateIcon

        Button {
          model.runAction(action)
        } label: {
          Label(model.runningActionID == action.id ? "Running" : "Run", systemImage: "play.fill")
        }
        .controlSize(.small)
        .disabled(!availability.canRun || model.runningActionID != nil)
        .help(availability.canRun ? "Run action" : availability.reason)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(action.id == model.selectedActionID ? Color.accentColor.opacity(0.10) : Color.clear)

      if let status = model.actionStatuses[action.id] {
        ActionStatusLine(status: status)
          .padding(.horizontal, 46)
          .padding(.bottom, 10)
      } else if !availability.canRun {
        Text(availability.reason)
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, 46)
          .padding(.bottom, 10)
      }

      Divider()
    }
  }

  @ViewBuilder
  private var actionStateIcon: some View {
    if model.runningActionID == action.id {
      ProgressView()
        .controlSize(.small)
        .frame(width: 20)
    } else if let status = model.actionStatuses[action.id] {
      Image(systemName: status.systemImage)
        .foregroundStyle(status.foreground)
        .frame(width: 20)
    }
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

struct ActionStatusLine: View {
  var status: DashboardActionStatus

  var body: some View {
    Label(status.message, systemImage: status.systemImage)
      .font(.caption)
      .foregroundStyle(status.foreground)
      .fixedSize(horizontal: false, vertical: true)
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
            ActionDetail(model: model, action: action)
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

        if let agentTask = model.selectedAgentTask {
          DetailSection(title: agentTask.record.id, systemImage: "person.crop.rectangle.stack") {
            AgentDetail(task: agentTask)
          }
        }
      }
      .padding(20)
    }
  }
}

struct ActionDetail: View {
  @ObservedObject var model: DashboardModel
  var action: ActionDefinition

  private var availability: DashboardActionAvailability {
    model.actionAvailability(for: action)
  }

  var body: some View {
    DetailRow(label: "ID", value: action.id)
    DetailRow(label: "Type", value: action.type.rawValue)
    DetailRow(label: "Risk", value: action.risk.rawValue)
    DetailRow(label: "Confirm", value: action.confirmation.rawValue)
    DetailRow(label: "State", value: action.enabled ? "Enabled" : "Blocked")

    Divider()

    targetRows
    DetailRow(label: "Expected", value: model.expectedBehavior(for: action))

    if !availability.canRun {
      DetailRow(label: "Disabled", value: availability.reason)
    }

    if let plan = model.executionPlan(for: action) {
      Divider()
      ActionExecutionPlanView(
        plan: plan,
        statuses: model.actionStepStatuses[action.id] ?? [:]
      )
    }

    HStack {
      Button {
        model.runAction(action)
      } label: {
        Label(model.runningActionID == action.id ? "Running" : "Run Action", systemImage: "play.fill")
      }
      .disabled(!availability.canRun || model.runningActionID != nil)

      if model.runningActionID == action.id {
        ProgressView()
          .controlSize(.small)
      }

      Spacer()
    }
    .padding(.top, 4)

    if let status = model.actionStatuses[action.id] {
      ActionStatusLine(status: status)
    }
  }

  @ViewBuilder
  private var targetRows: some View {
    switch action.type {
    case .repoOpen:
      if let repo = model.repo(for: action) {
        DetailRow(label: "Target", value: repo.label)
        DetailRow(label: "Path", value: model.resolvedPath(for: repo))
        DetailRow(label: "tmux", value: repo.tmuxSession)
        DetailRow(label: "Windows", value: repo.defaultWindows.joined(separator: ", "))
      } else {
        DetailRow(label: "Target", value: action.repoKey ?? "Missing repo")
      }
    case .layout:
      if let layout = model.layout(for: action) {
        DetailRow(label: "Target", value: layout.label)
        DetailRow(label: "Layout", value: layout.id)
        DetailRow(label: "Slots", value: "\(layout.slots.count)")
      } else {
        DetailRow(label: "Target", value: action.layoutID ?? "Missing layout")
      }
    case .commandRun:
      if let command = model.command(for: action) {
        DetailRow(label: "Target", value: command.label)
        DetailRow(label: "Command", value: command.id)
        DetailRow(label: "Repo", value: command.repoKey ?? "None")
        DetailRow(label: "Behavior", value: command.behavior.rawValue)
        if let commandPlan = model.executionPlan(for: action)?.steps.first?.commandRunPlan {
          DetailRow(label: "tmux", value: commandPlan.tmuxPane)
          DetailRow(label: "argv", value: commandPlan.displayCommand)
        }
      } else {
        DetailRow(label: "Target", value: action.commandID ?? "Missing command")
      }
    case .agent:
      DetailRow(label: "Target", value: action.commandID ?? action.role?.rawValue ?? "Agent")
    case .bundle:
      if let bundle = model.bundle(for: action) {
        DetailRow(label: "Target", value: bundle.label)
        DetailRow(label: "Bundle", value: bundle.id)
        DetailRow(label: "Actions", value: bundle.actionIDs.joined(separator: ", "))
      } else {
        DetailRow(label: "Target", value: action.bundleID ?? "Missing bundle")
      }
    }
  }
}

struct ActionExecutionPlanView: View {
  var plan: ActionExecutionPlan
  var statuses: [String: DashboardActionStatus]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("Execution Plan", systemImage: "list.number")
          .font(.headline)
        Spacer()
        Text(plan.runnable ? "Runnable" : "Blocked")
          .font(.caption)
          .foregroundStyle(plan.runnable ? .green : .orange)
      }

      VStack(spacing: 0) {
        ForEach(plan.steps) { step in
          ActionExecutionStepRow(step: step, status: statuses[step.id])
          Divider()
        }
      }
      .background(Color(nsColor: .controlBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
  }
}

struct ActionExecutionStepRow: View {
  var step: ActionExecutionStep
  var status: DashboardActionStatus?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("\(step.index + 1)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .frame(width: 22, alignment: .leading)
        Image(systemName: icon(for: step.type))
          .foregroundStyle(.secondary)
          .frame(width: 18)
        VStack(alignment: .leading, spacing: 2) {
          Text(step.label)
            .font(.body)
          Text(step.actionID)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if let status {
          Image(systemName: status.systemImage)
            .foregroundStyle(status.foreground)
        } else {
          Text(step.runnable ? "Ready" : "Blocked")
            .font(.caption)
            .foregroundStyle(step.runnable ? Color.secondary : Color.orange)
        }
      }

      if let commandPlan = step.commandRunPlan {
        DetailRow(label: "tmux", value: commandPlan.tmuxPane)
        DetailRow(label: "Command", value: commandPlan.displayCommand)
      }
      if let reason = step.blockedReason {
        Text(reason)
          .font(.caption)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let status {
        ActionStatusLine(status: status)
      }
    }
    .padding(10)
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

struct LayoutPlanPanel: View {
  @ObservedObject var model: DashboardModel

  private var availability: DashboardActionAvailability {
    guard let layout = model.selectedLayout else {
      return DashboardActionAvailability(canRun: false, reason: "No layout is selected.")
    }
    return model.layoutAvailability(for: layout)
  }

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
        .disabled(!availability.canRun)
        .help(availability.canRun ? "Apply layout" : availability.reason)
      }

      if let error = model.layoutPlanError {
        Text(error)
          .font(.caption)
          .foregroundStyle(.orange)
      }

      if !availability.canRun {
        Text(availability.reason)
          .font(.caption)
          .foregroundStyle(.secondary)
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

struct AgentList: View {
  @ObservedObject var model: DashboardModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        if let error = model.agentLoadError {
          Label(error, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Button {
          model.refreshAgents()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .controlSize(.small)
      }

      if model.agentTasks.isEmpty {
        AgentEmptyState()
      } else {
        VStack(spacing: 0) {
          ForEach(model.agentTasks) { task in
            AgentRow(
              task: task,
              selected: task.id == model.selectedAgentTask?.id
            ) {
              model.selectedAgentTaskID = task.id
            }
            Divider()
          }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
    }
  }
}

struct AgentRow: View {
  var task: AgentTaskSnapshot
  var selected: Bool
  var select: () -> Void

  var body: some View {
    Button(action: select) {
      HStack(spacing: 12) {
        Image(systemName: task.reviewArtifactAvailable ? "doc.text.magnifyingglass" : "terminal")
          .foregroundStyle(.secondary)
          .frame(width: 22)

        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Text(task.record.id)
              .font(.body)
              .lineLimit(1)
            AgentStateBadge(state: task.record.state)
          }

          Text("\(task.record.repoName)  \(task.record.branch)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

          Text(task.record.worktreePath)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Spacer()

        VStack(alignment: .trailing, spacing: 4) {
          Text(task.source.rawValue)
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(task.reviewArtifactAvailable ? "review ready" : "no review")
            .font(.caption)
            .foregroundStyle(task.reviewArtifactAvailable ? .green : .secondary)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(selected ? Color.accentColor.opacity(0.10) : Color.clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

struct AgentStateBadge: View {
  var state: AgentState

  var body: some View {
    Text(state.rawValue)
      .font(.caption.weight(.medium))
      .foregroundStyle(foreground)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(background)
      .clipShape(Capsule())
  }

  private var foreground: Color {
    switch state {
    case .needsInput:
      return .orange
    case .merged:
      return .green
    case .abandoned:
      return .secondary
    case .queued, .running, .review:
      return .primary
    }
  }

  private var background: Color {
    switch state {
    case .queued:
      return Color.gray.opacity(0.16)
    case .running:
      return Color.blue.opacity(0.16)
    case .needsInput:
      return Color.orange.opacity(0.18)
    case .review:
      return Color.green.opacity(0.16)
    case .merged:
      return Color.green.opacity(0.18)
    case .abandoned:
      return Color.gray.opacity(0.18)
    }
  }
}

struct AgentDetail: View {
  var task: AgentTaskSnapshot

  var body: some View {
    let record = task.record

    DetailRow(label: "Task", value: record.id)
    DetailRow(label: "State", value: record.state.rawValue)
    DetailRow(label: "Source", value: task.source.rawValue + (task.archived ? " archived" : " active"))
    DetailRow(label: "Repo", value: record.repoName)
    DetailRow(label: "Repo path", value: record.repoPath)
    DetailRow(label: "Branch", value: record.branch)
    DetailRow(label: "Base", value: record.baseRef)
    DetailRow(label: "Worktree", value: record.worktreePath)
    if let tmuxSession = record.tmuxSession, !tmuxSession.isEmpty {
      DetailRow(label: "tmux", value: tmuxSession)
    }
    if let tmuxWindow = record.tmuxWindow, !tmuxWindow.isEmpty {
      DetailRow(label: "Window", value: tmuxWindow)
    }
    DetailRow(label: "Created", value: DashboardDateFormatter.string(from: record.createdAt))
    DetailRow(label: "Updated", value: DashboardDateFormatter.string(from: record.updatedAt))
    if let cleanedAt = record.cleanedAt {
      DetailRow(label: "Cleaned", value: DashboardDateFormatter.string(from: cleanedAt))
    }
    if let note = record.note, !note.isEmpty {
      DetailRow(label: "Note", value: note)
    }
    if let checkExit = record.checkExit {
      DetailRow(label: "Check", value: "\(checkExit)")
    }
    if let reviewExit = record.reviewExit {
      DetailRow(label: "Review", value: "\(reviewExit)")
    }
    DetailRow(label: "Artifact", value: task.reviewArtifactAvailable ? "Available" : "None")
    DetailRow(label: "Record", value: task.recordPath)
  }
}

enum DashboardDateFormatter {
  static func string(from date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
  }
}

struct AgentEmptyState: View {
  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "tray")
        .foregroundStyle(.secondary)
      Text("No active agent tasks")
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(14)
    .background(Color(nsColor: .controlBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
