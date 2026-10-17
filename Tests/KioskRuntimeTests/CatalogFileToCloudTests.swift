import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct CatalogFileToCloudTests {
  @Test func selectedFileEntryIsSharedOnlyAfterImportAndSeparateConsent() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-catalog-file-to-cloud-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let snapshot = try #require(CatalogSnapshot(RuntimeFixture().profile()))
    let lobby = try #require(CatalogEntry(id: UUID(), name: "Lobby", snapshot: snapshot))
    let gallery = try #require(CatalogEntry(id: UUID(), name: "Gallery", snapshot: snapshot))
    let passphrase = "correct horse battery exhibition"
    let file = try await exportSelectedFile(
      from: [lobby, gallery], selectedID: lobby.id, passphrase: passphrase, in: directory)

    let destinationPort = CatalogPersistencePort(
      profile: ProfileRepository(fileURL: directory.appendingPathComponent("target/profile.json")),
      catalog: CatalogRepository(fileURL: directory.appendingPathComponent("target/catalog.json")),
      accountIdentifier: "account-a")
    let destinationExecutor = EffectExecutor(port: destinationPort)
    let destination = RootRuntime(clock: FakeClock(), executor: destinationExecutor)
    defer { destination.stop() }
    try await loadCatalog(destination, executor: destinationExecutor)
    destination.send(.catalogPassphraseEdited(passphrase), from: .settings)
    #expect(
      destination.send(.catalogImportFileRequested(file), from: .settings).reply
        == .accepted)
    await destinationExecutor.registry.waitForOperation(
      try #require(destination.snapshot.root.catalogImportOperation))
    #expect(destination.snapshot.root.catalogImportPreview?.map(\.name) == ["Lobby"])
    #expect(
      destination.send(.catalogImportConfirmed(replacementIDs: [UUID()]), from: .settings)
        .reply == .accepted)
    await destinationExecutor.registry.waitForOperation(
      try #require(destination.snapshot.root.catalogSaveOperation))
    #expect(destination.snapshot.root.catalog.entries.map(\.name) == ["Lobby"])
    let importedID = try #require(destination.snapshot.root.catalog.entries.first?.id)
    #expect(importedID == lobby.id)
    #expect(destination.snapshot.root.catalog.entries.first?.scope == .device)
    #expect(destinationPort.publishedEntries.isEmpty)
    try await enableSync(destination, port: destinationPort)
    #expect(destinationPort.publishedEntries.isEmpty)
    #expect(
      destination.send(.catalogSharePromptRequested(importedID), from: .settings).reply
        == .accepted)
    #expect(
      destination.send(.catalogShareConfirmed(importedID), from: .settings).reply
        == .accepted)
    await destinationExecutor.registry.waitForOperation(
      try #require(destination.snapshot.root.catalogSaveOperation))
    try await expectPublished(importedID, from: destinationPort)
    #expect(destination.snapshot.root.savedProfile == nil)
  }

  private func expectPublished(_ id: UUID, from port: CatalogPersistencePort) async throws {
    _ = await port.waitForPublishedEntry(id)
    #expect(port.publishedEntries.map(\.name) == ["Lobby"])
    #expect(port.publishedEntries.map(\.id) == [id])
  }

  private func exportSelectedFile(
    from entries: [CatalogEntry], selectedID: UUID, passphrase: String, in directory: URL
  ) async throws -> URL {
    let sourceCatalog = CatalogRepository(
      fileURL: directory.appendingPathComponent("source/catalog.json"))
    try await sourceCatalog.save(SettingsCatalog(revision: 1, entries: entries))
    let sourceExecutor = EffectExecutor(
      port: CatalogPersistencePort(
        profile: ProfileRepository(
          fileURL: directory.appendingPathComponent("source/profile.json")),
        catalog: sourceCatalog))
    let source = RootRuntime(clock: FakeClock(), executor: sourceExecutor)
    defer { source.stop() }
    try await loadCatalog(source, executor: sourceExecutor)
    source.send(.catalogPassphraseEdited(passphrase), from: .settings)
    source.send(.catalogConfirmPassphraseEdited(passphrase), from: .settings)
    #expect(
      source.send(.catalogExportRequested(ids: [selectedID]), from: .settings).reply
        == .accepted)
    await sourceExecutor.registry.waitForOperation(
      try #require(source.snapshot.root.catalogExportOperation))
    let encrypted = try #require(source.snapshot.root.catalogExportData)
    let file = directory.appendingPathComponent("selected.plinthsettings")
    try encrypted.write(to: file)
    return file
  }

  private func loadCatalog(_ runtime: RootRuntime, executor: EffectExecutor) async throws {
    runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1),
      from: .root)
    #expect(runtime.send(.catalogLoadRequested, from: .root).reply == .accepted)
    await executor.registry.waitForOperation(
      try #require(runtime.snapshot.root.catalogLoadOperation))
    #expect(runtime.snapshot.root.catalogLoaded)
  }

  private func enableSync(_ runtime: RootRuntime, port: CatalogPersistencePort) async throws {
    #expect(runtime.send(.catalogSyncEnableRequested, from: .settings).reply == .accepted)
    #expect(runtime.send(.catalogSyncEnableConfirmed, from: .settings).reply == .accepted)
    await port.waitForCloudStart()
    #expect(runtime.snapshot.root.catalogCloudSessionOperation != nil)
    #expect(runtime.snapshot.root.catalogSaveOperation == nil)
  }
}
