import Foundation

public enum RemoteMessageKind: String, Codable, Sendable {
  case pairingRequest, pairingResult, command, result
}

/// The routing fields are visible in CloudKit. Their exact bytes are signed and authenticated.
public struct RemoteMessageHeader: Codable, Equatable, Sendable {
  public let version: Int
  public let kind: RemoteMessageKind
  public let accountIdentifier: String
  public let senderID: UUID
  public var recipientID: UUID
  public let requestID: UUID
  public let expiresAt: Int64

  public init(
    kind: RemoteMessageKind, accountIdentifier: String, senderID: UUID,
    recipientID: UUID, requestID: UUID, expiresAt: Int64
  ) {
    version = 1
    self.kind = kind
    self.accountIdentifier = accountIdentifier
    self.senderID = senderID
    self.recipientID = recipientID
    self.requestID = requestID
    self.expiresAt = expiresAt
  }

  public var authenticatedData: Data {
    var data = Data("PlinthRemoteMessage".utf8)
    for field in [
      String(version), kind.rawValue, accountIdentifier, senderID.uuidString,
      recipientID.uuidString, requestID.uuidString, String(expiresAt),
    ] {
      let bytes = Data(field.utf8)
      var length = UInt32(bytes.count).bigEndian
      withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
      data.append(bytes)
    }
    return data
  }
}

public struct RemoteSealedMessage: Codable, Equatable, Sendable {
  public var header: RemoteMessageHeader
  public let ephemeralPublicKey: Data
  public var ciphertext: Data
  public let signature: Data

  public init(
    header: RemoteMessageHeader, ephemeralPublicKey: Data,
    ciphertext: Data, signature: Data
  ) {
    self.header = header
    self.ephemeralPublicKey = ephemeralPublicKey
    self.ciphertext = ciphertext
    self.signature = signature
  }
}
