import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct CatalogFollowupReviewTests {
  @Test func enteringExhibitionCancelsCatalogFileWorkAndDiscardsItsResult() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let profile = try fixture.profile()
    let entry = try #require(
      CatalogEntry(id: UUID(), name: "Device", snapshot: CatalogSnapshot(profile)!))
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.draftChanged(ProfileDraft(profile: profile)), from: .settings)
    fixture.runtime.send(.saveDraftRequested, from: .settings)
    let profileSave = try #require(fixture.port.effects.last)
    guard case .saveProfile(let saved) = profileSave.kind else {
      Issue.record("Expected profile save")
      return
    }
    fixture.port.deliver(.profileSaved(profileSave.token, saved), source: .profileRepository)
    fixture.runtime.send(
      .credentialConfigurationRequested("example-passcode"), from: .administration)
    let credential = try #require(fixture.runtime.snapshot.root.credentialOperation)
    fixture.port.deliver(.credentialConfigured(credential, succeeded: true), source: .credentials)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(load, SettingsCatalog(entries: [entry])), source: .catalogRepository)
    fixture.runtime.send(
      .catalogExportOperationRequested(ids: [entry.id], passphrase: "long-enough-file-passphrase"),
      from: .administration)
    let operation = try #require(fixture.runtime.snapshot.root.catalogExportOperation)
    #expect(fixture.runtime.send(.startExhibitionRequested, from: .settings).reply == .accepted)
    #expect(fixture.runtime.snapshot.root.catalogExportOperation == nil)
    #expect(fixture.runtime.snapshot.root.catalogExportData == nil)
    #expect(
      fixture.port.effects.contains { effect in
        if case .cancelOperation(let cancelled) = effect.kind { return cancelled == operation }
        return false
      })
    #expect(
      fixture.runtime.send(
        .catalogExportPrepared(operation, Data([1])), from: .catalogRepository
      ).reply == .rejected(.staleOperation))
  }
  @Test func oldAccountConflictCannotMoveAnEntryToTheNewAccount() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let entry = try #require(
      CatalogEntry(
        id: UUID(), name: "Old account", snapshot: CatalogSnapshot(fixture.profile())!,
        scope: .iCloud, accountIdentifier: "account-a"))
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(
        load,
        SettingsCatalog(
          accountIdentifier: "account-b", entries: [entry],
          conflicts: [.init(id: entry.id, remote: entry)])),
      source: .catalogRepository)

    #expect(
      fixture.runtime.send(
        .catalogConflictResolved(entry.id, useRemote: false), from: .settings
      ).reply == .rejected(.invalidState))
    #expect(fixture.runtime.snapshot.root.catalog.entries[0].accountIdentifier == "account-a")
    #expect(fixture.runtime.settingsProps.props.catalog.conflicts.isEmpty)
  }

  @Test func exportWaitsForTheCurrentCatalogSave() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let entry = try #require(
      CatalogEntry(id: UUID(), name: "Before", snapshot: CatalogSnapshot(fixture.profile())!))
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(load, SettingsCatalog(entries: [entry])), source: .catalogRepository)
    fixture.runtime.send(.catalogPassphraseEdited("long-enough-file-passphrase"), from: .settings)
    fixture.runtime.send(
      .catalogConfirmPassphraseEdited("long-enough-file-passphrase"), from: .settings)
    #expect(fixture.runtime.settingsProps.props.catalog.canExport)
    #expect(
      fixture.runtime.send(
        .catalogRenameRequested(id: entry.id, name: "After"), from: .settings
      ).reply == .accepted)
    #expect(fixture.runtime.snapshot.root.catalogSaveOperation != nil)
    #expect(!fixture.runtime.settingsProps.props.catalog.canExport)
    #expect(
      fixture.runtime.send(
        .catalogExportOperationRequested(
          ids: [entry.id], passphrase: "long-enough-file-passphrase"),
        from: .administration
      ).reply == .rejected(.invalidState))
  }

  @Test func accountResultWaitsForCatalogMutationToFinish() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let entry = try #require(
      CatalogEntry(id: UUID(), name: "Before", snapshot: CatalogSnapshot(fixture.profile())!))
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(load, SettingsCatalog(syncEnabled: true, entries: [entry])),
      source: .catalogRepository)
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    #expect(
      fixture.runtime.send(
        .catalogRenameRequested(id: entry.id, name: "After"), from: .settings
      ).reply == .accepted)
    let saving = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    let pending = try #require(fixture.runtime.snapshot.root.pendingCatalog)
    fixture.port.deliver(.catalogAccountChecked(check, "account-a"), source: .cloudCatalog)
    #expect(fixture.runtime.snapshot.root.catalogSaveOperation == saving)
    #expect(fixture.runtime.snapshot.root.pendingCatalog == pending)
    fixture.port.deliver(.catalogSaved(saving, pending), source: .catalogRepository)
    let retry = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    #expect(retry != check)
    fixture.port.deliver(.catalogAccountChecked(retry, "account-a"), source: .cloudCatalog)
    #expect(fixture.runtime.snapshot.root.pendingCatalog?.accountIdentifier == "account-a")
    #expect(fixture.runtime.snapshot.root.pendingCatalog?.entries[0].name == "After")
  }

  @Test func disablingSyncDuringAccountLookupDoesNotReplaceTheDisableSave() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(load, SettingsCatalog(syncEnabled: true)), source: .catalogRepository)
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    #expect(
      fixture.runtime.send(.catalogSyncDisableRequested, from: .settings).reply == .accepted)
    let saving = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    let pending = try #require(fixture.runtime.snapshot.root.pendingCatalog)
    fixture.port.deliver(.catalogAccountChecked(check, "account-a"), source: .cloudCatalog)
    #expect(fixture.runtime.snapshot.root.catalogSaveOperation == saving)
    fixture.port.deliver(.catalogSaved(saving, pending), source: .catalogRepository)
    #expect(!fixture.runtime.snapshot.root.catalog.syncEnabled)
    #expect(fixture.runtime.snapshot.root.catalogAccountCheckOperation == nil)
    #expect(fixture.runtime.snapshot.root.catalogCloudSessionOperation == nil)
  }

  @Test func oversizedEntryRemainsOnThisDeviceAfterShareConfirmation() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let profile = try oversizedProfile(from: fixture.profile())
    let entry = try #require(
      CatalogEntry(id: UUID(), name: "Large", snapshot: CatalogSnapshot(profile)!))
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
    let accountCheck = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(
      .catalogAccountChecked(accountCheck, "account-a"), source: .cloudCatalog)
    #expect(
      fixture.runtime.send(.catalogSelectRequested(entry.id), from: .settings).reply == .accepted)
    #expect(fixture.runtime.settingsProps.props.catalog.shareTooLarge)
    #expect(!fixture.runtime.settingsProps.props.catalog.canShare)
    #expect(
      fixture.runtime.send(.catalogSharePromptRequested(entry.id), from: .settings).reply
        == .accepted)
    #expect(
      fixture.runtime.send(.catalogShareConfirmed(entry.id), from: .settings).reply
        == .rejected(.invalidProfile))
    #expect(fixture.runtime.snapshot.root.catalog.entries[0].scope == .device)
    #expect(fixture.runtime.snapshot.root.catalogSaveOperation == nil)
  }

  @Test func oversizedUpdateDoesNotReplaceAnExistingSharedEntry() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let originalProfile = try fixture.profile()
    let largeProfile = try oversizedProfile(from: originalProfile)
    let entry = try #require(
      CatalogEntry(
        id: UUID(), name: "Shared", snapshot: CatalogSnapshot(originalProfile)!,
        scope: .iCloud, accountIdentifier: "account-a"))
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.draftChanged(ProfileDraft(profile: largeProfile)), from: .settings)
    fixture.runtime.send(.saveDraftRequested, from: .settings)
    let profileSave = try #require(fixture.runtime.snapshot.root.saveOperation)
    fixture.port.deliver(
      .profileSaved(profileSave, largeProfile), source: .profileRepository)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(
        load,
        SettingsCatalog(
          syncEnabled: true, accountIdentifier: "account-a", entries: [entry])),
      source: .catalogRepository)
    let accountCheck = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(
      .catalogAccountChecked(accountCheck, "account-a"), source: .cloudCatalog)
    #expect(
      fixture.runtime.send(.catalogSelectRequested(entry.id), from: .settings).reply == .accepted)
    #expect(fixture.runtime.settingsProps.props.catalog.updateTooLarge)
    #expect(!fixture.runtime.settingsProps.props.catalog.canUpdate)
    #expect(
      fixture.runtime.send(.catalogUpdateRequested(entry.id), from: .settings).reply == .accepted)
    #expect(
      fixture.runtime.send(.catalogUpdateConfirmed(entry.id), from: .settings).reply
        == .rejected(.invalidProfile))
    #expect(fixture.runtime.snapshot.root.catalog.entries[0].snapshot == entry.snapshot)
  }

  private func oversizedProfile(from initial: KioskProfile) throws -> KioskProfile {
    var profile = initial
    profile.startURL += String(repeating: "a", count: 920_000)
    try #require(profile.validationIssues.isEmpty)
    return profile
  }
}
