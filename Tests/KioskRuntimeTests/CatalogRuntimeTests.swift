import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct CatalogRuntimeTests {
  @Test func concurrentRemoteEditDoesNotRestoreALocallyRemovedSharedEntry() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let runtime = fixture.runtime
    let profile = try fixture.profile()
    let id = UUID()
    let base = try #require(
      CatalogEntry(
        id: id, name: "Base", snapshot: CatalogSnapshot(profile)!,
        scope: .iCloud, accountIdentifier: "account-a", syncedVersion: 1))
    let remote = try #require(
      CatalogEntry(
        id: id, name: "Changed elsewhere", snapshot: base.snapshot, version: 2,
        scope: .iCloud, accountIdentifier: "account-a", syncedVersion: 2))
    runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1),
      from: .root)
    runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(
        load,
        SettingsCatalog(
          syncEnabled: true, accountIdentifier: "account-a", entries: [base])),
      source: .catalogRepository)
    let accountCheck = try #require(runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(accountCheck, "account-a"), source: .cloudCatalog)
    let session = try #require(runtime.snapshot.root.catalogCloudSessionOperation)
    runtime.send(.catalogRemovePromptRequested(id), from: .settings)
    runtime.send(.catalogRemoveConfirmed(id), from: .settings)
    runtime.send(.catalogCloudChanges(session, "account-a", [.upsert(remote)]), from: .cloudCatalog)
    finishCatalogSave(fixture)
    finishCatalogSave(fixture)
    #expect(runtime.snapshot.root.catalog.entries.isEmpty)
    #expect(runtime.snapshot.root.catalog.pendingDeletions.map(\.id) == [id])
    #expect(runtime.snapshot.root.catalog.conflicts.first?.remote?.name == "Changed elsewhere")
    #expect(runtime.snapshot.root.savedProfile == nil)
    runtime.send(.catalogConflictResolved(id, useRemote: false), from: .settings)
    finishCatalogSave(fixture)
    #expect(runtime.snapshot.root.catalog.entries.isEmpty)
    #expect(runtime.snapshot.root.catalog.conflicts.isEmpty)
    #expect(
      fixture.port.effects.contains { effect in
        if case .publishCatalogChanges(_, _, _, let deletions) = effect.kind {
          return deletions.map(\.id) == [id] && deletions.first?.baseVersion == 2
        }
        return false
      })
    runtime.send(
      .catalogCloudDeletionsAcknowledged(session, "account-a", [id]),
      from: .cloudCatalog)
    #expect(runtime.snapshot.root.catalogSaveOperation != nil)
    finishCatalogSave(fixture)
    #expect(runtime.snapshot.root.catalog.pendingDeletions.isEmpty)
  }

  @Test func conflictingCloudUpdateWaitsForAdministratorChoice() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let runtime = fixture.runtime
    let profile = try fixture.profile()
    let id = UUID()
    let base = try #require(
      CatalogEntry(
        id: id, name: "Base", snapshot: CatalogSnapshot(profile)!,
        scope: .iCloud, accountIdentifier: "account-a", syncedVersion: 1))
    runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    runtime.send(.draftChanged(ProfileDraft(profile: profile)), from: .settings)
    runtime.send(.saveDraftRequested, from: .settings)
    let profileSave = try #require(fixture.port.effects.last)
    guard case .saveProfile(let saved) = profileSave.kind else {
      Issue.record("Expected device profile save")
      return
    }
    fixture.port.deliver(.profileSaved(profileSave.token, saved), source: .profileRepository)
    runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(
        load,
        SettingsCatalog(
          syncEnabled: true, accountIdentifier: "account-a", entries: [base])),
      source: .catalogRepository)
    let check = try #require(runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, "account-a"), source: .cloudCatalog)
    let session = try #require(runtime.snapshot.root.catalogCloudSessionOperation)
    runtime.send(.catalogRenameRequested(id: id, name: "Local edit"), from: .settings)
    #expect(runtime.snapshot.root.catalogRenameCandidate?.name == "Local edit")
    runtime.send(.catalogRenameConfirmed(id), from: .settings)
    finishCatalogSave(fixture)
    var remoteProfile = profile
    remoteProfile.startURL = "https://example.com/other"
    let remote = try #require(
      CatalogEntry(
        id: id, name: "Remote edit", snapshot: CatalogSnapshot(remoteProfile)!, version: 2,
        scope: .iCloud, accountIdentifier: "account-a", syncedVersion: 2))
    runtime.send(.catalogCloudChanges(session, "account-a", [.upsert(remote)]), from: .cloudCatalog)
    finishCatalogSave(fixture)
    #expect(runtime.snapshot.root.catalog.entries[0].name == "Local edit")
    #expect(runtime.snapshot.root.catalog.conflicts.first?.remote?.name == "Remote edit")
    #expect(
      runtime.settingsProps.props.catalog.conflictDifferences[id]?.first?.selected
        == .text("Remote edit"))
    #expect(
      runtime.settingsProps.props.catalog.conflictDifferences[id]?.contains {
        $0.labelKey == "Start URL" && $0.selected == .text("https://example.com/other")
      } == true)
    #expect(runtime.snapshot.root.savedProfile == saved)
    runtime.send(.catalogConflictResolved(id, useRemote: true), from: .settings)
    finishCatalogSave(fixture)
    #expect(runtime.snapshot.root.catalog.entries[0].name == "Remote edit")
    #expect(runtime.snapshot.root.catalog.conflicts.isEmpty)
    #expect(runtime.snapshot.root.savedProfile == saved)
  }

  @Test func changingAppleAccountHidesOldSharedItemsAndStopsSync() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let runtime = fixture.runtime
    let profile = try fixture.profile()
    let item = try #require(
      CatalogEntry(
        id: UUID(), name: "Old account", snapshot: CatalogSnapshot(profile)!,
        scope: .iCloud, accountIdentifier: "account-a", syncedVersion: 1))
    runtime.send(
      .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1), from: .root)
    let activeBefore = runtime.snapshot.root.activeProfile
    runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(
        load,
        SettingsCatalog(
          syncEnabled: true, accountIdentifier: "account-a", entries: [item])),
      source: .catalogRepository)
    let firstCheck = try #require(runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(firstCheck, "account-a"), source: .cloudCatalog)
    let session = try #require(runtime.snapshot.root.catalogCloudSessionOperation)
    #expect(runtime.settingsProps.props.catalog.visibleEntries.map(\.id) == [item.id])
    runtime.send(.catalogCloudAccountChanged(session), from: .cloudCatalog)
    #expect(runtime.settingsProps.props.catalog.visibleEntries.isEmpty)
    #expect(
      runtime.send(.catalogCloudStatus(session, .ready), from: .cloudCatalog).reply
        == .rejected(.invalidState))
    #expect(runtime.snapshot.root.catalogSyncStatus == .checking)
    let nextCheck = try #require(runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(nextCheck, "account-b"), source: .cloudCatalog)
    finishCatalogSave(fixture)
    #expect(!runtime.snapshot.root.catalog.syncEnabled)
    #expect(runtime.snapshot.root.catalogSyncStatus == .accountChanged)
    #expect(runtime.snapshot.root.catalog.accountIdentifier == "account-b")
    #expect(runtime.settingsProps.props.catalog.visibleEntries.isEmpty)
    #expect(runtime.snapshot.root.savedProfile == profile)
    #expect(runtime.snapshot.root.activeProfile == activeBefore)
  }

  @Test func syncConsentDoesNotPublishUntilAnEntryIsShared() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let runtime = fixture.runtime
    runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(.catalogLoaded(load, SettingsCatalog()), source: .catalogRepository)
    let profile = try fixture.profile()
    runtime.send(.draftChanged(ProfileDraft(profile: profile)), from: .settings)
    runtime.send(.saveDraftRequested, from: .settings)
    let profileSave = try #require(fixture.port.effects.last)
    fixture.port.deliver(.profileSaved(profileSave.token, profile), source: .profileRepository)
    let id = UUID()
    runtime.send(.catalogRegisterRequested(id: id, name: "Local"), from: .settings)
    finishCatalogSave(fixture)

    #expect(runtime.send(.catalogSyncEnableRequested, from: .settings).reply == .accepted)
    #expect(!runtime.snapshot.root.catalog.syncEnabled)
    #expect(runtime.send(.catalogSyncEnableConfirmed, from: .settings).reply == .accepted)
    finishCatalogSave(fixture)
    let check = try #require(runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, "account-a"), source: .cloudCatalog)
    finishCatalogSave(fixture)
    #expect(runtime.snapshot.root.catalog.entries[0].scope == .device)
    #expect(
      !fixture.port.effects.contains { effect in
        if case .publishCatalogChanges = effect.kind { return true }
        return false
      })
    #expect(runtime.send(.catalogSharePromptRequested(id), from: .settings).reply == .accepted)
    #expect(runtime.snapshot.root.catalog.entries[0].scope == .device)
    #expect(runtime.send(.catalogShareConfirmed(id), from: .settings).reply == .accepted)
    finishCatalogSave(fixture)
    guard
      case .publishCatalogChanges(_, _, let saves, let deletions) =
        try #require(fixture.port.effects.last).kind
    else {
      Issue.record("Expected cloud publish")
      return
    }
    #expect(saves.map(\.id) == [id])
    #expect(deletions.isEmpty)
    #expect(runtime.snapshot.root.savedProfile == profile)
  }

  @Test func receivingSharedSettingsRequiresASeparateDeviceChoice() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let runtime = fixture.runtime
    let saved = try fixture.profile()
    runtime.send(
      .bootstrapped(profile: saved, credentialsConfigured: true, displayCount: 1), from: .root)
    let activeBefore = runtime.snapshot.root.activeProfile
    runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(load, SettingsCatalog(syncEnabled: true, accountIdentifier: "account-a")),
      source: .catalogRepository)
    let check = try #require(runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, "account-a"), source: .cloudCatalog)
    let session = try #require(runtime.snapshot.root.catalogCloudSessionOperation)
    let remote = try #require(
      CatalogEntry(
        id: UUID(), name: "Other location", snapshot: CatalogSnapshot(saved)!,
        scope: .iCloud, accountIdentifier: "account-a"))
    runtime.send(.catalogCloudChanges(session, "account-a", [.upsert(remote)]), from: .cloudCatalog)
    finishCatalogSave(fixture)
    #expect(runtime.snapshot.root.catalog.entries.first?.name == "Other location")
    #expect(runtime.snapshot.root.catalog.entries.first?.isVisible == false)
    #expect(runtime.snapshot.root.savedProfile == saved)
    #expect(runtime.snapshot.root.activeProfile == activeBefore)
    #expect(
      runtime.send(.catalogSelectRequested(remote.id), from: .settings).reply
        == .rejected(.invalidState))
  }

  @Test func renamingHidingAndRemovingAnEntryLeaveTheDeviceProfileAlone() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let runtime = fixture.runtime
    runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(.catalogLoaded(load, SettingsCatalog()), source: .catalogRepository)
    runtime.send(.draftChanged(ProfileDraft(profile: try fixture.profile())), from: .settings)
    runtime.send(.saveDraftRequested, from: .settings)
    let profileSave = try #require(fixture.port.effects.last)
    guard case .saveProfile(let saved) = profileSave.kind else {
      Issue.record("Expected operation effect")
      return
    }
    fixture.port.deliver(.profileSaved(profileSave.token, saved), source: .profileRepository)
    let id = UUID()
    runtime.send(.catalogRegisterRequested(id: id, name: "Lobby"), from: .settings)
    finishCatalogSave(fixture)

    #expect(
      runtime.send(.catalogRenameRequested(id: id, name: "Entrance"), from: .settings)
        .reply == .accepted)
    finishCatalogSave(fixture)
    #expect(runtime.snapshot.root.catalog.entries.first?.name == "Entrance")
    #expect(runtime.snapshot.root.catalog.entries.first?.version == 2)
    #expect(
      runtime.send(.catalogVisibilityRequested(id: id, visible: false), from: .settings)
        .reply == .accepted)
    finishCatalogSave(fixture)
    #expect(runtime.snapshot.root.catalog.entries.first?.isVisible == false)
    #expect(
      runtime.send(.catalogSelectRequested(id), from: .settings).reply
        == .rejected(.invalidState))
    #expect(runtime.send(.catalogRemovePromptRequested(id), from: .settings).reply == .accepted)
    #expect(runtime.snapshot.root.catalogRemovalCandidateID == id)
    #expect(runtime.send(.catalogRemoveConfirmed(id), from: .settings).reply == .accepted)
    finishCatalogSave(fixture)
    #expect(runtime.snapshot.root.catalog.entries.isEmpty)
    #expect(runtime.snapshot.root.savedProfile == saved)
    #expect(runtime.snapshot.root.activeProfile == nil)
  }

  @Test func updatingSharedEntryUsesSavedSettingsAndQueuesTheNewVersion() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let runtime = fixture.runtime
    let original = try fixture.profile()
    let snapshot = try #require(CatalogSnapshot(original))
    let entry = try #require(
      CatalogEntry(
        id: UUID(), name: "Lobby", snapshot: snapshot,
        scope: .iCloud, accountIdentifier: "account", syncedVersion: 1))
    runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(
        load,
        SettingsCatalog(
          syncEnabled: true, accountIdentifier: "account", entries: [entry])),
      source: .catalogRepository)
    let check = try #require(runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, "account"), source: .cloudCatalog)
    runtime.send(.draftChanged(ProfileDraft(profile: original)), from: .settings)
    runtime.send(.saveDraftRequested, from: .settings)
    let firstSave = try #require(fixture.port.effects.last)
    guard case .saveProfile(let first) = firstSave.kind else {
      Issue.record("Expected operation effect")
      return
    }
    fixture.port.deliver(.profileSaved(firstSave.token, first), source: .profileRepository)
    runtime.send(.draftEdited(.startURL("https://example.com/other")), from: .settings)
    #expect(
      runtime.send(.catalogUpdateRequested(entry.id), from: .settings).reply
        == .rejected(.invalidState))
    runtime.send(.saveDraftRequested, from: .settings)
    let secondSave = try #require(fixture.port.effects.last)
    guard case .saveProfile(let second) = secondSave.kind else {
      Issue.record("Expected operation effect")
      return
    }
    fixture.port.deliver(.profileSaved(secondSave.token, second), source: .profileRepository)
    #expect(runtime.send(.catalogUpdateRequested(entry.id), from: .settings).reply == .accepted)
    #expect(runtime.snapshot.root.catalogUpdateCandidateID == entry.id)
    #expect(runtime.send(.catalogUpdateConfirmed(entry.id), from: .settings).reply == .accepted)
    finishCatalogSave(fixture)
    #expect(runtime.snapshot.root.catalog.entries.first?.snapshot.startURL == second.startURL)
    #expect(runtime.snapshot.root.catalog.entries.first?.version == 2)
    #expect(runtime.snapshot.root.savedProfile == second)
    #expect(runtime.snapshot.root.activeProfile == nil)
    #expect(
      fixture.port.effects.contains { effect in
        if case .publishCatalogChanges(_, _, let saves, _) = effect.kind {
          return saves.first?.id == entry.id && saves.first?.version == 2
        }
        return false
      })
  }

  private func finishCatalogSave(_ fixture: RuntimeFixture) {
    guard let token = fixture.runtime.snapshot.root.catalogSaveOperation,
      let effect = fixture.port.effects.last(where: {
        if case .saveCatalog = $0.kind { return $0.token == token }
        return false
      }),
      case .saveCatalog(let document) = effect.kind
    else {
      Issue.record("Expected catalog save")
      return
    }
    fixture.port.deliver(.catalogSaved(effect.token, document), source: .catalogRepository)
  }

  @Test func selectingAnEntryChangesOnlyTheDraftUntilTheDeviceSaves() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let runtime = fixture.runtime
    runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(.catalogLoaded(load, SettingsCatalog()), source: .catalogRepository)
    runtime.send(.draftChanged(ProfileDraft(profile: try fixture.profile())), from: .settings)
    runtime.send(.saveDraftRequested, from: .settings)
    let firstSave = try #require(fixture.port.effects.last)
    guard case .saveProfile(let first) = firstSave.kind else {
      Issue.record("Expected operation effect")
      return
    }
    fixture.port.deliver(.profileSaved(firstSave.token, first), source: .profileRepository)
    let id = UUID()
    runtime.send(.catalogRegisterRequested(id: id, name: "Lobby"), from: .settings)
    let catalogSave = try #require(fixture.port.effects.last)
    guard case .saveCatalog(let document) = catalogSave.kind else {
      Issue.record("Expected operation effect")
      return
    }
    fixture.port.deliver(.catalogSaved(catalogSave.token, document), source: .catalogRepository)

    runtime.send(.draftEdited(.startURL("https://example.com/other")), from: .settings)
    #expect(
      runtime.send(.catalogSelectRequested(id), from: .settings).reply
        == .rejected(.unsavedDraft))
    #expect(
      runtime.snapshot.administration.draft?.profile.startURL
        == "https://example.com/other")
    runtime.send(.saveDraftRequested, from: .settings)
    let secondSave = try #require(fixture.port.effects.last)
    guard case .saveProfile(let second) = secondSave.kind else {
      Issue.record("Expected operation effect")
      return
    }
    fixture.port.deliver(.profileSaved(secondSave.token, second), source: .profileRepository)
    #expect(second.startURL == "https://example.com/other")
    #expect(runtime.send(.catalogSelectRequested(id), from: .settings).reply == .accepted)
    #expect(runtime.snapshot.administration.catalogSelection?.name == "Lobby")
    #expect(runtime.snapshot.administration.draft?.profile.startURL == second.startURL)
    #expect(runtime.send(.catalogApplyRequested, from: .settings).reply == .accepted)
    #expect(runtime.snapshot.administration.draft?.profile.startURL == first.startURL)
    #expect(runtime.snapshot.root.savedProfile == second)
    #expect(runtime.snapshot.root.activeProfile == nil)
    runtime.send(.saveDraftRequested, from: .settings)
    let thirdSave = try #require(fixture.port.effects.last)
    guard case .saveProfile(let third) = thirdSave.kind else {
      Issue.record("Expected operation effect")
      return
    }
    fixture.port.deliver(.profileSaved(thirdSave.token, third), source: .profileRepository)
    #expect(runtime.snapshot.root.savedProfile?.startURL == first.startURL)
    #expect(runtime.snapshot.root.activeProfile == nil)
  }

  @Test func registeringSavedSettingsDoesNotChangeTheDeviceProfile() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    #expect(fixture.runtime.send(.catalogLoadRequested, from: .root).reply == .accepted)
    let catalogLoad = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(catalogLoad, SettingsCatalog()), source: .catalogRepository)
    fixture.runtime.send(
      .draftChanged(ProfileDraft(profile: try fixture.profile())), from: .settings)
    #expect(fixture.runtime.send(.saveDraftRequested, from: .settings).reply == .accepted)
    let profileSave = try #require(fixture.port.effects.last)
    guard case .saveProfile(let saved) = profileSave.kind else {
      Issue.record("Expected profile save")
      return
    }
    fixture.port.deliver(.profileSaved(profileSave.token, saved), source: .profileRepository)
    let id = try #require(UUID(uuidString: "5D6A2843-475B-452B-B542-A31479AC28CA"))
    let registration = fixture.runtime.send(
      .catalogRegisterRequested(id: id, name: "Lobby"), from: .settings)
    #expect(registration.reply == .accepted)
    let catalogSave = try #require(fixture.port.effects.last)
    guard case .saveCatalog(let document) = catalogSave.kind else {
      Issue.record("Expected catalog save")
      return
    }
    #expect(document.entries.count == 1)
    #expect(document.entries[0].name == "Lobby")
    #expect(document.entries[0].snapshot.startURL == saved.startURL)
    #expect(fixture.runtime.snapshot.root.savedProfile == saved)
    #expect(fixture.runtime.snapshot.root.activeProfile == nil)
    fixture.port.deliver(.catalogSaved(catalogSave.token, document), source: .catalogRepository)
    #expect(fixture.runtime.snapshot.root.catalog.entries == document.entries)
    #expect(fixture.runtime.snapshot.root.savedProfile == saved)
    #expect(fixture.runtime.snapshot.root.activeProfile == nil)
  }
}
