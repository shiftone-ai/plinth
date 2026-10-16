import KioskLocalization
import SwiftUI

struct SettingsInformationSection: View {
  @Environment(\.locale) private var locale
  @State private var showingLicenses = false

  var body: some View {
    Section(L10n.string("About", locale: locale)) {
      Link(destination: pageURL("privacy")) {
        Label(L10n.string("Privacy Policy", locale: locale), systemImage: "hand.raised")
      }
      .accessibilityIdentifier("privacy-policy")
      Link(destination: pageURL("support")) {
        Label(L10n.string("Support", locale: locale), systemImage: "questionmark.circle")
      }
      .accessibilityIdentifier("support")
      Button {
        showingLicenses = true
      } label: {
        Label(L10n.string("Licenses", locale: locale), systemImage: "doc.text")
      }
      .accessibilityIdentifier("licenses")
      .sheet(isPresented: $showingLicenses) { LicensesView() }
    }
  }

  private func pageURL(_ page: String) -> URL {
    let language: String
    switch locale.language.languageCode?.identifier {
    case "ja": language = "ja"
    case "ko": language = "ko"
    case "zh": language = "zh-Hans"
    default: language = "en"
    }
    return URL(string: "https://shiftone-ai.github.io/plinth/\(language)/\(page).html")!
  }
}
