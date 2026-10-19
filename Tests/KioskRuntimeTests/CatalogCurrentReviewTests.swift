import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct CatalogCurrentReviewTests {
  @Test func reFetchedConflictRemainsBlockedUntilItIsResolvedAgain() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let id = UUID()
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let local = try #require(
      CatalogEntry(
        id: id, name: "Device choice", snapshot: snapshot, version: 2,
        scope: .iCloud, accountIdentifier: "account-a", syncedVersion: 1))
    let remote = try #require(
      CatalogEntry(
        id: id, name: "Remote choice", snapshot: snapshot, version: 2,
        scope: .iCloud, accountIdentifier: "account-a", syncedVersion: 2))
    let newerRemote = try #require(
      CatalogEntry(
        id: id, name: "Newer remote", snapshot: snapshot, version: 4,
        scope: .iCloud, accountIdentifier: "account-a", syncedVersion: 4))
    try load(
      fixture,
      SettingsCatalog(
        syncEnabled: true, accountIdentifier: "account-a", entries: [local],
        conflicts: [.init(id: id, remote: remote)]), account: "account-a")
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    #expect(
      fixture.runtime.send(
        .catalogConflictResolved(id, useRemote: false), from: .settings
      ).reply == .accepted)
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-a", [.upsert(newerRemote)]), from: .cloudCatalog)
    let before = fixture.port.effects.count
    try finishSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalogSaveOperation != nil)
    #expect(
      !fixture.port.effects.dropFirst(before).contains {
        if case .publishCatalogChanges = $0.kind { return true }
        return false
      })
    try finishSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalog.conflicts.first?.remote?.name == "Newer remote")
  }

  @Test func retryStopsAnOfflineCloudSessionBeforeCheckingTheAccount() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    try load(
      fixture, SettingsCatalog(syncEnabled: true, accountIdentifier: "account-a"),
      account: "account-a")
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    fixture.runtime.send(.catalogCloudStatus(session, .offline), from: .cloudCatalog)
    #expect(
      fixture.runtime.send(.catalogSyncRetryRequested, from: .settings).reply == .accepted)
    #expect(fixture.runtime.snapshot.root.catalogCloudSessionOperation == nil)
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    let effect = try #require(fixture.port.effects.last(where: { $0.token == check }))
    guard case .checkCatalogAccountAfterStopping = effect.kind else {
      Issue.record("Expected the offline session to stop before checking")
      return
    }
  }

  @Test func importAndExportCannotPresentTwoFileSheetsAtOnce() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let entry = try #require(
      CatalogEntry(id: UUID(), name: "Device", snapshot: CatalogSnapshot(fixture.profile())!))
    try load(fixture, SettingsCatalog(entries: [entry]))
    fixture.runtime.send(.catalogPassphraseEdited("long-enough-file-passphrase"), from: .settings)
    fixture.runtime.send(
      .catalogConfirmPassphraseEdited("long-enough-file-passphrase"), from: .settings)
    #expect(fixture.runtime.settingsProps.props.catalog.canStartExport)
    #expect(fixture.runtime.settingsProps.props.catalog.canStartImport)
    #expect(!fixture.runtime.settingsProps.props.catalog.canExport)
    #expect(!fixture.runtime.settingsProps.props.catalog.canImport)
    #expect(
      fixture.runtime.send(
        .catalogExportPromptRequested(ids: [entry.id]), from: .settings
      ).reply == .accepted)
    #expect(!fixture.runtime.settingsProps.props.catalog.canStartImport)
    #expect(!fixture.runtime.settingsProps.props.catalog.canExport)
    fixture.runtime.send(.catalogPassphraseEdited("long-enough-file-passphrase"), from: .settings)
    fixture.runtime.send(
      .catalogConfirmPassphraseEdited("long-enough-file-passphrase"), from: .settings)
    #expect(fixture.runtime.settingsProps.props.catalog.canExport)

    #expect(
      fixture.runtime.send(
        .catalogExportOperationRequested(
          ids: [entry.id], passphrase: "long-enough-file-passphrase"),
        from: .administration
      ).reply == .accepted)
    #expect(!fixture.runtime.settingsProps.props.catalog.canImport)
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "backup.plinthsettings")
    #expect(
      fixture.runtime.send(
        .catalogImportOperationRequested(fileURL, passphrase: "long-enough-file-passphrase"),
        from: .administration
      ).reply == .rejected(.invalidState))
    let export = try #require(fixture.runtime.snapshot.root.catalogExportOperation)
    fixture.port.deliver(.catalogExportPrepared(export, Data([1])), source: .catalogRepository)
    #expect(!fixture.runtime.settingsProps.props.catalog.canImport)
    fixture.runtime.send(.catalogFileExportCompleted(true), from: .settings)
    #expect(
      fixture.runtime.send(.catalogImportFileSelected(fileURL), from: .settings).reply
        == .accepted)
    #expect(!fixture.runtime.settingsProps.props.catalog.canImport)
    fixture.runtime.send(.catalogPassphraseEdited("long-enough-file-passphrase"), from: .settings)
    #expect(fixture.runtime.settingsProps.props.catalog.canImport)

    #expect(
      fixture.runtime.send(
        .catalogImportOperationRequested(fileURL, passphrase: "long-enough-file-passphrase"),
        from: .administration
      ).reply == .accepted)
    #expect(!fixture.runtime.settingsProps.props.catalog.canExport)
    #expect(
      fixture.runtime.send(
        .catalogExportOperationRequested(
          ids: [entry.id], passphrase: "long-enough-file-passphrase"),
        from: .administration
      ).reply == .rejected(.invalidState))
    let importer = try #require(fixture.runtime.snapshot.root.catalogImportOperation)
    fixture.port.deliver(
      .catalogImportPreviewReady(importer, [entry]), source: .catalogRepository)
    #expect(!fixture.runtime.settingsProps.props.catalog.canExport)
  }

  @Test func failedFileUnlockCanBeRetriedWithoutChoosingTheFileAgain() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    try load(fixture, SettingsCatalog())
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "backup.plinthsettings")
    #expect(
      fixture.runtime.send(.catalogImportFileSelected(fileURL), from: .settings).reply
        == .accepted)
    fixture.runtime.send(.catalogPassphraseEdited("incorrect-passphrase"), from: .settings)
    #expect(
      fixture.runtime.send(.catalogImportFileRequested(fileURL), from: .settings).reply
        == .accepted)
    let operation = try #require(fixture.runtime.snapshot.root.catalogImportOperation)
    fixture.port.deliver(.catalogImportFailed(operation), source: .catalogRepository)
    #expect(fixture.runtime.settingsProps.props.catalog.importFileURL == fileURL)
    #expect(fixture.runtime.settingsProps.props.catalog.importFailed)
    #expect(fixture.runtime.settingsProps.props.catalog.passphrase.isEmpty)
    fixture.runtime.send(.catalogPassphraseEdited("correct-file-passphrase"), from: .settings)
    #expect(fixture.runtime.settingsProps.props.catalog.canImport)
    #expect(
      fixture.runtime.send(.catalogImportCancelled, from: .settings).reply == .accepted)
    #expect(fixture.runtime.settingsProps.props.catalog.importFileURL == nil)
    #expect(fixture.runtime.settingsProps.props.catalog.passphrase.isEmpty)
  }

  private func load(
    _ fixture: RuntimeFixture, _ document: SettingsCatalog, account: String? = nil
  ) throws {
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
