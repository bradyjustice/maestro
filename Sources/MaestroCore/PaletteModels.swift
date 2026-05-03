import Foundation

public enum MaestroJSON {
  public static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }

  public static var decoder: JSONDecoder {
    JSONDecoder()
  }
}

public struct PaletteConfig: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var roots: [ConfigRoot]
  public var targets: [TerminalTarget]
  public var regions: [LayoutRegion]
  public var layouts: [TerminalLayout]
  public var buttons: [CommandButton]
  public var sections: [DeckSection]
  public var profiles: [PaletteProfile]?

  public init(
    schemaVersion: Int,
    roots: [ConfigRoot],
    targets: [TerminalTarget],
    regions: [LayoutRegion],
    layouts: [TerminalLayout],
    buttons: [CommandButton],
    sections: [DeckSection],
    profiles: [PaletteProfile]? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.roots = roots
    self.targets = targets
    self.regions = regions
    self.layouts = layouts
    self.buttons = buttons
    self.sections = sections
    self.profiles = profiles
  }
}

public struct ConfigRoot: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var path: String

  public init(id: String, path: String) {
    self.id = id
    self.path = path
  }
}

public struct TerminalTarget: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var session: String
  public var window: String
  public var pane: Int
  public var root: String
  public var path: String

  public init(
    id: String,
    label: String,
    session: String,
    window: String,
    pane: Int,
    root: String,
    path: String = ""
  ) {
    self.id = id
    self.label = label
    self.session = session
    self.window = window
    self.pane = pane
    self.root = root
    self.path = path
  }
}

public struct LayoutRegion: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var container: PercentRect

  public init(id: String, label: String, container: PercentRect) {
    self.id = id
    self.label = label
    self.container = container
  }
}

public struct TerminalLayout: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var region: String
  public var slots: [LayoutSlot]

  public init(id: String, label: String, region: String, slots: [LayoutSlot]) {
    self.id = id
    self.label = label
    self.region = region
    self.slots = slots
  }
}

public struct LayoutSlot: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var target: String
  public var unit: PercentRect

  public init(id: String, target: String, unit: PercentRect) {
    self.id = id
    self.target = target
    self.unit = unit
  }
}

public enum CommandButtonKind: String, Codable, CaseIterable, Sendable {
  case command
  case stop
}

public struct CommandButton: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var kind: CommandButtonKind
  public var target: String
  public var argv: [String]?

  public init(
    id: String,
    label: String,
    kind: CommandButtonKind,
    target: String,
    argv: [String]? = nil
  ) {
    self.id = id
    self.label = label
    self.kind = kind
    self.target = target
    self.argv = argv
  }
}

public struct DeckSection: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var buttonIDs: [String]

  public init(id: String, label: String, buttonIDs: [String]) {
    self.id = id
    self.label = label
    self.buttonIDs = buttonIDs
  }
}

public struct PaletteProfile: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var layoutIDs: [String]
  public var targetIDs: [String]
  public var sectionIDs: [String]

  public init(
    id: String,
    label: String,
    layoutIDs: [String],
    targetIDs: [String],
    sectionIDs: [String]
  ) {
    self.id = id
    self.label = label
    self.layoutIDs = layoutIDs
    self.targetIDs = targetIDs
    self.sectionIDs = sectionIDs
  }
}

public struct PercentRect: Codable, Equatable, Sendable {
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

  public var isInsideUnitSpace: Bool {
    x >= 0 && y >= 0 && width > 0 && height > 0 && maxX <= 1 && maxY <= 1
  }

  public func frame(in bounds: LayoutRect) -> LayoutRect {
    LayoutRect(
      x: bounds.x + (bounds.width * x),
      y: bounds.y + (bounds.height * y),
      width: bounds.width * width,
      height: bounds.height * height
    ).rounded()
  }
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
}

public struct LayoutScreen: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var name: String
  public var frame: LayoutRect
  public var visibleFrame: LayoutRect
  public var scaleFactor: Double

  public init(
    id: String,
    name: String,
    frame: LayoutRect,
    visibleFrame: LayoutRect,
    scaleFactor: Double = 1
  ) {
    self.id = id
    self.name = name
    self.frame = frame
    self.visibleFrame = visibleFrame
    self.scaleFactor = scaleFactor
  }
}

public struct TerminalWindowSnapshot: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var targetID: String?
  public var frame: LayoutRect?
  public var isVisible: Bool
  public var isMinimized: Bool

  public init(
    id: String,
    targetID: String?,
    frame: LayoutRect? = nil,
    isVisible: Bool = true,
    isMinimized: Bool = false
  ) {
    self.id = id
    self.targetID = targetID
    self.frame = frame
    self.isVisible = isVisible
    self.isMinimized = isMinimized
  }
}

public struct ResolvedTerminalTarget: Codable, Identifiable, Equatable, Sendable {
  public var id: String
  public var label: String
  public var session: String
  public var window: String
  public var pane: Int
  public var cwd: String

  public init(
    id: String,
    label: String,
    session: String,
    window: String,
    pane: Int,
    cwd: String
  ) {
    self.id = id
    self.label = label
    self.session = session
    self.window = window
    self.pane = pane
    self.cwd = cwd
  }

  public var tmuxWindowTarget: String {
    "\(session):\(window)"
  }

  public var tmuxPaneTarget: String {
    "\(session):\(window).\(pane)"
  }
}

public struct PaletteValidationIssue: Codable, Equatable, Sendable {
  public var code: String
  public var message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

public struct PaletteValidationResult: Codable, Equatable, Sendable {
  public var ok: Bool
  public var issues: [PaletteValidationIssue]

  public init(issues: [PaletteValidationIssue]) {
    self.ok = issues.isEmpty
    self.issues = issues
  }
}

public enum PaletteConfigError: Error, LocalizedError, Equatable {
  case missingRoot(String)
  case missingTarget(String)
  case missingRegion(String)
  case missingLayout(String)
  case missingButton(String)
  case invalidConfig([PaletteValidationIssue])
  case missingCommandArgv(String)

  public var errorDescription: String? {
    switch self {
    case let .missingRoot(id):
      return "Unknown root: \(id)"
    case let .missingTarget(id):
      return "Unknown target: \(id)"
    case let .missingRegion(id):
      return "Unknown layout region: \(id)"
    case let .missingLayout(id):
      return "Unknown layout: \(id)"
    case let .missingButton(id):
      return "Unknown button: \(id)"
    case let .invalidConfig(issues):
      return issues.map(\.message).joined(separator: " ")
    case let .missingCommandArgv(id):
      return "Command button \(id) has no argv."
    }
  }
}
