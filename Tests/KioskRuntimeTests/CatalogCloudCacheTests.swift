import CloudKit
import Foundation
import KioskCore
import Testing

@testable import KioskRuntime

struct CatalogCloudCacheTests {
  @Test @MainActor func publicationsQueuedDuringStartAreAppliedInOrder() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let id = UUID()
    let first = try #require(
      CatalogEntry(
        id: id, name: "First", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    let second = try #require(
      CatalogEntry(
        id: id, name: "Second", snapshot: snapshot, version: 2, scope: .iCloud,
        accountIdentifier: "account-a"))
    let session = OperationToken(owner: .root, operationID: 1)
    var buffer = CatalogPublicationBuffer()
    buffer.append(
      .init(
        command: .init(owner: .root, operationID: 3), session: session,
        resolvedConflicts: [], saves: [second], deletions: []))
    buffer.append(
      .init(
        command: .init(owner: .root, operationID: 2), session: session,
        resolvedConflicts: [], saves: [first], deletions: []))
    #expect(buffer.takeNext(for: session)?.saves == [first])
    #expect(buffer.takeNext(for: session)?.saves == [second])
    buffer.append(
      .init(
        command: .init(owner: .root, operationID: 2), session: session,
        resolvedConflicts: [], saves: [first], deletions: []))
    #expect(buffer.takeNext(for: session) == nil)
    let another = try #require(
      CatalogEntry(
        id: UUID(), name: "Another", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    buffer.append(
      .init(
        command: .init(owner: .root, operationID: 2), session: session,
        resolvedConflicts: [], saves: [another], deletions: []))
    #expect(buffer.takeNext(for: session)?.saves == [another])
  }
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

  @Test @MainActor func aFetchedEditBlocksDeletionOfAnOlderVersion() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let id = UUID()
    let remote = try #require(
      CatalogEntry(
        id: id, name: "Changed elsewhere", snapshot: snapshot, version: 3,
        scope: .iCloud, accountIdentifier: "account-a", syncedVersion: 3))
    let deletion = CatalogPendingDeletion(
      id: id, accountIdentifier: "account-a", baseVersion: 2)
    #expect(
      CatalogCloudSync.fetchedChangeConflictingWithDeletion(
        deletion, serverEntries: [id: remote]) == .upsert(remote))
    let resolved = CatalogPendingDeletion(
      id: id, accountIdentifier: "account-a", baseVersion: 3)
    #expect(
      CatalogCloudSync.fetchedChangeConflictingWithDeletion(
        resolved, serverEntries: [id: remote]) == nil)
  }

  @Test @MainActor func acceptingAServerDeletionRemovesTheCachedEntry() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let id = UUID()
    let stale = try #require(
      CatalogEntry(
        id: id, name: "Stale", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    var disk = CatalogCloudSync.DiskState(
      accountIdentifier: "account-a", engineState: nil, entries: [id: stale],
      serverEntries: [:], serverDeletions: [id], recordSystemFields: [:], conflicts: [id])
    let removed = CatalogCloudSync.dropResolvedServerDeletions(
      resolvedConflicts: [id], saves: [], disk: &disk)
    #expect(removed == [id])
    #expect(disk.entries[id] == nil)
  }

  @Test func temporaryDeleteFailuresKeepTheOfflineStatus() {
    #expect(CatalogCloudSync.isTransient(CKError(.networkUnavailable)))
    #expect(CatalogCloudSync.isTransient(CKError(.operationCancelled)))
    #expect(!CatalogCloudSync.isTransient(CKError(.permissionFailure)))
  }
}
