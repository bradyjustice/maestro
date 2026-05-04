import Foundation
import MaestroAutomation
import MaestroCore

@main
struct MaestroCoreChecks {
  static func main() throws {
    try checkedInCommandCenterLoadsAndValidates()
    try appTargetDefaultBrowserDecodesAndValidates()
    try legacyPaletteMigratesToCommandCenter()
    try commandCenterValidationRejectsBrokenReferences()
    try commandCenterValidationRejectsUIRelevantMistakes()
    try commandCenterConfigStoreSavesRoundTrip()
    try commandCenterReferenceInspectorFindsDeletionBlockers()
    try defaultLayoutFramesAndAppOverlapResolve()
    try paneTemplateGeometryResolves()
    try legacyHostsResolveAsImplicitTerminalProfiles()
    try taggedHostPlanningIgnoresUnmanagedWindows()
    try layoutApplyReusesOwnedTerminalWindowFromState()
    try layoutApplyMovesCreatedTerminalByReturnedWindowID()
    try layoutApplyFailsWithoutSavingWhenCreatedTerminalIsNotTracked()
    try layoutApplyFailsWithoutSavingWhenTerminalMoveFails()
    try layoutApplyPropagatesAppMoveFailures()
    try duplicateTaggedTerminalWindowsAreQuarantined()
    try startupCommandsRunOnlyForIdlePanes()
    try itermProfileNameFlowsToCreatedWindow()
    try tmuxHostPlansCreateSplitRetagAndReattach()
    try actionPlansRenderSafeCommands()
    try busyPaneBlocksWithoutConfirmationAndSendsWithConfirmation()
    try paneOperationPlansSwapMoveAndRetag()
    try stateStoreRoundTrips()
    try debugOptionsParseEnvironment()
    try diagnosticEventsEncodeAsJSONLines()
    try diagnosticsAreDisabledByDefault()
    try tmuxDiagnosticsRedactArgvAndStderr()
    try runtimeDiagnosticsRecordActionSuccessBlockAndFailure()
    print("Maestro core checks passed.")
  }

  private static func checkedInCommandCenterLoadsAndValidates() throws {
    let loaded = try checkedInLoadedConfig()
    try expectEqual(loaded.migratedFromSchemaVersion, nil, "checked-in config is native v2")
    let config = loaded.config
    let validation = CommandCenterValidator().validate(config)
    try expect(validation.ok, "checked-in command center config validates")
    try expectEqual(config.schemaVersion, 2, "checked-in schema version")
    try expectEqual(config.workspace.id, "node", "workspace id")
    try expectEqual(config.screenLayouts.map(\.id), [
      "terminal-left-third",
      "terminal-right-third",
      "dual-half-stacks",
      "quad-full",
      "single-full"
    ], "starter layout order")
    try expectEqual(config.appTargets.map(\.id), ["browser", "editor"], "app target order")
    let browser = try require(config.appTargets.first { $0.id == "browser" }, "browser app target")
    try expect(browser.useSystemDefaultBrowser, "checked-in browser uses macOS default browser")
    try expectEqual(browser.bundleID, nil, "checked-in browser does not hard-code a bundle id")
    try expectEqual(browser.defaultURL, "http://localhost:3000", "checked-in browser default URL resolves default app")
    try expect(config.actions.contains { $0.id == "account.check" }, "account check action exists")
  }

  private static func appTargetDefaultBrowserDecodesAndValidates() throws {
    let explicitJSON = """
      {
        "id": "editor",
        "label": "Editor",
        "bundleID": "com.microsoft.VSCode",
        "role": "editor"
      }
      """
    let explicit = try MaestroJSON.decoder.decode(AppTarget.self, from: Data(explicitJSON.utf8))
    try expectEqual(explicit.bundleID, "com.microsoft.VSCode", "explicit bundle app target decodes")
    try expect(!explicit.useSystemDefaultBrowser, "explicit bundle app target keeps default-browser flag off")

    var config = try checkedInConfig()
    try expect(CommandCenterValidator().validate(config).ok, "checked-in default browser target validates")

    config.appTargets[0].role = .editor
    var codes = CommandCenterValidator().validate(config).issues.map(\.code)
    try expect(codes.contains("invalid_default_browser_target_role"), "default browser target must use browser role")

    config = try checkedInConfig()
    config.appTargets[0].defaultURL = nil
    codes = CommandCenterValidator().validate(config).issues.map(\.code)
    try expect(codes.contains("missing_default_browser_url"), "default browser target requires default URL")
  }

  private static func legacyPaletteMigratesToCommandCenter() throws {
    let legacyJSON = """
      {
        "schemaVersion": 1,
        "roots": [
          {
            "id": "repo",
            "path": "~/Code"
          }
        ],
        "targets": [
          {
            "id": "web",
            "label": "Web",
            "session": "legacy",
            "window": "web",
            "pane": 0,
            "root": "repo",
            "path": "website"
          }
        ],
        "regions": [
          {
            "id": "left",
            "label": "Left",
            "container": {
              "x": 0,
              "y": 0,
              "width": 0.5,
              "height": 1
            }
          }
        ],
        "layouts": [
          {
            "id": "legacy.left",
            "label": "Legacy Left",
            "region": "left",
            "slots": [
              {
                "id": "main",
                "target": "web",
                "unit": {
                  "x": 0,
                  "y": 0,
                  "width": 1,
                  "height": 1
                }
              }
            ]
          }
        ],
        "buttons": [
          {
            "id": "web.dev",
            "label": "Web Dev",
            "kind": "command",
            "target": "web",
            "argv": ["npm", "run", "dev"]
          }
        ],
        "sections": [
          {
            "id": "dev",
            "label": "Dev",
            "buttonIDs": ["web.dev"]
          }
        ]
      }
      """
    let legacy = try MaestroJSON.decoder.decode(PaletteConfig.self, from: Data(legacyJSON.utf8))
    let migrated = CommandCenterMigrator().migrate(legacy)
    try expectEqual(migrated.schemaVersion, 2, "legacy migrates to v2")
    try expectEqual(migrated.repos.first?.path, "~/Code/website", "legacy target path migrates into repo path")
    try expectEqual(migrated.screenLayouts.first?.terminalHosts.first?.sessionStrategy, .perHost, "legacy migration uses per-host sessions")
    try expectEqual(migrated.actions.first?.kind, .shellArgv, "legacy button migrates to shell action")
    try expect(CommandCenterValidator().validate(migrated).ok, "migrated legacy config validates")
  }

  private static func commandCenterValidationRejectsBrokenReferences() throws {
    var config = try checkedInConfig()
    config.screenLayouts[0].terminalHosts[0].repoID = "missing-repo"
    config.screenLayouts[0].appZones[0].appTargetIDs.append("missing-app")
    config.actions.append(CommandCenterAction(
      id: "broken",
      label: "Broken",
      kind: .shellArgv,
      hostID: "missing-host",
      slotID: "top",
      argv: []
    ))
    config.profiles = [
      CommandCenterProfile(
        id: "bad",
        label: "Bad",
        layoutIDs: ["missing-layout"],
        appTargetIDs: ["missing-app"],
        actionSectionIDs: ["missing-section"]
      )
    ]

    let codes = CommandCenterValidator().validate(config).issues.map(\.code)
    try expect(codes.contains("unknown_terminal_host_repo"), "unknown host repo rejected")
    try expect(codes.contains("unknown_app_zone_target"), "unknown app zone target rejected")
    try expect(codes.contains("empty_action_argv"), "empty shell argv rejected")
    try expect(codes.contains("unknown_action_host"), "unknown action host rejected")
    try expect(codes.contains("unknown_profile_layout"), "unknown profile layout rejected")
    try expect(codes.contains("unknown_profile_app_target"), "unknown profile app rejected")
    try expect(codes.contains("unknown_profile_section"), "unknown profile section rejected")
  }

  private static func commandCenterValidationRejectsUIRelevantMistakes() throws {
    var missingLayoutProfile = try configWithTerminalProfile()
    missingLayoutProfile.screenLayouts[0].terminalHosts[0].terminalProfileID = "missing-profile"
    let layoutCodes = CommandCenterValidator().validate(missingLayoutProfile).issues.map(\.code)
    try expect(layoutCodes.contains("unknown_terminal_host_profile"), "layout terminal profile reference is rejected")

    var missingStartupSlot = try configWithTerminalProfile()
    missingStartupSlot.terminalProfiles?[0].startupCommands = [
      TerminalStartupCommand(slotID: "missing-slot", argv: ["codex"])
    ]
    let startupCodes = CommandCenterValidator().validate(missingStartupSlot).issues.map(\.code)
    try expect(startupCodes.contains("unknown_terminal_profile_startup_slot"), "startup command slot reference is rejected")

    var missingActionSlot = try checkedInConfig()
    missingActionSlot.actions.append(CommandCenterAction(
      id: "bad.slot",
      label: "Bad Slot",
      kind: .shellArgv,
      hostID: "main",
      slotID: "missing-slot",
      argv: ["true"]
    ))
    let actionCodes = CommandCenterValidator().validate(missingActionSlot).issues.map(\.code)
    try expect(actionCodes.contains("unknown_action_slot"), "action slot reference is rejected")
  }

  private static func commandCenterConfigStoreSavesRoundTrip() throws {
    let store = CommandCenterConfigStore(environment: ["HOME": "/repo"])
    let fileURL = temporaryConfigFile()
    let startupCommands = [
      TerminalStartupCommand(slotID: "top", argv: ["codex"]),
      TerminalStartupCommand(slotID: "bottom", argv: ["env", "CLOUDFLARE_ENV=staging", "npm", "run", "db:staging"])
    ]
    let config = try configWithTerminalProfile(startupCommands: startupCommands)

    let save = try store.save(config, to: fileURL)
    try expectEqual(save.fileURL, fileURL, "save reports file URL")
    try expectEqual(save.backupURL, nil, "save does not create a sidecar backup")
    try expect(save.validation.ok, "saved config validates")

    let reloaded = try store.load(fileURL: fileURL).config
    try expectEqual(reloaded, config, "saved config round trips")
    try expectEqual(
      reloaded.terminalProfiles?[0].startupCommands,
      startupCommands,
      "terminal profile startup commands survive save/load"
    )

    let originalData = try Data(contentsOf: fileURL)
    var invalid = config
    invalid.screenLayouts[0].terminalHosts[0].terminalProfileID = "missing-profile"
    do {
      _ = try store.save(invalid, to: fileURL)
      throw CheckFailure("invalid config save should fail")
    } catch CommandCenterConfigError.invalidConfig {
    }
    let afterFailedSave = try Data(contentsOf: fileURL)
    try expectEqual(afterFailedSave, originalData, "invalid config is rejected before writing")
  }

  private static func commandCenterReferenceInspectorFindsDeletionBlockers() throws {
    let config = try checkedInConfig()
    let inspector = CommandCenterConfigReferenceInspector()

    try expect(
      inspector.references(to: .repo("website"), in: config).contains { $0.sourceKind == "Pane Template" },
      "repo references include pane templates"
    )
    try expect(
      inspector.references(to: .paneTemplate("work-stack"), in: config).contains { $0.sourceKind == "Screen Layout" },
      "pane template references include layouts"
    )
    try expect(
      inspector.references(to: .screenLayout("terminal-left-third"), in: config).contains { $0.sourceKind == "Profile" },
      "layout references include profiles"
    )
    try expect(
      inspector.references(to: .action("website.dev"), in: config).contains { $0.sourceKind == "Section" },
      "action references include sections"
    )

    let profileConfig = try configWithTerminalProfile()
    try expect(
      inspector.references(to: .terminalProfile("work"), in: profileConfig).contains { $0.sourceKind == "Screen Layout" },
      "terminal profile references include layouts"
    )
  }

  private static func defaultLayoutFramesAndAppOverlapResolve() throws {
    let config = try checkedInConfig()
    let runtime = runtimeForChecks(config: config, runner: RecordingRunner())
    let plan = try runtime.dryRunLayoutPlan(id: "terminal-left-third", screen: representativeScreen())
    let main = try require(plan.terminalHosts.first, "main terminal host")
    try expectEqual(main.frame, LayoutRect(x: 0, y: 0, width: 480, height: 900), "left-third terminal host frame")
    try expectEqual(main.slots[0].frame, LayoutRect(x: 0, y: 0, width: 480, height: 450), "stack top slot frame")
    try expectEqual(main.slots[1].frame, LayoutRect(x: 0, y: 450, width: 480, height: 450), "stack bottom slot frame")
    let appZone = try require(plan.appZones.first, "overlap app zone")
    try expectEqual(appZone.frame, LayoutRect(x: 480, y: 0, width: 960, height: 900), "right two-thirds app zone")
    try expectEqual(appZone.appTargetIDs, ["browser", "editor"], "browser and editor share app frame")

    let inverse = try runtime.dryRunLayoutPlan(id: "terminal-right-third", screen: representativeScreen())
    try expectEqual(inverse.terminalHosts[0].frame, LayoutRect(x: 960, y: 0, width: 480, height: 900), "inverse terminal host frame")
    try expectEqual(inverse.appZones[0].frame, LayoutRect(x: 0, y: 0, width: 960, height: 900), "inverse app zone frame")
  }

  private static func paneTemplateGeometryResolves() throws {
    let config = try checkedInConfig()
    let runtime = runtimeForChecks(config: config, runner: RecordingRunner())
    let quad = try runtime.dryRunLayoutPlan(id: "quad-full", screen: representativeScreen())
    let slots = try require(quad.terminalHosts.first, "quad host").slots
    try expectEqual(slots.map(\.slotID), ["top-left", "top-right", "bottom-left", "bottom-right"], "quad slot order")
    try expectEqual(slots[0].frame, LayoutRect(x: 0, y: 0, width: 720, height: 450), "quad top-left frame")
    try expectEqual(slots[3].frame, LayoutRect(x: 720, y: 450, width: 720, height: 450), "quad bottom-right frame")

    let single = try runtime.dryRunLayoutPlan(id: "single-full", screen: representativeScreen())
    try expectEqual(single.terminalHosts[0].slots[0].frame, LayoutRect(x: 0, y: 0, width: 1440, height: 900), "single pane fills host")
  }

  private static func legacyHostsResolveAsImplicitTerminalProfiles() throws {
    let config = try checkedInConfig()
    let layout = try require(config.screenLayouts.first { $0.id == "terminal-left-third" }, "terminal-left-third layout")
    let plan = try CommandCenterLayoutPlanner().plan(
      layout: layout,
      config: config,
      screen: representativeScreen(),
      windows: [TerminalWindowSnapshot(id: "main-window", targetID: "main")]
    )
    let host = try require(plan.terminalHosts.first, "main terminal host")
    try expectEqual(host.hostID, "main", "legacy layout host id is preserved")
    try expectEqual(host.terminalProfileID, "main", "legacy layout host becomes implicit terminal profile")
    try expectEqual(host.sessionName, "maestro_node_main", "implicit profile names tmux session")
    try expectEqual(host.ownershipDecision, .reused, "legacy tagged host is reusable")
  }

  private static func taggedHostPlanningIgnoresUnmanagedWindows() throws {
    let config = try checkedInConfig()
    let layout = try require(config.screenLayouts.first { $0.id == "terminal-left-third" }, "terminal-left-third layout")
    let windows = [
      TerminalWindowSnapshot(id: "managed-main", targetID: "main"),
      TerminalWindowSnapshot(id: "untagged", targetID: nil),
      TerminalWindowSnapshot(id: "duplicate-main", targetID: "main")
    ]
    let plan = try CommandCenterLayoutPlanner().plan(
      layout: layout,
      config: config,
      screen: representativeScreen(),
      windows: windows
    )
    try expectEqual(plan.terminalHosts[0].status, .matched, "managed host matched")
    try expectEqual(plan.unmanagedWindowCount, 1, "duplicate tagged window counted but untagged window ignored")
  }

  private static func layoutApplyReusesOwnedTerminalWindowFromState() throws {
    let config = try configWithTerminalProfile()
    let fakeWindows = FakeCommandCenterAutomation(taggedWindows: [
      TerminalWindowSnapshot(id: "owned-work", targetID: "work")
    ])
    let store = temporaryStateStore()
    try store.save(CommandCenterState(
      activeLayoutID: "profile-left",
      hostSessions: ["work": "maestro_node_work"],
      terminalWindows: [
        CommandCenterOwnedTerminalWindow(
          profileID: "work",
          iTermWindowID: "owned-work",
          sessionName: "maestro_node_work",
          windowName: "main",
          status: .canonical
        )
      ]
    ))

    let plan = try runtimeForChecks(
      config: config,
      runner: RecordingRunner(),
      windows: fakeWindows,
      stateStore: store
    ).applyLayout(id: "profile-left")

    let host = try require(plan.terminalHosts.first, "profile host")
    try expectEqual(host.terminalProfileID, "work", "explicit layout host resolves terminal profile")
    try expectEqual(host.window?.id, "owned-work", "layout reuses owned state window")
    try expectEqual(host.ownershipDecision, .reused, "reused state window is reported")
    try expect(fakeWindows.createdHosts.isEmpty, "reapplying layout does not create a duplicate iTerm window")
    try expectEqual(fakeWindows.movedFramesByWindowID["owned-work"], host.frame, "canonical owned window is moved by iTerm window id")
  }

  private static func layoutApplyMovesCreatedTerminalByReturnedWindowID() throws {
    let config = try configWithTerminalProfile()
    let fakeWindows = FakeCommandCenterAutomation(createdWindowID: "returned-work-window")
    let plan = try runtimeForChecks(
      config: config,
      runner: RecordingRunner(),
      windows: fakeWindows,
      stateStore: temporaryStateStore()
    ).applyLayout(id: "profile-left")

    let host = try require(plan.terminalHosts.first, "created profile host")
    try expectEqual(host.window?.id, "returned-work-window", "created terminal uses returned iTerm window id")
    try expectEqual(fakeWindows.movedFramesByWindowID["returned-work-window"], host.frame, "created terminal is moved by returned iTerm window id")
  }

  private static func layoutApplyFailsWithoutSavingWhenCreatedTerminalIsNotTracked() throws {
    let config = try configWithTerminalProfile()
    let fakeWindows = FakeCommandCenterAutomation(createdWindowIsTagged: false)
    let store = temporaryStateStore()

    do {
      _ = try runtimeForChecks(
        config: config,
        runner: RecordingRunner(),
        windows: fakeWindows,
        stateStore: store
      ).applyLayout(id: "profile-left")
      throw CheckFailure("untracked created terminal should fail layout apply")
    } catch CommandCenterLayoutApplyError.terminalWindowNotTracked {
    }

    let state = store.load()
    try expectEqual(state.activeLayoutID, nil, "failed terminal tracking does not save active layout")
    try expect(state.terminalWindows.isEmpty, "failed terminal tracking does not save clean window state")
  }

  private static func layoutApplyFailsWithoutSavingWhenTerminalMoveFails() throws {
    let config = try configWithTerminalProfile()
    let fakeWindows = FakeCommandCenterAutomation(taggedWindows: [
      TerminalWindowSnapshot(id: "work-window", targetID: "work")
    ])
    fakeWindows.terminalMoveFailuresByWindowID["work-window"] = .boundsNotApplied
    let store = temporaryStateStore()

    do {
      _ = try runtimeForChecks(
        config: config,
        runner: RecordingRunner(),
        windows: fakeWindows,
        stateStore: store
      ).applyLayout(id: "profile-left")
      throw CheckFailure("terminal move failure should fail layout apply")
    } catch CommandCenterLayoutApplyError.terminalWindowMoveFailed {
    }

    let state = store.load()
    try expectEqual(state.activeLayoutID, nil, "failed terminal move does not save active layout")
    try expect(state.terminalWindows.isEmpty, "failed terminal move does not save clean window state")
  }

  private static func layoutApplyPropagatesAppMoveFailures() throws {
    let config = try checkedInConfig()
    let fakeWindows = FakeCommandCenterAutomation(taggedWindows: [
      TerminalWindowSnapshot(id: "main-window", targetID: "main")
    ])
    fakeWindows.appMoveFailuresByTargetID["browser"] = .noFrontWindow
    let store = temporaryStateStore()

    do {
      _ = try runtimeForChecks(
        config: config,
        runner: RecordingRunner(),
        windows: fakeWindows,
        stateStore: store
      ).applyLayout(id: "terminal-left-third")
      throw CheckFailure("app move failure should fail layout apply")
    } catch CommandCenterLayoutApplyError.appWindowMoveFailed {
    }

    try expectEqual(fakeWindows.movedAppTargetIDs, ["browser", "editor"], "app move attempts are reported per target")
    let state = store.load()
    try expectEqual(state.activeLayoutID, nil, "failed app move does not save active layout")
  }

  private static func duplicateTaggedTerminalWindowsAreQuarantined() throws {
    let config = try configWithTerminalProfile()
    let fakeWindows = FakeCommandCenterAutomation(taggedWindows: [
      TerminalWindowSnapshot(id: "a-work", targetID: "work"),
      TerminalWindowSnapshot(id: "b-work", targetID: "work")
    ])
    let store = temporaryStateStore()
    let plan = try runtimeForChecks(
      config: config,
      runner: RecordingRunner(),
      windows: fakeWindows,
      stateStore: store
    ).applyLayout(id: "profile-left")

    let host = try require(plan.terminalHosts.first, "profile host")
    try expectEqual(host.window?.id, "a-work", "first duplicate becomes canonical without prior state")
    try expectEqual(host.quarantinedWindowIDs, ["b-work"], "duplicate tagged window is quarantined")
    try expectEqual(host.ownershipDecision, .duplicateQuarantined, "duplicate quarantine is reported in layout plan")
    try expect(fakeWindows.createdHosts.isEmpty, "duplicate tagged windows do not cause another create")
    let state = store.load()
    try expect(state.terminalWindows.contains {
      $0.iTermWindowID == "a-work" && $0.status == .canonical
    }, "canonical duplicate is stored")
    try expect(state.terminalWindows.contains {
      $0.iTermWindowID == "b-work" && $0.status == .quarantined
    }, "duplicate is stored as quarantined")
  }

  private static func startupCommandsRunOnlyForIdlePanes() throws {
    let startupCommands = [
      TerminalStartupCommand(slotID: "top", argv: ["npm", "run", "dev"]),
      TerminalStartupCommand(slotID: "bottom", argv: ["npm", "run", "dev"])
    ]
    let config = try configWithTerminalProfile(startupCommands: startupCommands)
    let runner = RecordingRunner()
    runner.result(
      stdout: "zsh\n",
      for: ["tmux", "display-message", "-p", "-t", "maestro_node_work:main.0", "#{pane_current_command}"]
    )
    runner.result(
      stdout: "node\n",
      for: ["tmux", "display-message", "-p", "-t", "maestro_node_work:main.1", "#{pane_current_command}"]
    )

    _ = try runtimeForChecks(
      config: config,
      runner: runner,
      windows: FakeCommandCenterAutomation(taggedWindows: [
        TerminalWindowSnapshot(id: "work-window", targetID: "work")
      ]),
      stateStore: temporaryStateStore()
    ).applyLayout(id: "profile-left")

    try expect(runner.calls.contains {
      $0 == ["tmux", "send-keys", "-t", "maestro_node_work:main.0", "npm run dev", "C-m"]
    }, "startup command is sent to shell-idle pane")
    try expect(!runner.calls.contains {
      $0 == ["tmux", "send-keys", "-t", "maestro_node_work:main.1", "npm run dev", "C-m"]
    }, "startup command is skipped for busy pane")
  }

  private static func itermProfileNameFlowsToCreatedWindow() throws {
    let config = try configWithTerminalProfile()
    let fakeWindows = FakeCommandCenterAutomation()
    let plan = try runtimeForChecks(
      config: config,
      runner: RecordingRunner(),
      windows: fakeWindows,
      stateStore: temporaryStateStore()
    ).applyLayout(id: "profile-left")

    let host = try require(plan.terminalHosts.first, "profile host")
    let createdHost = try require(fakeWindows.createdHosts.first, "created host")
    try expectEqual(createdHost.itermProfileName, "Maestro Work", "iTerm profile name is carried to create-window automation")
    try expectEqual(host.ownershipDecision, .created, "created window is reported in layout plan")
    try expectEqual(host.window?.targetID, "work", "created fake iTerm window is tagged by terminal profile id")
  }

  private static func tmuxHostPlansCreateSplitRetagAndReattach() throws {
    let config = try checkedInConfig()
    let host = try runtimeForChecks(config: config, runner: RecordingRunner()).resolveHost(hostID: "main", layoutID: "terminal-left-third")
    let missing = CommandCenterTmuxPlanner().ensureHostPlan(
      host: host,
      sessionExists: false,
      windowExists: false,
      existingPaneCount: 0
    )
    try expectEqual(missing.commands[0].arguments, [
      "new-session",
      "-d",
      "-s",
      "maestro_node_main",
      "-n",
      "main",
      "-c",
      "/repo/Documents/Coding/node/node_website"
    ], "missing host creates per-host session")
    try expect(missing.commands.contains { $0.arguments.prefix(2) == ["split-window", "-t"] }, "missing host creates stack split")
    try expect(missing.commands.contains { $0.arguments == ["select-layout", "-t", "maestro_node_main:main", "even-vertical"] }, "stack normalizes top-bottom layout")
    try expect(missing.commands.contains { $0.arguments == ["set-option", "-p", "-t", "maestro_node_main:main.0", "@maestro.slot", "top"] }, "top slot tagged")

    let reattach = CommandCenterTmuxPlanner().ensureHostPlan(
      host: host,
      sessionExists: true,
      windowExists: true,
      existingPaneCount: 2
    )
    try expect(!reattach.commands.contains { $0.arguments.first == "new-session" }, "existing host does not create a new session")
    try expect(!reattach.commands.contains { $0.arguments.first == "split-window" }, "existing host does not create extra panes")

    let missingWindow = CommandCenterTmuxPlanner().ensureHostPlan(
      host: host,
      sessionExists: true,
      windowExists: false,
      existingPaneCount: 0
    )
    try expect(missingWindow.commands.contains { $0.arguments.first == "new-window" }, "missing host window reattaches to existing session")
  }

  private static func actionPlansRenderSafeCommands() throws {
    try expectEqual(
      ShellCommandRenderer.render(["npm", "run", "script with space", "it's-ok"]),
      "npm run 'script with space' 'it'\\''s-ok'",
      "argv rendering quotes shell text"
    )

    let config = try checkedInConfig()
    let runtime = runtimeForChecks(config: config, runner: RecordingRunner())
    let plan = try runtime.actionPlan(id: "account.check", layoutID: "terminal-left-third")
    try expectEqual(plan.displayCommand, "npm run check", "action display command")
    try expectEqual(plan.targetPane, "maestro_node_main:main.1", "action targets bottom pane")
    try expectEqual(plan.tmuxCommand?.arguments, ["send-keys", "-t", "maestro_node_main:main.1", "npm run check", "C-m"], "action send-keys command")
    let encoded = String(data: try MaestroJSON.encoder.encode(plan), encoding: .utf8) ?? ""
    try expect(encoded.contains("\"actionID\" : \"account.check\""), "action dry-run JSON includes action id")
  }

  private static func busyPaneBlocksWithoutConfirmationAndSendsWithConfirmation() throws {
    let config = try checkedInConfig()
    let busyRunner = RecordingRunner()
    busyRunner.result(stdout: "node\n", for: ["tmux", "display-message", "-p", "-t", "maestro_node_main:main.0", "#{pane_current_command}"])
    let blocked = try runtimeForChecks(config: config, runner: busyRunner)
      .runAction(id: "website.dev", confirmation: DenyCommandCenterConfirmation())
    try expectEqual(blocked.status, .blocked, "busy pane denied status")
    try expect(!busyRunner.calls.contains { $0 == ["tmux", "send-keys", "-t", "maestro_node_main:main.0", "npm run dev", "C-m"] }, "busy denied does not send")

    let shellRunner = RecordingRunner()
    shellRunner.result(stdout: "zsh\n", for: ["tmux", "display-message", "-p", "-t", "maestro_node_main:main.0", "#{pane_current_command}"])
    let sent = try runtimeForChecks(config: config, runner: shellRunner)
      .runAction(id: "website.dev", confirmation: DenyCommandCenterConfirmation())
    try expectEqual(sent.status, .sent, "shell pane sends without confirmation")
    try expect(shellRunner.calls.contains { $0 == ["tmux", "send-keys", "-t", "maestro_node_main:main.0", "npm run dev", "C-m"] }, "shell pane sends command")
  }

  private static func paneOperationPlansSwapMoveAndRetag() throws {
    let config = try checkedInConfig()
    let runtime = runtimeForChecks(config: config, runner: RecordingRunner())
    let swap = try runtime.paneOperationPlan(
      kind: .swap,
      source: CommandCenterPaneRef(hostID: "main", slotID: "top"),
      destination: CommandCenterPaneRef(hostID: "main", slotID: "bottom"),
      layoutID: "terminal-left-third"
    )
    try expectEqual(swap.commands[0].arguments, ["swap-pane", "-s", "maestro_node_main:main.0", "-t", "maestro_node_main:main.1"], "swap-pane command")
    try expect(swap.commands.contains { $0.arguments == ["set-option", "-p", "-t", "maestro_node_main:main.1", "@maestro.slot", "bottom"] }, "swap retags destination slot")

    let move = try runtime.paneOperationPlan(
      kind: .move,
      source: CommandCenterPaneRef(hostID: "main", slotID: "top"),
      destination: CommandCenterPaneRef(hostID: "main", slotID: "bottom"),
      layoutID: "terminal-left-third"
    )
    try expectEqual(move.commands[0].arguments.first, "move-pane", "move-pane command")

    let bindings = try runtime.configuredPaneBindings(layoutID: "terminal-left-third")
    try expectEqual(bindings.map(\.slotID), ["top", "bottom"], "pane list dry-run returns configured slots")
  }

  private static func stateStoreRoundTrips() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("maestro-core-checks-\(UUID().uuidString)")
    let store = CommandCenterStateStore(stateDirectory: directory)
    try store.save(CommandCenterState(activeLayoutID: "terminal-left-third", hostSessions: ["main": "maestro_node_main"]))
    let loaded = store.load()
    try expectEqual(loaded.activeLayoutID, "terminal-left-third", "state active layout round trips")
    try expectEqual(loaded.hostSessions["main"], "maestro_node_main", "state host session round trips")
  }

  private static func debugOptionsParseEnvironment() throws {
    let disabled = MaestroDebugOptions(environment: ["HOME": "/tmp/maestro-home"])
    try expect(!disabled.enabled, "debug diagnostics disabled by default")
    try expectEqual(
      disabled.logFileURL.path,
      "/tmp/maestro-home/.maestro/state/debug/command-center.jsonl",
      "default debug log path falls back under home state directory"
    )

    let stateDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("maestro-debug-state")
    let stateOptions = MaestroDebugOptions(environment: [
      "MAESTRO_DEBUG": "YES",
      "MAESTRO_STATE_DIR": stateDir.path,
      "HOME": "/tmp/ignored"
    ])
    try expect(stateOptions.enabled, "YES enables diagnostics")
    try expectEqual(
      stateOptions.logFileURL.path,
      stateDir.appendingPathComponent("debug/command-center.jsonl").path,
      "debug log defaults under MAESTRO_STATE_DIR"
    )

    let explicit = MaestroDebugOptions(environment: [
      "MAESTRO_DEBUG": "true",
      "MAESTRO_DEBUG_LOG": "~/custom/debug.jsonl",
      "HOME": "/tmp/maestro-home"
    ])
    try expect(explicit.enabled, "true enables diagnostics")
    try expectEqual(explicit.logFileURL.path, "/tmp/maestro-home/custom/debug.jsonl", "explicit debug log expands home")
  }

  private static func diagnosticEventsEncodeAsJSONLines() throws {
    let fileURL = temporaryDiagnosticsFile()
    let diagnostics = MaestroDiagnostics(
      options: MaestroDebugOptions(enabled: true, logFileURL: fileURL),
      writesToStandardError: false
    )
    diagnostics.emit(MaestroDiagnosticEvent(
      timestamp: "2026-05-03T00:00:00Z",
      level: .info,
      component: "checks",
      name: "diagnostic.sample",
      message: "sample",
      context: ["id": "sample-id"]
    ))

    let contents = try diagnosticsLogContents(fileURL)
    try expect(contents.hasSuffix("\n"), "diagnostic events are written as JSON lines")
    let event = try MaestroJSON.decoder.decode(MaestroDiagnosticEvent.self, from: Data(contents.utf8))
    try expectEqual(event.timestamp, "2026-05-03T00:00:00Z", "event timestamp encodes")
    try expectEqual(event.level, .info, "event level encodes")
    try expectEqual(event.component, "checks", "event component encodes")
    try expectEqual(event.name, "diagnostic.sample", "event name encodes")
    try expectEqual(event.message, "sample", "event message encodes")
    try expectEqual(event.context["id"], "sample-id", "event context encodes")
  }

  private static func diagnosticsAreDisabledByDefault() throws {
    let fileURL = temporaryDiagnosticsFile()
    let diagnostics = MaestroDiagnostics(
      options: MaestroDebugOptions(enabled: false, logFileURL: fileURL),
      writesToStandardError: false
    )
    diagnostics.emit(level: .info, component: "checks", name: "disabled.sample", message: "disabled")
    try expect(!FileManager.default.fileExists(atPath: fileURL.path), "disabled diagnostics do not create log files")
  }

  private static func tmuxDiagnosticsRedactArgvAndStderr() throws {
    let fileURL = temporaryDiagnosticsFile()
    let diagnostics = MaestroDiagnostics(
      options: MaestroDebugOptions(enabled: true, logFileURL: fileURL),
      writesToStandardError: false
    )
    let runner = RecordingRunner()
    runner.result(
      status: 2,
      stderr: "full stderr includes TOPSECRET-STDERR and should not be logged",
      for: ["tmux", "send-keys", "-t", "maestro_node_main:main.0", "TOPSECRET-ARGV", "C-m"]
    )
    do {
      try TmuxController(runner: runner, diagnostics: diagnostics)
        .run(TmuxCommand(arguments: ["send-keys", "-t", "maestro_node_main:main.0", "TOPSECRET-ARGV", "C-m"]))
      throw CheckFailure("tmux failure should throw")
    } catch is TmuxControllerError {
    }

    let contents = try diagnosticsLogContents(fileURL)
    try expect(contents.contains("\"name\":\"tmux.command.failure\""), "tmux command failure is logged")
    try expect(contents.contains("\"status\":\"2\""), "tmux failure status is logged")
    try expect(!contents.contains("TOPSECRET-ARGV"), "tmux diagnostic omits raw argv")
    try expect(!contents.contains("TOPSECRET-STDERR"), "tmux diagnostic omits raw stderr")
  }

  private static func runtimeDiagnosticsRecordActionSuccessBlockAndFailure() throws {
    let config = try checkedInConfig()

    let successURL = temporaryDiagnosticsFile()
    let successDiagnostics = MaestroDiagnostics(
      options: MaestroDebugOptions(enabled: true, logFileURL: successURL),
      writesToStandardError: false
    )
    let successRunner = RecordingRunner()
    successRunner.result(stdout: "zsh\n", for: ["tmux", "display-message", "-p", "-t", "maestro_node_main:main.0", "#{pane_current_command}"])
    _ = try runtimeForChecks(config: config, runner: successRunner, diagnostics: successDiagnostics)
      .runAction(id: "website.dev", confirmation: DenyCommandCenterConfirmation())
    let successLog = try diagnosticsLogContents(successURL)
    try expect(successLog.contains("\"name\":\"action.success\""), "action success diagnostic is emitted")
    try expect(successLog.contains("\"action_id\":\"website.dev\""), "action success includes action id")
    try expect(successLog.contains("\"status\":\"sent\""), "action success includes run status")

    let blockedURL = temporaryDiagnosticsFile()
    let blockedDiagnostics = MaestroDiagnostics(
      options: MaestroDebugOptions(enabled: true, logFileURL: blockedURL),
      writesToStandardError: false
    )
    let busyRunner = RecordingRunner()
    busyRunner.result(stdout: "node\n", for: ["tmux", "display-message", "-p", "-t", "maestro_node_main:main.0", "#{pane_current_command}"])
    _ = try runtimeForChecks(config: config, runner: busyRunner, diagnostics: blockedDiagnostics)
      .runAction(id: "website.dev", confirmation: DenyCommandCenterConfirmation())
    let blockedLog = try diagnosticsLogContents(blockedURL)
    try expect(blockedLog.contains("\"name\":\"action.blocked\""), "blocked action diagnostic is emitted")
    try expect(blockedLog.contains("\"block_reason\":\"busy_pane\""), "blocked action includes safe reason")

    let failureURL = temporaryDiagnosticsFile()
    let failureDiagnostics = MaestroDiagnostics(
      options: MaestroDebugOptions(enabled: true, logFileURL: failureURL),
      writesToStandardError: false
    )
    let failureRunner = RecordingRunner()
    failureRunner.result(stdout: "zsh\n", for: ["tmux", "display-message", "-p", "-t", "maestro_node_main:main.0", "#{pane_current_command}"])
    failureRunner.result(
      status: 2,
      stderr: "stderr has TOPSECRET-RUNTIME",
      for: ["tmux", "send-keys", "-t", "maestro_node_main:main.0", "npm run dev", "C-m"]
    )
    do {
      _ = try runtimeForChecks(config: config, runner: failureRunner, diagnostics: failureDiagnostics)
        .runAction(id: "website.dev", confirmation: DenyCommandCenterConfirmation())
      throw CheckFailure("runtime tmux failure should throw")
    } catch is TmuxControllerError {
    }
    let failureLog = try diagnosticsLogContents(failureURL)
    try expect(failureLog.contains("\"name\":\"tmux.command.failure\""), "tmux failure diagnostic is emitted during action")
    try expect(failureLog.contains("\"name\":\"action.failure\""), "action failure diagnostic is emitted")
    try expect(!failureLog.contains("TOPSECRET-RUNTIME"), "runtime failure diagnostic omits raw stderr")
  }

  private static func checkedInLoadedConfig() throws -> LoadedCommandCenterConfig {
    try CommandCenterConfigLoader().load(fileURL: repoRoot().appendingPathComponent("maestro/config/palette.json"))
  }

  private static func checkedInConfig() throws -> CommandCenterConfig {
    try checkedInLoadedConfig().config
  }

  private static func runtimeForChecks(
    config: CommandCenterConfig,
    runner: RecordingRunner,
    diagnostics: MaestroDiagnostics = .disabled,
    windows: any CommandCenterWindowAutomation = FakeCommandCenterAutomation(),
    stateStore: CommandCenterStateStore? = nil
  ) -> CommandCenterRuntime {
    CommandCenterRuntime(
      config: config,
      configDirectory: repoRoot().appendingPathComponent("maestro/config"),
      environment: ["HOME": "/repo"],
      tmux: TmuxController(runner: runner, diagnostics: diagnostics),
      windows: windows,
      stateStore: stateStore ?? temporaryStateStore(),
      diagnostics: diagnostics
    )
  }

  private static func configWithTerminalProfile(
    startupCommands: [TerminalStartupCommand] = []
  ) throws -> CommandCenterConfig {
    var config = try checkedInConfig()
    config.terminalProfiles = [
      TerminalProfile(
        id: "work",
        label: "Work",
        repoID: "website",
        paneTemplateID: "work-stack",
        itermProfileName: "Maestro Work",
        startupCommands: startupCommands
      )
    ]
    config.screenLayouts.append(ScreenLayout(
      id: "profile-left",
      label: "Profile Left",
      terminalHosts: [
        TerminalHost(
          id: "work-left",
          label: "Work Placement",
          terminalProfileID: "work",
          frame: PercentRect(x: 0, y: 0, width: 0.5, height: 1)
        )
      ]
    ))
    try expect(CommandCenterValidator().validate(config).ok, "terminal profile test config validates")
    return config
  }

  private static func temporaryStateStore() -> CommandCenterStateStore {
    CommandCenterStateStore(
      stateDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("maestro-core-checks-state-\(UUID().uuidString)")
    )
  }

  private static func temporaryDiagnosticsFile() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("maestro-core-checks-\(UUID().uuidString)")
      .appendingPathComponent("command-center.jsonl")
  }

  private static func temporaryConfigFile() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("maestro-core-checks-config-\(UUID().uuidString)")
      .appendingPathComponent("palette.json")
  }

  private static func diagnosticsLogContents(_ fileURL: URL) throws -> String {
    String(data: try Data(contentsOf: fileURL), encoding: .utf8) ?? ""
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

final class FakeCommandCenterAutomation: CommandCenterWindowAutomation, @unchecked Sendable {
  var taggedWindows: [TerminalWindowSnapshot]
  var createdHosts: [ResolvedTerminalHost] = []
  var createdAttachCommands: [String] = []
  var createdWindowID: String?
  var createdTargetID: String?
  var createdWindowIsTagged: Bool
  var focusedHostIDs: [String] = []
  var focusedWindowIDs: [String] = []
  var focusedAppTargetIDs: [String] = []
  var openedURLs: [(url: String, appTargetID: String?)] = []
  var openedRepos: [(path: String, appTargetID: String)] = []
  var movedFramesByHostID: [String: LayoutRect] = [:]
  var movedFramesByWindowID: [String: LayoutRect] = [:]
  var movedAppTargetIDs: [String] = []
  var movedFramesByAppTargetID: [String: LayoutRect] = [:]
  var terminalMoveFailuresByWindowID: [String: CommandCenterWindowMoveOutcome] = [:]
  var appMoveFailuresByTargetID: [String: CommandCenterWindowMoveOutcome] = [:]

  init(
    taggedWindows: [TerminalWindowSnapshot] = [],
    createdWindowID: String? = nil,
    createdTargetID: String? = nil,
    createdWindowIsTagged: Bool = true
  ) {
    self.taggedWindows = taggedWindows
    self.createdWindowID = createdWindowID
    self.createdTargetID = createdTargetID
    self.createdWindowIsTagged = createdWindowIsTagged
  }

  func activeScreen() -> LayoutScreen {
    LayoutScreen(
      id: "screen",
      name: "Screen",
      frame: LayoutRect(x: 0, y: 0, width: 1440, height: 900),
      visibleFrame: LayoutRect(x: 0, y: 0, width: 1440, height: 900)
    )
  }

  func taggedTerminalHostWindows() throws -> [TerminalWindowSnapshot] {
    taggedWindows
  }

  func createTerminalHostWindow(for host: ResolvedTerminalHost, attachCommand: String) throws -> TerminalWindowSnapshot {
    createdHosts.append(host)
    createdAttachCommands.append(attachCommand)
    let snapshot = TerminalWindowSnapshot(
      id: createdWindowID ?? "created-\(host.id)",
      targetID: createdWindowIsTagged ? (createdTargetID ?? host.id) : nil
    )
    if snapshot.targetID != nil {
      taggedWindows.append(snapshot)
    }
    return snapshot
  }

  func focusTerminalHostWindow(hostID: String) throws {
    focusedHostIDs.append(hostID)
  }

  func focusTerminalHostWindow(windowID: String) throws {
    focusedWindowIDs.append(windowID)
  }

  func moveTerminalHostWindows(_ framesByHostID: [String: LayoutRect]) throws {
    movedFramesByHostID.merge(framesByHostID, uniquingKeysWith: { _, new in new })
  }

  func moveTerminalHostWindowsByWindowID(_ framesByWindowID: [String: LayoutRect]) throws -> [CommandCenterTerminalWindowMoveReport] {
    movedFramesByWindowID.merge(framesByWindowID, uniquingKeysWith: { _, new in new })
    return framesByWindowID
      .sorted { $0.key < $1.key }
      .map { windowID, frame in
        CommandCenterTerminalWindowMoveReport(
          windowID: windowID,
          frame: frame,
          outcome: terminalMoveFailuresByWindowID[windowID] ?? .moved
        )
      }
  }

  func focusApp(_ appTarget: AppTarget) throws {
    focusedAppTargetIDs.append(appTarget.id)
  }

  func openURL(_ url: String, appTarget: AppTarget?) throws {
    openedURLs.append((url: url, appTargetID: appTarget?.id))
  }

  func openRepo(path: String, appTarget: AppTarget) throws {
    openedRepos.append((path: path, appTargetID: appTarget.id))
  }

  func moveAppWindows(_ framesByAppTargetID: [String: LayoutRect], appTargets: [AppTarget]) throws -> [CommandCenterAppWindowMoveReport] {
    movedFramesByAppTargetID.merge(framesByAppTargetID, uniquingKeysWith: { _, new in new })
    movedAppTargetIDs = appTargets.map(\.id)
    return appTargets.compactMap { appTarget in
      guard let frame = framesByAppTargetID[appTarget.id] else {
        return nil
      }
      return CommandCenterAppWindowMoveReport(
        appTargetID: appTarget.id,
        bundleID: appTarget.bundleID,
        frame: frame,
        outcome: appMoveFailuresByTargetID[appTarget.id] ?? .moved
      )
    }
  }
}
