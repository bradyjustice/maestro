import Foundation

public enum AgentTaskRecordSource: String, Codable, Equatable, Sendable {
  case swift
  case legacy
}

public struct AgentTaskSnapshot: Codable, Identifiable, Equatable, Sendable {
  public var source: AgentTaskRecordSource
  public var archived: Bool
  public var recordPath: String
  public var record: AgentTaskRecord
  public var reviewArtifactAvailable: Bool

  public var id: String {
    "\(source.rawValue):\(record.id):\(recordPath)"
  }

  public init(
    source: AgentTaskRecordSource,
    archived: Bool,
    recordPath: String,
    record: AgentTaskRecord,
    reviewArtifactAvailable: Bool
  ) {
    self.source = source
    self.archived = archived
    self.recordPath = recordPath
    self.record = record
    self.reviewArtifactAvailable = reviewArtifactAvailable
  }
}

public struct AgentTaskList: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var stateDirectory: String
  public var tasks: [AgentTaskSnapshot]

  public init(
    schemaVersion: Int = 1,
    stateDirectory: String,
    tasks: [AgentTaskSnapshot]
  ) {
    self.schemaVersion = schemaVersion
    self.stateDirectory = stateDirectory
    self.tasks = tasks
  }
}

public enum AgentStateStoreError: Error, LocalizedError, Equatable {
  case unreadableRecord(String, String)
  case invalidLegacyRecord(String, String)
  case ambiguousTask(String, [String])
  case missingTask(String)
  case writeFailed(String)

  public var errorDescription: String? {
    switch self {
    case let .unreadableRecord(path, reason):
      return "Cannot read agent record at \(path): \(reason)"
    case let .invalidLegacyRecord(path, reason):
      return "Invalid legacy agent record at \(path): \(reason)"
    case let .ambiguousTask(query, matches):
      return "Agent task query \(query) is ambiguous: \(matches.joined(separator: ", "))"
    case let .missingTask(query):
      return "Agent task not found: \(query)"
    case let .writeFailed(path):
      return "Could not write agent record at \(path)"
    }
  }
}

public struct AgentStateStore {
  public var stateDirectory: URL
  public var environment: [String: String]
  public var fileManager: FileManager

  public init(
    stateDirectory: URL = MaestroPaths.defaultStateDirectory(),
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) {
    self.stateDirectory = stateDirectory
    self.environment = environment
    self.fileManager = fileManager
  }

  public var agentsDirectory: URL {
    stateDirectory.appendingPathComponent("agents")
  }

  public var activeDirectory: URL {
    agentsDirectory.appendingPathComponent("active")
  }

  public var archiveDirectory: URL {
    agentsDirectory.appendingPathComponent("archive")
  }

  public var legacyRegistryDirectory: URL {
    if let override = environment["AGENT_REGISTRY_DIR"], !override.isEmpty {
      return URL(fileURLWithPath: MaestroPaths.expandTilde(override, environment: environment))
    }

    let worktreeRoot: String
    if let override = environment["AGENT_WORKTREE_ROOT"], !override.isEmpty {
      worktreeRoot = MaestroPaths.expandTilde(override, environment: environment)
    } else {
      let nodeRoot = MaestroPaths.expandTilde(
        environment["AGENT_NODE_ROOT"].flatMap { $0.isEmpty ? nil : $0 } ?? "~/Documents/Coding/node",
        environment: environment
      )
      worktreeRoot = URL(fileURLWithPath: nodeRoot)
        .appendingPathComponent("_agent-worktrees")
        .path
    }
    return URL(fileURLWithPath: worktreeRoot).appendingPathComponent("_registry")
  }

  public func list(includeArchived: Bool = false) throws -> [AgentTaskSnapshot] {
    var snapshots = try swiftSnapshots(in: activeDirectory, archived: false)
    snapshots += try legacySnapshots(in: legacyRegistryDirectory, archived: false)

    if includeArchived {
      snapshots += try swiftSnapshots(in: archiveDirectory, archived: true)
      snapshots += try legacySnapshots(
        in: legacyRegistryDirectory.appendingPathComponent("archive"),
        archived: true
      )
    }

    return snapshots.sorted { lhs, rhs in
      if lhs.archived != rhs.archived {
        return !lhs.archived
      }
      if lhs.record.updatedAt != rhs.record.updatedAt {
        return lhs.record.updatedAt > rhs.record.updatedAt
      }
      return lhs.record.id < rhs.record.id
    }
  }

  public func task(matching query: String, includeArchived: Bool = true) throws -> AgentTaskSnapshot {
    let tasks = try list(includeArchived: includeArchived)
    let exact = tasks.filter { snapshot in
      snapshot.record.id == query
        || URL(fileURLWithPath: snapshot.recordPath).deletingPathExtension().lastPathComponent == query
    }
    if exact.count == 1 {
      return exact[0]
    }
    if exact.count > 1 {
      throw AgentStateStoreError.ambiguousTask(query, exact.map(\.record.id))
    }

    let fuzzy = tasks.filter { snapshot in
      snapshot.record.id.contains(query)
        || snapshot.record.branch.contains(query)
        || snapshot.record.repoName.contains(query)
    }
    if fuzzy.count == 1 {
      return fuzzy[0]
    }
    if fuzzy.count > 1 {
      throw AgentStateStoreError.ambiguousTask(query, fuzzy.map(\.record.id))
    }
    throw AgentStateStoreError.missingTask(query)
  }

  public func writeActive(_ record: AgentTaskRecord) throws {
    try write(record, to: activeDirectory.appendingPathComponent("\(safeFileName(record.id)).json"))
  }

  public func writeArchived(_ record: AgentTaskRecord) throws {
    try write(record, to: archiveDirectory.appendingPathComponent("\(safeFileName(record.id)).json"))
  }

  private func swiftSnapshots(in directory: URL, archived: Bool) throws -> [AgentTaskSnapshot] {
    guard fileManager.fileExists(atPath: directory.path) else {
      return []
    }

    let files = try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    )
      .filter { $0.pathExtension == "json" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

    return try files.map { file in
      do {
        let data = try Data(contentsOf: file)
        let record = try MaestroJSON.decoder.decode(AgentTaskRecord.self, from: data)
        return AgentTaskSnapshot(
          source: .swift,
          archived: archived,
          recordPath: file.path,
          record: record,
          reviewArtifactAvailable: artifactExists(record.reviewArtifact),
        )
      } catch {
        throw AgentStateStoreError.unreadableRecord(file.path, error.localizedDescription)
      }
    }
  }

  private func legacySnapshots(in directory: URL, archived: Bool) throws -> [AgentTaskSnapshot] {
    guard fileManager.fileExists(atPath: directory.path) else {
      return []
    }

    let files = try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey]
    )
      .filter { $0.pathExtension == "env" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

    return try files.map { file in
      let record = try legacyRecord(at: file)
      return AgentTaskSnapshot(
        source: .legacy,
        archived: archived,
        recordPath: file.path,
        record: record,
        reviewArtifactAvailable: artifactExists(record.reviewArtifact)
      )
    }
  }

  private func legacyRecord(at file: URL) throws -> AgentTaskRecord {
    let text: String
    do {
      text = try String(contentsOf: file, encoding: .utf8)
    } catch {
      throw AgentStateStoreError.unreadableRecord(file.path, error.localizedDescription)
    }

    let values = LegacyAgentEnvParser.parse(text)
    let taskID = values["task_id"].flatMap(nonEmpty) ?? file.deletingPathExtension().lastPathComponent
    let repoPath = values["repo_path"].flatMap(nonEmpty) ?? ""
    let repoName = values["repo_name"].flatMap(nonEmpty)
      ?? URL(fileURLWithPath: repoPath).lastPathComponent
      .nilIfEmpty
      ?? "unknown"
    let stateValue = values["state"].flatMap(nonEmpty) ?? "queued"
    guard let state = AgentState(rawValue: stateValue) else {
      throw AgentStateStoreError.invalidLegacyRecord(file.path, "Unknown state: \(stateValue)")
    }

    return AgentTaskRecord(
      id: taskID,
      repoName: repoName,
      repoPath: repoPath,
      worktreePath: values["worktree_path"].flatMap(nonEmpty) ?? "",
      branch: values["branch"].flatMap(nonEmpty) ?? "",
      baseRef: values["base_ref"].flatMap(nonEmpty) ?? "main",
      state: state,
      note: values["note"].flatMap(nonEmpty),
      checkExit: values["check_exit"].flatMap(nonEmpty).flatMap(Int.init),
      reviewExit: values["review_exit"].flatMap(nonEmpty).flatMap(Int.init),
      reviewArtifact: values["review_artifact"].flatMap(nonEmpty),
      tmuxSession: values["tmux_session"].flatMap(nonEmpty),
      tmuxWindow: values["tmux_window"].flatMap(nonEmpty),
      createdAt: legacyDate(values["created_at"], file: file),
      updatedAt: legacyDate(values["updated_at"], file: file),
      cleanedAt: values["cleaned_at"].flatMap(nonEmpty).flatMap(Self.parseDate)
    )
  }

  private func write(_ record: AgentTaskRecord, to destination: URL) throws {
    try fileManager.createDirectory(
      at: destination.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let temporary = destination.deletingLastPathComponent()
      .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
    let data = try MaestroJSON.encoder.encode(record)
    guard fileManager.createFile(
      atPath: temporary.path,
      contents: data,
      attributes: [.posixPermissions: 0o600]
    ) else {
      throw AgentStateStoreError.writeFailed(temporary.path)
    }
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)

    if fileManager.fileExists(atPath: destination.path) {
      _ = try fileManager.replaceItemAt(
        destination,
        withItemAt: temporary,
        backupItemName: nil,
        options: [.usingNewMetadataOnly]
      )
      try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    } else {
      try fileManager.moveItem(at: temporary, to: destination)
    }
  }

  private func artifactExists(_ path: String?) -> Bool {
    guard let path, !path.isEmpty else {
      return false
    }
    return fileManager.fileExists(atPath: MaestroPaths.expandTilde(path, environment: environment))
  }

  private func legacyDate(_ value: String?, file: URL) -> Date {
    if let parsed = value.flatMap(nonEmpty).flatMap(Self.parseDate) {
      return parsed
    }
    if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
       let modifiedAt = attributes[.modificationDate] as? Date {
      return modifiedAt
    }
    return Date(timeIntervalSince1970: 0)
  }

  private func safeFileName(_ value: String) -> String {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    let scalars = value.unicodeScalars.map { scalar in
      allowed.contains(scalar) ? Character(scalar) : "-"
    }
    let result = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    return result.isEmpty ? UUID().uuidString : result
  }

  private func nonEmpty(_ value: String) -> String? {
    value.isEmpty ? nil : value
  }

  private static func parseDate(_ value: String) -> Date? {
    return ISO8601DateFormatter().date(from: value)
  }
}

public enum LegacyAgentEnvParser {
  public static func parse(_ text: String) -> [String: String] {
    var values: [String: String] = [:]
    for rawLine in text.split(whereSeparator: \.isNewline) {
      let line = String(rawLine)
      guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
        continue
      }
      let key = String(line[..<separator])
      guard isValidKey(key) else {
        continue
      }
      let rawValue = String(line[line.index(after: separator)...])
      values[key] = decodeShellEscaped(rawValue)
    }
    return values
  }

  private static func isValidKey(_ key: String) -> Bool {
    key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
  }

  private static func decodeShellEscaped(_ value: String) -> String {
    var output = ""
    var index = value.startIndex

    func appendEscapedCharacter() {
      guard index < value.endIndex else {
        return
      }
      output.append(value[index])
      index = value.index(after: index)
    }

    while index < value.endIndex {
      let character = value[index]
      if character == "\\" {
        index = value.index(after: index)
        appendEscapedCharacter()
      } else if character == "'" {
        index = value.index(after: index)
        while index < value.endIndex, value[index] != "'" {
          output.append(value[index])
          index = value.index(after: index)
        }
        if index < value.endIndex {
          index = value.index(after: index)
        }
      } else if character == "\"" {
        index = value.index(after: index)
        while index < value.endIndex, value[index] != "\"" {
          if value[index] == "\\" {
            index = value.index(after: index)
            appendEscapedCharacter()
          } else {
            output.append(value[index])
            index = value.index(after: index)
          }
        }
        if index < value.endIndex {
          index = value.index(after: index)
        }
      } else if character == "$",
                value.index(after: index) < value.endIndex,
                value[value.index(after: index)] == "'" {
        index = value.index(index, offsetBy: 2)
        while index < value.endIndex, value[index] != "'" {
          if value[index] == "\\" {
            index = value.index(after: index)
            appendANSISequence(value, index: &index, output: &output)
          } else {
            output.append(value[index])
            index = value.index(after: index)
          }
        }
        if index < value.endIndex {
          index = value.index(after: index)
        }
      } else {
        output.append(character)
        index = value.index(after: index)
      }
    }

    return output
  }

  private static func appendANSISequence(
    _ value: String,
    index: inout String.Index,
    output: inout String
  ) {
    guard index < value.endIndex else {
      output.append("\\")
      return
    }
    let character = value[index]
    index = value.index(after: index)
    switch character {
    case "n":
      output.append("\n")
    case "r":
      output.append("\r")
    case "t":
      output.append("\t")
    case "\\":
      output.append("\\")
    case "'":
      output.append("'")
    case "\"":
      output.append("\"")
    default:
      output.append(character)
    }
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
