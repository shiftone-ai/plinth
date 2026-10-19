import CloudKit
import Foundation
import KioskCore
import Testing

@testable import KioskRuntime

struct CatalogCloudReplayTests {
  @Test func mixedSendFailuresRequireRetryRegardlessOfErrorOrder() {
    let orders: [[CatalogSyncStatus]] = [[.failed, .offline], [.offline, .failed]]
    for statuses in orders {
      var failures = CatalogCloudSync.SendFailures()
      for status in statuses { failures.record(status) }
      #expect(failures.hasNonretryable)
      #expect(failures.status == .failed)
    }
    var transient = CatalogCloudSync.SendFailures()
    transient.record(.offline)
    #expect(!transient.hasNonretryable)
    #expect(transient.status == .offline)
  }

  @Test func zoneSaveFailureSurvivesRestartAndOlderCachesRemainReadable() throws {
    let disk = CatalogCloudSync.DiskState(
      accountIdentifier: "account-a", engineState: nil, entries: [:],
      serverEntries: [:], serverDeletions: [], recordSystemFields: [:], conflicts: [],
      zoneSaveFailed: true)
    let encoded = try JSONEncoder().encode(disk)
    #expect(try JSONDecoder().decode(CatalogCloudSync.DiskState.self, from: encoded).zoneSaveFailed)

    var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    legacy.removeValue(forKey: "zoneSaveFailed")
    let legacyData = try JSONSerialization.data(withJSONObject: legacy)
    #expect(
      try !JSONDecoder().decode(CatalogCloudSync.DiskState.self, from: legacyData).zoneSaveFailed)
  }

  @Test func failedSendDoesNotBecomeReadyAfterEngineDropsItsPendingChange() {
    let disk = CatalogCloudSync.DiskState(
      accountIdentifier: "account-a", engineState: nil, entries: [:],
      serverEntries: [:], serverDeletions: [], recordSystemFields: [:], conflicts: [])

    #expect(
      !CatalogCloudSync.canReportReady(
        sendFailed: true, pendingRecordChanges: false, pendingDatabaseChanges: false,
        bufferedPublications: false, disk: disk))
    #expect(
      CatalogCloudSync.canReportReady(
        sendFailed: false, pendingRecordChanges: false, pendingDatabaseChanges: false,
        bufferedPublications: false, disk: disk))
    #expect(
      !CatalogCloudSync.canReportReady(
        sendFailed: false, pendingRecordChanges: false, pendingDatabaseChanges: false,
        bufferedPublications: true, disk: disk))
  }

  @Test @MainActor func cachedDeletionDoesNotReplaceANeverSyncedCreate() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let id = UUID()
    let newEntry = try #require(
      CatalogEntry(
        id: id, name: "Restored", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    let disk = CatalogCloudSync.DiskState(
      accountIdentifier: "account-a", engineState: nil, entries: [id: newEntry],
      serverEntries: [:], serverDeletions: [id], recordSystemFields: [:], conflicts: [])

    #expect(
      CatalogCloudSync.cachedReplay(disk: disk, local: [id: newEntry], pendingDeletions: []).isEmpty
    )

    var previouslySynced = newEntry
    previouslySynced.syncedVersion = 1
    #expect(
      CatalogCloudSync.cachedReplay(
        disk: disk, local: [id: previouslySynced], pendingDeletions: []) == [.delete(id)])
    #expect(
      CatalogCloudSync.cachedReplay(
        disk: disk, local: [:],
        pendingDeletions: [.init(id: id, accountIdentifier: "account-a", baseVersion: 1)])
        == [.delete(id)])
  }

  @Test func restoredPendingChangesWaitForConflictResolution() {
    let id = UUID()
    let otherID = UUID()
    let zone = CKRecordZone.ID(zoneName: "SettingsCatalog")
    let changes: [CKSyncEngine.PendingRecordZoneChange] = [
      .saveRecord(.init(recordName: id.uuidString, zoneID: zone)),
      .deleteRecord(.init(recordName: id.uuidString, zoneID: zone)),
      .saveRecord(.init(recordName: otherID.uuidString, zoneID: zone)),
    ]
    var disk = CatalogCloudSync.DiskState(
      accountIdentifier: "account-a", engineState: nil, entries: [:],
      serverEntries: [:], serverDeletions: [], recordSystemFields: [:], conflicts: [id])

    let stale = CatalogCloudSync.conflictingChanges(changes, disk: disk)
    #expect(stale == Array(changes.prefix(2)))
    #expect(CatalogCloudSync.sendableChanges(changes, disk: disk) == [changes[2]])
    disk.conflicts.remove(id)
    #expect(CatalogCloudSync.sendableChanges([changes[2]], disk: disk) == [changes[2]])
  }

  @Test func committedLocalResolutionReplacesCachedConflictOnRestart() throws {
    let snapshot = try #require(
      CatalogSnapshot(
        KioskProfile(startURL: "https://example.com", navigation: NavigationPolicy(rules: []))))
    let remote = try #require(
      CatalogEntry(
        id: UUID(), name: "Remote", snapshot: snapshot, version: 2, scope: .iCloud,
        accountIdentifier: "account-a", syncedVersion: 2))
    var chosenLocal = remote
    chosenLocal.name = "Local"
    chosenLocal.version = 3
    chosenLocal.syncedVersion = 1
    let disk = CatalogCloudSync.DiskState(
      accountIdentifier: "account-a", engineState: nil, entries: [remote.id: remote],
      serverEntries: [remote.id: remote], serverDeletions: [],
      recordSystemFields: [:], conflicts: [remote.id])

    #expect(
      CatalogCloudSync.cachedReplay(
        disk: disk, local: [remote.id: chosenLocal], pendingDeletions: [],
        unresolvedConflicts: []
      ) == [.upsert(remote)])
    chosenLocal.resolvedConflictVersion = 3
    #expect(
      CatalogCloudSync.cachedReplay(
        disk: disk, local: [remote.id: chosenLocal], pendingDeletions: [],
        unresolvedConflicts: []
      ).isEmpty)
    #expect(
      CatalogCloudSync.cachedReplay(
        disk: disk, local: [remote.id: chosenLocal], pendingDeletions: [],
        unresolvedConflicts: [remote.id]) == [.upsert(remote)])

    var queuedOnDisk = disk
    queuedOnDisk.conflicts.remove(remote.id)
    queuedOnDisk.entries[remote.id] = chosenLocal
    #expect(
      CatalogCloudSync.cachedReplay(
        disk: queuedOnDisk, local: [remote.id: chosenLocal], pendingDeletions: []
      ).isEmpty)
    queuedOnDisk.entries[remote.id]?.resolvedConflictVersion = nil
    chosenLocal.resolvedConflictVersion = nil
    #expect(
      CatalogCloudSync.cachedReplay(
        disk: queuedOnDisk, local: [remote.id: chosenLocal], pendingDeletions: [])
        == [.upsert(remote)])
  }

}
