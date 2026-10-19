import Foundation

extension RootMediator {
  static func renameCatalog(
    _ state: RootState, index: Int, name: String, token: OperationToken
  ) -> Mediation<RootState> {
    guard let version = ProfileRevision.next(after: state.catalog.entries[index].version)
    else { return .reject(state, .invalidProfile) }
    var document = state.catalog
    document.entries[index].name = name
    document.entries[index].version = version
    return commitCatalog(state, document, token: token)
  }

  static func updateCatalog(
    _ state: RootState, index: Int, snapshot: CatalogSnapshot, token: OperationToken
  ) -> Mediation<RootState> {
    guard let version = ProfileRevision.next(after: state.catalog.entries[index].version)
    else { return .reject(state, .invalidProfile) }
    var document = state.catalog
    document.entries[index].snapshot = snapshot
    document.entries[index].version = version
    return commitCatalog(state, document, token: token)
  }
}
