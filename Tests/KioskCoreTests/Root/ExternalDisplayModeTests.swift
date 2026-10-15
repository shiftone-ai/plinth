import Foundation
import KioskCore
import Testing

struct ExternalDisplayModeTests {
  let fullHD = ExternalDisplayMode(width: 1920, height: 1080)
  let taller = ExternalDisplayMode(width: 1920, height: 1200)

  private func state() throws -> RootState {
    var root = RootState()
    root.mode = .administration
    root.credentialsConfigured = true
    var profile = try fixtureProfile()
    profile.exhibitionDestination = .externalDisplay
    profile.externalDisplayMode = fullHD
    root.savedProfile = profile
    root.mobileDisplays = .init(
      deviceAvailable: true, externalAvailable: true, externalDisplayOnly: true,
      displayModes: [fullHD, taller], currentMode: taller)
    return root
  }

  @Test func selectionSurvivesProfileEncodingAndDraftEditing() throws {
    var draft = ProfileDraft(profile: try fixtureProfile())
    let selected = draft.apply(.externalDisplayMode(fullHD))
    #expect(selected)
    let profile = try #require(draft.validatedProfile)
    let restored = try JSONDecoder().decode(
      KioskProfile.self, from: JSONEncoder().encode(profile))
    #expect(restored.externalDisplayMode == fullHD)
    let cleared = draft.apply(.externalDisplayMode(nil))
    #expect(cleared)
    let automatic = try #require(draft.validatedProfile)
    let json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(automatic)) as? [String: Any])
    #expect(json["externalDisplayMode"] == nil)
    #expect(
      try JSONDecoder().decode(KioskProfile.self, from: JSONEncoder().encode(automatic))
        == automatic)
  }

  @Test func startPassesTheSavedModeInsteadOfTheDisplaysCurrentMode() throws {
    let root = try state()
    let result = try #require(
      handled(RootMediator.reduce(root, envelope(.startExhibitionRequested, source: .settings))))
    #expect(result.reply == .accepted)
    #expect(
      result.effects.map(\.kind) == [
        .applyPresentation(.init(externalDisplayMode: fullHD, usesExternalDisplay: true))
      ])
  }

  @Test(arguments: [false, true])
  func modeMustBeSupportedByTheConnectedDisplay(displayOnly: Bool) throws {
    var root = try state()
    root.mobileDisplays = .init(
      deviceAvailable: true, externalAvailable: true, externalDisplayOnly: displayOnly,
      displayModes: [taller], currentMode: taller)
    #expect(root.canPresent(try #require(root.savedProfile)) == false)
    let result = try #require(
      handled(RootMediator.reduce(root, envelope(.startExhibitionRequested, source: .settings))))
    #expect(result.reply == .rejected(.unsupportedDisplays))
    #expect(result.effects.isEmpty)
  }

  @Test(arguments: [false, true])
  func launchWaitsForTheExternalSceneBeforePresenting(explicitMode: Bool) throws {
    var root = RootState()
    root.mobileDisplays = .init(deviceAvailable: true, externalAvailable: false)
    var profile = try fixtureProfile()
    profile.exhibitionDestination = .externalDisplay
    profile.externalDisplayMode = explicitMode ? fullHD : nil
    let result = try #require(
      handled(
        RootMediator.reduce(
          root,
          envelope(
            .bootstrapped(profile: profile, credentialsConfigured: true, displayCount: 1)))))
    #expect(result.state.mode == .enteringKiosk)
    #expect(result.state.activeProfile == profile)
    #expect(result.state.presentationOperation != nil)
    #expect(result.childControls.isEmpty)
  }

  @Test func geometryAndSceneReplacementCanSettleDuringOwnedPreparation() throws {
    let root = try state()
    let started = try #require(
      handled(RootMediator.reduce(root, envelope(.startExhibitionRequested, source: .settings))))
    let token = try #require(started.state.presentationOperation)
    let settling = try #require(
      handled(
        RootMediator.reduce(
          started.state,
          envelope(
            .mobileDisplaysChanged(
              .init(
                deviceAvailable: true, externalAvailable: false, externalDisplayOnly: true,
                externalConnected: true, displayModes: [fullHD, taller], currentMode: fullHD)),
            source: .platform))))
    #expect(settling.state.mode == .enteringKiosk)
    #expect(settling.state.presentationOperation == token)
    #expect(settling.effects.isEmpty)
    let disconnected = try #require(
      handled(
        RootMediator.reduce(
          settling.state,
          envelope(
            .mobileDisplaysChanged(
              .init(
                deviceAvailable: true, externalAvailable: false, externalConnected: false)),
            source: .platform))))
    #expect(disconnected.state.mode == .enteringKiosk)
    #expect(disconnected.state.presentationOperation == token)
    #expect(disconnected.effects.isEmpty)
    let failed = try #require(
      handled(
        RootMediator.reduce(
          disconnected.state, envelope(.presentationFailed(token), source: .platform))))
    #expect(failed.state.mode == .safeHold)
    #expect(failed.state.presentationOperation == nil)

    let available = try #require(root.mobileDisplays)
    let reconnected = try #require(
      handled(
        RootMediator.reduce(
          failed.state,
          envelope(.mobileDisplaysChanged(available), source: .platform))))
    #expect(reconnected.state.mode == .safeHold)
    #expect(reconnected.effects.isEmpty)

  }
}
