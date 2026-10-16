import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct CatalogCrossDeviceTests {
  @Test func sharedEntryRequiresDeviceChoiceAndDeletionKeepsSavedProfileAfterRestart() async throws
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-catalog-cross-device-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let profile = try RuntimeFixture().profile()
    let id = UUID()
    let shared = try await publishSource(profile, id: id, in: directory)
    #expect(shared.scope == .iCloud)
    #expect(shared.accountIdentifier == "account-a")

    let destinationProfile = ProfileRepository(
      fileURL: directory.appendingPathComponent("b/profile.json"))
    let destinationCatalog = CatalogRepository(
      fileURL: directory.appendingPathComponent("b/catalog.json"))
    let destinationPort = CatalogPersistencePort(
      profile: destinationProfile, catalog: destinationCatalog,
      accountIdentifier: "account-a")
    let destinationExecutor = EffectExecutor(port: destinationPort)
    let destination = RootRuntime(clock: FakeClock(), executor: destinationExecutor)
    defer { destination.stop() }
    try await start(destination, executor: destinationExecutor)
    var ownProfile = profile
    ownProfile.startURL = "https://example.com/other"
    try await save(ownProfile, in: destination, executor: destinationExecutor)
    let savedBeforeReceipt = try #require(destination.snapshot.root.savedProfile)
    try await receive(
      shared, in: destination, executor: destinationExecutor, port: destinationPort,
      savedBeforeReceipt: savedBeforeReceipt)

    #expect(
      destination.send(.catalogVisibilityRequested(id: id, visible: true), from: .settings).reply
        == .accepted)
    await destinationExecutor.registry.waitForOperation(
      try #require(destination.snapshot.root.catalogSaveOperation))
    #expect(destination.send(.catalogSelectRequested(id), from: .settings).reply == .accepted)
    #expect(destination.send(.catalogApplyRequested, from: .settings).reply == .accepted)
    #expect(destination.snapshot.administration.draft?.profile.startURL == profile.startURL)
    #expect(destination.snapshot.root.savedProfile == savedBeforeReceipt)
    #expect(destination.send(.saveDraftRequested, from: .settings).reply == .accepted)
    await destinationExecutor.registry.waitForOperation(
      try #require(destination.snapshot.root.saveOperation))
    #expect(destination.snapshot.root.savedProfile?.startURL == profile.startURL)
    #expect(!destinationPort.credentialsConfigured)
    try await receiveDeletion(
      id, in: destination, executor: destinationExecutor, savedStartURL: profile.startURL)
    destination.stop()

    try await verifyRestart(
      profile: destinationProfile, catalog: destinationCatalog,
      startURL: profile.startURL)
  }

  private func receiveDeletion(
    _ id: UUID, in runtime: RootRuntime, executor: EffectExecutor, savedStartURL: String
  ) async throws {
    let session = try #require(runtime.snapshot.root.catalogCloudSessionOperation)
    #expect(
      runtime.send(
        .catalogCloudChanges(session, "account-a", [.delete(id)]), from: .cloudCatalog
      ).reply == .accepted)
    await executor.registry.waitForOperation(
      try #require(runtime.snapshot.root.catalogSaveOperation))
    #expect(runtime.snapshot.root.catalog.entries.isEmpty)
    #expect(runtime.snapshot.root.savedProfile?.startURL == savedStartURL)
  }

  private func publishSource(_ profile: KioskProfile, id: UUID, in directory: URL) async throws
    -> CatalogEntry
  {
    let port = CatalogPersistencePort(
      profile: ProfileRepository(fileURL: directory.appendingPathComponent("a/profile.json")),
      catalog: CatalogRepository(fileURL: directory.appendingPathComponent("a/catalog.json")),
      accountIdentifier: "account-a")
    let executor = EffectExecutor(port: port)
    let runtime = RootRuntime(clock: FakeClock(), executor: executor)
    defer { runtime.stop() }
    try await start(runtime, executor: executor)
    try await save(profile, in: runtime, executor: executor)
    #expect(
      runtime.send(.catalogRegisterRequested(id: id, name: "Lobby"), from: .settings).reply
        == .accepted)
    await executor.registry.waitForOperation(
      try #require(runtime.snapshot.root.catalogSaveOperation))
    try await enableSync(runtime, executor: executor)
    #expect(port.publishedEntries.isEmpty)
    #expect(runtime.send(.catalogSharePromptRequested(id), from: .settings).reply == .accepted)
    #expect(runtime.send(.catalogShareConfirmed(id), from: .settings).reply == .accepted)
    await executor.registry.waitForOperation(
      try #require(runtime.snapshot.root.catalogSaveOperation))
    return try await publishedEntry(id, from: port)
  }

  private func receive(
    _ shared: CatalogEntry, in runtime: RootRuntime, executor: EffectExecutor,
    port: CatalogPersistencePort, savedBeforeReceipt: KioskProfile
  ) async throws {
    try await enableSync(runtime, executor: executor)
    let session = try #require(runtime.snapshot.root.catalogCloudSessionOperation)
    runtime.send(
      .catalogCloudChanges(session, "account-a", [.upsert(shared)]), from: .cloudCatalog)
    await executor.registry.waitForOperation(
      try #require(runtime.snapshot.root.catalogSaveOperation))
    #expect(runtime.snapshot.root.savedProfile == savedBeforeReceipt)
    #expect(runtime.snapshot.root.activeProfile == nil)
    #expect(!port.credentialsConfigured)
    #expect(runtime.snapshot.root.catalog.entries.first?.isVisible == false)
    #expect(runtime.settingsProps.props.catalog.visibleEntries.isEmpty)
  }

  private func verifyRestart(
    profile: ProfileRepository, catalog: CatalogRepository, startURL: String
  ) async throws {
    let executor = EffectExecutor(
      port: CatalogPersistencePort(
        profile: profile, catalog: catalog, accountIdentifier: "account-a"))
    let runtime = RootRuntime(clock: FakeClock(), executor: executor)
    defer { runtime.stop() }
    try await start(runtime, executor: executor)
    #expect(runtime.snapshot.root.savedProfile?.startURL == startURL)
    #expect(runtime.snapshot.root.catalog.entries.isEmpty)
    #expect(runtime.snapshot.root.credentialsConfigured == false)
  }

  private func start(_ runtime: RootRuntime, executor: EffectExecutor) async throws {
    runtime.send(.bootstrapRequested, from: .root)
    await executor.registry.waitForOperation(try #require(runtime.snapshot.root.bootstrapOperation))
    #expect(runtime.send(.catalogLoadRequested, from: .root).reply == .accepted)
    await executor.registry.waitForOperation(
      try #require(runtime.snapshot.root.catalogLoadOperation))
    #expect(runtime.snapshot.root.catalogLoaded)
  }

  private func save(_ profile: KioskProfile, in runtime: RootRuntime, executor: EffectExecutor)
    async throws
  {
    runtime.send(.draftChanged(ProfileDraft(profile: profile)), from: .settings)
    #expect(runtime.send(.saveDraftRequested, from: .settings).reply == .accepted)
    await executor.registry.waitForOperation(try #require(runtime.snapshot.root.saveOperation))
    #expect(runtime.snapshot.root.savedProfile != nil)
  }

  private func enableSync(_ runtime: RootRuntime, executor: EffectExecutor) async throws {
    #expect(runtime.send(.catalogSyncEnableRequested, from: .settings).reply == .accepted)
    #expect(runtime.send(.catalogSyncEnableConfirmed, from: .settings).reply == .accepted)
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while runtime.snapshot.root.catalogCloudSessionOperation == nil
      || runtime.snapshot.root.catalogSaveOperation != nil, ContinuousClock.now < deadline
    {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(runtime.snapshot.root.catalogCloudSessionOperation != nil)
    #expect(runtime.snapshot.root.catalogSaveOperation == nil)
  }

  private func publishedEntry(_ id: UUID, from port: CatalogPersistencePort) async throws
    -> CatalogEntry
  {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while !port.publishedEntries.contains(where: { $0.id == id }), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    return try #require(port.publishedEntries.first(where: { $0.id == id }))
  }
}
