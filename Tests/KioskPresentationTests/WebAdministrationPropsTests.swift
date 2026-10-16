import Foundation
import KioskCore
import KioskPresentation
import Testing

struct WebAdministrationPropsTests {
  @Test func editorDraftAndValidationAreEncodedWithoutPasscode() throws {
    let origin = try #require(Origin(urlString: "https://example.com"))
    let profile = KioskProfile(
      startURL: "https://example.com/home",
      navigation: .init(rules: [.init(id: 1, origin: origin)]))
    var root = RootState()
    root.mode = .administration
    root.savedProfile = profile
    var administration = AdministrationState()
    administration.passcode = "private-value"
    administration.draft = ProfileDraft(profile: profile)
    administration.draft?.profile.startURL = "not-a-url"

    let props = Presenters.webAdministration(root, administration)
    let text = try #require(String(data: JSONEncoder().encode(props), encoding: .utf8))
    #expect(text.contains("https:\\/\\/example.com\\/home"))
    #expect(!text.contains("private-value"))
    #expect(text.contains("not-a-url"))
    #expect(
      props.validationMessages == Presenters.settings(root, administration).validationMessages)
  }

  @Test func outputChoicesUseTheSameDisplaySnapshotAsNativeSettings() throws {
    var root = RootState()
    root.mode = .administration
    root.macDisplays = [
      DisplayDescriptor(
        id: "screen-1", name: "Current display",
        builtIn: true)
    ]
    let administration = AdministrationState()
    let web = Presenters.webAdministration(root, administration)
    let native = Presenters.settings(root, administration)
    #expect(web.macDisplays == native.macDisplays)

    root.macDisplays = nil
    root.mobileDisplays = .init(
      deviceAvailable: true, externalAvailable: false,
      supportsExhibitionWindow: true, supportsExternalDisplay: true,
      displayModes: [.init(width: 1920, height: 1080)])
    let mobileWeb = Presenters.webAdministration(root, administration)
    let mobileNative = Presenters.settings(root, administration)
    #expect(mobileWeb.supportsExternalDisplay == mobileNative.supportsExternalDisplay)
    #expect(mobileWeb.externalDisplayModes == mobileNative.externalDisplayModes)
    #expect(
      mobileWeb.showsExhibitionWindowPreparation
        == mobileNative.showsExhibitionWindowPreparation)
  }
}
