import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct CatalogLatestReviewTests {
  @Test func sharingRequiresACurrentCloudSession() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let entry = try #require(
      CatalogEntry(id: UUID(), name: "Local", snapshot: CatalogSnapshot(fixture.profile())!))
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(
        load,
        SettingsCatalog(
          syncEnabled: true, accountIdentifier: "account-a", entries: [entry])),
      source: .catalogRepository)
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, nil), source: .cloudCatalog)
    #expect(fixture.runtime.snapshot.root.catalogSyncStatus == .signInRequired)
    #expect(
      fixture.runtime.send(.catalogSelectRequested(entry.id), from: .settings).reply == .accepted)
    #expect(!fixture.runtime.settingsProps.props.catalog.canShare)
    #expect(
      fixture.runtime.send(.catalogSharePromptRequested(entry.id), from: .settings).reply
        == .rejected(.invalidState))

    fixture.runtime.send(.catalogSyncRetryRequested, from: .settings)
    let retry = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(retry, "account-a"), source: .cloudCatalog)
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    #expect(
      fixture.runtime.send(.catalogSharePromptRequested(entry.id), from: .settings).reply
        == .accepted)
    fixture.runtime.send(.catalogCloudAccountChanged(session), from: .cloudCatalog)
    #expect(
      fixture.runtime.send(.catalogShareConfirmed(entry.id), from: .settings).reply
        == .rejected(.invalidState))
  }

  @Test func cloudStartExcludesConflictsFromAnotherAppleAccount() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let old = try #require(
      CatalogEntry(
        id: UUID(), name: "Old", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    let current = try #require(
      CatalogEntry(
        id: UUID(), name: "Current", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-b"))
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(
        load,
        SettingsCatalog(
          syncEnabled: true, accountIdentifier: "account-b", entries: [old, current],
          conflicts: [
            .init(id: old.id, remote: old), .init(id: current.id, remote: current),
          ])),
      source: .catalogRepository)
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, "account-b"), source: .cloudCatalog)
    let effect = try #require(fixture.port.effects.last)
    guard case .startCatalogCloudSync(_, _, let conflicts, _) = effect.kind else {
      Issue.record("Expected cloud start")
      return
    }
    #expect(conflicts == [current.id])
  }

  @Test func fetchedEditIsPersistedAsAConflictBeforeAnyLocalPublish() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let id = UUID()
    let original = try #require(
      CatalogEntry(
        id: id, name: "Original", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a", syncedVersion: 1))
    let remote = try #require(
      CatalogEntry(
        id: id, name: "Remote", snapshot: snapshot, version: 2, scope: .iCloud,
        accountIdentifier: "account-a", syncedVersion: 2))
    try startCatalog(fixture, entries: [original])
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    #expect(
      fixture.runtime.send(
        .catalogRenameRequested(id: id, name: "Local"), from: .settings
      ).reply == .accepted)
    #expect(
      fixture.runtime.send(.catalogRenameConfirmed(id), from: .settings).reply == .accepted)
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-a", [.upsert(remote)]), from: .cloudCatalog)
    let before = fixture.port.effects.count
    try finishCatalogSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalogSaveOperation != nil)
    #expect(
      !fixture.port.effects.dropFirst(before).contains {
        if case .publishCatalogChanges = $0.kind { return true }
        return false
      })
    try finishCatalogSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalog.conflicts.first?.remote?.name == "Remote")
    #expect(
      !fixture.port.effects.dropFirst(before).contains {
        if case .publishCatalogChanges = $0.kind { return true }
        return false
      })
  }

  @Test func choosingRemoteAfterZoneLossQueuesTheChosenVersion() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let id = UUID()
    let local = try #require(
      CatalogEntry(
        id: id, name: "Local", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a", syncedVersion: 1))
    let remote = try #require(
      CatalogEntry(
        id: id, name: "Remote", snapshot: snapshot, version: 2, scope: .iCloud,
        accountIdentifier: "account-a", syncedVersion: 2))
    try startCatalog(fixture, entries: [local], conflicts: [.init(id: id, remote: remote)])
    #expect(
      fixture.runtime.send(
        .catalogConflictResolved(id, useRemote: true), from: .settings
      ).reply == .accepted)
    let before = fixture.port.effects.count
    try finishCatalogSave(fixture)
    #expect(
      fixture.port.effects.dropFirst(before).contains {
        if case .publishCatalogChanges(_, let resolved, let saves, _) = $0.kind {
          return resolved.contains(id)
            && saves.contains(where: { $0.id == id && $0.name == "Remote" })
        }
        return false
      })
  }

  private func startCatalog(
    _ fixture: RuntimeFixture, entries: [CatalogEntry], conflicts: [CatalogConflict] = []
  ) throws {
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(
        load,
        SettingsCatalog(
          syncEnabled: true, accountIdentifier: "account-a", entries: entries,
          conflicts: conflicts)),
      source: .catalogRepository)
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, "account-a"), source: .cloudCatalog)
  }

  private func finishCatalogSave(_ fixture: RuntimeFixture) throws {
    let token = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    let effect = try #require(fixture.port.effects.last(where: { $0.token == token }))
    guard case .saveCatalog(let document) = effect.kind else {
      Issue.record("Expected catalog save")
      return
    }
    fixture.port.deliver(.catalogSaved(token, document), source: .catalogRepository)
  }
}
