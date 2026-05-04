import Foundation
import MaestroCore

public protocol CommandCenterWindowAutomation: Sendable {
  func activeScreen() -> LayoutScreen
  func taggedTerminalHostWindows() throws -> [TerminalWindowSnapshot]
  func createTerminalHostWindow(for host: ResolvedTerminalHost, attachCommand: String) throws -> TerminalWindowSnapshot
  func focusTerminalHostWindow(hostID: String) throws
  func focusTerminalHostWindow(windowID: String) throws
  func moveTerminalHostWindows(_ framesByHostID: [String: LayoutRect]) throws
  func moveTerminalHostWindowsByWindowID(_ framesByWindowID: [String: LayoutRect]) throws -> [CommandCenterTerminalWindowMoveReport]
  func focusApp(_ appTarget: AppTarget) throws
  func openURL(_ url: String, appTarget: AppTarget?) throws
  func openRepo(path: String, appTarget: AppTarget) throws
  func moveAppWindows(_ framesByAppTargetID: [String: LayoutRect], appTargets: [AppTarget]) throws -> [CommandCenterAppWindowMoveReport]
}

public enum CommandCenterWindowMoveOutcome: String, Codable, Equatable, Sendable {
  case moved
  case applicationNotFound = "application_not_found"
  case noFrontWindow = "no_front_window"
  case windowNotFound = "window_not_found"
  case moveRejected = "move_rejected"
  case boundsNotApplied = "bounds_not_applied"
  case missingReport = "missing_report"

  public var isSuccess: Bool {
    self == .moved
  }
}

public struct CommandCenterTerminalWindowMoveReport: Codable, Equatable, Sendable {
  public var windowID: String
  public var frame: LayoutRect
  public var outcome: CommandCenterWindowMoveOutcome
  public var message: String?

  public init(
    windowID: String,
    frame: LayoutRect,
    outcome: CommandCenterWindowMoveOutcome,
    message: String? = nil
  ) {
    self.windowID = windowID
    self.frame = frame
    self.outcome = outcome
    self.message = message
  }
}

public struct CommandCenterAppWindowMoveReport: Codable, Equatable, Sendable {
  public var appTargetID: String
  public var bundleID: String?
  public var frame: LayoutRect
  public var outcome: CommandCenterWindowMoveOutcome
  public var message: String?

  public init(
    appTargetID: String,
    bundleID: String? = nil,
    frame: LayoutRect,
    outcome: CommandCenterWindowMoveOutcome,
    message: String? = nil
  ) {
    self.appTargetID = appTargetID
    self.bundleID = bundleID
    self.frame = frame
    self.outcome = outcome
    self.message = message
  }
}

public enum CommandCenterLayoutApplyError: Error, LocalizedError, Equatable {
  case terminalWindowNotTracked(layoutID: String, terminalProfileID: String, windowID: String?)
  case terminalWindowMoveFailed(layoutID: String, reports: [CommandCenterTerminalWindowMoveReport])
  case appWindowMoveFailed(layoutID: String, reports: [CommandCenterAppWindowMoveReport])

  public var errorDescription: String? {
    switch self {
    case let .terminalWindowNotTracked(layoutID, terminalProfileID, windowID):
      let suffix = windowID.map { " Created iTerm window \($0) was not tagged for that profile." } ?? ""
      return "Failed to apply \(layoutID): terminal profile \(terminalProfileID) did not resolve to a tracked iTerm window.\(suffix)"
    case let .terminalWindowMoveFailed(layoutID, reports):
      let details = reports.map { report in
        "\(report.windowID): \(report.outcome.rawValue)\(report.message.map { " (\($0))" } ?? "")"
      }.joined(separator: ", ")
      return "Failed to apply \(layoutID): terminal window movement failed\(details.isEmpty ? "." : " for \(details).")"
    case let .appWindowMoveFailed(layoutID, reports):
      let details = reports.map { report in
        "\(report.appTargetID): \(report.outcome.rawValue)\(report.message.map { " (\($0))" } ?? "")"
      }.joined(separator: ", ")
      return "Failed to apply \(layoutID): app window movement failed\(details.isEmpty ? "." : " for \(details).")"
    }
  }
}

public protocol CommandCenterConfirmationProviding: Sendable {
  func confirmBusy(action: CommandCenterActionPlan, currentCommand: String) -> Bool
  func confirmStop(action: CommandCenterActionPlan) -> Bool
}

public struct DenyCommandCenterConfirmation: CommandCenterConfirmationProviding {
  public init() {}

  public func confirmBusy(action: CommandCenterActionPlan, currentCommand: String) -> Bool {
    false
  }

  public func confirmStop(action: CommandCenterActionPlan) -> Bool {
    false
  }
}

public struct AllowCommandCenterConfirmation: CommandCenterConfirmationProviding {
  public init() {}

  public func confirmBusy(action: CommandCenterActionPlan, currentCommand: String) -> Bool {
    true
  }

  public func confirmStop(action: CommandCenterActionPlan) -> Bool {
    true
  }
}

public enum CommandCenterRunStatus: String, Codable, Equatable, Sendable {
  case sent
  case opened
  case focused
  case applied
  case blocked
}

public struct CommandCenterRunResult: Codable, Equatable, Sendable {
  public var ok: Bool
  public var id: String
  public var status: CommandCenterRunStatus
  public var message: String

  public init(ok: Bool, id: String, status: CommandCenterRunStatus, message: String) {
    self.ok = ok
    self.id = id
    self.status = status
    self.message = message
  }
}

public struct CommandCenterRuntime: Sendable {
  public var config: CommandCenterConfig
  public var configDirectory: URL
  public var environment: [String: String]
  public var tmux: TmuxController
  public var windows: any CommandCenterWindowAutomation
  public var stateStore: CommandCenterStateStore
  public var diagnostics: MaestroDiagnostics

  public init(
    config: CommandCenterConfig,
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

  public func screenLayout(id: String?) throws -> ScreenLayout {
    let layoutID = id ?? stateStore.load().activeLayoutID ?? config.screenLayouts.first?.id
    guard let layoutID,
          let layout = config.screenLayouts.first(where: { $0.id == layoutID }) else {
      throw CommandCenterConfigError.missingScreenLayout(id ?? "")
    }
    return layout
  }

  public func repo(id: String) throws -> CommandRepo {
    guard let repo = config.repos.first(where: { $0.id == id }) else {
      throw CommandCenterConfigError.missingRepo(id)
    }
    return repo
  }

  public func appTarget(id: String) throws -> AppTarget {
    guard let appTarget = config.appTargets.first(where: { $0.id == id }) else {
      throw CommandCenterConfigError.missingAppTarget(id)
    }
    return appTarget
  }

  public func resolveRepo(id: String) throws -> ResolvedCommandRepo {
    let repo = try repo(id: id)
    return ResolvedCommandRepo(
      id: repo.id,
      label: repo.label,
      cwd: CommandCenterPathResolver(configDirectory: configDirectory, environment: environment)
        .resolve(repo: repo)
    )
  }

  public func resolveHost(hostID: String, layoutID: String? = nil) throws -> ResolvedTerminalHost {
    let layout = try screenLayout(id: layoutID)
    guard let host = layout.terminalHosts.first(where: { $0.effectiveTerminalProfileID == hostID })
      ?? layout.terminalHosts.first(where: { $0.id == hostID }) else {
      throw CommandCenterConfigError.missingTerminalHost(hostID)
    }
    return try resolveHost(host)
  }

  private func resolveHost(_ host: TerminalHost) throws -> ResolvedTerminalHost {
    let profile = try CommandCenterTerminalProfileResolver().profile(for: host, in: config)
    guard let template = config.paneTemplates.first(where: { $0.id == profile.paneTemplateID }) else {
      throw CommandCenterConfigError.missingPaneTemplate(profile.paneTemplateID)
    }
    var slotRepos: [String: ResolvedCommandRepo] = [:]
    for slot in template.slots {
      let repoID = slot.repoID ?? profile.repoID
      slotRepos[slot.id] = try resolveRepo(id: repoID)
    }
    return ResolvedTerminalHost(
      id: profile.id,
      layoutHostID: host.id,
      label: profile.label,
      repo: try resolveRepo(id: profile.repoID),
      sessionName: CommandCenterTmuxNaming.sessionName(workspaceID: config.workspace.id, hostID: profile.id),
      windowName: CommandCenterTmuxNaming.windowName,
      paneTemplate: template,
      slotRepos: slotRepos,
      itermProfileName: profile.itermProfileName,
      startupCommands: profile.startupCommands
    )
  }

  public func dryRunLayoutPlan(id: String? = nil, screen: LayoutScreen? = nil) throws -> CommandCenterLayoutPlan {
    let layout = try screenLayout(id: id)
    return try CommandCenterLayoutPlanner().plan(
      layout: layout,
      config: config,
      screen: screen ?? fallbackScreen()
    )
  }

  public func layoutPlan(id: String? = nil) throws -> CommandCenterLayoutPlan {
    let layout = try screenLayout(id: id)
    return try CommandCenterLayoutPlanner().plan(
      layout: layout,
      config: config,
      screen: windows.activeScreen(),
      windows: try windows.taggedTerminalHostWindows(),
      state: stateStore.load()
    )
  }

  public func applyLayout(id: String? = nil) throws -> CommandCenterLayoutPlan {
    diagnostics.emit(
      level: .info,
      component: "command_center.runtime",
      name: "layout.apply.start",
      message: "Applying layout",
      context: ["requested_layout_id": id ?? ""]
    )
    do {
      let layout = try screenLayout(id: id)
      let resolvedHosts = try layout.terminalHosts.map { try resolveHost($0) }
      var sessionsByHostID: [String: String] = [:]
      for host in resolvedHosts {
        let plan = try tmux.ensureHost(host)
        sessionsByHostID[host.id] = plan.host.sessionName
        try runStartupCommandsIfIdle(for: host)
      }

      let screen = windows.activeScreen()
      let state = stateStore.load()
      var tagged = try windows.taggedTerminalHostWindows()
      var plan = try CommandCenterLayoutPlanner().plan(
        layout: layout,
        config: config,
        screen: screen,
        windows: tagged,
        state: state
      )

      let missingIDs = Set(plan.missingTerminalProfileIDs)
      var createdProfileIDs = Set<String>()
      var createdTerminalWindows: [TerminalWindowSnapshot] = []
      for host in resolvedHosts where missingIDs.contains(host.id) {
        let window = try windows.createTerminalHostWindow(for: host, attachCommand: attachCommand(for: host))
        createdTerminalWindows.append(window)
        createdProfileIDs.insert(host.id)
      }

      if !missingIDs.isEmpty {
        tagged = mergeTerminalWindows(tagged, createdTerminalWindows)
        tagged = mergeTerminalWindows(
          try waitForTaggedHostWindows(hostIDs: missingIDs, existing: tagged),
          createdTerminalWindows
        )
        plan = try CommandCenterLayoutPlanner().plan(
          layout: layout,
          config: config,
          screen: screen,
          windows: tagged,
          state: state,
          createdTerminalProfileIDs: createdProfileIDs
        )
      }

      try requireResolvedTerminalHosts(plan: plan, layoutID: layout.id, createdWindows: createdTerminalWindows)

      var framesByWindowID: [String: LayoutRect] = [:]
      for host in plan.terminalHosts {
        if let windowID = host.window?.id {
          framesByWindowID[windowID] = host.frame
        }
      }
      let terminalMoveReports = try windows.moveTerminalHostWindowsByWindowID(framesByWindowID)
      try validateTerminalMoveReports(
        expectedFramesByWindowID: framesByWindowID,
        reports: terminalMoveReports,
        layoutID: layout.id
      )

      let appFrames = appFramesByTargetID(plan: plan)
      let appTargets = appTargetsForLayoutPlan(plan)
      let appMoveReports = try windows.moveAppWindows(appFrames, appTargets: appTargets)
      try validateAppMoveReports(
        expectedFramesByAppTargetID: appFrames,
        reports: appMoveReports,
        layoutID: layout.id
      )

      try stateStore.save(CommandCenterState(
        activeLayoutID: layout.id,
        hostSessions: sessionsByHostID,
        terminalWindows: terminalWindowRecords(
          plan: plan,
          taggedWindows: tagged,
          layoutID: layout.id,
          screenID: screen.id
        )
      ))
      diagnostics.emit(
        level: .info,
        component: "command_center.runtime",
        name: "layout.apply.success",
        message: "Applied layout",
        context: [
          "layout_id": layout.id,
          "host_count": String(plan.terminalHosts.count),
          "app_zone_count": String(plan.appZones.count),
          "terminal_moved_count": String(terminalMoveReports.filter { $0.outcome.isSuccess }.count),
          "terminal_missing_count": String(plan.missingTerminalProfileIDs.count),
          "app_moved_count": String(appMoveReports.filter { $0.outcome.isSuccess }.count),
          "app_missing_count": String(appFrames.count - appMoveReports.filter { $0.outcome.isSuccess }.count)
        ]
      )
      return plan
    } catch {
      var context = nativeAutomationDiagnosticContext(error)
      context["requested_layout_id"] = id ?? ""
      diagnostics.emit(
        level: .error,
        component: "command_center.runtime",
        name: "layout.apply.failure",
        message: "Layout apply failed",
        context: context
      )
      throw error
    }
  }

  public func actionPlan(id: String, layoutID: String? = nil) throws -> CommandCenterActionPlan {
    guard let action = config.actions.first(where: { $0.id == id }) else {
      throw CommandCenterConfigError.missingAction(id)
    }

    switch action.kind {
    case .shellArgv:
      guard let argv = action.argv, !argv.isEmpty else {
        throw CommandCenterConfigError.missingActionArgv(action.id)
      }
      let display = ShellCommandRenderer.render(argv)
      let paneTarget = try paneTarget(for: action, layoutID: layoutID)
      return CommandCenterActionPlan(
        actionID: action.id,
        label: action.label,
        kind: action.kind,
        displayCommand: display,
        targetPane: paneTarget,
        tmuxCommand: TmuxCommand(arguments: ["send-keys", "-t", paneTarget, display, "C-m"])
      )
    case .stop:
      let paneTarget = try paneTarget(for: action, layoutID: layoutID)
      return CommandCenterActionPlan(
        actionID: action.id,
        label: action.label,
        kind: action.kind,
        targetPane: paneTarget,
        tmuxCommand: TmuxCommand(arguments: ["send-keys", "-t", paneTarget, "C-c"])
      )
    case .openURL:
      guard let url = action.url, !url.isEmpty else {
        throw CommandCenterConfigError.missingActionURL(action.id)
      }
      let app = try action.appTargetID.map { try appTarget(id: $0) }
      return CommandCenterActionPlan(
        actionID: action.id,
        label: action.label,
        kind: action.kind,
        url: url,
        appTarget: app
      )
    case .openRepoInEditor:
      guard let repoID = action.repoID else {
        throw CommandCenterConfigError.missingRepo("")
      }
      let repo = try resolveRepo(id: repoID)
      let app = try action.appTargetID.map { try appTarget(id: $0) }
      return CommandCenterActionPlan(
        actionID: action.id,
        label: action.label,
        kind: action.kind,
        repoPath: repo.cwd,
        appTarget: app
      )
    case .focusSurface:
      let app = try action.appTargetID.map { try appTarget(id: $0) }
      return CommandCenterActionPlan(
        actionID: action.id,
        label: action.label,
        kind: action.kind,
        appTarget: app
      )
    case .codexPrompt:
      let paneTarget = try paneTarget(for: action, layoutID: layoutID)
      return CommandCenterActionPlan(
        actionID: action.id,
        label: action.label,
        kind: action.kind,
        targetPane: paneTarget
      )
    }
  }

  public func runAction(
    id: String,
    layoutID: String? = nil,
    confirmation: any CommandCenterConfirmationProviding
  ) throws -> CommandCenterRunResult {
    diagnostics.emit(
      level: .info,
      component: "command_center.runtime",
      name: "action.start",
      message: "Running action",
      context: [
        "action_id": id,
        "layout_id": layoutID ?? ""
      ]
    )
    do {
      let action = try requireAction(id)
      let plan = try actionPlan(id: id, layoutID: layoutID)
      var context = actionContext(action: action, plan: plan, layoutID: layoutID)

      switch action.kind {
      case .shellArgv:
        if let hostID = action.hostID {
          _ = try tmux.ensureHost(resolveHost(hostID: hostID, layoutID: layoutID))
        }
        let currentCommand = try tmux.paneCurrentCommand(paneTarget: plan.targetPane ?? "")
        if !ShellProcessClassifier.isShell(currentCommand) {
          guard confirmation.confirmBusy(action: plan, currentCommand: currentCommand) else {
            context["status"] = CommandCenterRunStatus.blocked.rawValue
            context["block_reason"] = "busy_pane"
            emitActionBlocked(context: context)
            return CommandCenterRunResult(ok: false, id: id, status: .blocked, message: "blocked")
          }
        }
        if let command = plan.tmuxCommand {
          try tmux.run(command)
        }
        context["status"] = CommandCenterRunStatus.sent.rawValue
        emitActionSuccess(context: context)
        return CommandCenterRunResult(ok: true, id: id, status: .sent, message: "sent")
      case .stop:
        guard confirmation.confirmStop(action: plan) else {
          context["status"] = CommandCenterRunStatus.blocked.rawValue
          context["block_reason"] = "confirmation_denied"
          emitActionBlocked(context: context)
          return CommandCenterRunResult(ok: false, id: id, status: .blocked, message: "blocked")
        }
        if let command = plan.tmuxCommand {
          try tmux.run(command)
        }
        context["status"] = CommandCenterRunStatus.sent.rawValue
        emitActionSuccess(context: context)
        return CommandCenterRunResult(ok: true, id: id, status: .sent, message: "sent")
      case .openURL:
        try windows.openURL(plan.url ?? "", appTarget: plan.appTarget)
        context["status"] = CommandCenterRunStatus.opened.rawValue
        emitActionSuccess(context: context)
        return CommandCenterRunResult(ok: true, id: id, status: .opened, message: "opened")
      case .openRepoInEditor:
        guard let repoPath = plan.repoPath,
              let appTarget = plan.appTarget else {
          throw CommandCenterConfigError.missingAppTarget(action.appTargetID ?? "")
        }
        try windows.openRepo(path: repoPath, appTarget: appTarget)
        context["status"] = CommandCenterRunStatus.opened.rawValue
        emitActionSuccess(context: context)
        return CommandCenterRunResult(ok: true, id: id, status: .opened, message: "opened")
      case .focusSurface:
        if let hostID = action.hostID {
          let host = try resolveHost(hostID: hostID, layoutID: layoutID)
          if let windowID = stateStore.load().canonicalTerminalWindow(profileID: host.id)?.iTermWindowID {
            try windows.focusTerminalHostWindow(windowID: windowID)
          } else {
            try windows.focusTerminalHostWindow(hostID: host.id)
          }
        }
        if let appTarget = plan.appTarget {
          try windows.focusApp(appTarget)
        }
        context["status"] = CommandCenterRunStatus.focused.rawValue
        emitActionSuccess(context: context)
        return CommandCenterRunResult(ok: true, id: id, status: .focused, message: "focused")
      case .codexPrompt:
        context["status"] = CommandCenterRunStatus.blocked.rawValue
        context["block_reason"] = "not_executable"
        emitActionBlocked(context: context)
        return CommandCenterRunResult(ok: false, id: id, status: .blocked, message: "codex prompt actions are planned but not executable in this milestone")
      }
    } catch {
      var context = MaestroDiagnostics.safeErrorContext(error)
      context["action_id"] = id
      context["layout_id"] = layoutID ?? ""
      diagnostics.emit(
        level: .error,
        component: "command_center.runtime",
        name: "action.failure",
        message: "Action failed",
        context: context
      )
      throw error
    }
  }

  public func configuredPaneBindings(layoutID: String? = nil) throws -> [CommandCenterPaneBinding] {
    let layout = try screenLayout(id: layoutID)
    return try layout.terminalHosts.flatMap { host -> [CommandCenterPaneBinding] in
      let resolved = try resolveHost(host)
      return resolved.paneTemplate.slots.enumerated().map { index, slot in
        CommandCenterPaneBinding(
          layoutID: layout.id,
          hostID: resolved.id,
          slotID: slot.id,
          role: slot.role,
          repoID: resolved.repo(for: slot).id,
          paneTarget: "\(resolved.tmuxWindowTarget).\(index)"
        )
      }
    }
  }

  public func livePaneList(layoutID: String? = nil) throws -> [LiveTmuxPaneSnapshot] {
    let layout = try screenLayout(id: layoutID)
    let sessions = try layout.terminalHosts.map {
      try resolveHost($0).sessionName
    }
    return try tmux.listMaestroPanes(sessions: sessions)
  }

  public func paneOperationPlan(
    kind: CommandCenterPaneOperationKind,
    source: CommandCenterPaneRef,
    destination: CommandCenterPaneRef,
    layoutID: String? = nil
  ) throws -> CommandCenterPaneOperationPlan {
    let sourceHost = try resolveHost(hostID: source.hostID, layoutID: layoutID)
    let destinationHost = try resolveHost(hostID: destination.hostID, layoutID: layoutID)
    let sourcePane = try sourceHost.paneTarget(slotID: source.slotID)
    let destinationPane = try destinationHost.paneTarget(slotID: destination.slotID)
    let commandName = kind == .swap ? "swap-pane" : "move-pane"
    var commands = [
      TmuxCommand(arguments: [commandName, "-s", sourcePane, "-t", destinationPane])
    ]
    let planner = CommandCenterTmuxPlanner()
    commands.append(contentsOf: planner.tagCommands(host: sourceHost))
    if sourceHost.id != destinationHost.id {
      commands.append(contentsOf: planner.tagCommands(host: destinationHost))
    }
    if let layout = planner.layoutCommand(host: sourceHost) {
      commands.append(layout)
    }
    if sourceHost.id != destinationHost.id, let layout = planner.layoutCommand(host: destinationHost) {
      commands.append(layout)
    }
    return CommandCenterPaneOperationPlan(
      kind: kind,
      source: source,
      destination: destination,
      sourcePaneTarget: sourcePane,
      destinationPaneTarget: destinationPane,
      commands: commands
    )
  }

  public func runPaneOperation(
    kind: CommandCenterPaneOperationKind,
    source: CommandCenterPaneRef,
    destination: CommandCenterPaneRef,
    layoutID: String? = nil
  ) throws -> CommandCenterPaneOperationPlan {
    let plan = try paneOperationPlan(kind: kind, source: source, destination: destination, layoutID: layoutID)
    try tmux.run(plan.commands)
    return plan
  }

  private func paneTarget(for action: CommandCenterAction, layoutID: String?) throws -> String {
    guard let hostID = action.hostID, let slotID = action.slotID else {
      throw CommandCenterConfigError.missingPaneSlot(hostID: action.hostID ?? "", slotID: action.slotID ?? "")
    }
    return try resolveHost(hostID: hostID, layoutID: layoutID).paneTarget(slotID: slotID)
  }

  private func requireAction(_ id: String) throws -> CommandCenterAction {
    guard let action = config.actions.first(where: { $0.id == id }) else {
      throw CommandCenterConfigError.missingAction(id)
    }
    return action
  }

  private func actionContext(
    action: CommandCenterAction,
    plan: CommandCenterActionPlan,
    layoutID: String?
  ) -> [String: String] {
    var context: [String: String] = [
      "action_id": action.id,
      "kind": action.kind.rawValue,
      "layout_id": layoutID ?? ""
    ]
    if let hostID = action.hostID {
      context["host_id"] = hostID
    }
    if let slotID = action.slotID {
      context["slot_id"] = slotID
    }
    if let targetPane = plan.targetPane {
      context["target_pane"] = targetPane
    }
    if let appTarget = plan.appTarget {
      context["app_target_id"] = appTarget.id
      if let bundleID = appTarget.bundleID {
        context["bundle_id"] = bundleID
      }
      if appTarget.useSystemDefaultBrowser {
        context["use_system_default_browser"] = "true"
      }
    }
    return context
  }

  private func emitActionSuccess(context: [String: String]) {
    diagnostics.emit(
      level: .info,
      component: "command_center.runtime",
      name: "action.success",
      message: "Action completed",
      context: context
    )
  }

  private func emitActionBlocked(context: [String: String]) {
    diagnostics.emit(
      level: .warning,
      component: "command_center.runtime",
      name: "action.blocked",
      message: "Action was blocked",
      context: context
    )
  }

  private func runStartupCommandsIfIdle(for host: ResolvedTerminalHost) throws {
    for startup in host.startupCommands {
      guard !startup.argv.isEmpty else {
        continue
      }
      let paneTarget = try host.paneTarget(slotID: startup.slotID)
      let currentCommand = try tmux.paneCurrentCommand(paneTarget: paneTarget)
      guard ShellProcessClassifier.isShell(currentCommand) else {
        diagnostics.emit(
          level: .info,
          component: "command_center.runtime",
          name: "startup.skip.busy_pane",
          message: "Skipped terminal startup command because the pane is busy",
          context: [
            "terminal_profile_id": host.id,
            "slot_id": startup.slotID,
            "pane_target": paneTarget,
            "current_command": MaestroDiagnostics.safeSummary(currentCommand)
          ]
        )
        continue
      }
      let display = ShellCommandRenderer.render(startup.argv)
      try tmux.run(TmuxCommand(arguments: ["send-keys", "-t", paneTarget, display, "C-m"]))
      diagnostics.emit(
        level: .info,
        component: "command_center.runtime",
        name: "startup.sent",
        message: "Sent terminal startup command",
        context: [
          "terminal_profile_id": host.id,
          "slot_id": startup.slotID,
          "pane_target": paneTarget
        ]
      )
    }
  }

  private func mergeTerminalWindows(
    _ existing: [TerminalWindowSnapshot],
    _ additions: [TerminalWindowSnapshot]
  ) -> [TerminalWindowSnapshot] {
    var windowsByID: [String: TerminalWindowSnapshot] = [:]
    var orderedIDs: [String] = []
    for window in existing + additions {
      if windowsByID[window.id] == nil {
        orderedIDs.append(window.id)
      }
      windowsByID[window.id] = window
    }
    return orderedIDs.compactMap { windowsByID[$0] }
  }

  private func requireResolvedTerminalHosts(
    plan: CommandCenterLayoutPlan,
    layoutID: String,
    createdWindows: [TerminalWindowSnapshot]
  ) throws {
    guard let missingProfileID = plan.missingTerminalProfileIDs.first else {
      return
    }
    let createdWindowID = createdWindows.first { $0.targetID == missingProfileID }?.id ?? createdWindows.first?.id
    throw CommandCenterLayoutApplyError.terminalWindowNotTracked(
      layoutID: layoutID,
      terminalProfileID: missingProfileID,
      windowID: createdWindowID
    )
  }

  private func validateTerminalMoveReports(
    expectedFramesByWindowID: [String: LayoutRect],
    reports: [CommandCenterTerminalWindowMoveReport],
    layoutID: String
  ) throws {
    guard !expectedFramesByWindowID.isEmpty else {
      return
    }
    var failures = reports.filter { !$0.outcome.isSuccess }
    let reportedWindowIDs = Set(reports.map(\.windowID))
    for (windowID, frame) in expectedFramesByWindowID where !reportedWindowIDs.contains(windowID) {
      failures.append(CommandCenterTerminalWindowMoveReport(
        windowID: windowID,
        frame: frame,
        outcome: .missingReport,
        message: "move operation returned no report"
      ))
    }
    if !failures.isEmpty {
      throw CommandCenterLayoutApplyError.terminalWindowMoveFailed(layoutID: layoutID, reports: failures)
    }
  }

  private func validateAppMoveReports(
    expectedFramesByAppTargetID: [String: LayoutRect],
    reports: [CommandCenterAppWindowMoveReport],
    layoutID: String
  ) throws {
    guard !expectedFramesByAppTargetID.isEmpty else {
      return
    }
    var failures = reports.filter { !$0.outcome.isSuccess }
    let reportedAppTargetIDs = Set(reports.map(\.appTargetID))
    for (appTargetID, frame) in expectedFramesByAppTargetID where !reportedAppTargetIDs.contains(appTargetID) {
      failures.append(CommandCenterAppWindowMoveReport(
        appTargetID: appTargetID,
        frame: frame,
        outcome: .missingReport,
        message: "move operation returned no report"
      ))
    }
    if !failures.isEmpty {
      throw CommandCenterLayoutApplyError.appWindowMoveFailed(layoutID: layoutID, reports: failures)
    }
  }

  private func terminalWindowRecords(
    plan: CommandCenterLayoutPlan,
    taggedWindows: [TerminalWindowSnapshot],
    layoutID: String,
    screenID: String
  ) -> [CommandCenterOwnedTerminalWindow] {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    var records: [CommandCenterOwnedTerminalWindow] = []
    var recordedWindowIDs = Set<String>()
    var hostByProfileID: [String: CommandCenterTerminalHostPlan] = [:]
    for host in plan.terminalHosts where hostByProfileID[host.terminalProfileID] == nil {
      hostByProfileID[host.terminalProfileID] = host
    }

    for host in plan.terminalHosts {
      if let window = host.window {
        records.append(CommandCenterOwnedTerminalWindow(
          profileID: host.terminalProfileID,
          iTermWindowID: window.id,
          sessionName: host.sessionName,
          windowName: host.windowName,
          layoutID: layoutID,
          screenID: screenID,
          frame: host.frame,
          lastSeenAt: timestamp,
          status: .canonical
        ))
        recordedWindowIDs.insert(window.id)
      }

      for windowID in host.quarantinedWindowIDs {
        records.append(CommandCenterOwnedTerminalWindow(
          profileID: host.terminalProfileID,
          iTermWindowID: windowID,
          sessionName: host.sessionName,
          windowName: host.windowName,
          layoutID: layoutID,
          screenID: screenID,
          frame: nil,
          lastSeenAt: timestamp,
          status: .quarantined
        ))
        recordedWindowIDs.insert(windowID)
      }
    }

    for window in taggedWindows where !recordedWindowIDs.contains(window.id) {
      guard let profileID = window.targetID else {
        continue
      }
      let host = hostByProfileID[profileID]
      records.append(CommandCenterOwnedTerminalWindow(
        profileID: profileID,
        iTermWindowID: window.id,
        sessionName: host?.sessionName ?? CommandCenterTmuxNaming.sessionName(workspaceID: config.workspace.id, hostID: profileID),
        windowName: host?.windowName ?? CommandCenterTmuxNaming.windowName,
        layoutID: host == nil ? nil : layoutID,
        screenID: screenID,
        frame: window.frame,
        lastSeenAt: timestamp,
        status: .unmanaged
      ))
    }

    return records.sorted {
      if $0.profileID == $1.profileID {
        return $0.iTermWindowID < $1.iTermWindowID
      }
      return $0.profileID < $1.profileID
    }
  }

  private func waitForTaggedHostWindows(
    hostIDs: Set<String>,
    existing: [TerminalWindowSnapshot]
  ) throws -> [TerminalWindowSnapshot] {
    let deadline = Date().addingTimeInterval(5)
    var latest = existing
    while Date() < deadline {
      let present = Set(latest.compactMap(\.targetID))
      if hostIDs.isSubset(of: present) {
        return latest
      }
      Thread.sleep(forTimeInterval: 0.1)
      latest = try windows.taggedTerminalHostWindows()
    }
    return latest
  }

  private func appFramesByTargetID(plan: CommandCenterLayoutPlan) -> [String: LayoutRect] {
    var frames: [String: LayoutRect] = [:]
    for zone in plan.appZones {
      for appTargetID in zone.appTargetIDs {
        frames[appTargetID] = zone.frame
      }
    }
    return frames
  }

  private func appTargetsForLayoutPlan(_ plan: CommandCenterLayoutPlan) -> [AppTarget] {
    var targets: [AppTarget] = []
    var seen = Set<String>()
    for appTargetID in plan.appZones.flatMap(\.appTargetIDs) where !seen.contains(appTargetID) {
      if let appTarget = config.appTargets.first(where: { $0.id == appTargetID }) {
        targets.append(appTarget)
        seen.insert(appTargetID)
      }
    }
    return targets
  }

  private func attachCommand(for host: ResolvedTerminalHost) -> String {
    let cwd = ShellCommandRenderer.quote(host.repo.cwd)
    let tmuxTarget = ShellCommandRenderer.quote(host.tmuxWindowTarget)
    return "cd \(cwd) && tmux attach-session -t \(tmuxTarget)"
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
