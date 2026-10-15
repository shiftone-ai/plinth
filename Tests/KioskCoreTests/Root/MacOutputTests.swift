import Foundation
import KioskCore
import Testing

struct MacOutputTests {
  private let screens: [DisplayDescriptor] = [
    .init(id: "internal", name: "Built in", builtIn: true),
    .init(id: "external-1", name: "Projector", builtIn: false),
    .init(id: "external-2", name: "Monitor", builtIn: false),
  ]

  @Test func selectionPrefersExternalAndHonorsAnExplicitDisplay() {
    #expect(DisplaySelection.select(.init(), from: screens)?.id == "external-1")
    #expect(
      DisplaySelection.select(.init(displayID: "external-2"), from: screens)?.id == "external-2")
    #expect(DisplaySelection.select(.init(displayID: "missing"), from: screens) == nil)
    #expect(DisplaySelection.select(.init(), from: Array(screens.prefix(1)))?.id == "internal")
    #expect(DisplaySelection.select(.init(), from: []) == nil)
    #expect(
      DisplaySelection.select(.init(mode: .projectionWindow, displayID: "missing"), from: screens)?
        .id == "internal")
  }

  @Test func startPassesTheSelectedOutputToPresentationAndRejectsMissingDisplay() throws {
    var root = RootState()
    root.mode = .administration
    root.credentialsConfigured = true
    root.macDisplays = screens
    var profile = try fixtureProfile()
    profile.macOutput = .init(displayID: "external-2")
    root.savedProfile = profile
    let started = try #require(
      handled(
        RootMediator.reduce(
          root,
          envelope(.startExhibitionRequested, source: .settings))))
    #expect(started.state.mode == .enteringKiosk)
    #expect(started.effects.map(\.kind) == [.applyPresentation(.init(displayID: "external-2"))])
    root.macDisplays = Array(screens.prefix(2))
    let rejected = try #require(
      handled(
        RootMediator.reduce(
          root,
          envelope(.startExhibitionRequested, source: .settings))))
    #expect(rejected.reply == .rejected(.unsupportedDisplays))
    #expect(rejected.effects.isEmpty)
    root.savedProfile?.macOutput?.mode = .projectionWindow
    let window = try #require(
      handled(
        RootMediator.reduce(
          root,
          envelope(.startExhibitionRequested, source: .settings))))
    #expect(
      window.effects.map(\.kind) == [
        .applyPresentation(.init(mode: .projectionWindow, displayID: "internal"))
      ])
  }

  @Test func legacyProfileDecodesWithoutMacOutputAndExplicitSelectionRoundTrips() throws {
    var profile = try fixtureProfile()
    let encoder = JSONEncoder()
    let legacy = try encoder.encode(profile)
    #expect(try JSONDecoder().decode(KioskProfile.self, from: legacy).macOutput == nil)
    profile.macOutput = .init(displayID: "external-2")
    #expect(try JSONDecoder().decode(KioskProfile.self, from: encoder.encode(profile)) == profile)
  }

  @Test(arguments: [AppMode.enteringKiosk, .exhibiting, .unlocking])
  func unchangedDisplayNotificationPreservesPresentation(mode: AppMode) throws {
    var root = RootState()
    root.mode = mode
    root.macDisplays = screens
    let unchanged = try #require(
      handled(RootMediator.reduce(root, envelope(.macDisplaysChanged(screens), source: .platform))))
    #expect(unchanged.state == root)
    #expect(unchanged.effects.isEmpty)
    #expect(unchanged.childControls.isEmpty)
  }

  @Test func changedResolutionStillStopsPresentation() throws {
    let display = DisplayDescriptor(
      id: "external", name: "Projector", builtIn: false,
      frame: .init(x: 0, y: 0, width: 1920, height: 1080))
    var root = RootState()
    root.mode = .exhibiting
    root.macDisplays = [display]
    let resized = DisplayDescriptor(
      id: display.id, name: display.name, builtIn: display.builtIn,
      frame: .init(x: 0, y: 0, width: 1280, height: 720))
    let changed = try #require(
      handled(
        RootMediator.reduce(root, envelope(.macDisplaysChanged([resized]), source: .platform))))
    #expect(changed.state.mode == .safeHold)
    #expect(changed.state.macDisplays == [resized])
    #expect(changed.childControls.contains(.init(.exhibition, .stopExhibition)))
  }

  @Test(arguments: [false, true])
  func stoppedExhibitionCanAuthenticateDuringDisplayReconnection(countOnly: Bool) throws {
    var root = RootState()
    root.mode = .safeHold
    root.macDisplays = Array(screens.prefix(1))
    let unlocking = try #require(
      handled(RootMediator.reduce(root, envelope(.unlockRequested, source: .platform))))
    let changed = try #require(
      handled(
        RootMediator.reduce(
          unlocking.state,
          envelope(
            countOnly ? .displayCountChanged(screens.count) : .macDisplaysChanged(screens),
            source: .platform, id: 2))))
    #expect(changed.state.mode == .unlocking)
    #expect(changed.state.unlockID == unlocking.state.unlockID)
    if !countOnly { #expect(changed.state.macDisplays == screens) }
    #expect(changed.state.displayCount == screens.count)
    #expect(changed.effects.isEmpty)
    #expect(changed.childControls.isEmpty)
  }
}
