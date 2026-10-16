import Foundation
import KioskCore
import KioskRuntime

/// Real local repositories with a controlled account and CloudKit boundary.
@MainActor
final class CatalogPersistencePort: EffectPort {
  private let profile: ProfileRepository
  private let catalog: CatalogRepository
  var accountIdentifier: String?
  private(set) var publishedEntries: [CatalogEntry] = []
  private(set) var credentialsConfigured: Bool

  init(
    profile: ProfileRepository, catalog: CatalogRepository, accountIdentifier: String? = nil,
    credentialsConfigured: Bool = false
  ) {
    self.profile = profile
    self.catalog = catalog
    self.accountIdentifier = accountIdentifier
    self.credentialsConfigured = credentialsConfigured
  }

  func perform(_ effect: Effect) async -> Event? {
    switch effect.kind {
    case .bootstrap:
      return await bootstrap(effect.token)
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
    case .recoverProfile(let value):
      do {
        try await profile.recover(value)
        return .profileSaved(effect.token, value)
      } catch { return .profileSaveFailed(effect.token) }
    case .checkCatalogAccount, .checkCatalogAccountAfterStopping:
      return .catalogAccountChecked(effect.token, accountIdentifier)
    case .publishCatalogChanges(_, _, let saves, _):
      publishedEntries.append(contentsOf: saves)
      return nil
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

  private func bootstrap(_ token: OperationToken) async -> Event {
    do {
      return try await .bootstrapped(
        profile: profile.load(), credentialsConfigured: credentialsConfigured, displayCount: 1)
    } catch ProfileRepository.Failure.corruptProfile {
      return .bootstrapFailed(
        token, displayCount: 1, credentialsConfigured: credentialsConfigured,
        profileCorrupt: true)
    } catch {
      return .bootstrapFailed(
        token, displayCount: 1, credentialsConfigured: credentialsConfigured,
        profileCorrupt: false)
    }
  }

  func stop() {}
}
