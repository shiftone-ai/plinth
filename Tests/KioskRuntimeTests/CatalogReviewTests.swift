import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct CatalogReviewTests {
  @Test func anUnchangedRemoteRecordDoesNotBlockAConfirmedDelete() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let profile = try fixture.profile()
    try openAdministration(fixture, profile: profile)
    let entry = try #require(
      CatalogEntry(
        id: UUID(), name: "Lobby", snapshot: CatalogSnapshot(profile)!,
        scope: .iCloud, accountIdentifier: "account-a", syncedVersion: 1))
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(
        load,
        SettingsCatalog(
          syncEnabled: true, accountIdentifier: "account-a", entries: [entry])),
      source: .catalogRepository)
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, "account-a"), source: .cloudCatalog)
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    #expect(
      fixture.runtime.send(.catalogRemovePromptRequested(entry.id), from: .settings).reply
        == .accepted)
    #expect(
      fixture.runtime.send(.catalogRemoveConfirmed(entry.id), from: .settings).reply == .accepted)
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-a", [.upsert(entry)]), from: .cloudCatalog)
    let save = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    let effect = try #require(fixture.port.effects.last(where: { $0.token == save }))
    guard case .saveCatalog(let document) = effect.kind else {
      Issue.record("Expected catalog save")
      return
    }
    fixture.port.deliver(.catalogSaved(save, document), source: .catalogRepository)
    #expect(fixture.runtime.snapshot.root.catalog.conflicts.isEmpty)
    #expect(fixture.runtime.snapshot.root.catalog.entries.isEmpty)
    #expect(fixture.runtime.snapshot.root.catalog.pendingDeletions.map(\.id) == [entry.id])
  }

  @Test func sharedConflictBlocksChangesUntilResolved() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let profile = try fixture.profile()
    let entry = try #require(
      CatalogEntry(
        id: UUID(), name: "Lobby", snapshot: CatalogSnapshot(profile)!,
        scope: .iCloud, accountIdentifier: "account-a", syncedVersion: 1))
    try openAdministration(fixture, profile: profile)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(
        load,
        SettingsCatalog(
          syncEnabled: true, accountIdentifier: "account-a", entries: [entry],
          conflicts: [.init(id: entry.id, remote: entry)])),
      source: .catalogRepository)

    #expect(
      fixture.runtime.send(
        .catalogRenameRequested(id: entry.id, name: "Changed"), from: .settings
      ).reply == .rejected(.invalidState))
    #expect(
      fixture.runtime.send(.catalogRemovePromptRequested(entry.id), from: .settings).reply
        == .rejected(.invalidState))
    #expect(fixture.runtime.snapshot.root.catalogSaveOperation == nil)
    #expect(fixture.runtime.snapshot.root.catalog.entries[0].name == "Lobby")
  }

  @Test func applyingSelectionUsesTheEntryCurrentlyShownInDetails() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let profile = try fixture.profile()
    let id = UUID()
    let entry = try #require(
      CatalogEntry(id: id, name: "Lobby", snapshot: CatalogSnapshot(profile)!))
    try openAdministration(fixture, profile: profile)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(load, SettingsCatalog(entries: [entry])), source: .catalogRepository)
    #expect(fixture.runtime.send(.catalogSelectRequested(id), from: .settings).reply == .accepted)

    var updated = profile
    updated.startURL = "https://example.com/new"
    fixture.runtime.send(.draftChanged(ProfileDraft(profile: updated)), from: .settings)
    fixture.runtime.send(.saveDraftRequested, from: .settings)
    let profileSave = try #require(fixture.port.effects.last)
    guard case .saveProfile(let saved) = profileSave.kind else {
      Issue.record("Expected profile save")
      return
    }
    fixture.port.deliver(.profileSaved(profileSave.token, saved), source: .profileRepository)
    #expect(fixture.runtime.send(.catalogUpdateRequested(id), from: .settings).reply == .accepted)
    let saveToken = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    let saving = try #require(fixture.port.effects.last(where: { $0.token == saveToken }))
    guard case .saveCatalog(let document) = saving.kind else {
      Issue.record("Expected catalog save")
      return
    }
    #expect(!fixture.runtime.settingsProps.props.catalog.canApply)
    #expect(
      fixture.runtime.send(.catalogApplyRequested, from: .settings).reply
        == .rejected(.invalidState))
    fixture.port.deliver(.catalogSaved(saveToken, document), source: .catalogRepository)
    #expect(
      fixture.runtime.settingsProps.props.catalog.selectedEntry?.snapshot.startURL
        == updated.startURL)
    #expect(fixture.runtime.send(.catalogApplyRequested, from: .settings).reply == .accepted)
    #expect(fixture.runtime.snapshot.administration.draft?.profile.startURL == updated.startURL)
  }

  @Test func applyingCatalogEntryPreservesDeviceWebAdministrationSetting() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    var profile = try fixture.profile()
    profile.webAdministrationEnabled = true
    try openAdministration(fixture, profile: profile)
    var selected = profile
    selected.startURL = "https://example.com/selected"
    let entry = try #require(
      CatalogEntry(id: UUID(), name: "Lobby", snapshot: CatalogSnapshot(selected)!))
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(load, SettingsCatalog(entries: [entry])), source: .catalogRepository)
    #expect(
      fixture.runtime.send(.catalogSelectRequested(entry.id), from: .settings).reply
        == .accepted)
    #expect(fixture.runtime.send(.catalogApplyRequested, from: .settings).reply == .accepted)
    #expect(fixture.runtime.snapshot.administration.draft?.profile.webAdministrationEnabled == true)
    #expect(fixture.runtime.send(.saveDraftRequested, from: .settings).reply == .accepted)
    let save = try #require(fixture.runtime.snapshot.root.saveOperation)
    let effect = try #require(fixture.port.effects.last(where: { $0.token == save }))
    guard case .saveProfile(let saved) = effect.kind else {
      Issue.record("Expected profile save")
      return
    }
    fixture.port.deliver(.profileSaved(save, saved), source: .profileRepository)
    #expect(fixture.runtime.snapshot.root.savedProfile?.webAdministrationEnabled == true)
  }
}

@MainActor
struct CatalogSafetyReviewTests {
  @Test func catalogOutputIsRecheckedIfTheDisplayDisconnectsBeforeSave() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let profile = try fixture.profile()
    var selected = profile
    selected.macOutput = .init(displayID: "chosen-display")
    let entry = try #require(
      CatalogEntry(id: UUID(), name: "Other display", snapshot: CatalogSnapshot(selected)!))
    try openAdministration(fixture, profile: profile)
    fixture.runtime.send(
      .macDisplaysChanged([.init(id: "chosen-display", name: "Chosen", builtIn: true)]),
      from: .platform)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(load, SettingsCatalog(entries: [entry])), source: .catalogRepository)
    #expect(
      fixture.runtime.send(.catalogSelectRequested(entry.id), from: .settings).reply
        == .accepted)
    #expect(fixture.runtime.send(.catalogApplyRequested, from: .settings).reply == .accepted)
    #expect(!fixture.runtime.settingsProps.props.catalogOutputUnavailable)
    fixture.runtime.send(
      .macDisplaysChanged([.init(id: "another-display", name: "Other", builtIn: true)]),
      from: .platform)
    #expect(fixture.runtime.settingsProps.props.catalogOutputUnavailable)
    #expect(!fixture.runtime.settingsProps.props.canSave)
    #expect(
      fixture.runtime.send(.saveDraftRequested, from: .settings).reply
        == .rejected(.invalidProfile))
  }

  @Test func iCloudSyncCanBeRetriedAfterSignIn() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(load, SettingsCatalog(syncEnabled: true)), source: .catalogRepository)
    let firstCheck = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(firstCheck, nil), source: .cloudCatalog)
    #expect(fixture.runtime.snapshot.root.catalogSyncStatus == .signInRequired)
    #expect(
      fixture.runtime.send(.catalogSyncRetryRequested, from: .settings).reply == .accepted)
    let retry = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    #expect(retry != firstCheck)
    fixture.port.deliver(.catalogAccountChecked(retry, "account-a"), source: .cloudCatalog)
    #expect(fixture.runtime.snapshot.root.catalogSaveOperation != nil)
  }

  @Test func leavingAdministrationClearsFilePassphrases() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    try openAdministration(fixture, profile: fixture.profile())
    fixture.runtime.send(.passcodeEdited("correct-passcode"), from: .settings)
    #expect(
      fixture.runtime.send(.configurePasscodeRequested, from: .settings).reply == .accepted)
    let credential = try #require(fixture.runtime.snapshot.root.credentialOperation)
    fixture.port.deliver(.credentialConfigured(credential, succeeded: true), source: .credentials)
    fixture.runtime.send(.catalogPassphraseEdited("long-enough-file-passphrase"), from: .settings)
    fixture.runtime.send(
      .catalogConfirmPassphraseEdited("long-enough-file-passphrase"), from: .settings)
    #expect(
      fixture.runtime.send(.startExhibitionRequested, from: .settings).reply == .accepted)
    #expect(fixture.runtime.snapshot.administration.catalogPassphrase.isEmpty)
    #expect(fixture.runtime.snapshot.administration.catalogConfirmPassphrase.isEmpty)
  }

  @Test func importedUnavailableOutputRequiresAUsableSelectionBeforeSave() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let profile = try fixture.profile()
    var unavailable = profile
    unavailable.macOutput = .init(displayID: "other-device-display")
    let entry = try #require(
      CatalogEntry(id: UUID(), name: "Other device", snapshot: CatalogSnapshot(unavailable)!))
    try openAdministration(fixture, profile: profile)
    fixture.runtime.send(
      .macDisplaysChanged([.init(id: "here", name: "Here", builtIn: true)]), from: .platform)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(load, SettingsCatalog(entries: [entry])), source: .catalogRepository)
    #expect(
      fixture.runtime.send(.catalogSelectRequested(entry.id), from: .settings).reply == .accepted)
    #expect(fixture.runtime.send(.catalogApplyRequested, from: .settings).reply == .accepted)
    #expect(fixture.runtime.settingsProps.props.catalogOutputUnavailable)
    #expect(!fixture.runtime.settingsProps.props.canSave)
    #expect(
      fixture.runtime.send(.saveDraftRequested, from: .settings).reply
        == .rejected(.invalidProfile))
    fixture.runtime.send(.draftEdited(.macDisplayID(nil)), from: .settings)
    #expect(!fixture.runtime.settingsProps.props.catalogOutputUnavailable)
    #expect(fixture.runtime.settingsProps.props.canSave)
  }

  @Test func cancelledFileImportRejectsALatePreview() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let profile = try fixture.profile()
    let existing = try #require(
      CatalogEntry(id: UUID(), name: "Existing", snapshot: CatalogSnapshot(profile)!))
    let incoming = try #require(
      CatalogEntry(id: UUID(), name: "Incoming", snapshot: CatalogSnapshot(profile)!))
    try openAdministration(fixture, profile: profile)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(load, SettingsCatalog(entries: [existing])), source: .catalogRepository)
    fixture.runtime.send(.catalogPassphraseEdited("long-enough-file-passphrase"), from: .settings)
    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "cancelled.plinthsettings")
    #expect(
      fixture.runtime.send(.catalogImportFileRequested(fileURL), from: .settings).reply == .accepted
    )
    let importToken = try #require(fixture.runtime.snapshot.root.catalogImportOperation)
    #expect(fixture.runtime.send(.catalogImportCancelled, from: .settings).reply == .accepted)
    #expect(
      fixture.runtime.send(
        .catalogImportPreviewReady(importToken, [incoming]), from: .catalogRepository
      ).reply == .rejected(.staleOperation))
    #expect(fixture.runtime.snapshot.root.catalog.entries == [existing])
    #expect(fixture.runtime.snapshot.root.catalogImportPreview == nil)
    #expect(fixture.runtime.snapshot.root.savedProfile != nil)
    #expect(fixture.runtime.snapshot.administration.catalogPassphrase.isEmpty)
  }
}

@MainActor
private func openAdministration(_ fixture: RuntimeFixture, profile: KioskProfile) throws {
  fixture.runtime.send(
    .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
  fixture.runtime.send(.draftChanged(ProfileDraft(profile: profile)), from: .settings)
  #expect(fixture.runtime.send(.saveDraftRequested, from: .settings).reply == .accepted)
  let effect = try #require(fixture.port.effects.last)
  guard case .saveProfile(let saved) = effect.kind else {
    Issue.record("Expected profile save")
    return
  }
  fixture.port.deliver(.profileSaved(effect.token, saved), source: .profileRepository)
  try #require(fixture.runtime.snapshot.root.mode == .administration)
}
