import Foundation
import KioskCore
import Testing

@testable import KioskRuntime

struct RemoteMessageCryptoTests {
  @Test func onlyTheAddressedDeviceCanReadAnUnmodifiedSignedMessage() throws {
    let controller = RemoteIdentity.generate()
    let exhibit = RemoteIdentity.generate()
    let anotherDevice = RemoteIdentity.generate()
    let message = RemoteMessageHeader(
      kind: .command, accountIdentifier: "account-a", senderID: UUID(),
      recipientID: UUID(), requestID: UUID(), expiresAt: 1_700_000_120)
    let plaintext = Data("save a different URL".utf8)

    let sealed = try RemoteMessageCrypto.seal(
      plaintext, header: message, sender: controller,
      recipientAgreementPublicKey: exhibit.agreementPublicKey)
    #expect(
      try RemoteMessageCrypto.open(
        sealed, recipient: exhibit, senderSigningPublicKey: controller.signingPublicKey
      ) == plaintext)
    #expect(throws: Error.self) {
      try RemoteMessageCrypto.open(
        sealed, recipient: anotherDevice,
        senderSigningPublicKey: controller.signingPublicKey)
    }
    #expect(throws: Error.self) {
      try RemoteMessageCrypto.open(
        sealed, recipient: exhibit,
        senderSigningPublicKey: anotherDevice.signingPublicKey)
    }
    var changed = sealed
    changed.header.recipientID = UUID()
    #expect(throws: Error.self) {
      try RemoteMessageCrypto.open(
        changed, recipient: exhibit,
        senderSigningPublicKey: controller.signingPublicKey)
    }
    changed = sealed
    changed.ciphertext[changed.ciphertext.startIndex] ^= 1
    #expect(throws: Error.self) {
      try RemoteMessageCrypto.open(
        changed, recipient: exhibit,
        senderSigningPublicKey: controller.signingPublicKey)
    }
  }
}
