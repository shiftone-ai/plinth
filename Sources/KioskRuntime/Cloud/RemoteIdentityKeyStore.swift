import Foundation
import LocalAuthentication
import Security

/// Stores installation private keys only in the device Keychain.
public actor RemoteIdentityKeyStore {
  public enum Failure: Error, Sendable {
    case keychain(OSStatus)
    case corruptIdentity
  }

  private nonisolated struct PrivateRecord: Codable {
    let version: Int
    let signingPrivateKey: Data
    let agreementPrivateKey: Data
  }

  private let service: String
  private let keychain: CredentialStore.Keychain

  public init(
    service: String = "ai.shiftone.plinth.remote-identity",
    keychain: CredentialStore.Keychain = .platformDefault
  ) {
    self.service = service
    self.keychain = keychain
  }

  public func loadOrCreate(installationID: UUID) throws -> RemoteIdentity {
    let attributes = query(for: installationID)
    var request = attributes
    request[kSecReturnData] = true
    request[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &result)
    if status == errSecSuccess {
      guard let data = result as? Data,
        let record = try? JSONDecoder().decode(PrivateRecord.self, from: data),
        record.version == 1,
        let identity = try? RemoteIdentity(
          signingPrivateKey: record.signingPrivateKey,
          agreementPrivateKey: record.agreementPrivateKey)
      else { throw Failure.corruptIdentity }
      return identity
    }
    guard status == errSecItemNotFound else { throw Failure.keychain(status) }
    let identity = RemoteIdentity.generate()
    let record = PrivateRecord(
      version: 1, signingPrivateKey: identity.signingPrivateKey,
      agreementPrivateKey: identity.agreementPrivateKey)
    var addition = attributes
    addition[kSecValueData] = try JSONEncoder().encode(record)
    addition[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    addition[kSecAttrSynchronizable] = false
    let added = SecItemAdd(addition as CFDictionary, nil)
    guard added == errSecSuccess else { throw Failure.keychain(added) }
    return identity
  }

  private func query(for installationID: UUID) -> [CFString: Any] {
    let context = LAContext()
    context.interactionNotAllowed = true
    var attributes: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: installationID.uuidString,
      kSecUseAuthenticationContext: context,
    ]
    if keychain == .dataProtection { attributes[kSecUseDataProtectionKeychain] = true }
    return attributes
  }
}
