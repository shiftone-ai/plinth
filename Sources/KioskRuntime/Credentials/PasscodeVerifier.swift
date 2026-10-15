import CommonCrypto
import Foundation
import Security

/// Stores only a salted PBKDF2 verifier; passcodes never enter profile JSON or diagnostics.
public nonisolated struct PasscodeVerifier: Codable, Sendable {
  public let version: Int
  public let rounds: UInt32
  public let salt: Data
  public let digest: Data
  public enum Failure: Error { case invalidPasscode, randomFailed, derivationFailed, invalidRecord }

  public static func create(_ passcode: String) throws -> Self {
    guard passcode.count >= 8, passcode.utf8.count <= 1024 else { throw Failure.invalidPasscode }
    var salt = Data(count: 32)
    let status = salt.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!)
    }
    guard status == errSecSuccess else { throw Failure.randomFailed }
    let rounds: UInt32 = 600_000
    return Self(
      version: 1, rounds: rounds, salt: salt,
      digest: try derive(passcode, salt: salt, rounds: rounds))
  }

  public func verify(_ passcode: String) throws -> Bool {
    guard version == 1, rounds == 600_000, salt.count == 32, digest.count == 32 else {
      throw Failure.invalidRecord
    }
    guard passcode.utf8.count <= 1024 else { return false }
    let candidate = try Self.derive(passcode, salt: salt, rounds: rounds)
    // Inspect every byte; no early exit at the first mismatch.
    return zip(candidate, digest).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
  }

  private static func derive(_ passcode: String, salt: Data, rounds: UInt32) throws -> Data {
    let password = Array(passcode.utf8)
    var result = Data(count: 32)
    let status = password.withUnsafeBytes { passwordBytes in
      salt.withUnsafeBytes { saltBytes in
        result.withUnsafeMutableBytes { output in
          CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self), password.count,
            saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
            output.baseAddress?.assumingMemoryBound(to: UInt8.self), output.count)
        }
      }
    }
    guard status == kCCSuccess else { throw Failure.derivationFailed }
    return result
  }
}
