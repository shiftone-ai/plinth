import CloudKit
import Foundation
import KioskCore
import Testing

@testable import KioskRuntime

struct CatalogValidationTests {
  @Test func anotherRecordTypeWithACatalogIdentifierBlocksReconciliation() {
    let id = UUID()
    let recordID = CKRecord.ID(
      recordName: id.uuidString, zoneID: CKRecordZone.ID(zoneName: "SettingsCatalog"))
    let record = CKRecord(recordType: "OtherEntry", recordID: recordID)
    #expect(
      CatalogCloudSync.classifyFetchedRecord(record, accountIdentifier: "account-a")
        == .opaque(id))
  }

  @Test @MainActor func contradictoryCloudCacheIsQuarantined() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let entry = try #require(
      CatalogEntry(
        id: UUID(), name: "Shared", snapshot: CatalogSnapshot(fixture.profile())!,
        scope: .iCloud, accountIdentifier: "account-a"))
    let disk = CatalogCloudSync.DiskState(
      accountIdentifier: "account-a", engineState: nil, entries: [:],
      serverEntries: [entry.id: entry], serverDeletions: [entry.id],
      recordSystemFields: [:], conflicts: [])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-contradictory-cloud-cache-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("catalog-cloud.json")
    try JSONEncoder().encode(disk).write(to: file)
    #expect(try CatalogCloudSync.loadDisk(at: file) == nil)
    #expect(!FileManager.default.fileExists(atPath: file.path))
  }

  @Test @MainActor func whitespaceOnlyCatalogNameIsRejectedDuringLoad() async throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-invalid-catalog-name-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var entry = try #require(
      CatalogEntry(id: UUID(), name: "Shared", snapshot: CatalogSnapshot(fixture.profile())!))
    entry.name = "   "
    let file = directory.appendingPathComponent("catalog.json")
    try JSONEncoder().encode(SettingsCatalog(entries: [entry])).write(to: file)
    await #expect(throws: CatalogRepository.Failure.corruptCatalog) {
      try await CatalogRepository(fileURL: file).load()
    }
  }
}
