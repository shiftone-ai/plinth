import Foundation
import KioskCore
import Testing

@testable import KioskRuntime

@MainActor
struct CatalogInitialFetchTests {
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
    let changes = fetch.reconcile(&disk)
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
}
