#if os(iOS)
  import Foundation
  import KioskCore
  import KioskLocalization
  import KioskRuntime

  @MainActor
  enum MobileBiometricComposition {
    static func make(
      service: String, fixtureService: String?, language: LanguagePreference
    ) -> any BiometricCredentialPort {
      #if DEBUG
        if fixtureService != nil, let port = MobileBiometricTestPort.make(service: service) {
          return port
        }
      #endif
      return BiometricCredentialAdapter(
        service: service,
        enableReason: { [language] in
          L10n.string("Enable administrator unlock with biometrics", locale: language.locale)
        },
        unlockReason: { [language] in
          L10n.string("Unlock administrator settings", locale: language.locale)
        })
    }
  }
#endif
