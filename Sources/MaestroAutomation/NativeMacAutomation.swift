#if os(macOS)
import AppKit
import ApplicationServices
import Foundation
import MaestroCore

public struct NativeMacAutomation: AppAutomation, WindowAutomation, LayoutAutomation {
  public init() {}

  public func launchOrFocus(bundleIdentifier: String) throws {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
      throw NativeMacAutomationError.applicationNotFound(bundleIdentifier)
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
      if let error {
        NSLog("Maestro could not launch %@: %@", bundleIdentifier, error.localizedDescription)
      }
    }
  }

  public func permissionSnapshot(promptForAccessibility: Bool = false) -> AutomationPermissionSnapshot {
    let accessibilityTrusted: Bool
    if promptForAccessibility {
      let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
      accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    } else {
      accessibilityTrusted = AXIsProcessTrusted()
    }

    let appleEventsAvailable = canRunLocalAppleScript()
    var notes: [String] = []
    if !accessibilityTrusted {
      notes.append("Accessibility is required before Maestro can inventory or place windows.")
    }
    if appleEventsAvailable {
      notes.append("macOS may still prompt for per-application Automation access the first time Maestro controls iTerm with Apple Events.")
    }

    return AutomationPermissionSnapshot(
      accessibilityTrusted: accessibilityTrusted,
      appleEventsAvailable: appleEventsAvailable,
      accessibilityState: accessibilityTrusted ? .ready : .missing,
      automationState: appleEventsAvailable ? .ready : .unavailable,
      accessibilityRecovery: PermissionRecovery(
        title: accessibilityTrusted ? "Accessibility Ready" : "Accessibility Permission Required",
        message: accessibilityTrusted ? "Maestro can inventory and place windows." : "Enable Accessibility for Maestro in System Settings to apply layouts.",
        actionLabel: accessibilityTrusted ? nil : "Open Accessibility Settings"
      ),
      automationRecovery: PermissionRecovery(
        title: appleEventsAvailable ? "Automation Ready" : "Automation Unavailable",
        message: appleEventsAvailable ? "Apple Events are available for iTerm-specific recovery paths when needed." : "Apple Events cannot be executed in this environment.",
        actionLabel: appleEventsAvailable ? nil : "Open Automation Settings"
      ),
      notes: notes
    )
  }

  public func iTermReadiness() -> ItermReadinessSnapshot {
    let bundleIdentifier = "com.googlecode.iterm2"
    let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    let running = NSWorkspace.shared.runningApplications.contains {
      $0.bundleIdentifier == bundleIdentifier
    }
    var notes: [String] = []
    if appURL == nil {
      notes.append("iTerm is not installed or Launch Services cannot resolve com.googlecode.iterm2.")
    }
    if appURL != nil && !running {
      notes.append("iTerm is installed but not currently running.")
    }

    return ItermReadinessSnapshot(
      bundleIdentifier: bundleIdentifier,
      installed: appURL != nil,
      running: running,
      applicationPath: appURL?.path,
      notes: notes
    )
  }

  public func screens() -> [LayoutScreen] {
    guard !NSScreen.screens.isEmpty else {
      return fallbackScreens()
    }
    let activeNSScreen = activeScreen()
    return NSScreen.screens.enumerated().map { index, screen in
      layoutScreen(
        for: screen,
        fallbackIndex: index,
        isMain: screen == NSScreen.main,
        isActive: screen == activeNSScreen
      )
    }
  }

  private func fallbackScreens() -> [LayoutScreen] {
    let displayID = CGMainDisplayID()
    let displayBounds = CGDisplayBounds(displayID)
    let bounds: LayoutRect
    if displayBounds.width > 0 && displayBounds.height > 0 {
      bounds = LayoutRect(
        x: Double(displayBounds.minX),
        y: Double(displayBounds.minY),
        width: Double(displayBounds.width),
        height: Double(displayBounds.height)
      ).rounded()
    } else {
      bounds = LayoutRect(x: 0, y: 0, width: 1440, height: 900)
    }

    return [
      LayoutScreen(
        id: "\(displayID)",
        name: "Fallback Display",
        frame: bounds,
        visibleFrame: bounds,
        scaleFactor: 1,
        isMain: true,
        isActive: true
      )
    ]
  }

  public func selectedScreen(_ selection: LayoutScreenSelection) throws -> LayoutScreen {
    let allScreens = screens()
    guard !allScreens.isEmpty else {
      throw LayoutPlanError.noScreens
    }

    switch selection {
    case .active:
      return allScreens.first(where: \.isActive)
        ?? allScreens.first(where: \.isMain)
        ?? allScreens[0]
    case .main:
      guard let mainScreen = allScreens.first(where: \.isMain) else {
        throw LayoutPlanError.missingScreen(selection)
      }
      return mainScreen
    }
  }

  public func windowInventory() throws -> [WindowSnapshot] {
    guard AXIsProcessTrusted() else {
      throw NativeMacAutomationError.accessibilityPermissionMissing
    }
    return try windowRecords().map(\.snapshot)
  }

  public func planLayout(
    _ layout: LayoutDefinition,
    screenSelection: LayoutScreenSelection
  ) throws -> LayoutPlan {
    let screen = try selectedScreen(screenSelection)
    let permissions = permissionSnapshot(promptForAccessibility: false)
    let inventoryStatus: LayoutWindowInventoryStatus
    let windows: [WindowSnapshot]

    if permissions.accessibilityTrusted {
      do {
        windows = try windowInventory()
        inventoryStatus = .available
      } catch {
        windows = []
        inventoryStatus = .unavailable
      }
    } else {
      windows = []
      inventoryStatus = .accessibilityPermissionMissing
    }

    return try LayoutPlanner().plan(
      layout: layout,
      screen: screen,
      windows: windows,
      inventoryStatus: inventoryStatus
    )
  }

  public func applyLayout(_ plan: LayoutPlan) throws -> LayoutApplicationResult {
    guard AXIsProcessTrusted() else {
      throw NativeMacAutomationError.accessibilityPermissionMissing
    }

    let records = try windowRecords()
    let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.snapshot.id, $0) })
    var movedWindowCount = 0
    var issues = plan.issues

    for slot in plan.slots {
      guard let window = slot.window else {
        continue
      }
      guard let record = recordsByID[window.id] else {
        issues.append(LayoutPlanIssue(
          code: "window_not_found",
          message: "Window \(window.id) was no longer available for slot \(slot.slotID)."
        ))
        continue
      }

      do {
        try setFrame(slot.frame, for: record.element)
        movedWindowCount += 1
      } catch let error as NativeMacAutomationError {
        issues.append(LayoutPlanIssue(
          code: error.code,
          message: error.localizedDescription
        ))
      }
    }

    return LayoutApplicationResult(
      ok: issues.isEmpty,
      layoutID: plan.layoutID,
      movedWindowCount: movedWindowCount,
      skippedSlotCount: plan.slots.count - movedWindowCount,
      issues: issues
    )
  }

  private func canRunLocalAppleScript() -> Bool {
    var error: NSDictionary?
    let result = NSAppleScript(source: "return 1")?.executeAndReturnError(&error)
    return result != nil
  }

  private func activeScreen() -> NSScreen? {
    let mouseLocation = NSEvent.mouseLocation
    return NSScreen.screens.first { screen in
      screen.frame.contains(mouseLocation)
    } ?? NSScreen.main ?? NSScreen.screens.first
  }

  private func layoutScreen(
    for screen: NSScreen,
    fallbackIndex: Int,
    isMain: Bool,
    isActive: Bool
  ) -> LayoutScreen {
    let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    let id = displayID?.stringValue ?? "screen-\(fallbackIndex)"
    let displayBounds = displayID.map {
      CGDisplayBounds(CGDirectDisplayID(truncating: $0))
    } ?? screen.frame

    return LayoutScreen(
      id: id,
      name: screen.localizedName,
      frame: convertToLayoutRect(screen.frame, screenFrame: screen.frame, displayBounds: displayBounds),
      visibleFrame: convertToLayoutRect(screen.visibleFrame, screenFrame: screen.frame, displayBounds: displayBounds),
      scaleFactor: screen.backingScaleFactor,
      isMain: isMain,
      isActive: isActive
    )
  }

  private func convertToLayoutRect(
    _ rect: CGRect,
    screenFrame: CGRect,
    displayBounds: CGRect
  ) -> LayoutRect {
    let x = displayBounds.minX + (rect.minX - screenFrame.minX)
    let y = displayBounds.minY + (screenFrame.maxY - rect.maxY)
    return LayoutRect(
      x: Double(x),
      y: Double(y),
      width: Double(rect.width),
      height: Double(rect.height)
    ).rounded()
  }

  private func windowRecords() throws -> [NativeWindowRecord] {
    var records: [NativeWindowRecord] = []
    let apps = NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy == .regular }
      .sorted {
        ($0.localizedName ?? "") < ($1.localizedName ?? "")
      }

    for app in apps {
      let appElement = AXUIElementCreateApplication(app.processIdentifier)
      var windowsValue: CFTypeRef?
      let result = AXUIElementCopyAttributeValue(
        appElement,
        kAXWindowsAttribute as CFString,
        &windowsValue
      )
      guard result == .success, let windows = windowsValue as? [AXUIElement] else {
        continue
      }

      for (index, windowElement) in windows.enumerated() {
        let title = stringAttribute(kAXTitleAttribute, from: windowElement) ?? ""
        let minimized = boolAttribute(kAXMinimizedAttribute, from: windowElement) ?? false
        let frame = frameAttribute(from: windowElement)
        let appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        let id = windowID(
          processIdentifier: app.processIdentifier,
          index: index,
          title: title,
          frame: frame
        )
        let snapshot = WindowSnapshot(
          id: id,
          appName: appName,
          bundleIdentifier: app.bundleIdentifier,
          processIdentifier: app.processIdentifier,
          title: title,
          frame: frame,
          isVisible: frame != nil,
          isMinimized: minimized
        )
        records.append(NativeWindowRecord(snapshot: snapshot, element: windowElement))
      }
    }

    return records
  }

  private func windowID(
    processIdentifier: pid_t,
    index: Int,
    title: String,
    frame: LayoutRect?
  ) -> String {
    let frameKey = frame.map {
      "\($0.x):\($0.y):\($0.width):\($0.height)"
    } ?? "no-frame"
    return "\(processIdentifier):\(index):\(title):\(frameKey)"
  }

  private func stringAttribute(_ name: String, from element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
      return nil
    }
    return value as? String
  }

  private func boolAttribute(_ name: String, from element: AXUIElement) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
      return nil
    }
    return value as? Bool
  }

  private func frameAttribute(from element: AXUIElement) -> LayoutRect? {
    guard let point = pointAttribute(kAXPositionAttribute, from: element),
          let size = sizeAttribute(kAXSizeAttribute, from: element) else {
      return nil
    }
    return LayoutRect(
      x: Double(point.x),
      y: Double(point.y),
      width: Double(size.width),
      height: Double(size.height)
    ).rounded()
  }

  private func pointAttribute(_ name: String, from element: AXUIElement) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXValueGetTypeID() else {
      return nil
    }
    let axValue = value as! AXValue
    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else {
      return nil
    }
    return point
  }

  private func sizeAttribute(_ name: String, from element: AXUIElement) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
          let value,
          CFGetTypeID(value) == AXValueGetTypeID() else {
      return nil
    }
    let axValue = value as! AXValue
    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else {
      return nil
    }
    return size
  }

  private func setFrame(_ frame: LayoutRect, for element: AXUIElement) throws {
    var position = CGPoint(x: frame.x, y: frame.y)
    var size = CGSize(width: frame.width, height: frame.height)
    guard let positionValue = AXValueCreate(.cgPoint, &position),
          let sizeValue = AXValueCreate(.cgSize, &size) else {
      throw NativeMacAutomationError.windowPlacementFailed("Could not create Accessibility frame values.")
    }

    let positionResult = AXUIElementSetAttributeValue(
      element,
      kAXPositionAttribute as CFString,
      positionValue
    )
    guard positionResult == .success else {
      throw NativeMacAutomationError.accessibilityCallFailed("set position", positionResult)
    }

    let sizeResult = AXUIElementSetAttributeValue(
      element,
      kAXSizeAttribute as CFString,
      sizeValue
    )
    guard sizeResult == .success else {
      throw NativeMacAutomationError.accessibilityCallFailed("set size", sizeResult)
    }
  }
}

public enum NativeMacAutomationError: Error, LocalizedError, Equatable, Sendable {
  case applicationNotFound(String)
  case accessibilityPermissionMissing
  case accessibilityCallFailed(String, AXError)
  case windowPlacementFailed(String)

  public var errorDescription: String? {
    switch self {
    case let .applicationNotFound(bundleIdentifier):
      return "Application not found: \(bundleIdentifier)"
    case .accessibilityPermissionMissing:
      return "Accessibility permission is required before Maestro can move windows."
    case let .accessibilityCallFailed(operation, status):
      return "Accessibility \(operation) failed with status \(status.rawValue)."
    case let .windowPlacementFailed(message):
      return message
    }
  }

  public var code: String {
    switch self {
    case .applicationNotFound:
      return "application_not_found"
    case .accessibilityPermissionMissing:
      return "accessibility_permission_missing"
    case .accessibilityCallFailed:
      return "accessibility_call_failed"
    case .windowPlacementFailed:
      return "window_placement_failed"
    }
  }
}

private struct NativeWindowRecord {
  var snapshot: WindowSnapshot
  var element: AXUIElement
}
#else
import Foundation
import MaestroCore

public struct NativeMacAutomation: AppAutomation, WindowAutomation, LayoutAutomation {
  public init() {}

  public func launchOrFocus(bundleIdentifier: String) throws {
    throw NativeMacAutomationError.unsupportedPlatform
  }

  public func permissionSnapshot(promptForAccessibility: Bool = false) -> AutomationPermissionSnapshot {
    AutomationPermissionSnapshot(
      accessibilityTrusted: false,
      appleEventsAvailable: false,
      notes: ["Native macOS automation is only available on macOS."]
    )
  }

  public func iTermReadiness() -> ItermReadinessSnapshot {
    ItermReadinessSnapshot(
      installed: false,
      running: false,
      notes: ["iTerm readiness is only available on macOS."]
    )
  }

  public func screens() -> [LayoutScreen] {
    []
  }

  public func selectedScreen(_ selection: LayoutScreenSelection) throws -> LayoutScreen {
    throw LayoutPlanError.noScreens
  }

  public func windowInventory() throws -> [WindowSnapshot] {
    throw NativeMacAutomationError.unsupportedPlatform
  }

  public func planLayout(
    _ layout: LayoutDefinition,
    screenSelection: LayoutScreenSelection
  ) throws -> LayoutPlan {
    throw NativeMacAutomationError.unsupportedPlatform
  }

  public func applyLayout(_ plan: LayoutPlan) throws -> LayoutApplicationResult {
    throw NativeMacAutomationError.unsupportedPlatform
  }
}

public enum NativeMacAutomationError: Error, LocalizedError, Equatable, Sendable {
  case unsupportedPlatform

  public var errorDescription: String? {
    "Native macOS automation is only available on macOS."
  }

  public var code: String {
    "unsupported_platform"
  }
}
#endif
