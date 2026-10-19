import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct CatalogLegacyConflictTests {
  @Test func deletionConflictWithoutStoredAccountDoesNotBlockAnotherAccountsItem() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let id = UUID()
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let old = try #require(
      CatalogEntry(
        id: id, name: "Old", snapshot: snapshot, version: 2, scope: .iCloud,
        accountIdentifier: "account-a", syncedVersion: 1))
    let current = try #require(
      CatalogEntry(
        id: id, name: "Current", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-b"))
    let document = SettingsCatalog(
      syncEnabled: true, accountIdentifier: "account-b", entries: [old, current],
      conflicts: [.init(id: id, remote: nil)])
    var json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
    var conflicts = try #require(json["conflicts"] as? [[String: Any]])
    conflicts[0].removeValue(forKey: "accountIdentifier")
    json["conflicts"] = conflicts
    let legacy = try JSONDecoder().decode(
      SettingsCatalog.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(legacy.isValid)
    #expect(legacy.conflictBelongsToAccount(legacy.conflicts[0], accountIdentifier: "account-a"))
    #expect(!legacy.conflictBelongsToAccount(legacy.conflicts[0], accountIdentifier: "account-b"))

    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(.catalogLoaded(load, legacy), source: .catalogRepository)
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, "account-b"), source: .cloudCatalog)
    #expect(fixture.runtime.settingsProps.props.catalog.conflicts.isEmpty)
    #expect(
      fixture.runtime.send(
        .catalogRenameRequested(id: id, name: "Renamed"), from: .settings
      ).reply == .accepted)
  }
}
