import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct CatalogReviewRoundTenTests {
  @Test func firstReceivedChangeSurvivesALocalSaveFailure() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let remote = try #require(
      CatalogEntry(
        id: UUID(), name: "Remote", snapshot: CatalogSnapshot(fixture.profile())!,
        scope: .iCloud, accountIdentifier: "account-a"))
    let session = try start(
      fixture,
      catalog: SettingsCatalog(
        syncEnabled: true, accountIdentifier: "account-a"))
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-a", [.upsert(remote)]), from: .cloudCatalog)
    let failed = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    fixture.port.deliver(.catalogSaveFailed(failed), source: .catalogRepository)
    let retry = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    #expect(retry != failed)
    try finishSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalog.entries.contains { $0.id == remote.id })
  }

  @Test func firstAcknowledgementsSurviveALocalSaveFailure() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let entry = try #require(
      CatalogEntry(
        id: UUID(), name: "Shared", snapshot: CatalogSnapshot(fixture.profile())!,
        scope: .iCloud, accountIdentifier: "account-a"))
    let removedID = UUID()
    let session = try start(
      fixture,
      catalog: SettingsCatalog(
        syncEnabled: true, accountIdentifier: "account-a", entries: [entry],
        pendingDeletions: [.init(id: removedID, accountIdentifier: "account-a")]))
    fixture.runtime.send(
      .catalogCloudAcknowledged(session, "account-a", [entry.id: entry.version]),
      from: .cloudCatalog)
    let failed = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    fixture.port.deliver(.catalogSaveFailed(failed), source: .catalogRepository)
    try finishSave(fixture)
    #expect(
      fixture.runtime.snapshot.root.catalog.entries.first { $0.id == entry.id }?.syncedVersion
        == entry.version)
    fixture.runtime.send(
      .catalogCloudDeletionsAcknowledged(session, "account-a", [removedID]),
      from: .cloudCatalog)
    let deletionFailed = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    fixture.port.deliver(.catalogSaveFailed(deletionFailed), source: .catalogRepository)
    try finishSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalog.pendingDeletions.isEmpty)
  }

  @Test func importedCopyOfAPendingDeletionGetsANewIdentifier() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let item = try #require(
      CatalogEntry(id: UUID(), name: "Backup", snapshot: CatalogSnapshot(fixture.profile())!))
    let replacementID = UUID()
    _ = try start(
      fixture,
      catalog: SettingsCatalog(
        syncEnabled: true, accountIdentifier: "account-a",
        pendingDeletions: [.init(id: item.id, accountIdentifier: "account-a")]))
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(
      "backup.plinthsettings")
    fixture.runtime.send(
      .catalogImportOperationRequested(file, passphrase: "long-enough-passphrase"),
      from: .administration)
    let operation = try #require(fixture.runtime.snapshot.root.catalogImportOperation)
    fixture.port.deliver(
      .catalogImportPreviewReady(operation, [item]), source: .catalogRepository)
    #expect(
      fixture.runtime.send(
        .catalogImportConfirmed(replacementIDs: [replacementID]), from: .settings
      ).reply == .accepted)
    let pending = try #require(fixture.runtime.snapshot.root.pendingCatalog)
    #expect(pending.isValid)
    #expect(pending.entries.map(\.id) == [replacementID])
    #expect(pending.pendingDeletions.map(\.id) == [item.id])
  }

  @Test func pendingDeletionConflictIsMarkedForTheDestructiveAction() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let remote = try #require(
      CatalogEntry(
        id: UUID(), name: "Remote", snapshot: CatalogSnapshot(fixture.profile())!,
        scope: .iCloud, accountIdentifier: "account-a"))
    _ = try start(
      fixture,
      catalog: SettingsCatalog(
        syncEnabled: true, accountIdentifier: "account-a",
        conflicts: [.init(id: remote.id, remote: remote)],
        pendingDeletions: [.init(id: remote.id, accountIdentifier: "account-a")]))
    let props = fixture.runtime.settingsProps.props.catalog
    #expect(props.conflicts.map(\.id) == [remote.id])
    #expect(props.pendingDeletionIDs == [remote.id])
  }

  @Test func deviceEntryCannotBeSharedWhileItsIdentifierAwaitsDeletion() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let item = try #require(
      CatalogEntry(id: UUID(), name: "Device", snapshot: CatalogSnapshot(fixture.profile())!))
    _ = try start(
      fixture,
      catalog: SettingsCatalog(
        syncEnabled: true, accountIdentifier: "account-a", entries: [item],
        pendingDeletions: [.init(id: item.id, accountIdentifier: "account-a")]))
    #expect(!fixture.runtime.settingsProps.props.catalog.canShare)
    #expect(
      fixture.runtime.send(.catalogSharePromptRequested(item.id), from: .settings).reply
        == .rejected(.invalidState))
  }

  private func start(
    _ fixture: RuntimeFixture, catalog: SettingsCatalog
  ) throws -> OperationToken {
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(.catalogLoaded(load, catalog), source: .catalogRepository)
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, "account-a"), source: .cloudCatalog)
    return try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
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
