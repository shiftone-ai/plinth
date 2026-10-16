import KioskCore
import KioskLocalization
import KioskPresentation
import SwiftUI

struct SettingsInformationSection: View {
  @Environment(\.locale) private var locale
  @State private var showingLicenses = false
  let send: (SettingsIntent) -> Void

  var body: some View {
    Section(L10n.string("About", locale: locale)) {
      Button {
        send(.openInformationPage(.privacy, locale: locale.identifier))
      } label: {
        Label(L10n.string("Privacy Policy", locale: locale), systemImage: "hand.raised")
      }
      .accessibilityIdentifier("privacy-policy")
      Button {
        send(.openInformationPage(.support, locale: locale.identifier))
      } label: {
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

}
