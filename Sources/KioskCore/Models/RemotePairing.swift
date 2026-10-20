import Foundation

/// Encrypted to the exhibition device; the code never appears in record metadata.
public struct RemotePairingRequestPayload: Codable, Equatable, Sendable {
  public let code: String
  public let name: String
  public let signingPublicKey: Data
  public let agreementPublicKey: Data

  public init(code: String, name: String, signingPublicKey: Data, agreementPublicKey: Data) {
    self.code = code
    self.name = name
    self.signingPublicKey = signingPublicKey
    self.agreementPublicKey = agreementPublicKey
  }
}

public struct RemotePairingProposal: Equatable, Sendable {
  public let header: RemoteMessageHeader
  public let name: String
  public let signingPublicKey: Data
  public let agreementPublicKey: Data

  public init(header: RemoteMessageHeader, payload: RemotePairingRequestPayload) {
    self.header = header
    name = payload.name
    signingPublicKey = payload.signingPublicKey
    agreementPublicKey = payload.agreementPublicKey
  }
}

public struct RemotePairingResultPayload: Codable, Equatable, Sendable {
  public let approved: Bool
  public init(approved: Bool) { self.approved = approved }
}

public struct RemotePairingResult: Equatable, Sendable {
  public let header: RemoteMessageHeader
  public let approved: Bool

  public init(header: RemoteMessageHeader, approved: Bool) {
    self.header = header
    self.approved = approved
  }
}

public struct RemotePairingCode: Equatable, Sendable {
  public let value: String
  public let expiresAt: Double
  public var remainingAttempts: Int

  public init(value: String, expiresAt: Double, remainingAttempts: Int = 5) {
    self.value = value
    self.expiresAt = expiresAt
    self.remainingAttempts = remainingAttempts
  }
}

public enum RemotePairingPhase: Equatable, Sendable {
  case idle, sending, awaitingApproval, storingApproval, approved, rejected, failed, unknown
}

public struct RemoteOutgoingPairing: Equatable, Sendable {
  public let requestID: UUID
  public let target: RemoteDevice
  public let accountIdentifier: String
  public let deadline: Double
  public var phase: RemotePairingPhase

  public init(
    requestID: UUID, target: RemoteDevice, accountIdentifier: String,
    deadline: Double, phase: RemotePairingPhase = .sending
  ) {
    self.requestID = requestID
    self.target = target
    self.accountIdentifier = accountIdentifier
    self.deadline = deadline
    self.phase = phase
  }
}

public struct RemotePairingState: Equatable, Sendable {
  public var code: RemotePairingCode?
  public var codeOperation: OperationToken?
  public var codeExpiryOperation: OperationToken?
  public var incoming: RemotePairingProposal?
  public var incomingDeadline: Double?
  public var incomingDeadlineOperation: OperationToken?
  public var approvalOperation: OperationToken?
  public var input = ""
  public var outgoing: RemoteOutgoingPairing?
  public var requestOperation: OperationToken?
  public var outgoingDeadlineOperation: OperationToken?
  public var targetGrantOperation: OperationToken?
  public var revokingControllerID: UUID?
  public var revocationOperation: OperationToken?

  public init() {}
}
