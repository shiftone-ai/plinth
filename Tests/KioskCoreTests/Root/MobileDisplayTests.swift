import Foundation
import KioskCore
import Testing

struct MobileDisplayTests {
  @Test(arguments: [false, true], [false, true])
  func connectedExternalOutputDoesNotCreateAnotherWindow(
    externalAvailable: Bool, displayOnly: Bool
  ) throws {
    var root = RootState()
    root.mode = .administration
    root.mobileDisplays = .init(
      deviceAvailable: true, externalAvailable: externalAvailable,
      supportsExhibitionWindow: true, externalDisplayOnly: displayOnly)
    let result = try #require(
      handled(
        RootMediator.reduce(
          root, envelope(.prepareExternalSceneRequested, source: .settings))))
    if externalAvailable || displayOnly {
      #expect(result.reply == .rejected(.invalidState))
      #expect(result.effects.isEmpty)
      #expect(result.state.externalSceneOperation == nil)
    } else {
      #expect(result.reply == .accepted)
      #expect(result.effects.map(\.kind) == [.prepareExternalScene])
    }
  }

  @Test func displayOnlyOutputDoesNotRequireMultipleApplicationWindows() throws {
    var root = RootState()
    root.mode = .administration
    root.credentialsConfigured = true
    var profile = try fixtureProfile()
    profile.exhibitionDestination = .externalDisplay
    root.savedProfile = profile
    root.mobileDisplays = .init(
      deviceAvailable: true, externalAvailable: true,
      supportsExhibitionWindow: false, externalDisplayOnly: true)
    #expect(root.canPresent(profile))
    let started = try #require(
      handled(
        RootMediator.reduce(
          root,
          envelope(.startExhibitionRequested, source: .settings))))
    #expect(started.state.mode == .enteringKiosk)
    #expect(started.effects.map(\.kind) == [.applyPresentation(.init(usesExternalDisplay: true))])
    let windowRequest = try #require(
      handled(
        RootMediator.reduce(
          root,
          envelope(.prepareExternalSceneRequested, source: .settings))))
    #expect(windowRequest.reply == .rejected(.invalidState))
    #expect(windowRequest.effects.isEmpty)
  }

  @Test func scenePreparationRequiresMatchingCompletionAndCanRetryFailure() throws {
    var root = RootState()
    root.mode = .administration
    root.mobileDisplays = .init(deviceAvailable: true, externalAvailable: false)
    let requested = try #require(
      handled(
        RootMediator.reduce(
          root,
          envelope(.prepareExternalSceneRequested, source: .settings))))
    let token = try #require(requested.state.externalSceneOperation)
    let stale = OperationToken(owner: .root, operationID: token.operationID + 1)
    #expect(
      handled(
        RootMediator.reduce(
          requested.state,
          envelope(.externalScenePrepared(stale), source: .platform)))?.reply
        == .rejected(.staleOperation))
    let failed = try #require(
      handled(
        RootMediator.reduce(
          requested.state,
          envelope(.externalScenePreparationFailed(token), source: .platform))))
    #expect(failed.state.externalSceneOperation == nil)
    #expect(failed.state.externalScenePreparationFailed)
    #expect(failed.state.mobileDisplays?.externalAvailable == false)
    let retried = try #require(
      handled(
        RootMediator.reduce(
          failed.state,
          envelope(.prepareExternalSceneRequested, source: .settings, id: 3))))
    #expect(!retried.state.externalScenePreparationFailed)
    let retryToken = try #require(retried.state.externalSceneOperation)
    let terminated = try #require(
      handled(
        RootMediator.reduce(
          retried.state,
          envelope(.terminateRequested, source: .platform, id: 4))))
    #expect(terminated.state.externalSceneOperation == nil)
    #expect(terminated.effects.map(\.kind) == [.cancelOperation(retryToken)])
  }
  @Test func deviceExhibitionDoesNotRequireAnExternalDisplay() throws {
    var root = RootState()
    root.mobileDisplays = .init(deviceAvailable: true, externalAvailable: false)
    root.displayCount = 2
    #expect(root.canPresent(try fixtureProfile()))
    var external = try fixtureProfile()
    external.exhibitionDestination = .externalDisplay
    #expect(!root.canPresent(external))
    root.mobileDisplays = .init(deviceAvailable: true, externalAvailable: true)
    #expect(root.canPresent(external))
    root.mobileDisplays = nil
    #expect(!root.canPresent(external))
  }

  @Test func lostExternalSceneStopsExhibitionWithoutMovingToDevice() throws {
    var root = RootState()
    var profile = try fixtureProfile()
    profile.exhibitionDestination = .externalDisplay
    root.activeProfile = profile
    root.mobileDisplays = .init(deviceAvailable: true, externalAvailable: true)
    root.mode = .exhibiting
    let result = try #require(
      handled(
        RootMediator.reduce(
          root,
          envelope(
            .mobileDisplaysChanged(.init(deviceAvailable: true, externalAvailable: false)),
            source: .platform))))
    #expect(result.state.mode == .safeHold)
    #expect(result.state.activeProfile?.exhibitionDestination == .externalDisplay)
    #expect(
      result.childControls == [
        .init(.administration, .cancelAuthentication), .init(.exhibition, .stopExhibition),
      ])
    #expect(result.effects.isEmpty)
  }

  @Test(arguments: [false, true])
  func stoppedExhibitionCanAuthenticateWhileExternalSceneChanges(available: Bool) throws {
    var root = RootState()
    var profile = try fixtureProfile()
    profile.exhibitionDestination = .externalDisplay
    root.activeProfile = profile
    root.mode = .safeHold
    root.mobileDisplays = .init(
      deviceAvailable: true, externalAvailable: false,
      supportsExhibitionWindow: false, externalDisplayOnly: false)
    let unlocking = try #require(
      handled(RootMediator.reduce(root, envelope(.unlockRequested, source: .platform))))
    let changed = try #require(
      handled(
        RootMediator.reduce(
          unlocking.state,
          envelope(
            .mobileDisplaysChanged(
              .init(
                deviceAvailable: true, externalAvailable: available,
                supportsExhibitionWindow: false, externalDisplayOnly: available)),
            source: .platform, id: 2))))
    #expect(changed.state.mode == .unlocking)
    #expect(changed.state.unlockID == unlocking.state.unlockID)
    #expect(changed.state.unlockTimeoutOperation == unlocking.state.unlockTimeoutOperation)
    #expect(changed.state.mobileDisplays?.externalAvailable == available)
    #expect(changed.effects.isEmpty)
    #expect(changed.childControls.isEmpty)
    let unlockID = try #require(unlocking.state.unlockID)
    let authenticated = try #require(
      handled(
        RootMediator.reduce(
          changed.state,
          envelope(
            .authenticationVerified(unlockID: unlockID),
            source: .administration, id: 3))))
    #expect(authenticated.state.mode == .leavingKiosk)
    #expect(authenticated.state.administratorSession)
  }

  @Test func lostExternalSceneDuringLiveUnlockStillCancelsAuthentication() throws {
    var root = RootState()
    var profile = try fixtureProfile()
    profile.exhibitionDestination = .externalDisplay
    root.activeProfile = profile
    root.mode = .exhibiting
    root.mobileDisplays = .init(
      deviceAvailable: true, externalAvailable: true, externalDisplayOnly: true)
    let unlocking = try #require(
      handled(RootMediator.reduce(root, envelope(.unlockRequested, source: .platform))))
    let timeout = try #require(unlocking.state.unlockTimeoutOperation)
    let changed = try #require(
      handled(
        RootMediator.reduce(
          unlocking.state,
          envelope(
            .mobileDisplaysChanged(.init(deviceAvailable: true, externalAvailable: false)),
            source: .platform, id: 2))))
    #expect(changed.state.mode == .safeHold)
    #expect(changed.state.unlockID == nil)
    #expect(changed.effects.map(\.kind) == [.cancelOperation(timeout)])
    #expect(changed.childControls.contains(.init(.administration, .cancelAuthentication)))
    #expect(changed.childControls.contains(.init(.exhibition, .stopExhibition)))
  }

  @Test func externalWindowPreparationIsOwnedAndAvailableOnlyToAdministration() throws {
    var root = RootState()
    root.mode = .administration
    root.mobileDisplays = .init(deviceAvailable: true, externalAvailable: false)
    let request = envelope(.prepareExternalSceneRequested, source: .settings)
    let result = try #require(handled(RootMediator.reduce(root, request)))
    let operation = try #require(result.state.externalSceneOperation)
    #expect(result.effects == [.init(operation, .prepareExternalScene)])
    #expect(result.reply == .accepted)
    let repeated = try #require(handled(RootMediator.reduce(result.state, request)))
    #expect(repeated.reply == .rejected(.invalidState))
    root.mode = .exhibiting
    #expect(handled(RootMediator.reduce(root, request))?.reply == .rejected(.invalidState))
  }

  @Test func profilesWithoutDestinationStillDecodeAndSaveAsDevice() throws {
    let profile = try fixtureProfile()
    let encoder = JSONEncoder()
    let value = try #require(
      JSONSerialization.jsonObject(with: encoder.encode(profile)) as? [String: Any])
    #expect(value["exhibitionDestination"] == nil)
    let decoded = try JSONDecoder().decode(KioskProfile.self, from: encoder.encode(profile))
    #expect(decoded.exhibitionDestination == nil)
    #expect(decoded == profile)
  }
}
