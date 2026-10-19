import CommonCrypto
import CryptoKit
import Foundation
import KioskCore
import Security

/// Versioned authenticated file format for portable catalog entries.
nonisolated public enum EncryptedCatalogFile {
  public enum Failure: Error, Equatable {
    case invalidPassphrase, invalidFile, unsupportedVersion, tooLarge
  }

  private static let magic = Data("PLNTHCAT".utf8)
  private static let version: UInt8 = 1
  private static let rounds: UInt32 = 600_000
  private static let saltLength = 32
  private static let nonceLength = 12
  private static let tagLength = 16
  private static let headerLength = 8 + 1 + 4 + saltLength + nonceLength
  private static let maximumPlaintext = 4 * 1024 * 1024
  public static let maximumFileBytes = 8 * 1024 * 1024

  @concurrent public nonisolated static func encrypt(
    entries: [CatalogEntry], passphrase: String
  ) async throws -> Data {
    try Task.checkCancellation()
    let normalized = try normalizedPassphrase(passphrase)
    guard !entries.isEmpty, Set(entries.map(\.id)).count == entries.count,
      entries.allSatisfy({
        $0.formatVersion == 1 && CatalogEntry.validName($0.name) && $0.snapshot.isValid
      })
    else { throw Failure.invalidFile }
    let archive = Archive(entries: entries.map(PortableEntry.init))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let plaintext = try encoder.encode(archive)
    guard plaintext.count <= maximumPlaintext else { throw Failure.tooLarge }
    var salt = [UInt8](repeating: 0, count: saltLength)
    guard SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt) == errSecSuccess else {
      throw Failure.invalidFile
    }
    let nonce = AES.GCM.Nonce()
    var header = magic
    header.append(version)
    header.append(contentsOf: [
      UInt8((rounds >> 24) & 0xff), UInt8((rounds >> 16) & 0xff),
      UInt8((rounds >> 8) & 0xff), UInt8(rounds & 0xff),
    ])
    header.append(contentsOf: salt)
    header.append(contentsOf: nonce)
    let key = try deriveKey(normalized, salt: salt)
    try Task.checkCancellation()
    let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: header)
    var result = header
    result.append(sealed.ciphertext)
    result.append(sealed.tag)
    guard result.count <= maximumFileBytes else { throw Failure.tooLarge }
    return result
  }

  @concurrent public nonisolated static func decrypt(
    _ file: Data, passphrase: String
  ) async throws -> [CatalogEntry] {
    try Task.checkCancellation()
    let parsed = try parseHeader(file)
    let normalized = try normalizedPassphrase(passphrase)
    let key = try deriveKey(normalized, salt: parsed.salt)
    try Task.checkCancellation()
    do {
      let nonce = try AES.GCM.Nonce(data: parsed.nonce)
      let box = try AES.GCM.SealedBox(
        nonce: nonce, ciphertext: parsed.ciphertext, tag: file.suffix(tagLength))
      let plaintext = try AES.GCM.open(
        box, using: key, authenticating: file.prefix(headerLength))
      guard plaintext.count <= maximumPlaintext else { throw Failure.tooLarge }
      guard validStructure(plaintext) else { throw Failure.invalidFile }
      let archive = try JSONDecoder().decode(Archive.self, from: plaintext)
      guard archive.version == 1 else { throw Failure.unsupportedVersion }
      guard !archive.entries.isEmpty,
        Set(archive.entries.map(\.id)).count == archive.entries.count
      else { throw Failure.invalidFile }
      let entries = try archive.entries.map { item in
        guard item.formatVersion == 1,
          let entry = CatalogEntry(
            id: item.id, name: item.name, snapshot: item.snapshot, version: item.version)
        else { throw Failure.invalidFile }
        return entry
      }
      return entries
    } catch let error as Failure { throw error } catch { throw Failure.invalidFile }
  }

  private struct ParsedHeader {
    let salt: [UInt8]
    let nonce: Data
    let ciphertext: Data
  }

  private nonisolated static func parseHeader(_ file: Data) throws
    -> ParsedHeader
  {
    guard file.count <= maximumFileBytes else { throw Failure.tooLarge }
    guard file.count >= headerLength + tagLength, file.prefix(magic.count) == magic
    else { throw Failure.invalidFile }
    guard file[magic.count] == version else { throw Failure.unsupportedVersion }
    let encodedRounds = file[(magic.count + 1)..<(magic.count + 5)].reduce(UInt32(0)) {
      ($0 << 8) | UInt32($1)
    }
    guard encodedRounds == rounds else { throw Failure.invalidFile }
    let saltStart = magic.count + 5
    let salt = Array(file[saltStart..<(saltStart + saltLength)])
    let nonceStart = saltStart + saltLength
    let nonceData = Data(file[nonceStart..<(nonceStart + nonceLength)])
    let ciphertext = Data(file[headerLength..<(file.count - tagLength)])
    guard ciphertext.count <= maximumPlaintext else { throw Failure.tooLarge }
    return ParsedHeader(salt: salt, nonce: nonceData, ciphertext: ciphertext)
  }

  private nonisolated static func normalizedPassphrase(_ value: String) throws -> [CChar] {
    let normalized = value.precomposedStringWithCanonicalMapping
    guard normalized.count >= 16, normalized.utf8.count <= 1024 else {
      throw Failure.invalidPassphrase
    }
    return Array(normalized.utf8CString)
  }

  private nonisolated static func deriveKey(_ passphrase: [CChar], salt: [UInt8]) throws
    -> SymmetricKey
  {
    var bytes = [UInt8](repeating: 0, count: 32)
    let result = passphrase.withUnsafeBufferPointer { password in
      salt.withUnsafeBufferPointer { saltBytes in
        bytes.withUnsafeMutableBufferPointer { output in
          CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2), password.baseAddress, password.count - 1,
            saltBytes.baseAddress, saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
            output.baseAddress, output.count)
        }
      }
    }
    guard result == kCCSuccess else { throw Failure.invalidFile }
    return SymmetricKey(data: bytes)
  }

  private nonisolated static func validStructure(_ data: Data) -> Bool {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      hasKeys(root, required: ["version", "entries"]),
      let items = root["entries"] as? [Any]
    else { return false }
    return items.allSatisfy { value in
      guard let item = value as? [String: Any],
        hasKeys(item, required: ["id", "name", "formatVersion", "version", "snapshot"]),
        let snapshot = item["snapshot"] as? [String: Any],
        hasKeys(
          snapshot,
          required: [
            "startURL", "navigation", "interaction", "idleTimeout", "resetMode", "recovery",
          ],
          optional: [
            "exhibitionDestination", "macOutput", "externalDisplayMode", "externalDisplayRotation",
          ]),
        let navigation = snapshot["navigation"] as? [String: Any],
        hasKeys(navigation, required: ["mode", "rules", "allowsHTTP"]),
        let rules = navigation["rules"] as? [Any],
        let interaction = snapshot["interaction"] as? [String: Any],
        hasKeys(interaction, required: ["allowsScroll", "allowsDrag"]),
        let recovery = snapshot["recovery"] as? [String: Any],
        hasKeys(recovery, required: ["maximumAttempts", "delay"])
      else { return false }
      guard
        rules.allSatisfy({ rule in
          guard let rule = rule as? [String: Any],
            hasKeys(rule, required: ["id", "origin", "includeSubdomains"]),
            let origin = rule["origin"] as? [String: Any]
          else { return false }
          return hasKeys(origin, required: ["scheme", "host", "port"])
        })
      else { return false }
      if let output = snapshot["macOutput"] as? [String: Any],
        !hasKeys(output, required: ["mode"], optional: ["displayID"])
      {
        return false
      }
      if let mode = snapshot["externalDisplayMode"] as? [String: Any],
        !hasKeys(mode, required: ["width", "height", "pixelAspectRatio"])
      {
        return false
      }
      return true
    }
  }

  private nonisolated static func hasKeys(
    _ value: [String: Any], required: Set<String>, optional: Set<String> = []
  ) -> Bool {
    let found = Set(value.keys)
    return required.isSubset(of: found) && found.isSubset(of: required.union(optional))
  }

  private struct Archive: Codable {
    let version: Int
    let entries: [PortableEntry]
    init(entries: [PortableEntry]) {
      version = 1
      self.entries = entries
    }
  }

  private struct PortableEntry: Codable {
    let id: UUID
    let name: String
    let formatVersion: Int
    let version: UInt64
    let snapshot: CatalogSnapshot
    init(_ entry: CatalogEntry) {
      id = entry.id
      name = entry.name
      formatVersion = entry.formatVersion
      version = entry.version
      snapshot = entry.snapshot
    }
  }
}
