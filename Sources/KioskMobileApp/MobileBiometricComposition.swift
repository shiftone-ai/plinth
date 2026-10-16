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
        if fixtureService != nil,
          let result = ProcessInfo.processInfo.environment["PLINTH_TEST_BIOMETRIC_RESULT"]
            .flatMap(MobileBiometricTestPort.UnlockResult.init(rawValue:))
        {
          let kind: BiometricKind =
            ProcessInfo.processInfo.environment["PLINTH_TEST_BIOMETRIC_KIND"] == "faceID"
            ? .faceID : .touchID
          return MobileBiometricTestPort(result: result, kind: kind)
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
