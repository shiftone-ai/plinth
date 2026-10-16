import KioskLocalization
import SwiftUI

struct SettingsLanguageSection: View {
  let language: InterfaceLanguage
  let select: (InterfaceLanguage) -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    Section {
      Picker(
        L10n.string("Display language", locale: locale),
        selection: Binding(get: { language }, set: { select($0) })
      ) {
        ForEach(InterfaceLanguage.allCases) { option in
          Text(
            option == .system
              ? L10n.string("Use system language", locale: locale) : option.nativeName
          ).tag(option).accessibilityIdentifier("interface-language-\(option.rawValue)")
        }
      }
      .accessibilityIdentifier("interface-language")
    }
  }
}
