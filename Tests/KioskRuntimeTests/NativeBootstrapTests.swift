import Foundation
import KioskCore
import Testing

@testable import KioskRuntime

@MainActor
struct NativeBootstrapTests {
  @Test func damagedProfileRemainsClassifiedWhenCredentialLookupFails() {
    let token = OperationToken(owner: .root, operationID: 1)
    let event = NativeEffectPort.bootstrapEvent(
      token,
      profile: .failure(ProfileRepository.Failure.corruptProfile),
      credentials: .failure(CocoaError(.fileReadUnknown)), displayCount: 1)
    guard case .bootstrapFailed(let completed, let displays, let credentials, let corrupt) = event
    else {
      Issue.record("Expected failed bootstrap")
      return
    }
    #expect(completed == token)
    #expect(displays == 1)
    #expect(!credentials)
    #expect(corrupt)
  }
}
