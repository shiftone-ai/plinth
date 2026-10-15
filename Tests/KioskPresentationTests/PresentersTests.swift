import KioskCore
import KioskPresentation
import Testing

struct PresentersTests {
  @Test func automaticAllowlistAddressTracksTheDraftWithoutAddingEditableRules() {
    var administration = AdministrationState()
    administration.draft = ProfileDraft(
      profile: KioskProfile(
        startURL: "https://display.example.com/exhibition", navigation: .init(rules: [])))
    var root = RootState()
    root.mode = .administration
    let first = Presenters.settings(root, administration)
    #expect(first.automaticallyAllowedAddress == "https://display.example.com")
    #expect(first.draft.rules.isEmpty)
    #expect(first.canSave)
    _ = administration.draft?.apply(.startURL("https://next.example.com:8443/other"))
    #expect(
      Presenters.settings(root, administration).automaticallyAllowedAddress
        == "https://next.example.com:8443")
    _ = administration.draft?.apply(.navigationMode(.denylist))
    #expect(Presenters.settings(root, administration).automaticallyAllowedAddress == nil)
  }

  @Test(arguments: [AppMode.safeHold, .administration, .exhibiting, .unlocking], [false, true])
  func pointerSetupHelpIsLimitedToTheRelevantStoppedExhibition(
    mode: AppMode, failed: Bool
  ) {
    var root = RootState()
    root.mode = mode
    root.pointerCaptureFailed = failed
    #expect(Presenters.root(root).showsPointerSetupHelp == (mode == .safeHold && failed))
  }

  @Test(arguments: [false, true], [false, true])
  func windowPreparationIsHiddenForConnectedExternalOutput(
    externalAvailable: Bool, displayOnly: Bool
  ) {
    var root = RootState()
    root.mode = .administration
    root.mobileDisplays = .init(
      deviceAvailable: true, externalAvailable: externalAvailable,
      supportsExhibitionWindow: true, externalDisplayOnly: displayOnly)
    let props = Presenters.settings(root, AdministrationState())
    let expected = !externalAvailable && !displayOnly
    #expect(props.showsExhibitionWindowPreparation == expected)
    #expect(props.canPrepareExternalScene == expected)
  }

  @Test func incompleteDraftIsPreservedAndCannotBeSaved() throws {
    let origin = try #require(Origin(urlString: "https://example.com"))
    let profile = KioskProfile(
      startURL: "https://example.com", navigation: .init(rules: [.init(id: 1, origin: origin)]))
    var root = RootState()
    root.mode = .administration
    root.credentialsConfigured = true
    root.savedProfile = profile
    var administration = AdministrationState()
    administration.savedProfile = profile
    administration.draft = ProfileDraft(profile: profile)
    let saved = Presenters.settings(root, administration)
    #expect(saved.canStart)
    #expect(saved.canSave == false)
    administration.draft?.idleTimeoutText = ""
    let incomplete = Presenters.settings(root, administration)
    #expect(incomplete.idleTimeout == "")
    #expect(incomplete.canStart == false)
    #expect(incomplete.canSave == false)
  }

  @Test func unlockingStopsWebInputWithoutChangingSurfaceIdentity() {
    var root = RootState()
    root.mode = .unlocking
    var exhibition = ExhibitionState()
    exhibition.phase = .ready
    exhibition.generation = 3
    let value = Presenters.web(root, exhibition)
    #expect(value.acceptsInput == false)
    #expect(value.generation == 3)
    #expect(Presenters.root(root).showsUnlock)
  }
}
