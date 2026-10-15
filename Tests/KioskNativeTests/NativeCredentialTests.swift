import Foundation
import KioskMacApp
import KioskRuntime
import LocalAuthentication
import Security
import Testing

@Suite(.enabled(if: ProcessInfo.processInfo.environment["PLINTH_NATIVE_TESTS"] == "1"))
struct NativeCredentialTests {
  @Test func existingNativeVerifierRemainsUsableUntilReplacementIsConfigured() async throws {
    let legacy = "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    let service = "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    let old = CredentialStore(service: legacy)
    let upgraded = CredentialStore(service: service, legacyService: legacy)
    defer {
      for name in [legacy, service] {
        let query: [CFString: Any] = [
          kSecClass: kSecClassGenericPassword, kSecAttrService: name,
          kSecAttrAccount: "administrator-verifier",
        ]
        #expect(SecItemDelete(query as CFDictionary) == errSecSuccess)
      }
    }
    try await old.configure("original-passcode")
    #expect(try await upgraded.isConfigured())
    #expect(try await upgraded.verify("original-passcode"))
    #expect(try await upgraded.verify("incorrect-passcode") == false)
    try await upgraded.configure("replacement-passcode")
    #expect(try await upgraded.verify("original-passcode") == false)
    #expect(try await upgraded.verify("replacement-passcode"))
    #expect(try await old.verify("original-passcode"))
  }

  @Test func isolatedKeychainVerifierCanBeConfiguredReadAndReplacedWithoutPrompts() async throws {
    let service = "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    let store = CredentialStore(service: service)
    let context = LAContext()
    context.interactionNotAllowed = true
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword, kSecAttrService: service,
      kSecAttrAccount: "administrator-verifier", kSecUseAuthenticationContext: context,
    ]
    defer {
      let result = SecItemDelete(query as CFDictionary)
      #expect(result == errSecSuccess || result == errSecItemNotFound)
    }
    #expect(try await store.isConfigured() == false)
    try await store.configure("plinth-test-passcode")
    #expect(try await store.isConfigured())
    #expect(try await store.verify("plinth-test-passcode"))
    #expect(try await store.verify("different-passcode") == false)
    var request = query
    request[kSecReturnData] = true
    var data: CFTypeRef?
    #expect(SecItemCopyMatching(request as CFDictionary, &data) == errSecSuccess)
    let stored = try #require(data as? Data)
    #expect(String(data: stored, encoding: .utf8)?.contains("plinth-test-passcode") == false)
    try await store.configure("replacement-passcode")
    #expect(try await store.verify("plinth-test-passcode") == false)
    #expect(try await store.verify("replacement-passcode"))
  }
}
