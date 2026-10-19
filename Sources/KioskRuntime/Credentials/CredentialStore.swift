import Foundation
import LocalAuthentication
import Security

public actor CredentialStore {
  public nonisolated enum Keychain: Sendable {
    case platformDefault, dataProtection
    #if DEBUG
      case testDefaults
    #endif
  }
  public nonisolated enum Failure: Error {
    case keychain(OSStatus)
    case corruptRecord
  }
  private let service: String
  private let keychain: Keychain
  private let legacyService: String?
  private let account = "administrator-verifier"
  public init(
    service: String = "ai.shiftone.plinth", keychain: Keychain = .platformDefault,
    legacyService: String? = nil
  ) {
    self.service = service
    self.keychain = keychain
    self.legacyService = legacyService
  }

  public func isConfigured() throws -> Bool { try read() != nil }

  public func configure(_ passcode: String) throws {
    let record = try PasscodeVerifier.create(passcode)
    try Task.checkCancellation()
    #if DEBUG
      if keychain == .testDefaults {
        UserDefaults.standard.set(
          try JSONEncoder().encode(record), forKey: "plinth-test-credential-\(service)")
        return
      }
    #endif
    let data = try JSONEncoder().encode(record)
    let status = SecItemUpdate(
      query(service: service, keychain: keychain) as CFDictionary,
      [kSecValueData: data] as CFDictionary)
    if status == errSecItemNotFound {
      var attributes = query(service: service, keychain: keychain)
      attributes[kSecValueData] = data
      attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      let added = SecItemAdd(attributes as CFDictionary, nil)
      guard added == errSecSuccess else { throw Failure.keychain(added) }
    } else if status != errSecSuccess {
      throw Failure.keychain(status)
    }
  }

  public func verify(_ passcode: String) throws -> Bool {
    guard let record = try read() else { return false }
    return try record.verify(passcode)
  }

  private func query(service: String, keychain: Keychain) -> [CFString: Any] {
    let context = LAContext()
    context.interactionNotAllowed = true
    var attributes: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
      kSecUseAuthenticationContext: context,
    ]
    if keychain == .dataProtection { attributes[kSecUseDataProtectionKeychain] = true }
    return attributes
  }

  private func read() throws -> PasscodeVerifier? {
    #if DEBUG
      if keychain == .testDefaults {
        guard let data = UserDefaults.standard.data(forKey: "plinth-test-credential-\(service)")
        else { return nil }
        guard let record = try? JSONDecoder().decode(PasscodeVerifier.self, from: data)
        else { throw Failure.corruptRecord }
        return record
      }
    #endif
    if let record = try read(service: service, keychain: keychain) { return record }
    // Native Mac beta 1 used this separate service in the file-based keychain.
    guard let legacyService else { return nil }
    return try read(service: legacyService, keychain: .platformDefault)
  }

  private func read(service: String, keychain: Keychain) throws -> PasscodeVerifier? {
    var request = query(service: service, keychain: keychain)
    request[kSecReturnData] = true
    request[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw Failure.keychain(status) }
    guard let data = result as? Data,
      let record = try? JSONDecoder().decode(PasscodeVerifier.self, from: data),
      record.version == 1, record.rounds == 600_000, record.salt.count == 32,
      record.digest.count == 32
    else { throw Failure.corruptRecord }
    return record
  }
}
