import Foundation
import KioskCore
import Testing

struct ExternalDisplayRotationTests {
  @Test(arguments: ExternalDisplayRotation.allCases)
  func savedRotationReachesExternalPresentation(_ rotation: ExternalDisplayRotation) throws {
    var draft = ProfileDraft(profile: try fixtureProfile())
    let destinationApplied = draft.apply(.exhibitionDestination(.externalDisplay))
    let rotationApplied = draft.apply(.externalDisplayRotation(rotation))
    #expect(destinationApplied)
    #expect(rotationApplied)
    let profile = try #require(draft.validatedProfile)
    let restored = try JSONDecoder().decode(
      KioskProfile.self, from: JSONEncoder().encode(profile))
    #expect(restored.externalDisplayRotation == rotation)

    var root = RootState()
    root.mode = .administration
    root.credentialsConfigured = true
    root.savedProfile = restored
    root.mobileDisplays = .init(
      deviceAvailable: true, externalAvailable: true, externalDisplayOnly: true)
    let started = try #require(
      handled(RootMediator.reduce(root, envelope(.startExhibitionRequested, source: .settings))))
    #expect(started.reply == .accepted)
    #expect(
      started.effects.map(\.kind) == [
        .applyPresentation(
          .init(usesExternalDisplay: true, externalDisplayRotation: rotation))
      ])
  }

  @Test(arguments: [false, true])
  func rotationDoesNotChangeDeviceOrMacOutput(mac: Bool) throws {
    var root = RootState()
    root.mode = .administration
    root.credentialsConfigured = true
    var profile = try fixtureProfile()
    profile.externalDisplayRotation = .clockwise
    root.savedProfile = profile
    if mac {
      root.macDisplays = [.init(id: "portrait-display", name: "Display", builtIn: false)]
    } else {
      root.mobileDisplays = .init(deviceAvailable: true, externalAvailable: true)
    }
    let started = try #require(
      handled(RootMediator.reduce(root, envelope(.startExhibitionRequested, source: .settings))))
    #expect(started.reply == .accepted)
    #expect(
      started.effects.map(\.kind) == [
        .applyPresentation(.init(displayID: mac ? "portrait-display" : nil))
      ])
  }

  @Test func profilesWithoutRotationKeepTheOriginalOrientation() throws {
    let original = try fixtureProfile()
    let encoded = try JSONEncoder().encode(original)
    let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(json["externalDisplayRotation"] == nil)
    let restored = try JSONDecoder().decode(KioskProfile.self, from: encoded)
    #expect(restored.externalDisplayRotation == nil)
    #expect(ProfileDraft(profile: restored).externalDisplayRotation == .standard)
  }
}
