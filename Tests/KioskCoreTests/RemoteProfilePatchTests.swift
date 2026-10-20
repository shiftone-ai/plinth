import Foundation
import KioskCore
import Testing

struct RemoteProfilePatchTests {
  @Test func outputMustStillExistOnTargetWhenRemoteSaveIsApplied() throws {
    let origin = try #require(Origin(urlString: "https://example.com"))
    var profile = KioskProfile(
      startURL: "https://example.com/home",
      navigation: .init(rules: [.init(id: 1, origin: origin)]))
    var root = RootState()
    root.macDisplays = [DisplayDescriptor(id: "display-1", name: "Main", builtIn: true)]
    profile.macOutput = .init(mode: .fixedFullscreen, displayID: "display-1")
    #expect(root.remoteOutputAvailable(profile))
    root.macDisplays = [DisplayDescriptor(id: "display-2", name: "Second", builtIn: false)]
    #expect(!root.remoteOutputAvailable(profile))

    profile.macOutput = .init(mode: .projectionWindow, displayID: "display-1")
    #expect(root.remoteOutputAvailable(profile))
    profile.macOutput = .init(mode: .fixedFullscreen, displayID: "display-1")

    profile.macOutput = nil
    profile.exhibitionDestination = .externalDisplay
    profile.externalDisplayMode = .init(width: 1920, height: 1080)
    root.macDisplays = nil
    root.mobileDisplays = MobileDisplayAvailability(
      deviceAvailable: true,
      externalAvailable: true, externalDisplayOnly: true,
      displayModes: [.init(width: 1920, height: 1080)])
    #expect(root.remoteOutputAvailable(profile))
    root.mobileDisplays = MobileDisplayAvailability(
      deviceAvailable: true,
      externalAvailable: false, externalDisplayOnly: false,
      displayModes: [])
    #expect(!root.remoteOutputAvailable(profile))
  }

  @Test func editorSendsOnlyChangedFieldsAndTargetRetainsUneditedSettings() throws {
    let origin = try #require(Origin(urlString: "https://example.com"))
    let second = try #require(Origin(urlString: "https://museum.example"))
    let original = KioskProfile(
      startURL: "https://example.com/home",
      navigation: .init(rules: [.init(id: 1, origin: origin)]),
      recovery: .init(maximumAttempts: 5, delay: 3),
      macOutput: .init(mode: .fixedFullscreen, displayID: "display-1"),
      webAdministrationEnabled: true)
    var editor = RemoteEditingState(targetID: UUID(), baseProfile: original)
    _ = editor.draft.apply(.navigationMode(.denylist))
    editor.draft.rules = [.init(id: 2, address: "museum.example")]
    _ = editor.draft.apply(.allowsHTTP(true))
    _ = editor.draft.apply(.allowsScroll(true))
    _ = editor.draft.apply(.allowsDrag(true))
    _ = editor.draft.apply(.idleTimeoutText("45"))
    _ = editor.draft.apply(.resetMode(.retainWebsiteData))
    let patch = editor.patch
    #expect(patch.baseRevision == original.revision)
    #expect(patch.edits.count == 7)
    let saved = try #require(patch.apply(to: original))
    #expect(saved.revision == original.revision + 1)
    #expect(saved.navigation.mode == .denylist)
    #expect(saved.navigation.rules == [.init(id: 2, origin: second)])
    #expect(saved.navigation.allowsHTTP)
    #expect(saved.interaction.allowsScroll && saved.interaction.allowsDrag)
    #expect(saved.idleTimeout == 45)
    #expect(saved.resetMode == .retainWebsiteData)
    #expect(saved.startURL == original.startURL)
    #expect(saved.recovery == original.recovery)
    #expect(saved.macOutput == original.macOutput)
    #expect(saved.webAdministrationEnabled == original.webAdministrationEnabled)
  }
}
