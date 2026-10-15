import KioskMacApp
import KioskRuntime
import Testing

struct PasscodeVerifierTests {
  @Test func saltedVerifierAcceptsOnlyMatchingPasscode() throws {
    let first = try PasscodeVerifier.create("exhibition-passcode")
    let second = try PasscodeVerifier.create("exhibition-passcode")
    #expect(first.salt != second.salt)
    #expect(first.digest != second.digest)
    #expect(try first.verify("exhibition-passcode"))
    #expect(try !first.verify("exhibition-passcodf"))
    #expect(try !first.verify(""))
  }

  @Test(arguments: ["", "1234567", String(repeating: "あ", count: 400)])
  func invalidSetupPasscodesAreRejected(_ passcode: String) {
    #expect(throws: PasscodeVerifier.Failure.self) { try PasscodeVerifier.create(passcode) }
  }
}
