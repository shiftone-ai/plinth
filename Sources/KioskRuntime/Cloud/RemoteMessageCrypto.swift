import CryptoKit
import Foundation
import KioskCore

public nonisolated struct RemoteIdentity: Sendable {
  let signingPrivateKey: Data
  let agreementPrivateKey: Data
  public let signingPublicKey: Data
  public let agreementPublicKey: Data

  fileprivate nonisolated init(
    signingPrivateKey: Data, agreementPrivateKey: Data,
    signingPublicKey: Data, agreementPublicKey: Data
  ) {
    self.signingPrivateKey = signingPrivateKey
    self.agreementPrivateKey = agreementPrivateKey
    self.signingPublicKey = signingPublicKey
    self.agreementPublicKey = agreementPublicKey
  }

  public nonisolated static func generate() -> RemoteIdentity {
    let signing = Curve25519.Signing.PrivateKey()
    let agreement = Curve25519.KeyAgreement.PrivateKey()
    return RemoteIdentity(
      signingPrivateKey: signing.rawRepresentation,
      agreementPrivateKey: agreement.rawRepresentation,
      signingPublicKey: signing.publicKey.rawRepresentation,
      agreementPublicKey: agreement.publicKey.rawRepresentation)
  }

  nonisolated init(signingPrivateKey: Data, agreementPrivateKey: Data) throws {
    let signing = try Curve25519.Signing.PrivateKey(rawRepresentation: signingPrivateKey)
    let agreement = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: agreementPrivateKey)
    self.init(
      signingPrivateKey: signingPrivateKey, agreementPrivateKey: agreementPrivateKey,
      signingPublicKey: signing.publicKey.rawRepresentation,
      agreementPublicKey: agreement.publicKey.rawRepresentation)
  }
}

public enum RemoteMessageCrypto {
  public nonisolated static func seal(
    _ plaintext: Data, header: RemoteMessageHeader, sender: RemoteIdentity,
    recipientAgreementPublicKey: Data
  ) throws -> RemoteSealedMessage {
    let recipient = try Curve25519.KeyAgreement.PublicKey(
      rawRepresentation: recipientAgreementPublicKey)
    let ephemeral = Curve25519.KeyAgreement.PrivateKey()
    let authenticatedData = header.authenticatedData
    let secret = try ephemeral.sharedSecretFromKeyAgreement(with: recipient)
    let key = secret.hkdfDerivedSymmetricKey(
      using: SHA256.self, salt: authenticatedData,
      sharedInfo: Data("PlinthRemoteEncryptionV1".utf8), outputByteCount: 32)
    let box = try AES.GCM.seal(
      plaintext, using: key, authenticating: authenticatedData)
    guard let ciphertext = box.combined else { throw Failure.invalidCiphertext }
    let ephemeralPublicKey = ephemeral.publicKey.rawRepresentation
    let signature = try Curve25519.Signing.PrivateKey(
      rawRepresentation: sender.signingPrivateKey
    )
    .signature(
      for: signedData(
        authenticatedData, ephemeralPublicKey: ephemeralPublicKey,
        ciphertext: ciphertext))
    return RemoteSealedMessage(
      header: header, ephemeralPublicKey: ephemeralPublicKey,
      ciphertext: ciphertext, signature: signature)
  }

  public nonisolated static func open(
    _ message: RemoteSealedMessage, recipient: RemoteIdentity,
    senderSigningPublicKey: Data
  ) throws -> Data {
    guard message.header.version == 1 else { throw Failure.unsupportedVersion }
    let authenticatedData = message.header.authenticatedData
    let sender = try Curve25519.Signing.PublicKey(rawRepresentation: senderSigningPublicKey)
    guard
      sender.isValidSignature(
        message.signature,
        for: signedData(
          authenticatedData, ephemeralPublicKey: message.ephemeralPublicKey,
          ciphertext: message.ciphertext))
    else { throw Failure.invalidSignature }
    let ephemeral = try Curve25519.KeyAgreement.PublicKey(
      rawRepresentation: message.ephemeralPublicKey)
    let secret = try Curve25519.KeyAgreement.PrivateKey(
      rawRepresentation: recipient.agreementPrivateKey
    )
    .sharedSecretFromKeyAgreement(with: ephemeral)
    let key = secret.hkdfDerivedSymmetricKey(
      using: SHA256.self, salt: authenticatedData,
      sharedInfo: Data("PlinthRemoteEncryptionV1".utf8), outputByteCount: 32)
    return try AES.GCM.open(
      AES.GCM.SealedBox(combined: message.ciphertext), using: key,
      authenticating: authenticatedData)
  }

  private nonisolated static func signedData(
    _ header: Data, ephemeralPublicKey: Data, ciphertext: Data
  ) -> Data {
    var data = header
    data.append(ephemeralPublicKey)
    data.append(ciphertext)
    return data
  }

  public enum Failure: Error, Sendable {
    case unsupportedVersion, invalidCiphertext, invalidSignature
  }
}
