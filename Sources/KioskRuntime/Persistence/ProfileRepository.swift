import Darwin
import Foundation
import KioskCore

/// Serializes revision checks and atomic replacement independently of UI execution.
public actor ProfileRepository {
  public nonisolated enum Failure: Error { case invalidProfile, staleRevision, corruptProfile }
  public let fileURL: URL
  public init(fileURL: URL) { self.fileURL = fileURL }

  public func load() throws -> KioskProfile? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    let profile: KioskProfile
    do {
      profile = try JSONDecoder().decode(KioskProfile.self, from: Data(contentsOf: fileURL))
    } catch { throw Failure.corruptProfile }
    guard profile.validationIssues.isEmpty else { throw Failure.corruptProfile }
    return profile
  }

  public func save(_ profile: KioskProfile) throws {
    guard profile.validationIssues.isEmpty else { throw Failure.invalidProfile }
    let current = try load()
    guard profile.revision == ProfileRevision.next(after: current?.revision) else {
      throw Failure.staleRevision
    }
    try Task.checkCancellation()
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let temporary = directory.appendingPathComponent(".profile-\(UUID()).tmp")
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard
      FileManager.default.createFile(
        atPath: temporary.path, contents: try encoder.encode(profile),
        attributes: [.posixPermissions: 0o600])
    else { throw CocoaError(.fileWriteUnknown) }
    let handle = try FileHandle(forWritingTo: temporary)
    do {
      try handle.synchronize()
      try handle.close()
    } catch {
      try? handle.close()
      throw error
    }
    try Task.checkCancellation()
    // rename is the commit point. No throwable work follows it, so a committed write is reported as success.
    guard Darwin.rename(temporary.path, fileURL.path) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }
}
