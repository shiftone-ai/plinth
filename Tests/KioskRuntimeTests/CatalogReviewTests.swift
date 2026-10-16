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
    fixture.port.deliver(.catalogSaved(saveToken, document), source: .catalogRepository)
    #expect(
      fixture.runtime.settingsProps.props.catalog.selectedEntry?.snapshot.startURL
        == updated.startURL)
    #expect(fixture.runtime.send(.catalogApplyRequested, from: .settings).reply == .accepted)
    #expect(fixture.runtime.snapshot.administration.draft?.profile.startURL == updated.startURL)
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
}
