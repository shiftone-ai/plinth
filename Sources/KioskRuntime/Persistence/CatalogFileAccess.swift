import Foundation

nonisolated enum CatalogFileAccess {
  @concurrent static func read(_ url: URL) async throws -> Data {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let coordinator = NSFileCoordinator(filePresenter: nil)
    var coordinationError: NSError?
    var result: Result<Data, Error>?
    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) {
      accessURL in
      result = Result {
        let size = try accessURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= EncryptedCatalogFile.maximumFileBytes else {
          throw EncryptedCatalogFile.Failure.tooLarge
        }
        let handle = try FileHandle(forReadingFrom: accessURL)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: EncryptedCatalogFile.maximumFileBytes + 1) ?? Data()
        guard data.count <= EncryptedCatalogFile.maximumFileBytes else {
          throw EncryptedCatalogFile.Failure.tooLarge
        }
        return data
      }
    }
    if let coordinationError { throw coordinationError }
    guard let result else { throw CocoaError(.fileReadUnknown) }
    return try result.get()
  }
}
