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

  public init(diagnostics: MaestroDiagnostics = .disabled) {
    self.diagnostics = diagnostics
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
    let output = try runAppleScript(taggedWindowsScript(), operation: "tagged_terminal_windows").stringValue ?? ""
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
    let output = try runAppleScript(taggedHostWindowsScript(), operation: "tagged_terminal_host_windows").stringValue ?? ""
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

  public func createTerminalHostWindow(for host: ResolvedTerminalHost, attachCommand: String) throws {
    launchItermIfNeeded()
    _ = try runAppleScript(createHostWindowScript(host: host, attachCommand: attachCommand), operation: "create_terminal_host_window")
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

  public func moveTerminalHostWindowsByWindowID(_ framesByWindowID: [String: LayoutRect]) throws {
    guard !framesByWindowID.isEmpty else {
      return
    }
    _ = try runAppleScript(moveHostWindowsByIDScript(framesByWindowID: framesByWindowID), operation: "move_terminal_host_windows_by_id")
  }

  public func focusApp(bundleID: String) throws {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      emitMissingApplication(bundleID: bundleID, operation: "focus_app")
      throw NativeMacAutomationError.applicationNotFound(bundleID)
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
  }

  public func openURL(_ url: String, bundleID: String?) throws {
    guard let targetURL = URL(string: url) else {
      emitInvalidURL(url, operation: "open_url")
      throw NativeMacAutomationError.invalidURL(url)
    }
    if let bundleID {
      guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
        emitMissingApplication(bundleID: bundleID, operation: "open_url")
        throw NativeMacAutomationError.applicationNotFound(bundleID)
      }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.open([targetURL], withApplicationAt: appURL, configuration: configuration) { _, _ in }
    } else {
      NSWorkspace.shared.open(targetURL)
    }
  }

  public func openRepo(path: String, bundleID: String) throws {
    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      emitMissingApplication(bundleID: bundleID, operation: "open_repo")
      throw NativeMacAutomationError.applicationNotFound(bundleID)
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: appURL, configuration: configuration) { _, _ in }
  }

  public func moveAppWindows(_ framesByAppTargetID: [String: LayoutRect], appTargets: [AppTarget]) throws {
    guard !framesByAppTargetID.isEmpty else {
      return
    }
    let targets = appTargets.filter { framesByAppTargetID[$0.id] != nil }
    guard !targets.isEmpty else {
      return
    }
    _ = try runAppleScript(moveAppWindowsScript(framesByAppTargetID: framesByAppTargetID, appTargets: targets), operation: "move_app_windows")
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
    set frameRecords to {\(records)}
    tell application id "\(Self.iTermBundleIdentifier)"
      repeat with frameRecord in frameRecords
        set expectedWindowID to item 1 of frameRecord
        repeat with targetWindow in windows
          try
            if (id of targetWindow as text) is expectedWindowID then
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

  private func moveAppWindowsScript(framesByAppTargetID: [String: LayoutRect], appTargets: [AppTarget]) -> String {
    let records = appTargets.compactMap { appTarget -> String? in
      guard let frame = framesByAppTargetID[appTarget.id] else {
        return nil
      }
      return "{\(appleScriptString(appTarget.bundleID)), \(Int(frame.x.rounded())), \(Int(frame.y.rounded())), \(Int(frame.maxX.rounded())), \(Int(frame.maxY.rounded()))}"
    }.joined(separator: ", ")

    return """
    set frameRecords to {\(records)}
    repeat with frameRecord in frameRecords
      set appBundleID to item 1 of frameRecord
      try
        tell application id appBundleID
          activate
          if (count of windows) is greater than 0 then
            set bounds of front window to {item 2 of frameRecord, item 3 of frameRecord, item 4 of frameRecord, item 5 of frameRecord}
          end if
        end tell
      end try
    end repeat
    """
  }

  private func runAppleScript(_ source: String, operation: String) throws -> NSAppleEventDescriptor {
    var error: NSDictionary?
    guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error) else {
      let message = error?.description ?? "Unknown AppleScript error."
      diagnostics.emit(
        level: .error,
        component: "native_mac_automation",
        name: "apple_script.failure",
        message: "AppleScript failed",
        context: [
          "operation": operation,
          "summary": MaestroDiagnostics.safeSummary(message),
          "script_bytes": String(source.utf8.count)
        ]
      )
      throw NativeMacAutomationError.appleScriptFailed(message)
    }
    return result
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
}
#endif
