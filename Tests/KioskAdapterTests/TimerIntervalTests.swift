import Foundation
import KioskCore
import Testing

@testable import KioskMacApp
@testable import KioskRuntime

struct TimerIntervalTests {
  @Test func validVeryLongTimeoutDoesNotOverflowNativeDurationConversion() throws {
    let origin = try #require(Origin(urlString: "https://example.com"))
    let profile = KioskProfile(
      startURL: "https://example.com", navigation: .init(rules: [.init(id: 1, origin: origin)]),
      idleTimeout: 1e100)
    #expect(profile.validationIssues.isEmpty)
    let interval = NativeEffectPort.timerInterval(until: profile.idleTimeout + 10, now: 10)
    let duration = Duration.seconds(interval)
    #expect(duration > .zero)
    #expect(duration <= .seconds(86_400))
    #expect(interval < profile.idleTimeout)
  }
}
