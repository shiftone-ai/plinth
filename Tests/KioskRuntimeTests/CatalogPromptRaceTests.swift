import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct CatalogPromptRaceTests {
  @Test func accountRecheckClosesSharedDetailBeforeItBecomesAvailableAgain() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let shared = try #require(
      CatalogEntry(
        id: UUID(), name: "Shared", snapshot: CatalogSnapshot(fixture.profile())!,
        scope: .iCloud, accountIdentifier: "account-a"))
    try load(
      fixture,
      SettingsCatalog(
        syncEnabled: true, accountIdentifier: "account-a", entries: [shared]),
      account: "account-a")
    #expect(
      fixture.runtime.send(
        .catalogSelectRequested(shared.id), from: .settings
      ).reply == .accepted)
    #expect(fixture.runtime.snapshot.administration.catalogSelection?.id == shared.id)
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    fixture.runtime.send(.catalogCloudAccountChanged(session), from: .cloudCatalog)
    #expect(fixture.runtime.snapshot.administration.catalogSelection == nil)
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, "account-a"), source: .cloudCatalog)
    #expect(fixture.runtime.snapshot.administration.catalogSelection == nil)
  }

  @Test func savedSettingsChangeInvalidatesSharedUpdateConfirmation() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let original = try fixture.profile()
    let shared = try #require(
      CatalogEntry(
        id: UUID(), name: "Shared", snapshot: CatalogSnapshot(original)!,
        scope: .iCloud, accountIdentifier: "account-a"))
    try load(
      fixture,
      SettingsCatalog(
        syncEnabled: true, accountIdentifier: "account-a", entries: [shared]),
      account: "account-a")
    var first = original
    first.startURL = "https://example.com/first"
    fixture.runtime.send(.draftChanged(ProfileDraft(profile: first)), from: .settings)
    fixture.runtime.send(.saveDraftRequested, from: .settings)
    let firstSave = try #require(fixture.runtime.snapshot.root.saveOperation)
    let firstProfile = try #require(fixture.runtime.snapshot.root.pendingProfile)
    fixture.port.deliver(.profileSaved(firstSave, firstProfile), source: .profileRepository)
    #expect(
      fixture.runtime.send(
        .catalogUpdateRequested(shared.id), from: .settings
      ).reply == .accepted)
    #expect(fixture.runtime.snapshot.root.catalogUpdateCandidateID == shared.id)

    fixture.runtime.send(.draftEdited(.startURL("https://example.com/second")), from: .settings)
    fixture.runtime.send(.saveDraftRequested, from: .settings)
    let secondSave = try #require(fixture.runtime.snapshot.root.saveOperation)
    let secondProfile = try #require(fixture.runtime.snapshot.root.pendingProfile)
    fixture.port.deliver(.profileSaved(secondSave, secondProfile), source: .profileRepository)
    #expect(fixture.runtime.snapshot.root.catalogUpdateCandidateID == nil)
    #expect(
      fixture.runtime.send(
        .catalogUpdateConfirmed(shared.id), from: .settings
      ).reply == .rejected(.invalidState))
    #expect(fixture.runtime.snapshot.root.catalog.entries.first?.snapshot == shared.snapshot)
  }

  @Test func scopeCollisionBlocksSharingBeforeAndAfterItsPrompt() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let id = UUID()
    let device = try #require(CatalogEntry(id: id, name: "Device", snapshot: snapshot))
    let remote = try #require(
      CatalogEntry(
        id: id, name: "Shared", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    try load(
      fixture,
      SettingsCatalog(
        syncEnabled: true, accountIdentifier: "account-a", entries: [device]),
      account: "account-a")
    #expect(fixture.runtime.send(.catalogSelectRequested(id), from: .settings).reply == .accepted)
    #expect(
      fixture.runtime.send(
        .catalogSharePromptRequested(id), from: .settings
      ).reply == .accepted)
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-a", [.upsert(remote)]), from: .cloudCatalog)
    try finishSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalog.conflicts.map(\.id) == [id])
    #expect(fixture.runtime.snapshot.root.catalogShareCandidateID == nil)
    #expect(!fixture.runtime.settingsProps.props.catalog.canShare)
    #expect(
      fixture.runtime.send(
        .catalogSharePromptRequested(id), from: .settings
      ).reply == .rejected(.invalidState))
    #expect(
      fixture.runtime.send(
        .catalogShareConfirmed(id), from: .settings
      ).reply == .rejected(.invalidState))
    #expect(fixture.runtime.snapshot.root.catalog.entries.first?.scope == .device)
  }

  @Test func remoteDeletionDisablesAnOpenExportSheet() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let shared = try #require(
      CatalogEntry(
        id: UUID(), name: "Shared", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a", syncedVersion: 1))
    let other = try #require(CatalogEntry(id: UUID(), name: "Other", snapshot: snapshot))
    try load(
      fixture,
      SettingsCatalog(
        syncEnabled: true, accountIdentifier: "account-a", entries: [shared, other]),
      account: "account-a")
    #expect(
      fixture.runtime.send(
        .catalogExportPromptRequested(ids: [shared.id]), from: .settings
      ).reply == .accepted)
    fixture.runtime.send(.catalogPassphraseEdited("long-enough-file-passphrase"), from: .settings)
    fixture.runtime.send(
      .catalogConfirmPassphraseEdited("long-enough-file-passphrase"), from: .settings)
    #expect(fixture.runtime.settingsProps.props.catalog.canExport)
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-a", [.delete(shared.id)]), from: .cloudCatalog)
    try finishSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalog.entries.map(\.id) == [other.id])
    #expect(!fixture.runtime.settingsProps.props.catalog.canExport)
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
