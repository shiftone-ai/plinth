import KioskCore
import KioskLocalization
import KioskPresentation
import SwiftUI

struct SettingsWebManagementSection: View {
  let props: SettingsProps
  let send: (SettingsIntent) -> Void
  @Environment(\.locale) private var locale

  var body: some View {
    Section(L10n.string("Web management", locale: locale)) {
      Toggle(
        L10n.string("Allow web management", locale: locale),
        isOn: Binding(
          get: { props.draft.profile.webAdministrationEnabled },
          set: { send(.edit(.webAdministrationEnabled($0))) }
        )
      )
      .accessibilityIdentifier("web-management-enabled")
      .disabled(!props.credentialsConfigured)
      if props.draft.profile.webAdministrationEnabled {
        Label(
          L10n.string("Use a separate network. Web management uses HTTP.", locale: locale),
          systemImage: "exclamationmark.shield"
        )
        .font(.caption).foregroundStyle(.secondary)
        if let url = props.webServerURL {
          Text(url).textSelection(.enabled).accessibilityIdentifier("web-management-url")
          WebManagementQRCode(url: url)
        }
        if let failure = props.webServerFailure {
          Label(
            failure == .portInUse
              ? L10n.string("Web management port is in use", locale: locale)
              : L10n.string("Web management is unavailable", locale: locale),
            systemImage: "exclamationmark.triangle"
          )
          .foregroundStyle(.red)
          .accessibilityIdentifier("web-management-error")
        }
      }
    }
  }

}
