import Foundation
import MaestroCore

public struct WorkspaceRuntime: Sendable {
  public var config: WorkspaceConfig
  public var configDirectory: URL
  public var environment: [String: String]
  public var tmux: TmuxController
  public var windows: any CommandCenterWindowAutomation
  public var stateStore: CommandCenterStateStore
  public var diagnostics: MaestroDiagnostics

  public init(
    config: WorkspaceConfig,
    configDirectory: URL,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    tmux: TmuxController = TmuxController(),
    windows: any CommandCenterWindowAutomation = NativeMacAutomation(),
    stateStore: CommandCenterStateStore? = nil,
    diagnostics: MaestroDiagnostics? = nil
  ) {
    let resolvedDiagnostics: MaestroDiagnostics
    if let diagnostics {
      resolvedDiagnostics = diagnostics
    } else if tmux.diagnostics.isEnabled {
      resolvedDiagnostics = tmux.diagnostics
    } else {
      resolvedDiagnostics = MaestroDiagnostics(options: MaestroDebugOptions(environment: environment))
    }
    var resolvedTmux = tmux
    if diagnostics != nil || !resolvedTmux.diagnostics.isEnabled {
      resolvedTmux.diagnostics = resolvedDiagnostics
    }
    self.config = config
    self.configDirectory = configDirectory
    self.environment = environment
    self.tmux = resolvedTmux
    self.windows = windows
    self.stateStore = stateStore ?? CommandCenterStateStore(environment: environment)
    self.diagnostics = resolvedDiagnostics
  }

  public func dryRunArrangePlan(screen: LayoutScreen? = nil) throws -> WorkspaceArrangePlan {
    let internalConfig = WorkspaceCommandCenterAdapter().commandCenterConfig(from: config)
    let runtime = commandCenterRuntime(config: internalConfig)
    let layoutPlan = try runtime.dryRunLayoutPlan(
      id: WorkspaceConfigConstants.layoutID,
      screen: screen ?? fallbackScreen()
    )
    return try WorkspaceArrangePlanBuilder().build(
      workspaceConfig: config,
      configDirectory: configDirectory,
      environment: environment,
      layoutPlan: layoutPlan,
      internalConfig: internalConfig
    )
  }

  public func arrange() throws -> WorkspaceArrangePlan {
    diagnostics.emit(
      level: .info,
      component: "workspace.runtime",
      name: "arrange.start",
      message: "Arranging workspace",
      context: ["workspace_id": config.workspace.id]
    )
    do {
      let internalConfig = WorkspaceCommandCenterAdapter().commandCenterConfig(from: config)
      let runtime = commandCenterRuntime(config: internalConfig)
      let layoutPlan = try runtime.applyLayout(
        id: WorkspaceConfigConstants.layoutID,
        tolerateMissingAppWindows: true
      )
      let plan = try WorkspaceArrangePlanBuilder().build(
        workspaceConfig: config,
        configDirectory: configDirectory,
        environment: environment,
        layoutPlan: layoutPlan,
        internalConfig: internalConfig
      )
      diagnostics.emit(
        level: .info,
        component: "workspace.runtime",
        name: "arrange.success",
        message: "Arranged workspace",
        context: [
          "workspace_id": config.workspace.id,
          "session_name": plan.terminal.sessionName
        ]
      )
      return plan
    } catch {
      var context = MaestroDiagnostics.safeErrorContext(error)
      context["workspace_id"] = config.workspace.id
      diagnostics.emit(
        level: .error,
        component: "workspace.runtime",
        name: "arrange.failure",
        message: "Workspace arrange failed",
        context: context
      )
      throw error
    }
  }

  private func commandCenterRuntime(config internalConfig: CommandCenterConfig) -> CommandCenterRuntime {
    CommandCenterRuntime(
      config: internalConfig,
      configDirectory: configDirectory,
      environment: environment,
      tmux: tmux,
      windows: windows,
      stateStore: stateStore,
      diagnostics: diagnostics
    )
  }

  private func fallbackScreen() -> LayoutScreen {
    LayoutScreen(
      id: "dry-run",
      name: "Dry Run",
      frame: LayoutRect(x: 0, y: 0, width: 1440, height: 900),
      visibleFrame: LayoutRect(x: 0, y: 0, width: 1440, height: 900)
    )
  }
}
