import Foundation

extension RootMediator {
  static func hasQueuedCloudFacts(_ state: RootState) -> Bool {
    !state.queuedCatalogCloudChanges.isEmpty
      || !state.queuedCatalogAcknowledgements.isEmpty
      || !state.queuedCatalogDeletionAcknowledgements.isEmpty
  }

  static func reconcileQueuedCloudFacts(
    _ state: RootState, into catalog: SettingsCatalog
  ) -> SettingsCatalog {
    var followup = catalog
    for index in followup.entries.indices {
      let entry = followup.entries[index]
      if entry.accountIdentifier == catalog.accountIdentifier,
        let version = state.queuedCatalogAcknowledgements[entry.id],
        entry.version == version
      {
        followup.entries[index].syncedVersion = version
        followup.entries[index].resolvedConflictVersion = nil
      }
    }
    followup.pendingDeletions.removeAll {
      $0.accountIdentifier == catalog.accountIdentifier
        && state.queuedCatalogDeletionAcknowledgements.contains($0.id)
    }
    if !state.queuedCatalogCloudChanges.isEmpty,
      let accountID = catalog.accountIdentifier,
      let received = receiveCloudChanges(
        state.queuedCatalogCloudChanges, into: followup, accountID: accountID)
    {
      followup = received
    }
    return followup
  }
}
