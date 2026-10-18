import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct CatalogSyncDisabledTests {
  @Test func aBuildWithoutCloudKitCannotEditCachedSharedEntries() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let shared = try #require(
      CatalogEntry(
        id: UUID(), name: "Shared", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    let device = try #require(CatalogEntry(id: UUID(), name: "Device", snapshot: snapshot))
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogCloudCapabilityUnavailable, from: .platform)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(
        load,
        SettingsCatalog(
          syncEnabled: true, accountIdentifier: "account-a", entries: [shared, device])),
      source: .catalogRepository)
    #expect(fixture.runtime.snapshot.root.catalogSyncStatus == .offline)
    #expect(fixture.runtime.settingsProps.props.catalog.visibleEntries.map(\.id) == [device.id])
    #expect(
      fixture.runtime.send(.catalogRemovePromptRequested(shared.id), from: .settings).reply
        == .rejected(.invalidState))
    #expect(fixture.runtime.snapshot.root.catalog.pendingDeletions.isEmpty)
  }

  @Test func disablingSyncHidesCachedEntriesFromAnUnverifiedAccount() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let shared = try #require(
      CatalogEntry(
        id: UUID(), name: "Shared", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    let device = try #require(CatalogEntry(id: UUID(), name: "Device", snapshot: snapshot))
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(
        load,
        SettingsCatalog(
          syncEnabled: true, accountIdentifier: "account-a", entries: [shared, device])),
      source: .catalogRepository)
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, "account-a"), source: .cloudCatalog)
    #expect(
      fixture.runtime.send(.catalogSelectRequested(shared.id), from: .settings).reply == .accepted)
    #expect(fixture.runtime.send(.catalogSyncDisableRequested, from: .settings).reply == .accepted)
    let saving = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    let document = try #require(fixture.runtime.snapshot.root.pendingCatalog)
    fixture.port.deliver(.catalogSaved(saving, document), source: .catalogRepository)
    fixture.runtime.send(.catalogAccountAvailabilityChanged, from: .cloudCatalog)
    #expect(fixture.runtime.settingsProps.props.catalog.visibleEntries.map(\.id) == [device.id])
    #expect(fixture.runtime.settingsProps.props.catalog.selectedEntry == nil)
    #expect(
      fixture.runtime.send(.catalogRemovePromptRequested(shared.id), from: .settings).reply
        == .rejected(.invalidState))
    #expect(fixture.runtime.snapshot.root.catalog.pendingDeletions.isEmpty)
    #expect(fixture.runtime.snapshot.root.catalog.entries.count == 2)
  }
}
