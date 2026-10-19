import Foundation
import KioskCore
import KioskRuntime
import Testing

@MainActor
struct CatalogSafeHoldRecoveryTests {
  @Test func corruptSavedProfileCanBeRecoveredAfterAuthenticationAndImport() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-catalog-corrupt-recovery-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let profileURL = directory.appendingPathComponent("profile.json")
    try Data("{corrupt".utf8).write(to: profileURL)
    let profileRepository = ProfileRepository(fileURL: profileURL)
    let catalogRepository = CatalogRepository(
      fileURL: directory.appendingPathComponent("catalog.json"))
    let usable = try RuntimeFixture().profile()
    let entry = try #require(
      CatalogEntry(id: UUID(), name: "Recovered", snapshot: CatalogSnapshot(usable)!))
    let passphrase = "correct horse battery exhibition"
    let encrypted = try await EncryptedCatalogFile.encrypt(entries: [entry], passphrase: passphrase)
    let file = directory.appendingPathComponent("recovery.plinthsettings")
    try encrypted.write(to: file)
    let executor = EffectExecutor(
      port: CatalogPersistencePort(
        profile: profileRepository, catalog: catalogRepository, credentialsConfigured: true))
    let runtime = RootRuntime(clock: FakeClock(), executor: executor)
    defer { runtime.stop() }
    runtime.send(.bootstrapRequested, from: .root)
    await executor.registry.waitForOperation(try #require(runtime.snapshot.root.bootstrapOperation))
    #expect(runtime.snapshot.root.mode == .safeHold)
    #expect(runtime.snapshot.root.credentialsConfigured)
    try authenticate(runtime)
    runtime.send(.catalogLoadRequested, from: .root)
    await executor.registry.waitForOperation(
      try #require(runtime.snapshot.root.catalogLoadOperation))
    try await importEntry(from: file, passphrase: passphrase, into: runtime, executor: executor)
    #expect(runtime.send(.catalogSelectRequested(entry.id), from: .settings).reply == .accepted)
    #expect(runtime.send(.catalogApplyRequested, from: .settings).reply == .accepted)
    #expect(runtime.send(.saveDraftRequested, from: .settings).reply == .accepted)
    await executor.registry.waitForOperation(try #require(runtime.snapshot.root.saveOperation))
    #expect(runtime.snapshot.root.savedProfile?.startURL == usable.startURL)
    #expect(!runtime.snapshot.root.profileCorrupt)
    #expect(try await profileRepository.load()?.startURL == usable.startURL)
    try expectOriginalProfilePreserved(in: directory)
  }

  @Test func importedEntryRepairsAnUnavailableSavedDisplayAfterAuthentication() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-catalog-safe-hold-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let profileRepository = ProfileRepository(
      fileURL: directory.appendingPathComponent("profile.json"))
    let catalogRepository = CatalogRepository(
      fileURL: directory.appendingPathComponent("catalog.json"))
    let usable = try RuntimeFixture().profile()
    var unavailable = usable
    unavailable.macOutput = .init(displayID: "removed-screen")
    try await profileRepository.save(unavailable)
    let entry = try #require(
      CatalogEntry(id: UUID(), name: "Working display", snapshot: CatalogSnapshot(usable)!))
    let passphrase = "correct horse battery exhibition"
    let encrypted = try await EncryptedCatalogFile.encrypt(entries: [entry], passphrase: passphrase)
    let file = directory.appendingPathComponent("recovery.plinthsettings")
    try encrypted.write(to: file)
    let executor = EffectExecutor(
      port: CatalogPersistencePort(
        profile: profileRepository, catalog: catalogRepository, credentialsConfigured: true))
    let runtime = RootRuntime(clock: FakeClock(), executor: executor)
    defer { runtime.stop() }
    runtime.send(
      .macDisplaysChanged([.init(id: "built-in", name: "Built in", builtIn: true)]),
      from: .platform)
    runtime.send(.bootstrapRequested, from: .root)
    await executor.registry.waitForOperation(try #require(runtime.snapshot.root.bootstrapOperation))
    #expect(runtime.snapshot.root.mode == .safeHold)
    #expect(runtime.snapshot.root.savedProfile == unavailable)
    #expect(runtime.snapshot.root.credentialsConfigured)
    runtime.send(.catalogLoadRequested, from: .root)
    await executor.registry.waitForOperation(
      try #require(runtime.snapshot.root.catalogLoadOperation))

    try authenticate(runtime)
    #expect(runtime.snapshot.root.savedProfile == unavailable)
    try await importEntry(from: file, passphrase: passphrase, into: runtime, executor: executor)
    #expect(runtime.send(.catalogSelectRequested(entry.id), from: .settings).reply == .accepted)
    #expect(runtime.send(.catalogApplyRequested, from: .settings).reply == .accepted)
    #expect(runtime.snapshot.root.savedProfile == unavailable)
    #expect(runtime.send(.saveDraftRequested, from: .settings).reply == .accepted)
    await executor.registry.waitForOperation(try #require(runtime.snapshot.root.saveOperation))
    #expect(runtime.snapshot.root.savedProfile?.macOutput == usable.macOutput)
    #expect(runtime.snapshot.root.activeProfile == nil)
    #expect(runtime.snapshot.root.credentialsConfigured)
    #expect(try await profileRepository.load()?.macOutput == usable.macOutput)
  }

  private func authenticate(_ runtime: RootRuntime) throws {
    #expect(runtime.send(.unlockRequested, from: .platform).reply == .accepted)
    runtime.send(.passcodeEdited("existing-passcode"), from: .unlock)
    #expect(runtime.send(.passcodeSubmitted, from: .unlock).reply == .accepted)
    let verification = try #require(runtime.snapshot.administration.verification)
    runtime.send(.credentialVerified(verification, succeeded: true), from: .credentials)
    #expect(runtime.snapshot.root.mode == .administration)
    #expect(runtime.snapshot.root.administratorSession)
  }

  private func expectOriginalProfilePreserved(in directory: URL) throws {
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    let backups = files.filter { $0.lastPathComponent.hasPrefix(".profile-corrupt-") }
    let backup = try #require(backups.first)
    #expect(backups.count == 1)
    #expect(try Data(contentsOf: backup) == Data("{corrupt".utf8))
    let permissions =
      try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions]
      as? NSNumber
    #expect(permissions?.intValue == 0o600)
  }

  private func importEntry(
    from file: URL, passphrase: String, into runtime: RootRuntime, executor: EffectExecutor
  ) async throws {
    runtime.send(.catalogPassphraseEdited(passphrase), from: .settings)
    #expect(runtime.send(.catalogImportFileRequested(file), from: .settings).reply == .accepted)
    await executor.registry.waitForOperation(
      try #require(runtime.snapshot.root.catalogImportOperation))
    #expect(runtime.snapshot.root.catalogImportPreview?.count == 1)
    #expect(
      runtime.send(.catalogImportConfirmed(replacementIDs: [UUID()]), from: .settings).reply
        == .accepted)
    await executor.registry.waitForOperation(
      try #require(runtime.snapshot.root.catalogSaveOperation))
  }
}
