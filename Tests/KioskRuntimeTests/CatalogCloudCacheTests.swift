import Foundation
import KioskCore
import Testing

@testable import KioskRuntime

struct CatalogCloudCacheTests {
  @Test @MainActor func aFetchedChangeBlocksAnUnreconciledLocalSave() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let id = UUID()
    let local = try #require(
      CatalogEntry(
        id: id, name: "Local", snapshot: snapshot, version: 2, scope: .iCloud,
        accountIdentifier: "account-a", syncedVersion: 1))
    let remote = try #require(
      CatalogEntry(
        id: id, name: "Remote", snapshot: snapshot, version: 2, scope: .iCloud,
        accountIdentifier: "account-a", syncedVersion: 2))
    #expect(
      CatalogCloudSync.fetchedChangeConflictingWithSave(
        local, serverEntries: [id: remote], serverDeletions: [], resolvedConflicts: [])
        == .upsert(remote))
    #expect(
      CatalogCloudSync.fetchedChangeConflictingWithSave(
        local, serverEntries: [:], serverDeletions: [id], resolvedConflicts: [])
        == .delete(id))
    #expect(
      CatalogCloudSync.fetchedChangeConflictingWithSave(
        local, serverEntries: [:], serverDeletions: [], resolvedConflicts: []) == nil)
    var chosenLocal = local
    chosenLocal.version = 3
    #expect(
      CatalogCloudSync.fetchedChangeConflictingWithSave(
        chosenLocal, serverEntries: [id: remote], serverDeletions: [],
        resolvedConflicts: [id]) == nil)
  }

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
