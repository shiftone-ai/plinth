import Foundation
import KioskCore
import Testing

struct CatalogAdministrationExitTests {
  @Test func passcodeFinishingAfterLastSceneClosedRequiresAuthentication() throws {
    var state = RootState()
    state.mode = .administration
    state.mobileDisplays = .init(deviceAvailable: true, externalAvailable: false)
    let credential = OperationToken(owner: .root, ownerEpoch: state.epoch, operationID: 41)
    state.credentialOperation = credential
    let disconnected = try #require(
      handled(
        RootMediator.reduce(
          state, envelope(.mobileLastSceneDisconnected, source: .platform))))
    #expect(disconnected.state.mode == .administration)
    let configured = try #require(
      handled(
        RootMediator.reduce(
          disconnected.state,
          envelope(.credentialConfigured(credential, succeeded: true), source: .credentials))))
    #expect(configured.state.credentialsConfigured)
    #expect(configured.state.mode == .safeHold)
    #expect(!configured.state.administratorSession)
  }

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

  @Test(arguments: [false, true], [false, true])
  func closingTheLastMobileSceneDiscardsCatalogConfirmations(
    recovery: Bool, credentialsConfigured: Bool
  ) throws {
    var state = RootState()
    state.mode = .administration
    state.credentialsConfigured = credentialsConfigured
    state.mobileDisplays = .init(deviceAvailable: true, externalAvailable: false)
    let information = OperationToken(owner: .root, ownerEpoch: state.epoch, operationID: 42)
    let file = OperationToken(owner: .root, ownerEpoch: state.epoch, operationID: 43)
    state.informationPageOperation = information
    state.licenseSheetPresented = true
    let id = UUID()
    state.catalogRenameCandidate = .init(id: id, name: "Earlier edit")
    state.catalogExportOperation = file
    state.catalogExportCandidateIDs = [id]
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
    #expect(disconnected.state.mode == (credentialsConfigured ? .safeHold : .administration))
    #expect(disconnected.state.catalogRenameCandidate == nil)
    #expect(!disconnected.state.catalogSyncConsentPending)
    #expect(!disconnected.state.catalogRecoveryPending)
    #expect(!disconnected.state.licenseSheetPresented)
    #expect(disconnected.state.informationPageOperation == nil)
    #expect(disconnected.state.catalogExportOperation == nil)
    #expect(disconnected.state.catalogExportCandidateIDs == nil)
    #expect(disconnected.effects.map(\.kind).contains(.cancelOperation(information)))
    #expect(disconnected.effects.map(\.kind).contains(.cancelOperation(file)))
  }
}
