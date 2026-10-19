import Foundation
import KioskCore
import Testing

@testable import KioskRuntime

struct CatalogZoneRecoveryTests {
  @Test func deletedZoneAcknowledgesBufferedConflictedDeletion() {
    let deletionID = UUID()
    let unrelatedConflictID = UUID()
    var disk = CatalogCloudSync.DiskState(
      accountIdentifier: "account-a", engineState: nil, entries: [:],
      serverEntries: [:], serverDeletions: [], recordSystemFields: [:],
      conflicts: [deletionID, unrelatedConflictID])
    let buffered = [
      deletionID: CatalogPendingDeletion(
        id: deletionID, accountIdentifier: "account-a", baseVersion: 2)
    ]

    let acknowledged = CatalogCloudSync.reconcileDeletedZone(
      pendingEngineDeletions: [], bufferedDeletions: buffered, disk: &disk)

    #expect(acknowledged == [deletionID])
    #expect(!disk.conflicts.contains(deletionID))
    #expect(disk.conflicts.contains(unrelatedConflictID))
  }
}
