import Darwin
import Foundation
import KioskCore

/// Serializes catalog revisions and commits each complete document by atomic replacement.
public actor CatalogRepository {
  public nonisolated enum Failure: Error {
    case invalidCatalog, staleRevision, corruptCatalog
  }

  public let fileURL: URL
  public init(fileURL: URL) { self.fileURL = fileURL }

  public func load() throws -> SettingsCatalog {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return SettingsCatalog() }
    let catalog: SettingsCatalog
    let data = try Data(contentsOf: fileURL)
    do {
      catalog = try JSONDecoder().decode(SettingsCatalog.self, from: data)
    } catch { throw Failure.corruptCatalog }
    guard catalog.isValid else { throw Failure.corruptCatalog }
    return catalog
  }

  public func save(_ catalog: SettingsCatalog) throws {
    guard catalog.isValid else { throw Failure.invalidCatalog }
    let current = try load()
    guard catalog.revision == ProfileRevision.next(after: current.revision) else {
      throw Failure.staleRevision
    }
    try Task.checkCancellation()
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let temporary = directory.appendingPathComponent(".catalog-\(UUID()).tmp")
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard
      FileManager.default.createFile(
        atPath: temporary.path, contents: try encoder.encode(catalog),
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
    guard Darwin.rename(temporary.path, fileURL.path) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  public func recoverDamaged() throws -> SettingsCatalog {
    do {
      _ = try load()
      throw Failure.invalidCatalog
    } catch Failure.corruptCatalog {
      let quarantine = fileURL.deletingLastPathComponent().appendingPathComponent(
        "catalog.invalid-\(UUID().uuidString).json")
      try FileManager.default.moveItem(at: fileURL, to: quarantine)
      return SettingsCatalog()
    }
  }
}
