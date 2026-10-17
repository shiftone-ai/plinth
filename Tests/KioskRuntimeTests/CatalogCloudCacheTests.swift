import Foundation
import Testing

@testable import KioskRuntime

struct CatalogCloudCacheTests {
  @Test func unreadableCloudCacheIsPreservedBeforeFreshStateIsLoaded() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-cloud-cache-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("catalog-cloud.json")
    let corrupt = Data("{\"accountIdentifier\":".utf8)
    try corrupt.write(to: file)

    #expect(try CatalogCloudSync.loadDisk(at: file)?.accountIdentifier == nil)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    let quarantined = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.hasPrefix("catalog-cloud.json.invalid-") }
    #expect(quarantined.count == 1)
    #expect(try Data(contentsOf: quarantined[0]) == corrupt)

    let fresh = CatalogCloudSync.DiskState(
      accountIdentifier: "account-a", engineState: nil, entries: [:], serverEntries: [:],
      serverDeletions: [], recordSystemFields: [:], conflicts: [])
    try JSONEncoder().encode(fresh).write(to: file)
    #expect(try CatalogCloudSync.loadDisk(at: file)?.accountIdentifier == "account-a")
  }
}
