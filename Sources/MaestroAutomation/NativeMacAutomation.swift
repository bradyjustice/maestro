#if os(macOS)
import AppKit
import ApplicationServices
import Foundation

public struct NativeMacAutomation: AppAutomation, WindowAutomation {
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

    var notes: [String] = []
    if !accessibilityTrusted {
      notes.append("Accessibility is required before Maestro can inventory or place windows.")
    }

    return AutomationPermissionSnapshot(
      accessibilityTrusted: accessibilityTrusted,
      appleEventsAvailable: true,
      notes: notes
    )
  }
}

public enum NativeMacAutomationError: Error, LocalizedError, Equatable, Sendable {
  case applicationNotFound(String)

  public var errorDescription: String? {
    switch self {
    case let .applicationNotFound(bundleIdentifier):
      return "Application not found: \(bundleIdentifier)"
    }
  }
}
#else
import Foundation

public struct NativeMacAutomation: AppAutomation, WindowAutomation {
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
}

public enum NativeMacAutomationError: Error, LocalizedError, Equatable, Sendable {
  case unsupportedPlatform

  public var errorDescription: String? {
    "Native macOS automation is only available on macOS."
  }
}
#endif
