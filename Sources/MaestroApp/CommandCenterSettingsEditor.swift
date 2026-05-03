import MaestroCore
import SwiftUI

struct SettingsTabs: View {
  @ObservedObject var model: CommandCenterViewModel
  var config: CommandCenterConfig

  @State private var sheet: CommandCenterSettingsSheet?
  @State private var showReloadConfirmation = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Settings")
            .font(.title3)
            .fontWeight(.semibold)
          Text(config.workspace.label)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          model.revertDraft()
        } label: {
          Label("Revert", systemImage: "arrow.uturn.backward")
        }
        .controlSize(.small)
        .disabled(!model.hasUnsavedChanges)

        Button {
          if model.hasUnsavedChanges {
            showReloadConfirmation = true
          } else {
            model.load()
          }
        } label: {
          Label("Reload", systemImage: "arrow.clockwise")
        }
        .controlSize(.small)

        Button {
          model.saveDraft()
        } label: {
          Label("Save", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(!model.hasUnsavedChanges || !model.validationResult.ok)
      }

      ValidationSummary(result: model.validationResult, hasUnsavedChanges: model.hasUnsavedChanges)

      TabView {
        SettingsCollection(
          title: "Repos",
          addTitle: "Repo",
          rows: config.repos.enumerated().map { index, repo in
            SettingsRowModel(
              rowID: "repo-\(index)-\(repo.id)",
              itemID: repo.id,
              title: repo.label,
              detail: repo.path,
              systemImage: "folder"
            )
          },
          add: { sheet = .repo(.add, defaultRepo(in: config)) },
          edit: { id in
            if let repo = config.repos.first(where: { $0.id == id }) {
              sheet = .repo(.edit(originalID: repo.id), repo)
            }
          },
          delete: { model.deleteRepo(id: $0) }
        )
        .tabItem { Label("Repos", systemImage: "folder") }

        SettingsCollection(
          title: "Pane Templates",
          addTitle: "Template",
          rows: config.paneTemplates.enumerated().map { index, template in
            SettingsRowModel(
              rowID: "pane-template-\(index)-\(template.id)",
              itemID: template.id,
              title: template.label,
              detail: "\(template.slots.count) slots",
              systemImage: "rectangle.split.2x1"
            )
          },
          add: { sheet = .paneTemplate(.add, defaultPaneTemplate(in: config)) },
          edit: { id in
            if let template = config.paneTemplates.first(where: { $0.id == id }) {
              sheet = .paneTemplate(.edit(originalID: template.id), template)
            }
          },
          delete: { model.deletePaneTemplate(id: $0) }
        )
        .tabItem { Label("Pane Templates", systemImage: "rectangle.split.2x1") }

        SettingsCollection(
          title: "Terminal Profiles",
          addTitle: "Profile",
          rows: (config.terminalProfiles ?? []).enumerated().map { index, profile in
            let commandCount = profile.startupCommands.count
            let detail = commandCount == 0 ? "Standard shell" : "\(commandCount) startup commands"
            return SettingsRowModel(
              rowID: "terminal-profile-\(index)-\(profile.id)",
              itemID: profile.id,
              title: profile.label,
              detail: detail,
              systemImage: "terminal"
            )
          },
          add: { sheet = .terminalProfile(.add, defaultTerminalProfile(in: config)) },
          edit: { id in
            if let profile = config.terminalProfiles?.first(where: { $0.id == id }) {
              sheet = .terminalProfile(.edit(originalID: profile.id), profile)
            }
          },
          delete: { model.deleteTerminalProfile(id: $0) }
        )
        .tabItem { Label("Terminal Profiles", systemImage: "terminal") }

        SettingsCollection(
          title: "Screen Layouts",
          addTitle: "Layout",
          rows: config.screenLayouts.enumerated().map { index, layout in
            SettingsRowModel(
              rowID: "screen-layout-\(index)-\(layout.id)",
              itemID: layout.id,
              title: layout.label,
              detail: "\(layout.terminalHosts.count) hosts, \(layout.appZones.count) app zones",
              systemImage: "rectangle.3.group"
            )
          },
          add: { sheet = .screenLayout(.add, defaultScreenLayout(in: config)) },
          edit: { id in
            if let layout = config.screenLayouts.first(where: { $0.id == id }) {
              sheet = .screenLayout(.edit(originalID: layout.id), layout)
            }
          },
          delete: { model.deleteScreenLayout(id: $0) }
        )
        .tabItem { Label("Screen Layouts", systemImage: "rectangle.3.group") }

        SettingsCollection(
          title: "Actions",
          addTitle: "Action",
          rows: config.actions.enumerated().map { index, action in
            SettingsRowModel(
              rowID: "action-\(index)-\(action.id)",
              itemID: action.id,
              title: action.label,
              detail: action.kind.displayName,
              systemImage: action.kind.systemImage
            )
          },
          add: { sheet = .action(.add, defaultAction(in: config), config.sections.first?.id) },
          edit: { id in
            if let action = config.actions.first(where: { $0.id == id }) {
              sheet = .action(.edit(originalID: action.id), action, model.sectionID(containing: action.id))
            }
          },
          delete: { model.deleteAction(id: $0) }
        )
        .tabItem { Label("Actions", systemImage: "bolt") }
      }
    }
    .sheet(item: $sheet) { activeSheet in
      switch activeSheet {
      case let .repo(mode, repo):
        RepoEditorSheet(mode: mode, repo: repo) {
          model.upsertRepo($0, replacing: mode.originalID)
        }
      case let .paneTemplate(mode, template):
        PaneTemplateEditorSheet(mode: mode, template: template, config: config) {
          model.upsertPaneTemplate($0, replacing: mode.originalID)
        }
      case let .terminalProfile(mode, profile):
        TerminalProfileEditorSheet(mode: mode, profile: profile, config: config) {
          model.upsertTerminalProfile($0, replacing: mode.originalID)
        }
      case let .screenLayout(mode, layout):
        ScreenLayoutEditorSheet(mode: mode, layout: layout, config: config) {
          model.upsertScreenLayout($0, replacing: mode.originalID)
        }
      case let .action(mode, action, sectionID):
        ActionEditorSheet(mode: mode, action: action, sectionID: sectionID, config: config) { action, sectionID in
          model.upsertAction(action, replacing: mode.originalID, sectionID: sectionID)
        }
      }
    }
    .alert("Discard unsaved settings?", isPresented: $showReloadConfirmation) {
      Button("Reload", role: .destructive) {
        model.load()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Reloading will replace the current draft with palette.json from disk.")
    }
  }
}

private struct ValidationSummary: View {
  var result: PaletteValidationResult
  var hasUnsavedChanges: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      if result.ok {
        Label(hasUnsavedChanges ? "Draft validates" : "Saved config validates", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
      } else {
        Label("\(result.issues.count) blocking issue\(result.issues.count == 1 ? "" : "s")", systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        ForEach(Array(result.issues.prefix(6).enumerated()), id: \.offset) { _, issue in
          Text(issue.message)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
    }
    .font(.caption)
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
    )
  }
}

private struct SettingsCollection: View {
  var title: String
  var addTitle: String
  var rows: [SettingsRowModel]
  var add: () -> Void
  var edit: (String) -> Void
  var delete: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(title)
          .font(.headline)
        Spacer()
        Button(action: add) {
          Label(addTitle, systemImage: "plus")
        }
        .controlSize(.small)
      }

      ScrollView {
        LazyVStack(spacing: 7) {
          ForEach(rows) { row in
            HStack(spacing: 9) {
              Image(systemName: row.systemImage)
                .frame(width: 20)
                .foregroundStyle(.secondary)
              VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                  .font(.callout)
                  .lineLimit(1)
                Text(row.detail)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
                  .truncationMode(.middle)
              }
              Spacer(minLength: 0)
              Button {
                edit(row.itemID)
              } label: {
                Image(systemName: "pencil")
              }
              .buttonStyle(.borderless)
              .help("Edit")
              Button {
                delete(row.itemID)
              } label: {
                Image(systemName: "trash")
              }
              .buttonStyle(.borderless)
              .foregroundStyle(.red)
              .help("Delete")
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
          }
        }
        .padding(.vertical, 2)
      }
    }
    .padding(10)
  }
}

private struct SettingsRowModel: Identifiable {
  var id: String
  var itemID: String
  var title: String
  var detail: String
  var systemImage: String

  init(rowID: String, itemID: String, title: String, detail: String, systemImage: String) {
    self.id = rowID
    self.itemID = itemID
    self.title = title
    self.detail = detail
    self.systemImage = systemImage
  }
}

private enum CommandCenterSettingsSheet: Identifiable {
  case repo(ConfigEditorMode, CommandRepo)
  case paneTemplate(ConfigEditorMode, PaneTemplate)
  case terminalProfile(ConfigEditorMode, TerminalProfile)
  case screenLayout(ConfigEditorMode, ScreenLayout)
  case action(ConfigEditorMode, CommandCenterAction, String?)

  var id: String {
    switch self {
    case let .repo(mode, repo):
      return "repo-\(mode.id)-\(repo.id)"
    case let .paneTemplate(mode, template):
      return "pane-template-\(mode.id)-\(template.id)"
    case let .terminalProfile(mode, profile):
      return "terminal-profile-\(mode.id)-\(profile.id)"
    case let .screenLayout(mode, layout):
      return "screen-layout-\(mode.id)-\(layout.id)"
    case let .action(mode, action, _):
      return "action-\(mode.id)-\(action.id)"
    }
  }
}

private enum ConfigEditorMode {
  case add
  case edit(originalID: String)

  var id: String {
    switch self {
    case .add:
      return "add"
    case let .edit(originalID):
      return "edit-\(originalID)"
    }
  }

  var originalID: String? {
    switch self {
    case .add:
      return nil
    case let .edit(originalID):
      return originalID
    }
  }

  var titlePrefix: String {
    switch self {
    case .add:
      return "Add"
    case .edit:
      return "Edit"
    }
  }
}

private struct RepoEditorSheet: View {
  var mode: ConfigEditorMode
  var save: (CommandRepo) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var repo: CommandRepo

  init(mode: ConfigEditorMode, repo: CommandRepo, save: @escaping (CommandRepo) -> Void) {
    self.mode = mode
    self.save = save
    _repo = State(initialValue: repo)
  }

  var body: some View {
    EditorSheetFrame(title: "\(mode.titlePrefix) Repo", canSave: repo.hasRequiredFields) {
      Form {
        TextField("ID", text: $repo.id)
        TextField("Label", text: $repo.label)
        TextField("Path", text: $repo.path)
      }
    } cancel: {
      dismiss()
    } save: {
      save(repo.normalized)
      dismiss()
    }
  }
}

private struct PaneTemplateEditorSheet: View {
  var mode: ConfigEditorMode
  var config: CommandCenterConfig
  var save: (PaneTemplate) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var template: PaneTemplate

  init(
    mode: ConfigEditorMode,
    template: PaneTemplate,
    config: CommandCenterConfig,
    save: @escaping (PaneTemplate) -> Void
  ) {
    self.mode = mode
    self.config = config
    self.save = save
    _template = State(initialValue: template)
  }

  var body: some View {
    EditorSheetFrame(title: "\(mode.titlePrefix) Pane Template", canSave: template.hasRequiredFields) {
      VStack(alignment: .leading, spacing: 12) {
        Form {
          TextField("ID", text: $template.id)
          TextField("Label", text: $template.label)
        }

        HStack {
          Text("Slots")
            .font(.headline)
          Spacer()
          Button {
            template.slots.append(defaultPaneSlot(in: config, existing: template.slots.map(\.id)))
          } label: {
            Label("Slot", systemImage: "plus")
          }
          .controlSize(.small)
        }

        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(template.slots.indices, id: \.self) { index in
              SlotEditorCard(
                slot: bindingForSlot(at: index),
                repos: config.repos,
                delete: {
                  template.slots.remove(at: index)
                }
              )
            }
          }
        }
        .frame(minHeight: 220)
      }
    } cancel: {
      dismiss()
    } save: {
      save(template.normalized)
      dismiss()
    }
    .frame(width: 620, height: 620)
  }

  private func bindingForSlot(at index: Int) -> Binding<PaneSlot> {
    Binding(
      get: { template.slots[index] },
      set: { template.slots[index] = $0 }
    )
  }
}

private struct SlotEditorCard: View {
  @Binding var slot: PaneSlot
  var repos: [CommandRepo]
  var delete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(slot.label.isEmpty ? slot.id : slot.label)
          .font(.callout)
          .fontWeight(.semibold)
        Spacer()
        Button(action: delete) {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.red)
      }
      Form {
        TextField("ID", text: $slot.id)
        TextField("Label", text: $slot.label)
        TextField("Role", text: $slot.role)
        Picker("Repo", selection: $slot.repoID) {
          Text("Profile repo").tag(Optional<String>.none)
          ForEach(repos) { repo in
            Text(repo.label).tag(Optional(repo.id))
          }
        }
      }
      PercentRectEditor(title: "Frame", rect: $slot.unit)
    }
    .padding(10)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }
}

private struct TerminalProfileEditorSheet: View {
  var mode: ConfigEditorMode
  var config: CommandCenterConfig
  var save: (TerminalProfile) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var profile: TerminalProfile

  init(
    mode: ConfigEditorMode,
    profile: TerminalProfile,
    config: CommandCenterConfig,
    save: @escaping (TerminalProfile) -> Void
  ) {
    self.mode = mode
    self.config = config
    self.save = save
    _profile = State(initialValue: profile)
  }

  var body: some View {
    EditorSheetFrame(title: "\(mode.titlePrefix) Terminal Profile", canSave: profile.hasRequiredFields) {
      VStack(alignment: .leading, spacing: 12) {
        Form {
          TextField("ID", text: $profile.id)
          TextField("Label", text: $profile.label)
          Picker("Repo", selection: $profile.repoID) {
            ForEach(config.repos) { repo in
              Text(repo.label).tag(repo.id)
            }
          }
          Picker("Pane Template", selection: $profile.paneTemplateID) {
            ForEach(config.paneTemplates) { template in
              Text(template.label).tag(template.id)
            }
          }
          TextField("iTerm Profile", text: optionalString($profile.itermProfileName))
        }

        HStack {
          Text("Startup")
            .font(.headline)
          Spacer()
          Button("Standard Shell") {
            profile.startupCommands = []
          }
          .controlSize(.small)
          Button {
            setStartupCommand(argv: ["codex"])
          } label: {
            Label("Run Codex", systemImage: "text.cursor")
          }
          .controlSize(.small)
          Button {
            setStartupCommand(argv: ["env", "CLOUDFLARE_ENV=staging", "npm", "run", "db:staging"])
          } label: {
            Label("DB Staging", systemImage: "server.rack")
          }
          .controlSize(.small)
          Button {
            profile.startupCommands.append(TerminalStartupCommand(slotID: firstSlotID, argv: ["codex"]))
          } label: {
            Image(systemName: "plus")
          }
          .controlSize(.small)
          .help("Add startup command")
        }

        ScrollView {
          VStack(alignment: .leading, spacing: 9) {
            ForEach(profile.startupCommands.indices, id: \.self) { index in
              StartupCommandCard(
                command: bindingForStartup(at: index),
                slots: selectedTemplate?.slots ?? [],
                delete: {
                  profile.startupCommands.remove(at: index)
                }
              )
            }
          }
        }
        .frame(minHeight: 200)
      }
    } cancel: {
      dismiss()
    } save: {
      save(profile.normalized)
      dismiss()
    }
    .frame(width: 620, height: 620)
  }

  private var selectedTemplate: PaneTemplate? {
    config.paneTemplates.first { $0.id == profile.paneTemplateID }
  }

  private var firstSlotID: String {
    selectedTemplate?.slots.first?.id ?? "main"
  }

  private func setStartupCommand(argv: [String]) {
    let slotID = profile.startupCommands.first?.slotID ?? firstSlotID
    profile.startupCommands = [TerminalStartupCommand(slotID: slotID, argv: argv)]
  }

  private func bindingForStartup(at index: Int) -> Binding<TerminalStartupCommand> {
    Binding(
      get: { profile.startupCommands[index] },
      set: { profile.startupCommands[index] = $0 }
    )
  }
}

private struct StartupCommandCard: View {
  @Binding var command: TerminalStartupCommand
  var slots: [PaneSlot]
  var delete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Picker("Slot", selection: $command.slotID) {
          ForEach(slots) { slot in
            Text(slot.label).tag(slot.id)
          }
          if !slots.contains(where: { $0.id == command.slotID }) {
            Text(command.slotID).tag(command.slotID)
          }
        }
        Spacer()
        Button(action: delete) {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.red)
      }
      ArgvEditor(title: "Argv", argv: $command.argv)
    }
    .padding(10)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }
}

private struct ScreenLayoutEditorSheet: View {
  var mode: ConfigEditorMode
  var config: CommandCenterConfig
  var save: (ScreenLayout) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var layout: ScreenLayout
  @State private var selection: LayoutElementSelection?

  init(
    mode: ConfigEditorMode,
    layout: ScreenLayout,
    config: CommandCenterConfig,
    save: @escaping (ScreenLayout) -> Void
  ) {
    self.mode = mode
    self.config = config
    self.save = save
    _layout = State(initialValue: layout)
    let firstSelection = layout.terminalHosts.first.map { LayoutElementSelection.terminalHost($0.id) }
      ?? layout.appZones.first.map { LayoutElementSelection.appZone($0.id) }
    _selection = State(initialValue: firstSelection)
  }

  var body: some View {
    EditorSheetFrame(title: "\(mode.titlePrefix) Screen Layout", canSave: layout.hasRequiredFields) {
      VStack(alignment: .leading, spacing: 12) {
        Form {
          TextField("ID", text: $layout.id)
          TextField("Label", text: $layout.label)
        }

        HStack(alignment: .top, spacing: 12) {
          EditableScreenMapView(layout: layout, config: config, selection: $selection)
            .frame(minWidth: 360, minHeight: 230)

          VStack(alignment: .leading, spacing: 10) {
            HStack {
              Button {
                let host = defaultTerminalHost(in: config, existing: layout.terminalHosts.map(\.id))
                layout.terminalHosts.append(host)
                selection = .terminalHost(host.id)
              } label: {
                Label("Host", systemImage: "plus")
              }
              .controlSize(.small)

              Button {
                let zone = defaultAppZone(in: config, existing: layout.appZones.map(\.id))
                layout.appZones.append(zone)
                selection = .appZone(zone.id)
              } label: {
                Label("Zone", systemImage: "plus")
              }
              .controlSize(.small)
            }

            Divider()

            if let selection {
              LayoutElementEditor(
                selection: selection,
                layout: $layout,
                selectedElement: $selection,
                config: config
              )
            } else {
              Text("No selection")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .frame(width: 300, alignment: .topLeading)
        }
      }
    } cancel: {
      dismiss()
    } save: {
      save(layout.normalized)
      dismiss()
    }
    .frame(width: 820, height: 660)
  }
}

private struct EditableScreenMapView: View {
  var layout: ScreenLayout
  var config: CommandCenterConfig
  @Binding var selection: LayoutElementSelection?

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72))
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)

        ForEach(layout.appZones) { zone in
          Button {
            selection = .appZone(zone.id)
          } label: {
            EditableAppZonePreview(
              zone: zone,
              size: size,
              selected: selection == .appZone(zone.id)
            )
          }
          .buttonStyle(.plain)
        }

        ForEach(layout.terminalHosts) { host in
          Button {
            selection = .terminalHost(host.id)
          } label: {
            EditableTerminalHostPreview(
              host: host,
              config: config,
              size: size,
              selected: selection == .terminalHost(host.id)
            )
          }
          .buttonStyle(.plain)
        }
      }
    }
    .aspectRatio(16 / 10, contentMode: .fit)
  }
}

private struct EditableAppZonePreview: View {
  var zone: AppZone
  var size: CGSize
  var selected: Bool

  var body: some View {
    ZoneRect(rect: zone.frame, in: size) {
      VStack(alignment: .leading, spacing: 3) {
        Label(zone.label, systemImage: "macwindow")
          .font(.caption)
          .fontWeight(.semibold)
        Text(zone.appTargetIDs.joined(separator: ", "))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .padding(7)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.78))
    .overlay(
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .stroke(selected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.6), lineWidth: selected ? 2 : 1)
    )
  }
}

private struct EditableTerminalHostPreview: View {
  var host: TerminalHost
  var config: CommandCenterConfig
  var size: CGSize
  var selected: Bool

  var body: some View {
    ZoneRect(rect: host.frame, in: size) {
      TerminalHostPreview(host: host, config: config)
    }
    .background(Color.accentColor.opacity(0.13))
    .overlay(
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .stroke(selected ? Color.accentColor : Color.accentColor.opacity(0.55), lineWidth: selected ? 2 : 1)
    )
  }
}

private struct LayoutElementEditor: View {
  var selection: LayoutElementSelection
  @Binding var layout: ScreenLayout
  @Binding var selectedElement: LayoutElementSelection?
  var config: CommandCenterConfig

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      switch selection {
      case let .terminalHost(id):
        if let index = layout.terminalHosts.firstIndex(where: { $0.id == id }) {
          terminalHostEditor(index: index)
        }
      case let .appZone(id):
        if let index = layout.appZones.firstIndex(where: { $0.id == id }) {
          appZoneEditor(index: index)
        }
      }
    }
  }

  private func terminalHostEditor(index: Int) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text("Terminal Host")
          .font(.headline)
        Spacer()
        Button {
          let id = layout.terminalHosts[index].id
          layout.terminalHosts.remove(at: index)
          selectedElement = layout.terminalHosts.first.map { .terminalHost($0.id) }
            ?? layout.appZones.first.map { .appZone($0.id) }
          _ = id
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.red)
      }
      Form {
        TextField("ID", text: hostIDBinding(index: index))
        TextField("Label", text: $layout.terminalHosts[index].label)
        Picker("Profile", selection: $layout.terminalHosts[index].terminalProfileID) {
          Text("Legacy repo/template").tag(Optional<String>.none)
          ForEach(config.terminalProfiles ?? []) { profile in
            Text(profile.label).tag(Optional(profile.id))
          }
        }
        if layout.terminalHosts[index].terminalProfileID == nil {
          Picker("Repo", selection: optionalStringID($layout.terminalHosts[index].repoID, fallback: config.repos.first?.id ?? "")) {
            ForEach(config.repos) { repo in
              Text(repo.label).tag(repo.id)
            }
          }
          Picker("Pane Template", selection: optionalStringID($layout.terminalHosts[index].paneTemplateID, fallback: config.paneTemplates.first?.id ?? "")) {
            ForEach(config.paneTemplates) { template in
              Text(template.label).tag(template.id)
            }
          }
        }
      }
      PercentRectEditor(title: "Frame", rect: $layout.terminalHosts[index].frame)
      QuickPresetBar(rect: $layout.terminalHosts[index].frame)
    }
  }

  private func appZoneEditor(index: Int) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text("App Zone")
          .font(.headline)
        Spacer()
        Button {
          layout.appZones.remove(at: index)
          selectedElement = layout.terminalHosts.first.map { .terminalHost($0.id) }
            ?? layout.appZones.first.map { .appZone($0.id) }
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.red)
      }
      Form {
        TextField("ID", text: appZoneIDBinding(index: index))
        TextField("Label", text: $layout.appZones[index].label)
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("Apps")
          .font(.caption)
          .foregroundStyle(.secondary)
        ForEach(config.appTargets) { app in
          Toggle(app.label, isOn: appTargetBinding(app.id, zoneIndex: index))
        }
      }
      PercentRectEditor(title: "Frame", rect: $layout.appZones[index].frame)
      QuickPresetBar(rect: $layout.appZones[index].frame)
    }
  }

  private func hostIDBinding(index: Int) -> Binding<String> {
    Binding(
      get: { layout.terminalHosts[index].id },
      set: {
        layout.terminalHosts[index].id = $0
        selectedElement = .terminalHost($0)
      }
    )
  }

  private func appZoneIDBinding(index: Int) -> Binding<String> {
    Binding(
      get: { layout.appZones[index].id },
      set: {
        layout.appZones[index].id = $0
        selectedElement = .appZone($0)
      }
    )
  }

  private func appTargetBinding(_ id: String, zoneIndex: Int) -> Binding<Bool> {
    Binding(
      get: { layout.appZones[zoneIndex].appTargetIDs.contains(id) },
      set: { enabled in
        if enabled {
          if !layout.appZones[zoneIndex].appTargetIDs.contains(id) {
            layout.appZones[zoneIndex].appTargetIDs.append(id)
          }
        } else {
          layout.appZones[zoneIndex].appTargetIDs.removeAll { $0 == id }
        }
      }
    )
  }
}

private enum LayoutElementSelection: Hashable {
  case terminalHost(String)
  case appZone(String)
}

private struct ActionEditorSheet: View {
  var mode: ConfigEditorMode
  var config: CommandCenterConfig
  var save: (CommandCenterAction, String?) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var action: CommandCenterAction
  @State private var sectionID: String?

  init(
    mode: ConfigEditorMode,
    action: CommandCenterAction,
    sectionID: String?,
    config: CommandCenterConfig,
    save: @escaping (CommandCenterAction, String?) -> Void
  ) {
    self.mode = mode
    self.config = config
    self.save = save
    _action = State(initialValue: action)
    _sectionID = State(initialValue: sectionID)
  }

  var body: some View {
    EditorSheetFrame(title: "\(mode.titlePrefix) Action", canSave: action.hasRequiredFields) {
      VStack(alignment: .leading, spacing: 12) {
        Form {
          TextField("ID", text: $action.id)
          TextField("Label", text: $action.label)
          Picker("Kind", selection: $action.kind) {
            ForEach(CommandCenterActionKind.allCases, id: \.self) { kind in
              Text(kind.displayName).tag(kind)
            }
          }
          Picker("Section", selection: $sectionID) {
            Text("None").tag(Optional<String>.none)
            ForEach(config.sections) { section in
              Text(section.label).tag(Optional(section.id))
            }
          }
        }

        Divider()

        actionSpecificFields
      }
    } cancel: {
      dismiss()
    } save: {
      save(action.normalized, sectionID)
      dismiss()
    }
    .frame(width: 600, height: 560)
    .onAppear {
      applyDefaults(for: action.kind)
    }
    .onChange(of: action.kind) { _, newKind in
      applyDefaults(for: newKind)
    }
  }

  @ViewBuilder
  private var actionSpecificFields: some View {
    switch action.kind {
    case .shellArgv:
      paneTargetFields
      ArgvEditor(title: "Argv", argv: optionalArgv($action.argv))
    case .stop, .codexPrompt:
      paneTargetFields
    case .openURL:
      Form {
        TextField("URL", text: optionalString($action.url))
        appTargetPicker(selection: $action.appTargetID, allowNone: true)
      }
    case .openRepoInEditor:
      Form {
        Picker("Repo", selection: optionalStringID($action.repoID, fallback: config.repos.first?.id ?? "")) {
          ForEach(config.repos) { repo in
            Text(repo.label).tag(repo.id)
          }
        }
        appTargetPicker(selection: $action.appTargetID, allowNone: false)
      }
    case .focusSurface:
      Form {
        hostPicker(selection: $action.hostID, allowNone: true)
        appTargetPicker(selection: $action.appTargetID, allowNone: true)
      }
    }
  }

  private var paneTargetFields: some View {
    Form {
      hostPicker(selection: $action.hostID, allowNone: false)
      Picker("Slot", selection: optionalStringID($action.slotID, fallback: firstSlotID(for: action.hostID, in: config))) {
        ForEach(slotOptions(for: action.hostID, in: config), id: \.self) { slotID in
          Text(slotID).tag(slotID)
        }
      }
    }
  }

  private func hostPicker(selection: Binding<String?>, allowNone: Bool) -> some View {
    Picker("Host", selection: selection) {
      if allowNone {
        Text("None").tag(Optional<String>.none)
      }
      ForEach(hostOptions(in: config), id: \.self) { hostID in
        Text(hostID).tag(Optional(hostID))
      }
    }
  }

  private func appTargetPicker(selection: Binding<String?>, allowNone: Bool) -> some View {
    Picker("App", selection: selection) {
      if allowNone {
        Text("None").tag(Optional<String>.none)
      }
      ForEach(config.appTargets) { app in
        Text(app.label).tag(Optional(app.id))
      }
    }
  }

  private func applyDefaults(for kind: CommandCenterActionKind) {
    switch kind {
    case .shellArgv:
      ensurePaneTarget()
      if action.argv?.isEmpty ?? true {
        action.argv = ["codex"]
      }
    case .stop, .codexPrompt:
      ensurePaneTarget()
      action.argv = nil
    case .openURL:
      action.hostID = nil
      action.slotID = nil
      action.repoID = nil
      action.argv = nil
    case .openRepoInEditor:
      action.hostID = nil
      action.slotID = nil
      action.url = nil
      action.argv = nil
      if action.repoID == nil {
        action.repoID = config.repos.first?.id
      }
      if action.appTargetID == nil {
        action.appTargetID = config.appTargets.first(where: { $0.role == .editor })?.id ?? config.appTargets.first?.id
      }
    case .focusSurface:
      action.slotID = nil
      action.repoID = nil
      action.url = nil
      action.argv = nil
      if action.hostID == nil && action.appTargetID == nil {
        action.hostID = hostOptions(in: config).first
      }
    }
  }

  private func ensurePaneTarget() {
    if action.hostID == nil {
      action.hostID = hostOptions(in: config).first
    }
    if action.slotID == nil {
      action.slotID = firstSlotID(for: action.hostID, in: config)
    }
    action.appTargetID = nil
    action.repoID = nil
    action.url = nil
  }
}

private struct EditorSheetFrame<Content: View>: View {
  var title: String
  var canSave: Bool
  @ViewBuilder var content: Content
  var cancel: () -> Void
  var save: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(title)
        .font(.title3)
        .fontWeight(.semibold)
      content
      Spacer(minLength: 0)
      HStack {
        Spacer()
        Button("Cancel", action: cancel)
        Button("Save", action: save)
          .buttonStyle(.borderedProminent)
          .disabled(!canSave)
      }
    }
    .padding(16)
    .frame(minWidth: 460, minHeight: 260)
  }
}

private struct PercentRectEditor: View {
  var title: String
  @Binding var rect: PercentRect

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(spacing: 8) {
        DecimalField(label: "X", value: $rect.x)
        DecimalField(label: "Y", value: $rect.y)
        DecimalField(label: "W", value: $rect.width)
        DecimalField(label: "H", value: $rect.height)
      }
    }
  }
}

private struct DecimalField: View {
  var label: String
  @Binding var value: Double

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
      TextField(label, value: $value, format: .number.precision(.fractionLength(0...4)))
        .textFieldStyle(.roundedBorder)
        .frame(width: 66)
    }
  }
}

private struct QuickPresetBar: View {
  @Binding var rect: PercentRect

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Presets")
        .font(.caption)
        .foregroundStyle(.secondary)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 6)], spacing: 6) {
        ForEach(LayoutQuickPreset.allCases) { preset in
          Button(preset.title) {
            rect = preset.rect
          }
          .controlSize(.small)
        }
      }
    }
  }
}

private enum LayoutQuickPreset: String, CaseIterable, Identifiable {
  case full
  case leftThird
  case rightThird
  case leftHalf
  case rightHalf
  case topHalf
  case bottomHalf

  var id: String { rawValue }

  var title: String {
    switch self {
    case .full:
      return "Full"
    case .leftThird:
      return "Left Third"
    case .rightThird:
      return "Right Third"
    case .leftHalf:
      return "Left Half"
    case .rightHalf:
      return "Right Half"
    case .topHalf:
      return "Top Half"
    case .bottomHalf:
      return "Bottom Half"
    }
  }

  var rect: PercentRect {
    switch self {
    case .full:
      return PercentRect(x: 0, y: 0, width: 1, height: 1)
    case .leftThird:
      return PercentRect(x: 0, y: 0, width: 1.0 / 3.0, height: 1)
    case .rightThird:
      return PercentRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 1)
    case .leftHalf:
      return PercentRect(x: 0, y: 0, width: 0.5, height: 1)
    case .rightHalf:
      return PercentRect(x: 0.5, y: 0, width: 0.5, height: 1)
    case .topHalf:
      return PercentRect(x: 0, y: 0, width: 1, height: 0.5)
    case .bottomHalf:
      return PercentRect(x: 0, y: 0.5, width: 1, height: 0.5)
    }
  }
}

private struct ArgvEditor: View {
  var title: String
  @Binding var argv: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      TextEditor(text: Binding(
        get: { argv.joined(separator: "\n") },
        set: {
          argv = $0
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        }
      ))
      .font(.system(.caption, design: .monospaced))
      .frame(minHeight: 78)
      .overlay(
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
      )
    }
  }
}

private func optionalString(_ value: Binding<String?>) -> Binding<String> {
  Binding(
    get: { value.wrappedValue ?? "" },
    set: {
      let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
      value.wrappedValue = trimmed.isEmpty ? nil : trimmed
    }
  )
}

private func optionalStringID(_ value: Binding<String?>, fallback: String) -> Binding<String> {
  Binding(
    get: { value.wrappedValue ?? fallback },
    set: { value.wrappedValue = $0.isEmpty ? nil : $0 }
  )
}

private func optionalArgv(_ value: Binding<[String]?>) -> Binding<[String]> {
  Binding(
    get: { value.wrappedValue ?? [] },
    set: { value.wrappedValue = $0.isEmpty ? nil : $0 }
  )
}

private func defaultRepo(in config: CommandCenterConfig) -> CommandRepo {
  let id = uniqueID(base: "new-repo", existing: config.repos.map(\.id))
  return CommandRepo(id: id, label: "New Repo", path: "~/Documents/Coding/\(id)")
}

private func defaultPaneTemplate(in config: CommandCenterConfig) -> PaneTemplate {
  let id = uniqueID(base: "new-template", existing: config.paneTemplates.map(\.id))
  return PaneTemplate(id: id, label: "New Template", slots: [
    PaneSlot(
      id: "main",
      label: "Main",
      role: "shell",
      unit: PercentRect(x: 0, y: 0, width: 1, height: 1),
      repoID: config.repos.first?.id
    )
  ])
}

private func defaultPaneSlot(in config: CommandCenterConfig, existing: [String]) -> PaneSlot {
  PaneSlot(
    id: uniqueID(base: "slot", existing: existing),
    label: "Slot",
    role: "shell",
    unit: PercentRect(x: 0, y: 0, width: 1, height: 1),
    repoID: config.repos.first?.id
  )
}

private func defaultTerminalProfile(in config: CommandCenterConfig) -> TerminalProfile {
  let id = uniqueID(base: "new-profile", existing: config.terminalProfiles?.map(\.id) ?? [])
  return TerminalProfile(
    id: id,
    label: "New Profile",
    repoID: config.repos.first?.id ?? "",
    paneTemplateID: config.paneTemplates.first?.id ?? ""
  )
}

private func defaultScreenLayout(in config: CommandCenterConfig) -> ScreenLayout {
  let id = uniqueID(base: "new-layout", existing: config.screenLayouts.map(\.id))
  return ScreenLayout(
    id: id,
    label: "New Layout",
    terminalHosts: [
      defaultTerminalHost(in: config, existing: [])
    ]
  )
}

private func defaultTerminalHost(in config: CommandCenterConfig, existing: [String]) -> TerminalHost {
  let id = uniqueID(base: "main", existing: existing)
  if let profile = config.terminalProfiles?.first {
    return TerminalHost(
      id: id,
      label: profile.label,
      terminalProfileID: profile.id,
      frame: PercentRect(x: 0, y: 0, width: 1, height: 1)
    )
  }
  return TerminalHost(
    id: id,
    label: "Main Terminal",
    repoID: config.repos.first?.id,
    paneTemplateID: config.paneTemplates.first?.id,
    frame: PercentRect(x: 0, y: 0, width: 1, height: 1)
  )
}

private func defaultAppZone(in config: CommandCenterConfig, existing: [String]) -> AppZone {
  AppZone(
    id: uniqueID(base: "apps", existing: existing),
    label: "Apps",
    frame: PercentRect(x: 0.5, y: 0, width: 0.5, height: 1),
    appTargetIDs: config.appTargets.first.map { [$0.id] } ?? []
  )
}

private func defaultAction(in config: CommandCenterConfig) -> CommandCenterAction {
  let id = uniqueID(base: "new.action", existing: config.actions.map(\.id))
  let target = firstPaneTarget(in: config)
  return CommandCenterAction(
    id: id,
    label: "New Action",
    kind: .shellArgv,
    hostID: target.hostID,
    slotID: target.slotID,
    argv: ["codex"]
  )
}

private func uniqueID(base: String, existing: [String]) -> String {
  let existing = Set(existing)
  if !existing.contains(base) {
    return base
  }
  var suffix = 2
  while existing.contains("\(base)-\(suffix)") {
    suffix += 1
  }
  return "\(base)-\(suffix)"
}

private func firstPaneTarget(in config: CommandCenterConfig) -> (hostID: String?, slotID: String?) {
  guard let host = config.screenLayouts.first?.terminalHosts.first else {
    return (nil, nil)
  }
  let hostID = host.terminalProfileID ?? host.id
  return (hostID, firstSlotID(for: hostID, in: config))
}

private func hostOptions(in config: CommandCenterConfig) -> [String] {
  var values: [String] = []
  for host in config.screenLayouts.flatMap(\.terminalHosts) {
    appendUnique(host.id, to: &values)
    appendUnique(host.effectiveTerminalProfileID, to: &values)
  }
  return values
}

private func slotOptions(for hostID: String?, in config: CommandCenterConfig) -> [String] {
  guard let hostID else {
    return []
  }
  var values: [String] = []
  for layout in config.screenLayouts {
    for host in layout.terminalHosts where host.id == hostID || host.effectiveTerminalProfileID == hostID {
      let profile = try? CommandCenterTerminalProfileResolver().profile(for: host, in: config)
      let templateID = profile?.paneTemplateID ?? host.paneTemplateID
      guard let templateID,
            let template = config.paneTemplates.first(where: { $0.id == templateID }) else {
        continue
      }
      for slot in template.slots {
        appendUnique(slot.id, to: &values)
      }
    }
  }
  return values
}

private func firstSlotID(for hostID: String?, in config: CommandCenterConfig) -> String {
  slotOptions(for: hostID, in: config).first ?? "main"
}

private func appendUnique(_ value: String, to values: inout [String]) {
  guard !value.isEmpty, !values.contains(value) else {
    return
  }
  values.append(value)
}

private extension CommandRepo {
  var hasRequiredFields: Bool {
    !id.trimmed.isEmpty && !label.trimmed.isEmpty && !path.trimmed.isEmpty
  }

  var normalized: CommandRepo {
    CommandRepo(id: id.trimmed, label: label.trimmed, path: path.trimmed)
  }
}

private extension PaneTemplate {
  var hasRequiredFields: Bool {
    !id.trimmed.isEmpty && !label.trimmed.isEmpty
  }

  var normalized: PaneTemplate {
    PaneTemplate(
      id: id.trimmed,
      label: label.trimmed,
      slots: slots.map(\.normalized)
    )
  }
}

private extension PaneSlot {
  var normalized: PaneSlot {
    PaneSlot(
      id: id.trimmed,
      label: label.trimmed,
      role: role.trimmed,
      unit: unit,
      repoID: repoID?.trimmed.nilIfEmpty
    )
  }
}

private extension TerminalProfile {
  var hasRequiredFields: Bool {
    !id.trimmed.isEmpty && !label.trimmed.isEmpty && !repoID.trimmed.isEmpty && !paneTemplateID.trimmed.isEmpty
  }

  var normalized: TerminalProfile {
    TerminalProfile(
      id: id.trimmed,
      label: label.trimmed,
      repoID: repoID.trimmed,
      paneTemplateID: paneTemplateID.trimmed,
      itermProfileName: itermProfileName?.trimmed.nilIfEmpty,
      startupCommands: startupCommands
        .map { TerminalStartupCommand(slotID: $0.slotID.trimmed, argv: $0.argv.map(\.trimmed).filter { !$0.isEmpty }) }
    )
  }
}

private extension ScreenLayout {
  var hasRequiredFields: Bool {
    !id.trimmed.isEmpty && !label.trimmed.isEmpty
  }

  var normalized: ScreenLayout {
    ScreenLayout(
      id: id.trimmed,
      label: label.trimmed,
      terminalHosts: terminalHosts.map(\.normalized),
      appZones: appZones.map(\.normalized)
    )
  }
}

private extension TerminalHost {
  var normalized: TerminalHost {
    TerminalHost(
      id: id.trimmed,
      label: label.trimmed,
      repoID: repoID?.trimmed.nilIfEmpty,
      paneTemplateID: paneTemplateID?.trimmed.nilIfEmpty,
      terminalProfileID: terminalProfileID?.trimmed.nilIfEmpty,
      frame: frame,
      sessionStrategy: sessionStrategy
    )
  }
}

private extension AppZone {
  var normalized: AppZone {
    AppZone(
      id: id.trimmed,
      label: label.trimmed,
      frame: frame,
      appTargetIDs: appTargetIDs.map(\.trimmed).filter { !$0.isEmpty }
    )
  }
}

private extension CommandCenterAction {
  var hasRequiredFields: Bool {
    !id.trimmed.isEmpty && !label.trimmed.isEmpty
  }

  var normalized: CommandCenterAction {
    let cleanHostID = hostID?.trimmed.nilIfEmpty
    let cleanSlotID = slotID?.trimmed.nilIfEmpty
    let cleanAppTargetID = appTargetID?.trimmed.nilIfEmpty
    let cleanRepoID = repoID?.trimmed.nilIfEmpty
    let cleanURL = url?.trimmed.nilIfEmpty
    let cleanArgv = argv?.map(\.trimmed).filter { !$0.isEmpty }.nilIfEmpty

    switch kind {
    case .shellArgv:
      return CommandCenterAction(
        id: id.trimmed,
        label: label.trimmed,
        kind: kind,
        hostID: cleanHostID,
        slotID: cleanSlotID,
        argv: cleanArgv
      )
    case .stop, .codexPrompt:
      return CommandCenterAction(
        id: id.trimmed,
        label: label.trimmed,
        kind: kind,
        hostID: cleanHostID,
        slotID: cleanSlotID
      )
    case .openURL:
      return CommandCenterAction(
        id: id.trimmed,
        label: label.trimmed,
        kind: kind,
        appTargetID: cleanAppTargetID,
        url: cleanURL
      )
    case .openRepoInEditor:
      return CommandCenterAction(
        id: id.trimmed,
        label: label.trimmed,
        kind: kind,
        appTargetID: cleanAppTargetID,
        repoID: cleanRepoID
      )
    case .focusSurface:
      return CommandCenterAction(
        id: id.trimmed,
        label: label.trimmed,
        kind: kind,
        hostID: cleanHostID,
        appTargetID: cleanAppTargetID
      )
    }
  }
}

private extension CommandCenterActionKind {
  var displayName: String {
    switch self {
    case .shellArgv:
      return "Shell Argv"
    case .stop:
      return "Stop"
    case .openURL:
      return "Open URL"
    case .openRepoInEditor:
      return "Open Repo"
    case .focusSurface:
      return "Focus"
    case .codexPrompt:
      return "Codex Prompt"
    }
  }

  var systemImage: String {
    switch self {
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

private extension String {
  var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}

private extension Array where Element == String {
  var nilIfEmpty: [String]? {
    isEmpty ? nil : self
  }
}
