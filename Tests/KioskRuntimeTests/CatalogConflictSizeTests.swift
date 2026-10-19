import Foundation
import KioskCore
import Testing

@testable import KioskRuntime

@MainActor
struct CatalogConflictSizeTests {
  @Test func oversizedLocalConflictChoiceShowsSizeWarningAndStaysDisabled() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let large = try oversizedProfile(from: fixture.profile())
    let local = try #require(
      CatalogEntry(id: UUID(), name: "Large local", snapshot: CatalogSnapshot(large)!))
    let remote = try #require(
      CatalogEntry(
        id: local.id, name: "Remote", snapshot: CatalogSnapshot(fixture.profile())!,
        scope: .iCloud, accountIdentifier: "account-a"))
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(
        load,
        SettingsCatalog(syncEnabled: true, accountIdentifier: "account-a", entries: [local])),
      source: .catalogRepository)
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, "account-a"), source: .cloudCatalog)
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-a", [.upsert(remote)]), from: .cloudCatalog)
    let save = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    fixture.port.deliver(
      .catalogSaved(save, try #require(fixture.runtime.snapshot.root.pendingCatalog)),
      source: .catalogRepository)

    #expect(fixture.runtime.settingsProps.props.catalog.oversizedConflictLocalIDs == [local.id])
    #expect(
      fixture.runtime.send(.catalogConflictResolved(local.id, useRemote: false), from: .settings)
        .reply == .rejected(.invalidProfile))
  }

  private func oversizedProfile(from initial: KioskProfile) throws -> KioskProfile {
    var profile = initial
    profile.startURL += String(repeating: "a", count: 920_000)
    try #require(profile.validationIssues.isEmpty)
    return profile
  }
}
