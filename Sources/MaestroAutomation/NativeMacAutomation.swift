#if os(macOS)
import AppKit
import Foundation
import MaestroCore

public struct NativeMacAutomation: PaletteWindowAutomation, CommandCenterWindowAutomation {
  public static let iTermBundleIdentifier = "com.googlecode.iterm2"
  public static let targetVariable = "user.maestroTargetID"
  public static let hostVariable = "user.maestroHostID"
  public static let sessionVariable = "user.maestroSession"
  public static let windowVariable = "user.maestroWindow"
  public static let paneVariable = "user.maestroPane"

  public var diagnostics: MaestroDiagnostics
  private var appleScriptRunner: @Sendable (_ source: String, _ operation: String) throws -> String
  private var launchIterm: @Sendable () -> Void
  private var terminalHostWindowRecoveryTimeout: TimeInterval

  public init(diagnostics: MaestroDiagnostics = .disabled) {
    self.diagnostics = diagnostics
    appleScriptRunner = { source, operation in
      try Self.executeAppleScript(source: source, operation: operation)
    }
    launchIterm = {
      Self.defaultLaunchItermIfNeeded()
    }
    terminalHostWindowRecoveryTimeout = 5
  }

  package init(
    diagnostics: MaestroDiagnostics = .disabled,
    appleScriptRunner: @escaping @Sendable (_ source: String, _ operation: String) throws -> String,
    launchIterm: @escaping @Sendable () -> Void = {
      Self.defaultLaunchItermIfNeeded()
    },
    terminalHostWindowRecoveryTimeout: TimeInterval = 5
  ) {
    self.diagnostics = diagnostics
    self.appleScriptRunner = appleScriptRunner
    self.launchIterm = launchIterm
    self.terminalHostWindowRecoveryTimeout = terminalHostWindowRecoveryTimeout
  }

  public func activeScreen() -> LayoutScreen {
    guard let screen = screenUnderMouse() ?? NSScreen.main ?? NSScreen.screens.first else {
      return LayoutScreen(
        id: "fallback",
        name: "Fallback Display",
        frame: LayoutRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: LayoutRect(x: 0, y: 0, width: 1440, height: 900)
      )
    }
    return layoutScreen(for: screen)
  }

  public func taggedTerminalWindows() throws -> [TerminalWindowSnapshot] {
    let output = try runAppleScript(taggedWindowsScript(), operation: "tagged_terminal_windows")
    guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return []
    }

    return output
      .split(separator: "\n", omittingEmptySubsequences: true)
      .compactMap { line in
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 6,
              let x = Double(fields[2]),
              let y = Double(fields[3]),
              let right = Double(fields[4]),
              let bottom = Double(fields[5]) else {
          return nil
        }
        return TerminalWindowSnapshot(
          id: fields[0],
          targetID: fields[1].isEmpty ? nil : fields[1],
          frame: LayoutRect(x: x, y: y, width: right - x, height: bottom - y)
        )
      }
  }

  public func createTerminalWindow(for target: ResolvedTerminalTarget, attachCommand: String) throws {
    launchItermIfNeeded()
    _ = try runAppleScript(createWindowScript(target: target, attachCommand: attachCommand), operation: "create_terminal_window")
  }

  public func focusTerminalWindow(targetID: String) throws {
    launchItermIfNeeded()
    _ = try runAppleScript(focusWindowScript(targetID: targetID), operation: "focus_terminal_window")
  }

  public func moveTerminalWindows(_ framesByTargetID: [String: LayoutRect]) throws {
    guard !framesByTargetID.isEmpty else {
      return
    }
    _ = try runAppleScript(moveWindowsScript(framesByTargetID: framesByTargetID), operation: "move_terminal_windows")
  }

  public func taggedTerminalHostWindows() throws -> [TerminalWindowSnapshot] {
    let output = try runAppleScript(taggedHostWindowsScript(), operation: "tagged_terminal_host_windows")
    guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return []
    }

    return output
      .split(separator: "\n", omittingEmptySubsequences: true)
      .compactMap { line in
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 6,
              let x = Double(fields[2]),
              let y = Double(fields[3]),
              let right = Double(fields[4]),
              let bottom = Double(fields[5]) else {
          return nil
        }
        return TerminalWindowSnapshot(
          id: fields[0],
          targetID: fields[1].isEmpty ? nil : fields[1],
          frame: LayoutRect(x: x, y: y, width: right - x, height: bottom - y)
        )
      }
  }

  public func createTerminalHostWindow(for host: ResolvedTerminalHost, attachCommand: String) throws -> TerminalWindowSnapshot {
    launchItermIfNeeded()
    let operation = "create_terminal_host_window"
    let beforeInventory = try terminalHostWindowInventory()
    let output = try runAppleScript(createHostWindowScript(host: host, attachCommand: attachCommand), operation: operation)
    do {
      return try parseTerminalWindowSnapshot(output, operation: operation)
    } catch {
      emitUnexpectedAppleScriptOutput(output, operation: operation)
      if let window = try recoverTerminalHostWindowAfterMalformedCreate(
        host: host,
        beforeInventory: beforeInventory
      ) {
        return window
      }
      throw error
    }
  }

  public func focusTerminalHostWindow(hostID: String) throws {
    launchItermIfNeeded()
    _ = try runAppleScript(focusHostWindowScript(hostID: hostID), operation: "focus_terminal_host_window")
  }

  public func focusTerminalHostWindow(windowID: String) throws {
    launchItermIfNeeded()
    _ = try runAppleScript(focusHostWindowScript(windowID: windowID), operation: "focus_terminal_host_window_by_id")
  }

  public func moveTerminalHostWindows(_ framesByHostID: [String: LayoutRect]) throws {
    guard !framesByHostID.isEmpty else {
      return
    }
    _ = try runAppleScript(moveHostWindowsScript(framesByHostID: framesByHostID), operation: "move_terminal_host_windows")
  }

  public func moveTerminalHostWindowsByWindowID(_ framesByWindowID: [String: LayoutRect]) throws -> [CommandCenterTerminalWindowMoveReport] {
    guard !framesByWindowID.isEmpty else {
      return []
    }
    let output = try runAppleScript(moveHostWindowsByIDScript(framesByWindowID: framesByWindowID), operation: "move_terminal_host_windows_by_id")
    return parseTerminalMoveReports(output, expectedFramesByWindowID: framesByWindowID)
  }

  public func focusApp(_ appTarget: AppTarget) throws {
    let url = try applicationURL(for: appTarget, fallbackURL: nil, operation: "focus_app")
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
  }

  public func openURL(_ url: String, appTarget: AppTarget?) throws {
    guard let targetURL = URL(string: url) else {
      emitInvalidURL(url, operation: "open_url")
      throw NativeMacAutomationError.invalidURL(url)
    }
    if let appTarget {
      let appURL = try applicationURL(for: appTarget, fallbackURL: url, operation: "open_url")
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.open([targetURL], withApplicationAt: appURL, configuration: configuration) { _, _ in }
    } else {
      NSWorkspace.shared.open(targetURL)
    }
  }

  public func openRepo(path: String, appTarget: AppTarget) throws {
    let appURL = try applicationURL(for: appTarget, fallbackURL: nil, operation: "open_repo")
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: appURL, configuration: configuration) { _, _ in }
  }

  public func moveAppWindows(_ framesByAppTargetID: [String: LayoutRect], appTargets: [AppTarget]) throws -> [CommandCenterAppWindowMoveReport] {
    guard !framesByAppTargetID.isEmpty else {
      return []
    }
    let targets = appTargets.filter { framesByAppTargetID[$0.id] != nil }
    guard !targets.isEmpty else {
      return []
    }
    var reports: [CommandCenterAppWindowMoveReport] = []
    for appTarget in targets {
      guard let frame = framesByAppTargetID[appTarget.id] else {
        continue
      }
      let bundleID: String
      do {
        bundleID = try resolvedBundleID(for: appTarget, fallbackURL: appTarget.defaultURL, operation: "move_app_windows")
      } catch let error as NativeMacAutomationError {
        reports.append(appMoveFailureReport(appTarget: appTarget, bundleID: nil, frame: frame, error: error))
        continue
      }

      do {
        let output = try runAppleScript(moveAppWindowScript(bundleID: bundleID, frame: frame), operation: "move_app_window")
        reports.append(parseAppMoveReport(
          output,
          appTarget: appTarget,
          bundleID: bundleID,
          frame: frame
        ))
      } catch {
        reports.append(CommandCenterAppWindowMoveReport(
          appTargetID: appTarget.id,
          bundleID: bundleID,
          frame: frame,
          outcome: .moveRejected,
          message: MaestroDiagnostics.safeSummary(error.localizedDescription)
        ))
      }
    }
    return reports
  }

  private func parseTerminalWindowSnapshot(_ output: String, operation: String) throws -> TerminalWindowSnapshot {
    let fields = output.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "\t", omittingEmptySubsequences: false)
      .map(String.init)
    guard fields.count >= 6,
          let x = Double(fields[2]),
          let y = Double(fields[3]),
          let right = Double(fields[4]),
          let bottom = Double(fields[5]) else {
      throw NativeMacAutomationError.appleScriptFailed("Unexpected \(operation) result.")
    }
    return TerminalWindowSnapshot(
      id: fields[0],
      targetID: fields[1].isEmpty ? nil : fields[1],
      frame: LayoutRect(x: x, y: y, width: right - x, height: bottom - y)
    )
  }

  private struct TerminalHostWindowInventoryItem: Equatable {
    var windowID: String
    var alternateIdentifier: String
    var currentSessionID: String
    var hostID: String?
    var isVisible: Bool
    var isMinimized: Bool
    var frame: LayoutRect?

    var identityKeys: Set<String> {
      var keys = Set<String>()
      if !windowID.isEmpty {
        keys.insert("window:\(windowID)")
      }
      if !alternateIdentifier.isEmpty {
        keys.insert("alternate:\(alternateIdentifier)")
      }
      if !currentSessionID.isEmpty {
        keys.insert("session:\(currentSessionID)")
      }
      return keys
    }

    var snapshot: TerminalWindowSnapshot? {
      guard !windowID.isEmpty else {
        return nil
      }
      return TerminalWindowSnapshot(
        id: windowID,
        targetID: hostID,
        frame: frame,
        isVisible: isVisible,
        isMinimized: isMinimized
      )
    }
  }

  private func terminalHostWindowInventory() throws -> [TerminalHostWindowInventoryItem] {
    let output = try runAppleScript(
      terminalHostWindowInventoryScript(),
      operation: "terminal_host_window_inventory"
    )
    return parseTerminalHostWindowInventory(output)
  }

  private func parseTerminalHostWindowInventory(_ output: String) -> [TerminalHostWindowInventoryItem] {
    output
      .split(separator: "\n", omittingEmptySubsequences: true)
      .compactMap { line in
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 10 else {
          return nil
        }

        let frame: LayoutRect?
        if let x = Double(fields[6]),
           let y = Double(fields[7]),
           let right = Double(fields[8]),
           let bottom = Double(fields[9]) {
          frame = LayoutRect(x: x, y: y, width: right - x, height: bottom - y)
        } else {
          frame = nil
        }

        return TerminalHostWindowInventoryItem(
          windowID: fields[0],
          alternateIdentifier: fields[1],
          currentSessionID: fields[2],
          hostID: fields[3].isEmpty ? nil : fields[3],
          isVisible: parseAppleScriptBool(fields[4]) ?? true,
          isMinimized: parseAppleScriptBool(fields[5]) ?? false,
          frame: frame
        )
      }
  }

  private func parseAppleScriptBool(_ value: String) -> Bool? {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "true", "yes", "1":
      return true
    case "false", "no", "0":
      return false
    default:
      return nil
    }
  }

  private func parseTerminalMoveReports(
    _ output: String,
    expectedFramesByWindowID: [String: LayoutRect]
  ) -> [CommandCenterTerminalWindowMoveReport] {
    output
      .split(separator: "\n", omittingEmptySubsequences: true)
      .compactMap { line -> CommandCenterTerminalWindowMoveReport? in
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 2,
              let frame = expectedFramesByWindowID[fields[0]] else {
          return nil
        }
        return CommandCenterTerminalWindowMoveReport(
          windowID: fields[0],
          frame: frame,
          outcome: CommandCenterWindowMoveOutcome(rawValue: fields[1]) ?? .moveRejected,
          message: fields.indices.contains(2) && !fields[2].isEmpty ? fields[2] : nil
        )
      }
  }

  private func parseAppMoveReport(
    _ output: String,
    appTarget: AppTarget,
    bundleID: String,
    frame: LayoutRect
  ) -> CommandCenterAppWindowMoveReport {
    let fields = output.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "\t", omittingEmptySubsequences: false)
      .map(String.init)
    guard fields.count >= 2 else {
      return CommandCenterAppWindowMoveReport(
        appTargetID: appTarget.id,
        bundleID: bundleID,
        frame: frame,
        outcome: .missingReport,
        message: "move operation returned no report"
      )
    }
    return CommandCenterAppWindowMoveReport(
      appTargetID: appTarget.id,
      bundleID: bundleID,
      frame: frame,
      outcome: CommandCenterWindowMoveOutcome(rawValue: fields[1]) ?? .moveRejected,
      message: fields.indices.contains(2) && !fields[2].isEmpty ? fields[2] : nil
    )
  }

  private func appMoveFailureReport(
    appTarget: AppTarget,
    bundleID: String?,
    frame: LayoutRect,
    error: NativeMacAutomationError
  ) -> CommandCenterAppWindowMoveReport {
    let outcome: CommandCenterWindowMoveOutcome
    switch error {
    case .applicationNotFound:
      outcome = .applicationNotFound
    default:
      outcome = .moveRejected
    }
    return CommandCenterAppWindowMoveReport(
      appTargetID: appTarget.id,
      bundleID: bundleID,
      frame: frame,
      outcome: outcome,
      message: error.localizedDescription
    )
  }

  private func applicationURL(for appTarget: AppTarget, fallbackURL: String?, operation: String) throws -> URL {
    if appTarget.useSystemDefaultBrowser {
      let urlString = fallbackURL ?? appTarget.defaultURL ?? ""
      guard let targetURL = URL(string: urlString) else {
        emitInvalidURL(urlString, operation: operation)
        throw NativeMacAutomationError.invalidURL(urlString)
      }
      guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: targetURL) else {
        emitMissingApplication(bundleID: "system-default-browser", operation: operation)
        throw NativeMacAutomationError.applicationNotFound("system-default-browser")
      }
      return appURL
    }

    guard let bundleID = appTarget.bundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
          !bundleID.isEmpty,
          let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      emitMissingApplication(bundleID: appTarget.bundleID ?? appTarget.id, operation: operation)
      throw NativeMacAutomationError.applicationNotFound(appTarget.bundleID ?? appTarget.id)
    }
    return appURL
  }

  private func resolvedBundleID(for appTarget: AppTarget, fallbackURL: String?, operation: String) throws -> String {
    let appURL = try applicationURL(for: appTarget, fallbackURL: fallbackURL, operation: operation)
    if let bundleID = Bundle(url: appURL)?.bundleIdentifier {
      return bundleID
    }
    throw NativeMacAutomationError.applicationNotFound(appTarget.id)
  }

  private func screenUnderMouse() -> NSScreen? {
    let location = NSEvent.mouseLocation
    return NSScreen.screens.first { $0.frame.contains(location) }
  }

  private func layoutScreen(for screen: NSScreen) -> LayoutScreen {
    let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    let id = displayID?.stringValue ?? screen.localizedName
    let displayBounds = displayID.map {
      CGDisplayBounds(CGDirectDisplayID(truncating: $0))
    } ?? screen.frame
    return LayoutScreen(
      id: id,
      name: screen.localizedName,
      frame: convert(screen.frame, screenFrame: screen.frame, displayBounds: displayBounds),
      visibleFrame: convert(screen.visibleFrame, screenFrame: screen.frame, displayBounds: displayBounds),
      scaleFactor: screen.backingScaleFactor
    )
  }

  private func convert(_ rect: CGRect, screenFrame: CGRect, displayBounds: CGRect) -> LayoutRect {
    let x = displayBounds.minX + (rect.minX - screenFrame.minX)
    let y = displayBounds.minY + (screenFrame.maxY - rect.maxY)
    return LayoutRect(
      x: Double(x),
      y: Double(y),
      width: Double(rect.width),
      height: Double(rect.height)
    ).rounded()
  }

  private func launchItermIfNeeded() {
    launchIterm()
  }

  private static func defaultLaunchItermIfNeeded() {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.iTermBundleIdentifier) else {
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
  }

  private func taggedWindowsScript() -> String {
    """
    set outputLines to {}
    tell application id "\(Self.iTermBundleIdentifier)"
      repeat with targetWindow in windows
        try
          tell current session of targetWindow
            set targetID to variable named "\(Self.targetVariable)"
          end tell
          if targetID is not "" then
            set b to bounds of targetWindow
            set windowID to id of targetWindow as text
            set end of outputLines to windowID & tab & targetID & tab & (item 1 of b as text) & tab & (item 2 of b as text) & tab & (item 3 of b as text) & tab & (item 4 of b as text)
          end if
        end try
      end repeat
    end tell
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to linefeed
    set joinedOutput to outputLines as text
    set AppleScript's text item delimiters to oldDelimiters
    return joinedOutput
    """
  }

  private func taggedHostWindowsScript() -> String {
    """
    set outputLines to {}
    tell application id "\(Self.iTermBundleIdentifier)"
      repeat with targetWindow in windows
        try
          tell current session of targetWindow
            set hostID to variable named "\(Self.hostVariable)"
          end tell
          if hostID is not "" then
            set b to bounds of targetWindow
            set windowID to id of targetWindow as text
            set end of outputLines to windowID & tab & hostID & tab & (item 1 of b as text) & tab & (item 2 of b as text) & tab & (item 3 of b as text) & tab & (item 4 of b as text)
          end if
        end try
      end repeat
    end tell
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to linefeed
    set joinedOutput to outputLines as text
    set AppleScript's text item delimiters to oldDelimiters
    return joinedOutput
    """
  }

  private func terminalHostWindowInventoryScript() -> String {
    """
    set outputLines to {}
    tell application id "\(Self.iTermBundleIdentifier)"
      repeat with targetWindow in windows
        set windowID to ""
        set alternateID to ""
        set currentSessionID to ""
        set hostID to ""
        set visibleState to ""
        set minimizedState to ""
        set leftBound to ""
        set topBound to ""
        set rightBound to ""
        set bottomBound to ""

        try
          set windowID to id of targetWindow as text
        end try
        try
          set alternateID to alternate identifier of targetWindow as text
        end try
        try
          set currentSessionID to id of current session of targetWindow as text
        end try
        try
          tell current session of targetWindow
            set hostID to variable named "\(Self.hostVariable)"
          end tell
        end try
        try
          set visibleState to visible of targetWindow as text
        end try
        try
          set minimizedState to miniaturized of targetWindow as text
        on error
          try
            set minimizedState to minimized of targetWindow as text
          end try
        end try
        try
          set b to bounds of targetWindow
          set leftBound to item 1 of b as text
          set topBound to item 2 of b as text
          set rightBound to item 3 of b as text
          set bottomBound to item 4 of b as text
        end try
        set end of outputLines to windowID & tab & alternateID & tab & currentSessionID & tab & hostID & tab & visibleState & tab & minimizedState & tab & leftBound & tab & topBound & tab & rightBound & tab & bottomBound
      end repeat
    end tell
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to linefeed
    set joinedOutput to outputLines as text
    set AppleScript's text item delimiters to oldDelimiters
    return joinedOutput
    """
  }

  private func createWindowScript(target: ResolvedTerminalTarget, attachCommand: String) -> String {
    """
    tell application id "\(Self.iTermBundleIdentifier)"
      set newWindow to (create window with default profile)
      tell current session of newWindow
        set variable named "\(Self.targetVariable)" to \(appleScriptString(target.id))
        set variable named "\(Self.sessionVariable)" to \(appleScriptString(target.session))
        set variable named "\(Self.windowVariable)" to \(appleScriptString(target.window))
        set variable named "\(Self.paneVariable)" to \(appleScriptString(String(target.pane)))
        write text \(appleScriptString(attachCommand))
      end tell
      activate
    end tell
    """
  }

  private func createHostWindowScript(host: ResolvedTerminalHost, attachCommand: String) -> String {
    let createWindowCommand: String
    if let profileName = host.itermProfileName, !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      createWindowCommand = "create window with profile \(appleScriptString(profileName))"
    } else {
      createWindowCommand = "create window with default profile"
    }

    return """
    tell application id "\(Self.iTermBundleIdentifier)"
      set newWindow to (\(createWindowCommand))
      tell current session of newWindow
        set variable named "\(Self.hostVariable)" to \(appleScriptString(host.id))
        set variable named "\(Self.sessionVariable)" to \(appleScriptString(host.sessionName))
        set variable named "\(Self.windowVariable)" to \(appleScriptString(host.windowName))
        write text \(appleScriptString(attachCommand))
      end tell
      activate
      set b to bounds of newWindow
      set windowID to id of newWindow as text
      tell current session of newWindow
        set snapshotHostID to variable named "\(Self.hostVariable)"
      end tell
      set snapshotLine to windowID & tab & snapshotHostID & tab & (item 1 of b as text) & tab & (item 2 of b as text) & tab & (item 3 of b as text) & tab & (item 4 of b as text)
      return snapshotLine
    end tell
    """
  }

  private func focusWindowScript(targetID: String) -> String {
    """
    tell application id "\(Self.iTermBundleIdentifier)"
      repeat with targetWindow in windows
        try
          tell current session of targetWindow
            set foundTargetID to variable named "\(Self.targetVariable)"
          end tell
          if foundTargetID is \(appleScriptString(targetID)) then
            set index of targetWindow to 1
            activate
            return true
          end if
        end try
      end repeat
    end tell
    return false
    """
  }

  private func focusHostWindowScript(hostID: String) -> String {
    """
    tell application id "\(Self.iTermBundleIdentifier)"
      repeat with targetWindow in windows
        try
          tell current session of targetWindow
            set foundHostID to variable named "\(Self.hostVariable)"
          end tell
          if foundHostID is \(appleScriptString(hostID)) then
            set index of targetWindow to 1
            activate
            return true
          end if
        end try
      end repeat
    end tell
    return false
    """
  }

  private func focusHostWindowScript(windowID: String) -> String {
    """
    tell application id "\(Self.iTermBundleIdentifier)"
      repeat with targetWindow in windows
        try
          if (id of targetWindow as text) is \(appleScriptString(windowID)) then
            set index of targetWindow to 1
            activate
            return true
          end if
        end try
      end repeat
    end tell
    return false
    """
  }

  private func moveWindowsScript(framesByTargetID: [String: LayoutRect]) -> String {
    let records = framesByTargetID
      .sorted { $0.key < $1.key }
      .map { targetID, frame in
        "{\(appleScriptString(targetID)), \(Int(frame.x.rounded())), \(Int(frame.y.rounded())), \(Int(frame.maxX.rounded())), \(Int(frame.maxY.rounded()))}"
      }
      .joined(separator: ", ")

    return """
    set frameRecords to {\(records)}
    tell application id "\(Self.iTermBundleIdentifier)"
      repeat with frameRecord in frameRecords
        set expectedTargetID to item 1 of frameRecord
        repeat with targetWindow in windows
          try
            tell current session of targetWindow
              set foundTargetID to variable named "\(Self.targetVariable)"
            end tell
            if foundTargetID is expectedTargetID then
              set bounds of targetWindow to {item 2 of frameRecord, item 3 of frameRecord, item 4 of frameRecord, item 5 of frameRecord}
              exit repeat
            end if
          end try
        end repeat
      end repeat
      activate
    end tell
    """
  }

  private func moveHostWindowsScript(framesByHostID: [String: LayoutRect]) -> String {
    let records = framesByHostID
      .sorted { $0.key < $1.key }
      .map { hostID, frame in
        "{\(appleScriptString(hostID)), \(Int(frame.x.rounded())), \(Int(frame.y.rounded())), \(Int(frame.maxX.rounded())), \(Int(frame.maxY.rounded()))}"
      }
      .joined(separator: ", ")

    return """
    set frameRecords to {\(records)}
    tell application id "\(Self.iTermBundleIdentifier)"
      repeat with frameRecord in frameRecords
        set expectedHostID to item 1 of frameRecord
        repeat with targetWindow in windows
          try
            tell current session of targetWindow
              set foundHostID to variable named "\(Self.hostVariable)"
            end tell
            if foundHostID is expectedHostID then
              set bounds of targetWindow to {item 2 of frameRecord, item 3 of frameRecord, item 4 of frameRecord, item 5 of frameRecord}
              exit repeat
            end if
          end try
        end repeat
      end repeat
      activate
    end tell
    """
  }

  private func moveHostWindowsByIDScript(framesByWindowID: [String: LayoutRect]) -> String {
    let records = framesByWindowID
      .sorted { $0.key < $1.key }
      .map { windowID, frame in
        "{\(appleScriptString(windowID)), \(Int(frame.x.rounded())), \(Int(frame.y.rounded())), \(Int(frame.maxX.rounded())), \(Int(frame.maxY.rounded()))}"
      }
      .joined(separator: ", ")

    return """
    on withinTolerance(actualValue, expectedValue)
      set difference to actualValue - expectedValue
      if difference < 0 then set difference to -difference
      if difference is less than or equal to 4 then return true
      return false
    end withinTolerance

    on boundsMatch(actualBounds, expectedBounds)
      repeat with i from 1 to 4
        if not my withinTolerance(item i of actualBounds, item i of expectedBounds) then return false
      end repeat
      return true
    end boundsMatch

    set frameRecords to {\(records)}
    set outputLines to {}
    tell application id "\(Self.iTermBundleIdentifier)"
      repeat with frameRecord in frameRecords
        set expectedWindowID to item 1 of frameRecord
        set expectedBounds to {item 2 of frameRecord, item 3 of frameRecord, item 4 of frameRecord, item 5 of frameRecord}
        set didFindWindow to false
        repeat with targetWindow in windows
          if (id of targetWindow as text) is expectedWindowID then
            set didFindWindow to true
            try
              set bounds of targetWindow to expectedBounds
              delay 0.05
              set actualBounds to bounds of targetWindow
              if my boundsMatch(actualBounds, expectedBounds) then
                set end of outputLines to expectedWindowID & tab & "moved" & tab & ""
              else
                set end of outputLines to expectedWindowID & tab & "bounds_not_applied" & tab & ((item 1 of actualBounds as text) & "," & (item 2 of actualBounds as text) & "," & (item 3 of actualBounds as text) & "," & (item 4 of actualBounds as text))
              end if
            on error errorMessage
              set end of outputLines to expectedWindowID & tab & "move_rejected" & tab & errorMessage
            end try
            exit repeat
          end if
        end repeat
        if didFindWindow is false then
          set end of outputLines to expectedWindowID & tab & "window_not_found" & tab & ""
        end if
      end repeat
      activate
    end tell
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to linefeed
    set joinedOutput to outputLines as text
    set AppleScript's text item delimiters to oldDelimiters
    return joinedOutput
    """
  }

  private func moveAppWindowScript(bundleID: String, frame: LayoutRect) -> String {
    return """
    on withinTolerance(actualValue, expectedValue)
      set difference to actualValue - expectedValue
      if difference < 0 then set difference to -difference
      if difference is less than or equal to 4 then return true
      return false
    end withinTolerance

    on boundsMatch(actualBounds, expectedBounds)
      repeat with i from 1 to 4
        if not my withinTolerance(item i of actualBounds, item i of expectedBounds) then return false
      end repeat
      return true
    end boundsMatch

    set appBundleID to \(appleScriptString(bundleID))
    set expectedBounds to {\(Int(frame.x.rounded())), \(Int(frame.y.rounded())), \(Int(frame.maxX.rounded())), \(Int(frame.maxY.rounded()))}
    tell application id appBundleID
      activate
      repeat with attempt from 1 to 25
        if (count of windows) is greater than 0 then exit repeat
        delay 0.1
      end repeat
      if (count of windows) is 0 then
        return appBundleID & tab & "no_front_window" & tab & ""
      end if
      try
        set bounds of front window to expectedBounds
        delay 0.05
        set actualBounds to bounds of front window
        if my boundsMatch(actualBounds, expectedBounds) then
          return appBundleID & tab & "moved" & tab & ""
        end if
        return appBundleID & tab & "bounds_not_applied" & tab & ((item 1 of actualBounds as text) & "," & (item 2 of actualBounds as text) & "," & (item 3 of actualBounds as text) & "," & (item 4 of actualBounds as text))
      on error errorMessage
        return appBundleID & tab & "move_rejected" & tab & errorMessage
      end try
    end tell
    """
  }

  private func retagTerminalHostWindowScript(
    candidate: TerminalHostWindowInventoryItem,
    host: ResolvedTerminalHost
  ) -> String {
    """
    set expectedWindowID to \(appleScriptString(candidate.windowID))
    set expectedAlternateID to \(appleScriptString(candidate.alternateIdentifier))
    set expectedSessionID to \(appleScriptString(candidate.currentSessionID))
    tell application id "\(Self.iTermBundleIdentifier)"
      repeat with targetWindow in windows
        set didMatch to false
        try
          if expectedWindowID is not "" and (id of targetWindow as text) is expectedWindowID then set didMatch to true
        end try
        if didMatch is false then
          try
            if expectedAlternateID is not "" and (alternate identifier of targetWindow as text) is expectedAlternateID then set didMatch to true
          end try
        end if
        if didMatch is false then
          try
            if expectedSessionID is not "" and (id of current session of targetWindow as text) is expectedSessionID then set didMatch to true
          end try
        end if

        if didMatch then
          tell current session of targetWindow
            set variable named "\(Self.hostVariable)" to \(appleScriptString(host.id))
            set variable named "\(Self.sessionVariable)" to \(appleScriptString(host.sessionName))
            set variable named "\(Self.windowVariable)" to \(appleScriptString(host.windowName))
            set snapshotHostID to variable named "\(Self.hostVariable)"
          end tell
          set b to bounds of targetWindow
          set windowID to id of targetWindow as text
          return windowID & tab & snapshotHostID & tab & (item 1 of b as text) & tab & (item 2 of b as text) & tab & (item 3 of b as text) & tab & (item 4 of b as text)
        end if
      end repeat
    end tell
    return ""
    """
  }

  private func recoverTerminalHostWindowAfterMalformedCreate(
    host: ResolvedTerminalHost,
    beforeInventory: [TerminalHostWindowInventoryItem]
  ) throws -> TerminalWindowSnapshot? {
    let deadline = Date().addingTimeInterval(terminalHostWindowRecoveryTimeout)
    repeat {
      let currentInventory = try terminalHostWindowInventory()
      if let tagged = currentInventory.first(where: { $0.hostID == host.id })?.snapshot {
        return tagged
      }

      let candidates = newTerminalHostWindowCandidates(
        before: beforeInventory,
        after: currentInventory
      )
      if candidates.count == 1 {
        return try retagTerminalHostWindow(candidates[0], host: host)
      }
      if candidates.count > 1 || Date() >= deadline {
        return nil
      }
      Thread.sleep(forTimeInterval: 0.1)
    }
    while true
  }

  private func newTerminalHostWindowCandidates(
    before: [TerminalHostWindowInventoryItem],
    after: [TerminalHostWindowInventoryItem]
  ) -> [TerminalHostWindowInventoryItem] {
    let previousKeys = Set(before.flatMap(\.identityKeys))
    return after.filter { item in
      !item.identityKeys.isEmpty
        && item.identityKeys.isDisjoint(with: previousKeys)
        && (item.hostID ?? "").isEmpty
    }
  }

  private func retagTerminalHostWindow(
    _ candidate: TerminalHostWindowInventoryItem,
    host: ResolvedTerminalHost
  ) throws -> TerminalWindowSnapshot? {
    let operation = "retag_terminal_host_window"
    let output = try runAppleScript(
      retagTerminalHostWindowScript(candidate: candidate, host: host),
      operation: operation
    )
    do {
      return try parseTerminalWindowSnapshot(output, operation: operation)
    } catch {
      return nil
    }
  }

  private func runAppleScript(_ source: String, operation: String) throws -> String {
    do {
      return try appleScriptRunner(source, operation)
    } catch {
      var context: [String: String] = [
        "operation": operation,
        "script_bytes": String(source.utf8.count)
      ]
      context.merge(nativeAutomationDiagnosticContext(error), uniquingKeysWith: { current, _ in current })
      diagnostics.emit(
        level: .error,
        component: "native_mac_automation",
        name: "apple_script.failure",
        message: "AppleScript failed",
        context: context
      )
      throw error
    }
  }

  private static func executeAppleScript(source: String, operation _: String) throws -> String {
    var error: NSDictionary?
    guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
      let message = error?.description ?? "Unknown AppleScript error."
      throw NativeMacAutomationError.appleScriptFailed(message)
    }
    return result.stringValue ?? ""
  }

  private func emitUnexpectedAppleScriptOutput(_ output: String, operation: String) {
    diagnostics.emit(
      level: .warning,
      component: "native_mac_automation",
      name: "apple_script.unexpected_output",
      message: "AppleScript returned unexpected output",
      context: [
        "operation": operation,
        "summary": "unexpected \(operation) result",
        "output_bytes": String(output.utf8.count),
        "field_count": String(appleScriptFieldCount(output))
      ]
    )
  }

  private func appleScriptFieldCount(_ output: String) -> Int {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return 0
    }
    return trimmed.split(separator: "\t", omittingEmptySubsequences: false).count
  }

  private func emitMissingApplication(bundleID: String, operation: String) {
    diagnostics.emit(
      level: .warning,
      component: "native_mac_automation",
      name: "app_target.missing",
      message: "Application target is unavailable",
      context: [
        "operation": operation,
        "bundle_id": bundleID
      ]
    )
  }

  private func emitInvalidURL(_ url: String, operation: String) {
    diagnostics.emit(
      level: .warning,
      component: "native_mac_automation",
      name: "url.invalid",
      message: "URL is invalid",
      context: [
        "operation": operation,
        "url_bytes": String(url.utf8.count)
      ]
    )
  }

  private func appleScriptString(_ value: String) -> String {
    "\"" + value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"") + "\""
  }
}

public final class NativePaletteConfirmation: PaletteConfirmationProviding {
  public init() {}

  public func confirmBusy(target: ResolvedTerminalTarget, command: String, currentCommand: String) -> Bool {
    ask(
      title: "Pane Busy",
      message: "\(target.label) pane 0 is running \(currentCommand).\n\nSend \(command)?",
      primary: "Send"
    )
  }

  public func confirmStop(target: ResolvedTerminalTarget) -> Bool {
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

public final class NativeCommandCenterConfirmation: CommandCenterConfirmationProviding {
  public init() {}

  public func confirmBusy(action: CommandCenterActionPlan, currentCommand: String) -> Bool {
    let displayCommand = action.displayCommand ?? "this command"
    return ask(
      title: "Pane Busy",
      message: "\(action.label) targets a pane running \(currentCommand).\n\nSend \(displayCommand) anyway?",
      primary: "Send"
    )
  }

  public func confirmStop(action: CommandCenterActionPlan) -> Bool {
    ask(
      title: "Stop \(action.label)?",
      message: "Send Control-C to \(action.targetPane ?? "the selected pane")?",
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

public enum NativeMacAutomationError: Error, LocalizedError {
  case appleScriptFailed(String)
  case applicationNotFound(String)
  case invalidURL(String)

  public var errorDescription: String? {
    switch self {
    case let .appleScriptFailed(message):
      return "AppleScript failed: \(message)"
    case let .applicationNotFound(bundleID):
      return "Application not found for bundle ID: \(bundleID)"
    case let .invalidURL(url):
      return "Invalid URL: \(url)"
    }
  }

  var diagnosticContext: [String: String] {
    [
      "native_error_kind": nativeErrorKind,
      "summary": diagnosticSummary
    ]
  }

  private var nativeErrorKind: String {
    switch self {
    case .appleScriptFailed:
      return "apple_script_failed"
    case .applicationNotFound:
      return "application_not_found"
    case .invalidURL:
      return "invalid_url"
    }
  }

  private var diagnosticSummary: String {
    switch self {
    case let .appleScriptFailed(message):
      return Self.appleScriptFailureSummary(message)
    case .applicationNotFound:
      return "application not found"
    case .invalidURL:
      return "invalid URL"
    }
  }

  private static func appleScriptFailureSummary(_ message: String) -> String {
    let summary = MaestroDiagnostics.safeSummary(message)
    let lowercased = summary.lowercased()
    if lowercased.contains("not authorized")
      || lowercased.contains("not permitted")
      || lowercased.contains("automation")
      || lowercased.contains("privacy") {
      return "Apple Events permission failure"
    }
    if lowercased.contains("application isn't running")
      || lowercased.contains("application is not running")
      || lowercased.contains("can't get application") {
      return "AppleScript application unavailable"
    }
    if summary.hasPrefix("Unexpected ") {
      var generated = summary
      if generated.hasSuffix(".") {
        generated.removeLast()
      }
      return String(generated.prefix(1)).lowercased() + String(generated.dropFirst())
    }
    return "AppleScript operation failed"
  }
}

func nativeAutomationDiagnosticContext(_ error: any Error) -> [String: String] {
  guard let nativeError = error as? NativeMacAutomationError else {
    return MaestroDiagnostics.safeErrorContext(error)
  }
  var context = MaestroDiagnostics.safeErrorContext(error)
  context.merge(nativeError.diagnosticContext, uniquingKeysWith: { _, new in new })
  return context
}
#endif
