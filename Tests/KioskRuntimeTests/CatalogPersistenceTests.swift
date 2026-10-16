import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct CatalogPersistenceTests {
  @Test func importingTheSameIdentifierWithADifferentNameKeepsBothEntries() throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    let runtime = fixture.runtime
    let snapshot = try #require(CatalogSnapshot(fixture.profile()))
    let id = UUID()
    let original = try #require(CatalogEntry(id: id, name: "Lobby", snapshot: snapshot))
    let renamed = try #require(CatalogEntry(id: id, name: "Entrance", snapshot: snapshot))
    runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(runtime.snapshot.root.catalogLoadOperation)
    fixture.port.deliver(
      .catalogLoaded(load, SettingsCatalog(entries: [original])),
      source: .catalogRepository)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(
      "catalog.plinthsettings")
    runtime.send(
      .catalogImportOperationRequested(file, passphrase: "long-enough-passphrase"),
      from: .administration)
    let importToken = try #require(runtime.snapshot.root.catalogImportOperation)
    fixture.port.deliver(
      .catalogImportPreviewReady(importToken, [renamed]),
      source: .catalogRepository)
    let replacementID = UUID()
    #expect(
      runtime.send(
        .catalogImportConfirmed(replacementIDs: [replacementID]),
        from: .settings
      ).reply == .accepted)
    finishCatalogSave(fixture)
    #expect(Set(runtime.snapshot.root.catalog.entries.map(\.name)) == ["Lobby", "Entrance"])
    #expect(Set(runtime.snapshot.root.catalog.entries.map(\.id)) == [id, replacementID])
  }

  @Test func encryptedFileImportWaitsForExplicitConfirmationAndKeepsTheDeviceSettings() async throws
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-catalog-file-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let firstCatalog = CatalogRepository(
      fileURL: directory.appendingPathComponent("first/catalog.json"))
    let firstExecutor = EffectExecutor(
      port: CatalogPersistencePort(
        profile: ProfileRepository(fileURL: directory.appendingPathComponent("first/profile.json")),
        catalog: firstCatalog))
    let first = RootRuntime(clock: FakeClock(), executor: firstExecutor)
    defer { first.stop() }
    first.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    first.send(.catalogLoadRequested, from: .root)
    await firstExecutor.registry.waitForOperation(
      try #require(first.snapshot.root.catalogLoadOperation))
    first.send(
      .draftChanged(ProfileDraft(profile: try RuntimeFixture().profile())), from: .settings)
    first.send(.saveDraftRequested, from: .settings)
    await firstExecutor.registry.waitForOperation(try #require(first.snapshot.root.saveOperation))
    let id = UUID()
    first.send(.catalogRegisterRequested(id: id, name: "Lobby"), from: .settings)
    await firstExecutor.registry.waitForOperation(
      try #require(first.snapshot.root.catalogSaveOperation))
    let passphrase = "correct horse battery exhibition"
    first.send(.catalogPassphraseEdited(passphrase), from: .settings)
    first.send(.catalogConfirmPassphraseEdited(passphrase), from: .settings)
    #expect(
      first.send(.catalogExportRequested(ids: [id]), from: .settings)
        .reply == .accepted)
    await firstExecutor.registry.waitForOperation(
      try #require(first.snapshot.root.catalogExportOperation))
    let encrypted = try #require(first.snapshot.root.catalogExportData)
    #expect(encrypted.range(of: Data("https://example.com/home".utf8)) == nil)
    let fileURL = directory.appendingPathComponent("settings.plinthsettings")
    try encrypted.write(to: fileURL)

    let secondExecutor = EffectExecutor(
      port: CatalogPersistencePort(
        profile: ProfileRepository(
          fileURL: directory.appendingPathComponent("second/profile.json")),
        catalog: CatalogRepository(fileURL: directory.appendingPathComponent("second/catalog.json"))
      ))
    let second = RootRuntime(clock: FakeClock(), executor: secondExecutor)
    defer { second.stop() }
    second.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    second.send(.catalogLoadRequested, from: .root)
    await secondExecutor.registry.waitForOperation(
      try #require(second.snapshot.root.catalogLoadOperation))
    second.send(.catalogPassphraseEdited("wrong passphrase value"), from: .settings)
    second.send(.catalogImportFileRequested(fileURL), from: .settings)
    await secondExecutor.registry.waitForOperation(
      try #require(second.snapshot.root.catalogImportOperation))
    #expect(second.snapshot.root.catalogImportPreview == nil)
    #expect(second.snapshot.root.catalog.entries.isEmpty)
    second.send(.catalogPassphraseEdited(passphrase), from: .settings)
    second.send(.catalogImportFileRequested(fileURL), from: .settings)
    await secondExecutor.registry.waitForOperation(
      try #require(second.snapshot.root.catalogImportOperation))
    #expect(second.snapshot.root.catalogImportPreview?.map(\.name) == ["Lobby"])
    #expect(second.snapshot.root.catalog.entries.isEmpty)
    #expect(second.snapshot.root.savedProfile == nil)
    #expect(
      second.send(.catalogImportConfirmed(replacementIDs: [UUID()]), from: .settings)
        .reply == .accepted)
    await secondExecutor.registry.waitForOperation(
      try #require(second.snapshot.root.catalogSaveOperation))
    #expect(second.snapshot.root.catalog.entries.map(\.name) == ["Lobby"])
    #expect(second.snapshot.root.savedProfile == nil)
    #expect(second.snapshot.root.activeProfile == nil)
  }

  @Test func encryptedFileRejectsTamperingUnknownVersionAndOversizeInput() async throws {
    let profile = try RuntimeFixture().profile()
    let entry = try #require(
      CatalogEntry(
        id: UUID(), name: "Lobby", snapshot: CatalogSnapshot(profile)!))
    let passphrase = "long-enough-catalog-passphrase"
    let encrypted = try await EncryptedCatalogFile.encrypt(
      entries: [entry], passphrase: passphrase)
    var tampered = encrypted
    tampered[tampered.count - 1] ^= 1
    await #expect(throws: EncryptedCatalogFile.Failure.self) {
      try await EncryptedCatalogFile.decrypt(tampered, passphrase: passphrase)
    }
    var unknownVersion = encrypted
    unknownVersion[8] = 2
    await #expect(throws: EncryptedCatalogFile.Failure.unsupportedVersion) {
      try await EncryptedCatalogFile.decrypt(unknownVersion, passphrase: passphrase)
    }
    let oversized = Data(repeating: 0, count: EncryptedCatalogFile.maximumFileBytes + 1)
    await #expect(throws: EncryptedCatalogFile.Failure.tooLarge) {
      try await EncryptedCatalogFile.decrypt(oversized, passphrase: passphrase)
    }
  }

  @Test func registeredSettingsSurviveRestartThroughTheRealRepositories() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-catalog-runtime-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let profileRepository = ProfileRepository(
      fileURL: directory.appendingPathComponent("profile.json"))
    let catalogRepository = CatalogRepository(
      fileURL: directory.appendingPathComponent("catalog.json"))
    let port = CatalogPersistencePort(profile: profileRepository, catalog: catalogRepository)
    let executor = EffectExecutor(port: port)
    let runtime = RootRuntime(clock: FakeClock(), executor: executor)
    runtime.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    runtime.send(.catalogLoadRequested, from: .root)
    let load = try #require(runtime.snapshot.root.catalogLoadOperation)
    await executor.registry.waitForOperation(load)
    #expect(runtime.snapshot.root.catalogLoaded)
    let profile = try RuntimeFixture().profile()
    runtime.send(.draftChanged(ProfileDraft(profile: profile)), from: .settings)
    #expect(runtime.send(.saveDraftRequested, from: .settings).reply == .accepted)
    let profileSave = try #require(runtime.snapshot.root.saveOperation)
    await executor.registry.waitForOperation(profileSave)
    let saved = try #require(runtime.snapshot.root.savedProfile)
    let id = UUID()
    #expect(
      runtime.send(.catalogRegisterRequested(id: id, name: "Lobby"), from: .settings)
        .reply == .accepted)
    let catalogSave = try #require(runtime.snapshot.root.catalogSaveOperation)
    await executor.registry.waitForOperation(catalogSave)
    #expect(runtime.snapshot.root.catalog.entries.map(\.id) == [id])
    #expect(runtime.snapshot.root.savedProfile == saved)
    runtime.stop()

    let restartExecutor = EffectExecutor(
      port: CatalogPersistencePort(
        profile: profileRepository, catalog: catalogRepository))
    let restarted = RootRuntime(clock: FakeClock(), executor: restartExecutor)
    defer { restarted.stop() }
    restarted.send(.catalogLoadRequested, from: .root)
    let reload = try #require(restarted.snapshot.root.catalogLoadOperation)
    await restartExecutor.registry.waitForOperation(reload)
    #expect(restarted.snapshot.root.catalog.entries.map(\.id) == [id])
    #expect(restarted.snapshot.root.catalog.entries.first?.name == "Lobby")
    #expect(restarted.snapshot.root.savedProfile == nil)
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

}

@MainActor
private final class CatalogPersistencePort: EffectPort {
  private let profile: ProfileRepository
  private let catalog: CatalogRepository

  init(profile: ProfileRepository, catalog: CatalogRepository) {
    self.profile = profile
    self.catalog = catalog
  }

  func perform(_ effect: Effect) async -> Event? {
    switch effect.kind {
    case .loadCatalog:
      do { return try await .catalogLoaded(effect.token, catalog.load()) } catch {
        return .catalogLoadFailed(effect.token)
      }
    case .saveCatalog(let document):
      do {
        try await catalog.save(document)
        return .catalogSaved(effect.token, document)
      } catch { return .catalogSaveFailed(effect.token) }
    case .saveProfile(let value):
      do {
        try await profile.save(value)
        return .profileSaved(effect.token, value)
      } catch { return .profileSaveFailed(effect.token) }
    case .prepareCatalogExport(let entries, let passphrase):
      do {
        return try await .catalogExportPrepared(
          effect.token, EncryptedCatalogFile.encrypt(entries: entries, passphrase: passphrase))
      } catch { return .catalogExportFailed(effect.token) }
    case .importCatalogFile(let url, let passphrase):
      do {
        let data = try Data(contentsOf: url)
        return try await .catalogImportPreviewReady(
          effect.token, EncryptedCatalogFile.decrypt(data, passphrase: passphrase))
      } catch { return .catalogImportFailed(effect.token) }
    default: return nil
    }
  }

  func stop() {}
}
