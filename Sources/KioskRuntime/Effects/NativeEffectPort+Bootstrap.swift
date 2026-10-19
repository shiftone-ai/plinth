import Foundation
import KioskCore

extension NativeEffectPort {
  static func bootstrapEvent(
    _ token: OperationToken, profile: Result<KioskProfile?, Error>,
    credentials: Result<Bool, Error>, displayCount: Int
  ) -> Event {
    let hasCredentials = (try? credentials.get()) ?? false
    let credentialFailed: Bool
    if case .failure = credentials { credentialFailed = true } else { credentialFailed = false }
    switch profile {
    case .success(let savedProfile):
      if !credentialFailed {
        return .bootstrapped(
          profile: savedProfile, credentialsConfigured: hasCredentials,
          displayCount: displayCount)
      }
      return .bootstrapFailed(
        token, displayCount: displayCount, credentialsConfigured: false,
        profileCorrupt: false)
    case .failure(let error):
      let corrupt: Bool
      if case ProfileRepository.Failure.corruptProfile = error {
        corrupt = true
      } else {
        corrupt = false
      }
      return .bootstrapFailed(
        token, displayCount: displayCount, credentialsConfigured: hasCredentials,
        profileCorrupt: corrupt)
    }
  }
}
