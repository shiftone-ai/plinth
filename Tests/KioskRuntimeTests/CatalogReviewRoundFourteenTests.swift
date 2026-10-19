import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct CatalogReviewRoundFourteenTests {
  @Test func queuedCloudChangeKeepsSyncPendingUntilItsSaveCompletes() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let local = try #require(CatalogEntry(id: UUID(), name: "Local", snapshot: snapshot))
    let remote = try #require(
      CatalogEntry(
        id: UUID(), name: "Remote", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    try start(
      fixture,
      catalog: SettingsCatalog(
        syncEnabled: true, accountIdentifier: "account-a", entries: [local]))
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    fixture.runtime.send(.catalogCloudStatus(session, .ready), from: .cloudCatalog)
    #expect(fixture.runtime.snapshot.root.catalogSyncStatus == .ready)

    fixture.runtime.send(.catalogVisibilityRequested(id: local.id, visible: false), from: .settings)
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-a", [.upsert(remote)]), from: .cloudCatalog)
    fixture.runtime.send(.catalogCloudStatus(session, .ready), from: .cloudCatalog)
    #expect(fixture.runtime.snapshot.root.catalogSyncStatus == .pending)
    try finishSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalogSaveOperation != nil)
    #expect(!fixture.runtime.snapshot.root.catalog.entries.contains { $0.id == remote.id })
    fixture.runtime.send(.catalogCloudStatus(session, .ready), from: .cloudCatalog)
    #expect(fixture.runtime.snapshot.root.catalogSyncStatus == .pending)
    try finishSave(fixture)
    #expect(fixture.runtime.snapshot.root.catalog.entries.contains { $0.id == remote.id })
    #expect(fixture.runtime.snapshot.root.catalogSyncStatus == .ready)
  }

  @Test func queuedCloudChangeSurvivesASecondSaveFailure() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let local = try #require(CatalogEntry(id: UUID(), name: "Local", snapshot: snapshot))
    let remote = try #require(
      CatalogEntry(
        id: UUID(), name: "Remote", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "account-a"))
    try start(
      fixture,
      catalog: SettingsCatalog(
        syncEnabled: true, accountIdentifier: "account-a", entries: [local]))
    let session = try #require(fixture.runtime.snapshot.root.catalogCloudSessionOperation)
    fixture.runtime.send(.catalogVisibilityRequested(id: local.id, visible: false), from: .settings)
    let first = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    fixture.runtime.send(
      .catalogCloudChanges(session, "account-a", [.upsert(remote)]), from: .cloudCatalog)
    fixture.port.deliver(
      .catalogSaved(first, try #require(fixture.runtime.snapshot.root.pendingCatalog)),
      source: .catalogRepository)
    let second = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    fixture.port.deliver(.catalogSaveFailed(second), source: .catalogRepository)
    #expect(fixture.runtime.snapshot.root.catalogSyncStatus == .failed)
    #expect(!fixture.runtime.snapshot.root.queuedCatalogCloudChanges.isEmpty)
    #expect(
      fixture.runtime.send(.catalogSyncRetryRequested, from: .settings).reply == .accepted)
    let retry = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    fixture.port.deliver(
      .catalogSaved(retry, try #require(fixture.runtime.snapshot.root.pendingCatalog)),
      source: .catalogRepository)
    #expect(fixture.runtime.snapshot.root.catalog.entries.contains { $0.id == remote.id })
    #expect(fixture.runtime.snapshot.root.queuedCatalogCloudChanges.isEmpty)
  }

  @Test func failedInitialAccountSaveCanBeRetried() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(load, SettingsCatalog(syncEnabled: true)), source: .catalogRepository)
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, "account-a"), source: .cloudCatalog)
    let first = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    fixture.port.deliver(.catalogSaveFailed(first), source: .catalogRepository)
    #expect(fixture.runtime.snapshot.root.catalogSyncStatus == .failed)
    #expect(
      fixture.runtime.send(.catalogSyncRetryRequested, from: .settings).reply == .accepted)
    let retryCheck = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(retryCheck, "account-a"), source: .cloudCatalog)
    let retrySave = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    fixture.port.deliver(
      .catalogSaved(retrySave, try #require(fixture.runtime.snapshot.root.pendingCatalog)),
      source: .catalogRepository)
    #expect(fixture.runtime.snapshot.root.catalog.accountIdentifier == "account-a")
    #expect(fixture.runtime.snapshot.root.catalogCloudSessionOperation != nil)
  }

  @Test func closingTheLastMobileSceneRevokesAdministratorAccess() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    fixture.runtime.send(
      .mobileDisplaysChanged(.init(deviceAvailable: true, externalAvailable: false)),
      from: .platform)
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: true, displayCount: 1), from: .root)
    #expect(fixture.runtime.send(.unlockRequested, from: .platform).reply == .accepted)
    let unlockID = try #require(fixture.runtime.snapshot.root.unlockID)
    fixture.runtime.send(.authenticationVerified(unlockID: unlockID), from: .administration)
    #expect(fixture.runtime.snapshot.root.mode == .administration)
    #expect(fixture.runtime.snapshot.root.administratorSession)
    fixture.runtime.send(.mobileLastSceneDisconnected, from: .platform)
    #expect(fixture.runtime.snapshot.root.mode == .safeHold)
    #expect(!fixture.runtime.snapshot.root.administratorSession)
    #expect(fixture.runtime.send(.unlockRequested, from: .platform).reply == .accepted)
    #expect(fixture.runtime.snapshot.root.mode == .unlocking)
  }

  @Test func closingTheLastMobileSceneCancelsAnOutstandingUnlock() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    fixture.runtime.send(
      .mobileDisplaysChanged(.init(deviceAvailable: true, externalAvailable: false)),
      from: .platform)
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: true, displayCount: 1), from: .root)
    #expect(fixture.runtime.send(.unlockRequested, from: .platform).reply == .accepted)
    let unlockID = try #require(fixture.runtime.snapshot.root.unlockID)
    fixture.runtime.send(.mobileLastSceneDisconnected, from: .platform)
    #expect(fixture.runtime.snapshot.root.mode == .safeHold)
    #expect(fixture.runtime.snapshot.root.unlockID == nil)
    #expect(
      fixture.runtime.send(.authenticationVerified(unlockID: unlockID), from: .administration)
        .reply == .rejected(.staleOperation))
    #expect(!fixture.runtime.snapshot.root.administratorSession)
  }

  @Test func closingTheLastSceneDuringUnlockCompletionCannotReopenAdministration() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    fixture.runtime.send(
      .mobileDisplaysChanged(.init(deviceAvailable: true, externalAvailable: false)),
      from: .platform)
    try fixture.startExhibiting()
    #expect(fixture.runtime.send(.unlockRequested, from: .platform).reply == .accepted)
    let unlockID = try #require(fixture.runtime.snapshot.root.unlockID)
    fixture.runtime.send(.authenticationVerified(unlockID: unlockID), from: .administration)
    #expect(fixture.runtime.snapshot.root.mode == .leavingKiosk)
    fixture.runtime.send(
      .mobileDisplaysChanged(.init(deviceAvailable: false, externalAvailable: false)),
      from: .platform)
    fixture.runtime.send(.mobileLastSceneDisconnected, from: .platform)
    fixture.runtime.send(.exhibitionStopped, from: .exhibition)
    if let release = fixture.runtime.snapshot.root.presentationOperation {
      fixture.port.deliver(.presentationReleased(release), source: .platform)
    }
    #expect(fixture.runtime.snapshot.root.mode == .safeHold)
    #expect(!fixture.runtime.snapshot.root.administratorSession)
  }

  @Test func credentialConfiguredAfterTheLastSceneClosesRequiresUnlock() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    fixture.runtime.send(
      .mobileDisplaysChanged(.init(deviceAvailable: true, externalAvailable: false)),
      from: .platform)
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(
      .credentialConfigurationRequested("test-passcode"), from: .administration)
    let operation = try #require(fixture.runtime.snapshot.root.credentialOperation)
    fixture.runtime.send(
      .mobileDisplaysChanged(.init(deviceAvailable: false, externalAvailable: false)),
      from: .platform)
    fixture.runtime.send(.mobileLastSceneDisconnected, from: .platform)
    fixture.port.deliver(.credentialConfigured(operation, succeeded: true), source: .credentials)
    #expect(fixture.runtime.snapshot.root.mode == .safeHold)
    #expect(!fixture.runtime.snapshot.root.administratorSession)
  }

  private func start(_ fixture: RuntimeFixture, catalog: SettingsCatalog) throws {
    fixture.runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    fixture.runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(fixture.runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(.catalogLoaded(load, catalog), source: .catalogRepository)
    let check = try #require(fixture.runtime.snapshot.root.catalogAccountCheckOperation)
    fixture.port.deliver(.catalogAccountChecked(check, "account-a"), source: .cloudCatalog)
  }

  private func finishSave(_ fixture: RuntimeFixture) throws {
    let token = try #require(fixture.runtime.snapshot.root.catalogSaveOperation)
    let document = try #require(fixture.runtime.snapshot.root.pendingCatalog)
    fixture.port.deliver(.catalogSaved(token, document), source: .catalogRepository)
  }
}
