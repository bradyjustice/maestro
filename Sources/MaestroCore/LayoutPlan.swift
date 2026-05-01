import Foundation

public enum LayoutScreenSelection: String, Codable, CaseIterable, Sendable {
  case active
  case main
}

public struct LayoutRect: Codable, Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public var maxX: Double { x + width }
  public var maxY: Double { y + height }

  public func rounded() -> LayoutRect {
    LayoutRect(
      x: x.rounded(),
      y: y.rounded(),
      width: width.rounded(),
      height: height.rounded()
    )
  }

  public func insetBy(dx: Double, dy: Double) -> LayoutRect {
    LayoutRect(
      x: x + dx,
      y: y + dy,
      width: max(0, width - (dx * 2)),
      height: max(0, height - (dy * 2))
    )
  }

  public func contains(_ rect: LayoutRect) -> Bool {
    rect.x >= x &&
      rect.y >= y &&
      rect.maxX <= maxX &&
      rect.maxY <= maxY
  }
}

public struct LayoutScreen: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var frame: LayoutRect
  public var visibleFrame: LayoutRect
  public var scaleFactor: Double
  public var isMain: Bool
  public var isActive: Bool

  public init(
    id: String,
    name: String,
    frame: LayoutRect,
    visibleFrame: LayoutRect,
    scaleFactor: Double = 1,
    isMain: Bool = false,
    isActive: Bool = false
  ) {
    self.id = id
    self.name = name
    self.frame = frame
    self.visibleFrame = visibleFrame
    self.scaleFactor = scaleFactor
    self.isMain = isMain
    self.isActive = isActive
  }
}

public struct WindowSnapshot: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var appName: String
  public var bundleIdentifier: String?
  public var processIdentifier: Int32
  public var title: String
  public var frame: LayoutRect?
  public var isVisible: Bool
  public var isMinimized: Bool

  public init(
    id: String,
    appName: String,
    bundleIdentifier: String? = nil,
    processIdentifier: Int32,
    title: String,
    frame: LayoutRect? = nil,
    isVisible: Bool = true,
    isMinimized: Bool = false
  ) {
    self.id = id
    self.appName = appName
    self.bundleIdentifier = bundleIdentifier
    self.processIdentifier = processIdentifier
    self.title = title
    self.frame = frame
    self.isVisible = isVisible
    self.isMinimized = isMinimized
  }
}

public enum LayoutWindowInventoryStatus: String, Codable, Equatable, Sendable {
  case available
  case accessibilityPermissionMissing = "accessibility-permission-missing"
  case unavailable
}

public enum LayoutPlanSlotStatus: String, Codable, Equatable, Sendable {
  case matched
  case missingWindow = "missing-window"
}

public struct LayoutPlanSlot: Codable, Equatable, Sendable {
  public var slotID: String
  public var app: String
  public var role: String
  public var unit: String
  public var frame: LayoutRect
  public var status: LayoutPlanSlotStatus
  public var window: WindowSnapshot?

  public init(
    slotID: String,
    app: String,
    role: String,
    unit: String,
    frame: LayoutRect,
    status: LayoutPlanSlotStatus,
    window: WindowSnapshot? = nil
  ) {
    self.slotID = slotID
    self.app = app
    self.role = role
    self.unit = unit
    self.frame = frame
    self.status = status
    self.window = window
  }
}

public struct LayoutPlanIssue: Codable, Equatable, Sendable {
  public var code: String
  public var message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

public struct LayoutPlan: Codable, Equatable, Sendable {
  public var layoutID: String
  public var label: String
  public var description: String
  public var screen: LayoutScreen
  public var inventoryStatus: LayoutWindowInventoryStatus
  public var slots: [LayoutPlanSlot]
  public var unmanagedWindowCount: Int
  public var unmanagedTargetWindows: [WindowSnapshot]
  public var issues: [LayoutPlanIssue]

  public init(
    layoutID: String,
    label: String,
    description: String,
    screen: LayoutScreen,
    inventoryStatus: LayoutWindowInventoryStatus,
    slots: [LayoutPlanSlot],
    unmanagedWindowCount: Int,
    unmanagedTargetWindows: [WindowSnapshot],
    issues: [LayoutPlanIssue] = []
  ) {
    self.layoutID = layoutID
    self.label = label
    self.description = description
    self.screen = screen
    self.inventoryStatus = inventoryStatus
    self.slots = slots
    self.unmanagedWindowCount = unmanagedWindowCount
    self.unmanagedTargetWindows = unmanagedTargetWindows
    self.issues = issues
  }

  public var moveCount: Int {
    slots.filter { $0.window != nil }.count
  }

  public var canExecute: Bool {
    inventoryStatus == .available && moveCount > 0
  }
}

public struct LayoutApplicationResult: Codable, Equatable, Sendable {
  public var ok: Bool
  public var layoutID: String
  public var movedWindowCount: Int
  public var skippedSlotCount: Int
  public var issues: [LayoutPlanIssue]

  public init(
    ok: Bool,
    layoutID: String,
    movedWindowCount: Int,
    skippedSlotCount: Int,
    issues: [LayoutPlanIssue] = []
  ) {
    self.ok = ok
    self.layoutID = layoutID
    self.movedWindowCount = movedWindowCount
    self.skippedSlotCount = skippedSlotCount
    self.issues = issues
  }
}

public enum LayoutPlanError: Error, LocalizedError, Equatable, Sendable {
  case unknownUnit(String)
  case missingScreen(LayoutScreenSelection)
  case noScreens

  public var errorDescription: String? {
    switch self {
    case let .unknownUnit(unit):
      return "Unknown layout unit: \(unit)"
    case let .missingScreen(selection):
      return "No \(selection.rawValue) screen is available."
    case .noScreens:
      return "No screens are available."
    }
  }

  public var code: String {
    switch self {
    case .unknownUnit:
      return "unknown_layout_unit"
    case .missingScreen:
      return "missing_layout_screen"
    case .noScreens:
      return "no_layout_screens"
    }
  }
}

public struct LayoutGeometry: Sendable {
  public static let knownUnits: Set<String> = [
    "full",
    "left",
    "right",
    "left-half",
    "right-half",
    "top-half",
    "bottom-half",
    "top-left",
    "top-center",
    "top-right",
    "bottom-left",
    "bottom-center",
    "bottom-right",
    "top-left-third",
    "top-center-third",
    "top-right-third",
    "bottom-left-third",
    "bottom-center-third",
    "bottom-right-third",
    "left-two-thirds",
    "right-third",
    "center"
  ]

  public static func isKnownUnit(_ unit: String) -> Bool {
    knownUnits.contains(unit)
  }

  public static func frame(for unit: String, in screen: LayoutScreen) throws -> LayoutRect {
    try frame(for: unit, in: screen.visibleFrame)
  }

  public static func frame(for unit: String, in bounds: LayoutRect) throws -> LayoutRect {
    let third = bounds.width / 3
    let halfWidth = bounds.width / 2
    let halfHeight = bounds.height / 2

    let frame: LayoutRect
    switch unit {
    case "full":
      frame = bounds
    case "left", "left-half":
      frame = LayoutRect(x: bounds.x, y: bounds.y, width: halfWidth, height: bounds.height)
    case "right", "right-half":
      frame = LayoutRect(x: bounds.x + halfWidth, y: bounds.y, width: halfWidth, height: bounds.height)
    case "top-half":
      frame = LayoutRect(x: bounds.x, y: bounds.y, width: bounds.width, height: halfHeight)
    case "bottom-half":
      frame = LayoutRect(x: bounds.x, y: bounds.y + halfHeight, width: bounds.width, height: halfHeight)
    case "top-left":
      frame = LayoutRect(x: bounds.x, y: bounds.y, width: halfWidth, height: halfHeight)
    case "top-center":
      frame = LayoutRect(x: bounds.x + third, y: bounds.y, width: third, height: halfHeight)
    case "top-right":
      frame = LayoutRect(x: bounds.x + halfWidth, y: bounds.y, width: halfWidth, height: halfHeight)
    case "bottom-left":
      frame = LayoutRect(x: bounds.x, y: bounds.y + halfHeight, width: halfWidth, height: halfHeight)
    case "bottom-center":
      frame = LayoutRect(x: bounds.x + third, y: bounds.y + halfHeight, width: third, height: halfHeight)
    case "bottom-right":
      frame = LayoutRect(x: bounds.x + halfWidth, y: bounds.y + halfHeight, width: halfWidth, height: halfHeight)
    case "top-left-third":
      frame = LayoutRect(x: bounds.x, y: bounds.y, width: third, height: halfHeight)
    case "top-center-third":
      frame = LayoutRect(x: bounds.x + third, y: bounds.y, width: third, height: halfHeight)
    case "top-right-third":
      frame = LayoutRect(x: bounds.x + (third * 2), y: bounds.y, width: third, height: halfHeight)
    case "bottom-left-third":
      frame = LayoutRect(x: bounds.x, y: bounds.y + halfHeight, width: third, height: halfHeight)
    case "bottom-center-third":
      frame = LayoutRect(x: bounds.x + third, y: bounds.y + halfHeight, width: third, height: halfHeight)
    case "bottom-right-third":
      frame = LayoutRect(x: bounds.x + (third * 2), y: bounds.y + halfHeight, width: third, height: halfHeight)
    case "left-two-thirds":
      frame = LayoutRect(x: bounds.x, y: bounds.y, width: third * 2, height: bounds.height)
    case "right-third":
      frame = LayoutRect(x: bounds.x + (third * 2), y: bounds.y, width: third, height: bounds.height)
    case "center":
      frame = bounds.insetBy(dx: bounds.width * 0.125, dy: bounds.height * 0.1)
    default:
      throw LayoutPlanError.unknownUnit(unit)
    }

    return frame.rounded()
  }
}

public struct LayoutPlanner: Sendable {
  public init() {}

  public func plan(
    layout: LayoutDefinition,
    screen: LayoutScreen,
    windows: [WindowSnapshot] = [],
    inventoryStatus: LayoutWindowInventoryStatus = .available
  ) throws -> LayoutPlan {
    let visibleWindows = windows
      .filter { $0.isVisible && !$0.isMinimized }
      .sorted(by: windowSort)
    let targetedApps = Set(layout.slots.map { AppMatcher.normalized($0.app) })
    var usedWindowIDs = Set<String>()
    var slots: [LayoutPlanSlot] = []
    var issues: [LayoutPlanIssue] = []

    if inventoryStatus != .available {
      issues.append(LayoutPlanIssue(
        code: inventoryStatus.rawValue,
        message: "Window inventory is unavailable, so this dry-run shows geometry without target windows."
      ))
    }

    for slot in layout.slots {
      let frame = try LayoutGeometry.frame(for: slot.unit, in: screen)
      let window = visibleWindows.first { candidate in
        !usedWindowIDs.contains(candidate.id) && AppMatcher.matches(slotApp: slot.app, window: candidate)
      }
      if let window {
        usedWindowIDs.insert(window.id)
        slots.append(LayoutPlanSlot(
          slotID: slot.id,
          app: slot.app,
          role: slot.role,
          unit: slot.unit,
          frame: frame,
          status: .matched,
          window: window
        ))
      } else {
        slots.append(LayoutPlanSlot(
          slotID: slot.id,
          app: slot.app,
          role: slot.role,
          unit: slot.unit,
          frame: frame,
          status: .missingWindow
        ))
      }
    }

    let unmanagedWindows = visibleWindows.filter { !usedWindowIDs.contains($0.id) }
    let unmanagedTargets = unmanagedWindows.filter { window in
      AppMatcher.aliases(for: window.appName, bundleIdentifier: window.bundleIdentifier)
        .contains { targetedApps.contains($0) }
    }

    if slots.contains(where: { $0.status == .missingWindow }) {
      issues.append(LayoutPlanIssue(
        code: "missing_layout_windows",
        message: "One or more layout slots does not currently have a matching window."
      ))
    }

    return LayoutPlan(
      layoutID: layout.id,
      label: layout.label,
      description: layout.description,
      screen: screen,
      inventoryStatus: inventoryStatus,
      slots: slots,
      unmanagedWindowCount: unmanagedWindows.count,
      unmanagedTargetWindows: unmanagedTargets,
      issues: issues
    )
  }

  private func windowSort(_ lhs: WindowSnapshot, _ rhs: WindowSnapshot) -> Bool {
    let lhsKey = [
      AppMatcher.normalized(lhs.appName),
      lhs.id,
      lhs.title.lowercased()
    ]
    let rhsKey = [
      AppMatcher.normalized(rhs.appName),
      rhs.id,
      rhs.title.lowercased()
    ]
    return lhsKey.lexicographicallyPrecedes(rhsKey)
  }
}

public enum AppMatcher {
  public static func matches(slotApp: String, window: WindowSnapshot) -> Bool {
    let slotAliases = aliases(for: slotApp, bundleIdentifier: nil)
    let windowAliases = aliases(for: window.appName, bundleIdentifier: window.bundleIdentifier)
    return !slotAliases.isDisjoint(with: windowAliases)
  }

  public static func aliases(for appName: String, bundleIdentifier: String?) -> Set<String> {
    var aliases = Set<String>()
    let app = normalized(appName)
    aliases.insert(app)

    if let bundleIdentifier {
      aliases.insert(normalized(bundleIdentifier))
    }

    switch app {
    case "iterm", "iterm2":
      aliases.formUnion(["iterm", "iterm2", "comgooglecodeiterm2"])
    case "visualstudiocode", "code":
      aliases.formUnion(["visualstudiocode", "code", "commicrosoftvscode"])
    case "safari":
      aliases.formUnion(["safari", "comapplesafari"])
    case "googlechrome", "chrome":
      aliases.formUnion(["googlechrome", "chrome", "comgooglechrome"])
    default:
      break
    }

    return aliases
  }

  public static func normalized(_ value: String) -> String {
    value
      .lowercased()
      .filter { $0.isLetter || $0.isNumber }
  }
}
