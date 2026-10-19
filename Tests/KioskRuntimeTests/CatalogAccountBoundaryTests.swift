import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct CatalogAccountBoundaryTests {
  @Test func buildWithoutCloudCapabilityCannotStartSync() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    #expect(
      fixture.runtime.send(.catalogCloudCapabilityUnavailable, from: .platform).handler == .root)
    try load(fixture, SettingsCatalog())
    #expect(!fixture.runtime.settingsProps.props.catalog.cloudAvailable)
    #expect(
      fixture.runtime.send(.catalogSyncEnableRequested, from: .settings).reply
        == .rejected(.invalidState))
    #expect(fixture.runtime.snapshot.root.catalogAccountCheckOperation == nil)
  }

  @Test func temporaryAccountFailureKeepsSyncEnabledAndAllowsRetry() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    try load(fixture, SettingsCatalog(syncEnabled: true))
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountCheckDeferred(check), source: .cloudCatalog)
    #expect(fixture.runtime.snapshot.root.catalog.syncEnabled)
    #expect(fixture.runtime.snapshot.root.catalogSyncStatus == .offline)
    #expect(fixture.runtime.snapshot.root.catalogCloudSessionOperation == nil)
    #expect(
      fixture.runtime.send(.catalogSyncRetryRequested, from: .settings).reply == .accepted)
    #expect(fixture.runtime.snapshot.root.catalogAccountCheckOperation != nil)
  }

  @Test func accountChangeClearsAllSharedEntryConfirmationCandidates() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let shared = try #require(
      CatalogEntry(
        id: UUID(), name: "Shared", snapshot: CatalogSnapshot(fixture.profile())!,
        scope: .iCloud, accountIdentifier: "account-a"))
    let device = try #require(
      CatalogEntry(id: UUID(), name: "Device", snapshot: CatalogSnapshot(fixture.profile())!))
    try load(
      fixture,
      SettingsCatalog(
        syncEnabled: true, accountIdentifier: "account-a", entries: [shared, device]),
      account: "account-a")
    #expect(
      fixture.runtime.send(
        .catalogRenameRequested(id: shared.id, name: "Changed"), from: .settings
      ).reply == .accepted)
    #expect(
      fixture.runtime.send(.catalogRemovePromptRequested(shared.id), from: .settings).reply
        == .accepted)
    #expect(
      fixture.runtime.send(.catalogSharePromptRequested(device.id), from: .settings).reply
        == .accepted)
    let before = fixture.runtime.snapshot.root
    #expect(before.catalogRenameCandidate != nil)
    #expect(before.catalogRemovalCandidateID != nil)
    #expect(before.catalogShareCandidateID != nil)
    let session = try #require(before.catalogCloudSessionOperation)
    fixture.runtime.send(.catalogCloudAccountChanged(session), from: .cloudCatalog)
    let after = fixture.runtime.snapshot.root
    #expect(after.catalogRenameCandidate == nil)
    #expect(after.catalogUpdateCandidateID == nil)
    #expect(after.catalogRemovalCandidateID == nil)
    #expect(after.catalogShareCandidateID == nil)
  }

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
    #expect(chosen.resolvedConflictVersion == chosen.version)
    let restored = try JSONDecoder().decode(
      CatalogEntry.self, from: JSONEncoder().encode(chosen))
    #expect(restored.resolvedConflictVersion == chosen.version)
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

  @Test func remoteDeletionClearsTheSelectedEntryConfirmation() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let entry = try #require(
      CatalogEntry(
        id: UUID(), name: "Shared", snapshot: CatalogSnapshot(fixture.profile())!,
        scope: .iCloud, accountIdentifier: "account-a", syncedVersion: 1))
    try load(
      fixture, SettingsCatalog(syncEnabled: true, accountIdentifier: "account-a", entries: [entry]),
      account: "account-a")
    #expect(
      fixture.runtime.send(.catalogSelectRequested(entry.id), from: .settings).reply == .accepted)
    #expect(
      fixture.runtime.send(
        .catalogRenameRequested(id: entry.id, name: "Stale name"), from: .settings
      ).reply == .accepted)
    #expect(
      fixture.runtime.send(.catalogRemovePromptRequested(entry.id), from: .settings).reply
        == .accepted)
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-a", [.delete(entry.id)]), from: .cloudCatalog)
    try finishSave(fixture)
    #expect(fixture.runtime.settingsProps.props.catalog.selectedEntry == nil)
    #expect(fixture.runtime.snapshot.root.catalogRenameCandidate == nil)
    #expect(fixture.runtime.snapshot.root.catalogUpdateCandidateID == nil)
    #expect(fixture.runtime.snapshot.root.catalogRemovalCandidateID == nil)
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-a", [.upsert(entry)]), from: .cloudCatalog)
    try finishSave(fixture)
    let returned = try #require(
      fixture.runtime.snapshot.root.catalog.entries.first { $0.id == entry.id })
    #expect(!returned.isVisible)
    #expect(
      fixture.runtime.send(
        .catalogVisibilityRequested(id: entry.id, visible: true), from: .settings
      ).reply == .accepted)
    try finishSave(fixture)
    #expect(
      fixture.runtime.send(.catalogSelectRequested(entry.id), from: .settings).reply == .accepted)
    #expect(fixture.runtime.settingsProps.props.catalog.renameCandidate == nil)
    #expect(fixture.runtime.settingsProps.props.catalog.removalCandidate == nil)
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
}

// Account-specific records can share a portable identifier without sharing local state.
extension CatalogAccountBoundaryTests {
  @Test func sameIdentifierFromTwoAccountsKeepsBothAndOnlyRemovesTheCurrentOne() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let id = UUID()
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let old = try #require(
      CatalogEntry(
        id: id, name: "Old account", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    let current = try #require(
      CatalogEntry(
        id: id, name: "Current account", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-b"))
    try load(
      fixture,
      SettingsCatalog(
        syncEnabled: true, accountIdentifier: "account-b", entries: [old],
        conflicts: [.init(id: id, remote: old)]),
      account: "account-b")
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-b", [.upsert(current)]), from: .cloudCatalog)
    try finishSave(fixture)
    let document = fixture.runtime.snapshot.root.catalog
    #expect(document.isValid)
    #expect(
      try JSONDecoder().decode(SettingsCatalog.self, from: JSONEncoder().encode(document)).isValid)
    #expect(document.entries.count == 2)
    #expect(document.entries.map(\.name) == ["Old account", "Current account"])
    #expect(document.conflicts.map(\.remote?.accountIdentifier) == ["account-a"])
    #expect(
      fixture.runtime.settingsProps.props.catalog.hiddenEntries.map(\.name) == ["Current account"])
    #expect(
      fixture.runtime.send(
        .catalogVisibilityRequested(id: id, visible: true), from: .settings
      ).reply == .accepted)
    try finishSave(fixture)
    #expect(
      fixture.runtime.settingsProps.props.catalog.visibleEntries.map(\.name) == ["Current account"])
    #expect(
      fixture.runtime.send(.catalogRemovePromptRequested(id), from: .settings).reply == .accepted)
    #expect(
      fixture.runtime.send(.catalogRemoveConfirmed(id), from: .settings).reply == .accepted)
    try finishSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalog.entries == [old])
    #expect(
      fixture.runtime.snapshot.root.catalog.pendingDeletions.map(\.accountIdentifier) == [
        "account-b"
      ])
    #expect(fixture.runtime.snapshot.root.catalog.isValid)
  }

  @Test func cloudAcknowledgementAndDeletionDoNotChangeAnotherAccountsMatchingID() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let id = UUID()
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let old = try #require(
      CatalogEntry(
        id: id, name: "Old", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    let current = try #require(
      CatalogEntry(
        id: id, name: "Current", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-b"))
    let document = SettingsCatalog(
      syncEnabled: true, accountIdentifier: "account-b", entries: [old, current])
    #expect(document.isValid)
    try load(fixture, document, account: "account-b")
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    fixture.runtime.send(
      .catalogCloudAcknowledged(session, "account-b", [id: current.version]),
      from: .cloudCatalog)
    try finishSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalog.entries[0].syncedVersion == nil)
    #expect(fixture.runtime.snapshot.root.catalog.entries[1].syncedVersion == current.version)
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-b", [.delete(id)]), from: .cloudCatalog)
    try finishSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalog.entries == [old])
  }

  @Test func resolvingCurrentAccountsConflictKeepsTheOlderAccountsItemAndConflict() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let id = UUID()
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let old = try #require(
      CatalogEntry(
        id: id, name: "Old", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    let local = try #require(
      CatalogEntry(
        id: id, name: "Local", snapshot: snapshot, version: 2, scope: .iCloud,
        accountIdentifier: "account-b", syncedVersion: 1))
    let remote = try #require(
      CatalogEntry(
        id: id, name: "Remote", snapshot: snapshot, version: 2, scope: .iCloud,
        accountIdentifier: "account-b", syncedVersion: 2))
    let document = SettingsCatalog(
      syncEnabled: true, accountIdentifier: "account-b", entries: [old, local],
      conflicts: [.init(id: id, remote: old), .init(id: id, remote: remote)])
    #expect(document.isValid)
    try load(fixture, document, account: "account-b")
    #expect(fixture.runtime.settingsProps.props.catalog.conflicts.map(\.remote?.name) == ["Remote"])
    #expect(
      fixture.runtime.send(
        .catalogConflictResolved(id, useRemote: true), from: .settings
      ).reply == .accepted)
    try finishSave(fixture)
    let saved = fixture.runtime.snapshot.root.catalog
    #expect(saved.entries == [old, remote])
    #expect(saved.conflicts.map(\.remote?.name) == ["Old"])
    #expect(saved.isValid)
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
