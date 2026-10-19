import Foundation
import Security

enum RemotePairingCodeGenerator {
  enum Failure: Error { case entropyUnavailable }

  nonisolated static func generate() throws -> String {
    let range: UInt32 = 100_000_000
    let threshold = UInt32.max - UInt32.max % range
    while true {
      var random: UInt32 = 0
      let status = SecRandomCopyBytes(
        kSecRandomDefault, MemoryLayout.size(ofValue: random),
        &random)
      guard status == errSecSuccess else { throw Failure.entropyUnavailable }
      if random < threshold { return String(format: "%08u", random % range) }
    }
  }
}
