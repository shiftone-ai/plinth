import CloudKit
import Foundation
import KioskCore
import Testing

@testable import KioskRuntime

struct CatalogOpaqueRecoveryTests {
  @Test func incrementalOpaqueDeletionResumesNeverSyncedSave() throws {
    let snapshot = try #require(
      CatalogSnapshot(
        KioskProfile(startURL: "https://example.com", navigation: NavigationPolicy(rules: []))))
    let local = try #require(
      CatalogEntry(
        id: UUID(), name: "Local", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    var disk = CatalogCloudSync.DiskState(
      accountIdentifier: "account-a", engineState: nil, entries: [local.id: local],
      serverEntries: [local.id: local], serverDeletions: [],
      recordSystemFields: [local.id: Data("old fields".utf8)], conflicts: [],
      opaqueRecordIDs: [local.id])

    let change = CatalogCloudSync.reconcileDeletedOpaqueRecord(local.id, disk: &disk)
    #expect(
      change
        == .saveRecord(
          CKRecord.ID(
            recordName: local.id.uuidString,
            zoneID: CKRecordZone.ID(zoneName: "SettingsCatalog"))))
    #expect(disk.entries[local.id] == local)
    #expect(disk.serverEntries[local.id] == nil)
    #expect(disk.recordSystemFields[local.id] == nil)
    #expect(!disk.serverDeletions.contains(local.id))
    #expect(disk.opaqueRecordIDs.isEmpty)
  }

  @Test func readableOpaqueRecordResumesMatchingPendingDeletion() throws {
    let snapshot = try #require(
      CatalogSnapshot(
        KioskProfile(startURL: "https://example.com", navigation: NavigationPolicy(rules: []))))
    let remote = try #require(
      CatalogEntry(
        id: UUID(), name: "Remote", snapshot: snapshot, version: 2, scope: .iCloud,
        accountIdentifier: "account-a", syncedVersion: 2))
    var disk = CatalogCloudSync.DiskState(
      accountIdentifier: "account-a", engineState: nil, entries: [:],
      serverEntries: [:], serverDeletions: [remote.id], recordSystemFields: [:],
      conflicts: [remote.id], opaqueRecordIDs: [remote.id])
    let deletion = CatalogPendingDeletion(
      id: remote.id, accountIdentifier: "account-a", baseVersion: 2)

    let change = CatalogCloudSync.reconcileReadableOpaqueRecord(
      remote, systemFields: Data("current fields".utf8), pendingDeletion: deletion,
      disk: &disk)
    #expect(
      change
        == .deleteRecord(
          CKRecord.ID(
            recordName: remote.id.uuidString,
            zoneID: CKRecordZone.ID(zoneName: "SettingsCatalog"))))
    #expect(disk.serverEntries[remote.id] == remote)
    #expect(disk.recordSystemFields[remote.id] == Data("current fields".utf8))
    #expect(!disk.serverDeletions.contains(remote.id))
    #expect(!disk.conflicts.contains(remote.id))
    #expect(disk.opaqueRecordIDs.isEmpty)

    disk.opaqueRecordIDs.insert(remote.id)
    #expect(
      CatalogCloudSync.reconcileReadableOpaqueRecord(
        remote, systemFields: Data(),
        pendingDeletion: .init(id: remote.id, accountIdentifier: "account-a", baseVersion: 1),
        disk: &disk) == nil)
  }

}
