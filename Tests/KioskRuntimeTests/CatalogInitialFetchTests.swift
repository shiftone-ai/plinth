import Foundation
import KioskCore
import Testing

@testable import KioskRuntime

@MainActor
struct CatalogInitialFetchTests {
  @Test func fullFetchClearsOpaqueRecordsThatDisappearedFromCloud() throws {
    let snapshot = try #require(
      CatalogSnapshot(
        KioskProfile(startURL: "https://example.com", navigation: NavigationPolicy(rules: []))))
    let stale = try #require(
      CatalogEntry(
        id: UUID(), name: "Stale", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a", syncedVersion: 1))
    let cacheOnly = try #require(
      CatalogEntry(
        id: UUID(), name: "Cached but not saved", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a", syncedVersion: 1))
    let retained = UUID()
    var disk = CatalogCloudSync.DiskState(
      accountIdentifier: "account-a", engineState: nil, entries: [stale.id: stale],
      serverEntries: [cacheOnly.id: cacheOnly], serverDeletions: [],
      recordSystemFields: [cacheOnly.id: Data("old fields".utf8)], conflicts: [],
      opaqueRecordIDs: [stale.id, cacheOnly.id, retained])
    var fetch = CatalogInitialFetch(
      entries: disk.entries, pendingDeletions: [], opaqueRecordIDs: disk.opaqueRecordIDs)
    fetch.observe(retained)

    let changes = fetch.reconcile(&disk).changes
    #expect(changes.count == 2)
    #expect(changes.contains(.delete(stale.id)))
    #expect(changes.contains(.delete(cacheOnly.id)))
    #expect(disk.opaqueRecordIDs == [retained])
    #expect(disk.entries[stale.id] == nil)
    #expect(disk.serverEntries[cacheOnly.id] == nil)
    #expect(disk.recordSystemFields[cacheOnly.id] == nil)
  }

  @Test func rebuildingTheCacheRemovesARecordDeletedWhileAnotherAccountWasActive() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let stale = try #require(
      CatalogEntry(
        id: UUID(), name: "Deleted elsewhere", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a", syncedVersion: 1))
    let retained = try #require(
      CatalogEntry(
        id: UUID(), name: "Still on iCloud", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a", syncedVersion: 1))
    let newLocal = try #require(
      CatalogEntry(
        id: UUID(), name: "New local change", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    var disk = CatalogCloudSync.DiskState(
      accountIdentifier: "account-a", engineState: nil,
      entries: [stale.id: stale, retained.id: retained, newLocal.id: newLocal],
      serverEntries: [stale.id: stale], serverDeletions: [], recordSystemFields: [:], conflicts: [])
    var fetch = CatalogInitialFetch(
      entries: disk.entries, pendingDeletions: [], opaqueRecordIDs: [])
    fetch.observe(retained.id)
    let changes = fetch.reconcile(&disk).changes
    #expect(changes == [.delete(stale.id)])
    #expect(disk.serverDeletions == [stale.id])
    #expect(disk.entries[stale.id] == nil)
    #expect(disk.entries[retained.id] == retained)
    #expect(disk.entries[newLocal.id] == newLocal)

    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(
        load,
        SettingsCatalog(
          syncEnabled: true, accountIdentifier: "account-a",
          entries: [stale, retained, newLocal])), source: .catalogRepository)
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, "account-a"), source: .cloudCatalog)
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    fixture.runtime.send(.catalogCloudChanges(session, "account-a", changes), from: .cloudCatalog)
    let save = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    fixture.port.deliver(
      .catalogSaved(save, try #require(fixture.runtime.snapshot.root.pendingCatalog)),
      source: .catalogRepository)
    #expect(!fixture.runtime.snapshot.root.catalog.entries.contains { $0.id == stale.id })
    #expect(fixture.runtime.snapshot.root.catalog.entries.contains { $0.id == retained.id })
    #expect(fixture.runtime.snapshot.root.catalog.entries.contains { $0.id == newLocal.id })
  }

  @Test func vanishedOpaqueRecordResumesNeverSyncedLocalCreate() throws {
    let snapshot = try #require(
      CatalogSnapshot(
        KioskProfile(startURL: "https://example.com", navigation: NavigationPolicy(rules: []))))
    let local = try #require(
      CatalogEntry(
        id: UUID(), name: "Local create", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    var disk = CatalogCloudSync.DiskState(
      accountIdentifier: "account-a", engineState: nil, entries: [local.id: local],
      serverEntries: [local.id: local], serverDeletions: [],
      recordSystemFields: [local.id: Data("old fields".utf8)], conflicts: [local.id],
      opaqueRecordIDs: [local.id])
    let fetch = CatalogInitialFetch(
      entries: disk.entries, pendingDeletions: [], opaqueRecordIDs: disk.opaqueRecordIDs)

    let result = fetch.reconcile(&disk)
    #expect(result.changes.isEmpty)
    #expect(result.resumingSaves == [local.id])
    #expect(!disk.conflicts.contains(local.id))
    #expect(disk.entries[local.id] == local)
    #expect(disk.serverEntries[local.id] == nil)
    #expect(disk.recordSystemFields[local.id] == nil)
    #expect(disk.opaqueRecordIDs.isEmpty)
  }
}
