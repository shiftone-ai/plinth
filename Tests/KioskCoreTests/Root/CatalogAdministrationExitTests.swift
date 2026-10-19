import Foundation
import KioskCore
import Testing

struct CatalogAdministrationExitTests {
  @Test func startingExhibitionDiscardsCatalogConfirmations() throws {
    var state = RootState()
    state.mode = .administration
    state.savedProfile = try fixtureProfile()
    state.credentialsConfigured = true
    let id = UUID()
    state.catalogRenameCandidate = .init(id: id, name: "Earlier edit")
    state.catalogUpdateCandidateID = id
    state.catalogRemovalCandidateID = id
    state.catalogShareCandidateID = id
    state.catalogSyncConsentPending = true
    state.catalogRecoveryPending = true

    let started = try #require(
      handled(RootMediator.reduce(state, envelope(.startExhibitionRequested, source: .settings))))
    #expect(started.state.mode == .enteringKiosk)
    #expect(started.state.catalogRenameCandidate == nil)
    #expect(started.state.catalogUpdateCandidateID == nil)
    #expect(started.state.catalogRemovalCandidateID == nil)
    #expect(started.state.catalogShareCandidateID == nil)
    #expect(!started.state.catalogSyncConsentPending)
    #expect(!started.state.catalogRecoveryPending)
  }

  @Test(arguments: [false, true])
  func closingTheLastMobileSceneDiscardsCatalogConfirmations(recovery: Bool) throws {
    var state = RootState()
    state.mode = .administration
    state.credentialsConfigured = true
    state.mobileDisplays = .init(deviceAvailable: true, externalAvailable: false)
    let information = OperationToken(owner: .root, ownerEpoch: state.epoch, operationID: 42)
    state.informationPageOperation = information
    state.licenseSheetPresented = true
    let id = UUID()
    state.catalogRenameCandidate = .init(id: id, name: "Earlier edit")
    state.catalogSyncConsentPending = !recovery
    state.catalogRecoveryPending = recovery
    if recovery {
      state.catalogCorrupt = true
      state.catalogLoadFailed = true
    }

    let disconnected = try #require(
      handled(
        RootMediator.reduce(
          state, envelope(.mobileLastSceneDisconnected, source: .platform))))
    #expect(disconnected.state.mode == .safeHold)
    #expect(disconnected.state.catalogRenameCandidate == nil)
    #expect(!disconnected.state.catalogSyncConsentPending)
    #expect(!disconnected.state.catalogRecoveryPending)
    #expect(!disconnected.state.licenseSheetPresented)
    #expect(disconnected.state.informationPageOperation == nil)
    #expect(disconnected.effects.map(\.kind).contains(.cancelOperation(information)))
  }
}
