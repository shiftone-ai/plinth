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

  @Test func encryptedFilePreservesNavigationAndOutputSettings() async throws {
    let fixture = RuntimeFixture()
    defer { fixture.runtime.stop() }
    var mac = try fixture.profile()
    let blocked = try #require(Origin(urlString: "https://blocked.example.net"))
    mac.navigation = .init(
      mode: .denylist, rules: [.init(id: 2, origin: blocked, includeSubdomains: true)],
      allowsHTTP: true)
    mac.interaction = .init(allowsScroll: true, allowsDrag: true)
    mac.resetMode = .retainWebsiteData
    mac.recovery = .init(maximumAttempts: 5, delay: 3)
    mac.macOutput = .init(mode: .projectionWindow, displayID: "second-display")
    var mobile = try fixture.profile()
    mobile.exhibitionDestination = .externalDisplay
    mobile.externalDisplayMode = .init(width: 1920, height: 1080)
    mobile.externalDisplayRotation = .clockwise
    let macSnapshot = try #require(CatalogSnapshot(mac))
    let mobileSnapshot = try #require(CatalogSnapshot(mobile))
    let entries = [
      try #require(CatalogEntry(id: UUID(), name: "Mac", snapshot: macSnapshot)),
      try #require(CatalogEntry(id: UUID(), name: "iPad", snapshot: mobileSnapshot)),
    ]
    let passphrase = "correct horse battery exhibition"
    let encrypted = try await EncryptedCatalogFile.encrypt(
      entries: entries, passphrase: passphrase)
    let decoded = try await EncryptedCatalogFile.decrypt(encrypted, passphrase: passphrase)
    #expect(decoded.map(\.snapshot) == [macSnapshot, mobileSnapshot])
  }

  @Test func wholeCollectionFileTransfersAvailableEntriesWithoutSharingThem() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-catalog-whole-file-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let snapshot = try #require(CatalogSnapshot(RuntimeFixture().profile()))
    let lobby = try #require(CatalogEntry(id: UUID(), name: "Lobby", snapshot: snapshot))
    let gallery = try #require(CatalogEntry(id: UUID(), name: "Gallery", snapshot: snapshot))
    let formerAccount = try #require(
      CatalogEntry(
        id: UUID(), name: "Former account", snapshot: snapshot, scope: .iCloud,
        accountIdentifier: "previous-account"))
    let sourceCatalog = CatalogRepository(
      fileURL: directory.appendingPathComponent("source/catalog.json"))
    try await sourceCatalog.save(
      SettingsCatalog(revision: 1, entries: [lobby, gallery, formerAccount]))
    let sourceExecutor = EffectExecutor(
      port: CatalogPersistencePort(
        profile: ProfileRepository(
          fileURL: directory.appendingPathComponent("source/profile.json")),
        catalog: sourceCatalog))
    let source = RootRuntime(clock: FakeClock(), executor: sourceExecutor)
    defer { source.stop() }
    source.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    source.send(.catalogLoadRequested, from: .root)
    await sourceExecutor.registry.waitForOperation(
      try #require(source.snapshot.root.catalogLoadOperation))
    let passphrase = "correct horse battery exhibition"
    source.send(.catalogPassphraseEdited(passphrase), from: .settings)
    source.send(.catalogConfirmPassphraseEdited(passphrase), from: .settings)
    #expect(source.send(.catalogExportRequested(ids: []), from: .settings).reply == .accepted)
    await sourceExecutor.registry.waitForOperation(
      try #require(source.snapshot.root.catalogExportOperation))
    let encrypted = try #require(source.snapshot.root.catalogExportData)
    #expect(encrypted.range(of: Data("https://example.com/home".utf8)) == nil)
    let fileURL = directory.appendingPathComponent("whole.plinthsettings")
    try encrypted.write(to: fileURL)

    let destinationCatalog = CatalogRepository(
      fileURL: directory.appendingPathComponent("destination/catalog.json"))
    let destinationExecutor = EffectExecutor(
      port: CatalogPersistencePort(
        profile: ProfileRepository(
          fileURL: directory.appendingPathComponent("destination/profile.json")),
        catalog: destinationCatalog))
    let destination = RootRuntime(clock: FakeClock(), executor: destinationExecutor)
    defer { destination.stop() }
    destination.send(
      .bootstrapped(profile: nil, credentialsConfigured: false, displayCount: 1), from: .root)
    destination.send(.catalogLoadRequested, from: .root)
    await destinationExecutor.registry.waitForOperation(
      try #require(destination.snapshot.root.catalogLoadOperation))
    destination.send(.catalogPassphraseEdited(passphrase), from: .settings)
    #expect(
      destination.send(.catalogImportFileRequested(fileURL), from: .settings).reply == .accepted)
    await destinationExecutor.registry.waitForOperation(
      try #require(destination.snapshot.root.catalogImportOperation))
    let preview = try #require(destination.snapshot.root.catalogImportPreview)
    #expect(Set(preview.map(\.name)) == ["Lobby", "Gallery"])
    #expect(destination.snapshot.root.catalog.entries.isEmpty)
    #expect(
      destination.send(
        .catalogImportConfirmed(replacementIDs: preview.map { _ in UUID() }), from: .settings
      ).reply == .accepted)
    await destinationExecutor.registry.waitForOperation(
      try #require(destination.snapshot.root.catalogSaveOperation))
    let reloaded = try await destinationCatalog.load()
    #expect(Set(reloaded.entries.map(\.name)) == ["Lobby", "Gallery"])
    #expect(reloaded.entries.allSatisfy { $0.scope == .device })
    #expect(!reloaded.syncEnabled)
    #expect(destination.snapshot.root.savedProfile == nil)
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
