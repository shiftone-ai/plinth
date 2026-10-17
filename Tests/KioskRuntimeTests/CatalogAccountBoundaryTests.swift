import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct CatalogAccountBoundaryTests {
  @Test func importedDeviceCopyWithSharedIdentifierCanResolveItsConflict() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let id = UUID()
    let local = try #require(CatalogEntry(id: id, name: "Local", snapshot: snapshot))
    let remote = try #require(
      CatalogEntry(
        id: id, name: "Shared", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    try load(
      fixture, SettingsCatalog(syncEnabled: true, accountIdentifier: "account-a", entries: [local]),
      account: "account-a")
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-a", [.upsert(remote)]), from: .cloudCatalog)
    try finishSave(fixture)
    let conflict = try #require(fixture.runtime.snapshot.root.catalog.conflicts.first)
    #expect(fixture.runtime.snapshot.root.catalogConflictAvailable(conflict))
    #expect(fixture.runtime.settingsProps.props.catalog.conflicts.map(\.id) == [id])
    #expect(
      fixture.runtime.send(
        .catalogConflictResolved(id, useRemote: false), from: .settings
      ).reply == .accepted)
    try finishSave(fixture)
    let chosen = try #require(fixture.runtime.snapshot.root.catalog.entries.first)
    #expect(chosen.name == "Local")
    #expect(chosen.scope == .iCloud)
    #expect(chosen.accountIdentifier == "account-a")
  }

  @Test func oldAccountDetailCannotMutateAnUnavailableEntry() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let entry = try #require(
      CatalogEntry(
        id: UUID(), name: "Old", snapshot: CatalogSnapshot(fixture.profile())!,
        scope: .iCloud, accountIdentifier: "account-a"))
    try load(
      fixture, SettingsCatalog(syncEnabled: true, accountIdentifier: "account-a", entries: [entry]),
      account: "account-a")
    #expect(
      fixture.runtime.send(.catalogSelectRequested(entry.id), from: .settings).reply == .accepted)
    #expect(
      fixture.runtime.send(.catalogRemovePromptRequested(entry.id), from: .settings).reply
        == .accepted)
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    fixture.runtime.send(.catalogCloudAccountChanged(session), from: .cloudCatalog)
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, "account-b"), source: .cloudCatalog)
    try finishSave(fixture)
    #expect(fixture.runtime.settingsProps.props.catalog.selectedEntry == nil)
    #expect(
      fixture.runtime.send(.catalogRenameRequested(id: entry.id, name: "Changed"), from: .settings)
        .reply == .rejected(.invalidState))
    #expect(
      fixture.runtime.send(
        .catalogVisibilityRequested(id: entry.id, visible: false), from: .settings
      )
      .reply == .rejected(.invalidState))
    #expect(
      fixture.runtime.send(.catalogRemoveConfirmed(entry.id), from: .settings).reply
        == .rejected(.invalidState))
    #expect(fixture.runtime.snapshot.root.catalog.pendingDeletions.isEmpty)
  }

  @Test func deletingACollidingRemoteEntryKeepsTheDeviceCopy() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let id = UUID()
    let local = try #require(CatalogEntry(id: id, name: "Device", snapshot: snapshot))
    let remote = try #require(
      CatalogEntry(
        id: id, name: "Shared", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    try load(
      fixture, SettingsCatalog(syncEnabled: true, accountIdentifier: "account-a", entries: [local]),
      account: "account-a")
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-a", [.upsert(remote)]), from: .cloudCatalog)
    try finishSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalog.conflicts.map(\.id) == [id])
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-a", [.delete(id)]), from: .cloudCatalog)
    try finishSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalog.conflicts.isEmpty)
    #expect(fixture.runtime.snapshot.root.catalog.entries == [local])
  }

  @Test func anotherAccountsDeletionDoesNotClearAnOlderConflict() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let id = UUID()
    let old = try #require(
      CatalogEntry(
        id: id, name: "Old", snapshot: CatalogSnapshot(fixture.profile())!,
        scope: .iCloud, accountIdentifier: "account-a"))
    try load(
      fixture,
      SettingsCatalog(
        syncEnabled: true, accountIdentifier: "account-b", entries: [old],
        conflicts: [.init(id: id, remote: old)]),
      account: "account-b")
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-b", [.delete(id)]), from: .cloudCatalog)
    #expect(fixture.runtime.snapshot.root.catalogSaveOperation == nil)
    if fixture.runtime.snapshot.root.catalogSaveOperation != nil { try finishSave(fixture) }
    #expect(fixture.runtime.snapshot.root.catalog.conflicts.map(\.id) == [id])
  }

  @Test func anAcknowledgementDoesNotClearOfflineStatus() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let entry = try #require(
      CatalogEntry(
        id: UUID(), name: "Shared", snapshot: CatalogSnapshot(fixture.profile())!,
        scope: .iCloud, accountIdentifier: "account-a"))
    try load(
      fixture, SettingsCatalog(syncEnabled: true, accountIdentifier: "account-a", entries: [entry]),
      account: "account-a")
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    fixture.runtime.send(.catalogCloudStatus(session, .offline), from: .cloudCatalog)
    fixture.runtime.send(
      .catalogCloudAcknowledged(session, "account-a", [entry.id: entry.version]),
      from: .cloudCatalog)
    #expect(fixture.runtime.snapshot.root.catalogSyncStatus == .offline)
    try finishSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalogSyncStatus == .offline)
  }

  @Test func backupOfAnUnavailableSharedEntryImportsAsADeviceCopy() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let id = UUID()
    let replacementID = UUID()
    let old = try #require(
      CatalogEntry(
        id: id, name: "Old", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    let incoming = try #require(CatalogEntry(id: id, name: "Old", snapshot: snapshot))
    try load(fixture, SettingsCatalog(accountIdentifier: "account-b", entries: [old]))
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    #expect(
      fixture.runtime.send(
        .catalogImportOperationRequested(file, passphrase: "long-enough-passphrase"),
        from: .administration
      ).reply == .accepted)
    let operation = try #require(fixture.runtime.snapshot.root.catalogImportOperation)
    fixture.port.deliver(
      .catalogImportPreviewReady(operation, [incoming]), source: .catalogRepository)
    #expect(fixture.runtime.settingsProps.props.catalog.importMatches[id] == .separateCopy)
    #expect(
      fixture.runtime.send(
        .catalogImportConfirmed(replacementIDs: [replacementID]), from: .settings
      )
      .reply == .accepted)
    try finishSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalog.entries.count == 2)
    let copy = try #require(
      fixture.runtime.snapshot.root.catalog.entries.first(where: { $0.id == replacementID }))
    #expect(copy.scope == .device)
    #expect(copy.name == "Old")
  }

  private func load(_ fixture: RuntimeFixture, _ document: SettingsCatalog, account: String? = nil)
    throws
  {
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(.catalogLoaded(load, document), source: .catalogRepository)
    if let account {
      let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
      fixture.port.deliver(.catalogAccountChecked(check, account), source: .cloudCatalog)
    }
  }

  private func finishSave(_ fixture: RuntimeFixture) throws {
    let token = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    let effect = try #require(fixture.port.effects.last(where: { $0.token == token }))
    guard case .saveCatalog(let document) = effect.kind else {
      Issue.record("Expected catalog save")
      return
    }
    fixture.port.deliver(.catalogSaved(token, document), source: .catalogRepository)
  }
}
