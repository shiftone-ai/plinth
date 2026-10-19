import Foundation

/// Device-local preferences. The installation ID is never copied through the settings catalog.
public struct RemoteInstallation: Codable, Equatable, Sendable {
  public let id: UUID
  public var enabledAccountIdentifier: String?
  public var hiddenDeviceIDsByAccount: [String: Set<UUID>]
  public var lastAccountIdentifier: String?
  public var approvedControllers: [UUID: RemotePeerGrant]
  public var approvedTargets: [UUID: RemotePeerGrant]
  public var processedRequestExpirations: [UUID: Int64]

  public init(
    id: UUID, enabledAccountIdentifier: String? = nil,
    hiddenDeviceIDsByAccount: [String: Set<UUID>] = [:],
    lastAccountIdentifier: String? = nil,
    approvedControllers: [UUID: RemotePeerGrant] = [:],
    approvedTargets: [UUID: RemotePeerGrant] = [:],
    processedRequestExpirations: [UUID: Int64] = [:]
  ) {
    self.id = id
    self.enabledAccountIdentifier = enabledAccountIdentifier
    self.hiddenDeviceIDsByAccount = hiddenDeviceIDsByAccount
    self.lastAccountIdentifier = lastAccountIdentifier
    self.approvedControllers = approvedControllers
    self.approvedTargets = approvedTargets
    self.processedRequestExpirations = processedRequestExpirations
  }

  private enum CodingKeys: String, CodingKey {
    case id, enabledAccountIdentifier, hiddenDeviceIDsByAccount
    case lastAccountIdentifier, approvedControllers, approvedTargets
    case processedRequestExpirations
  }

  public init(from decoder: Decoder) throws {
    let fields = try decoder.container(keyedBy: CodingKeys.self)
    id = try fields.decode(UUID.self, forKey: .id)
    enabledAccountIdentifier = try fields.decodeIfPresent(
      String.self, forKey: .enabledAccountIdentifier)
    hiddenDeviceIDsByAccount =
      try fields.decodeIfPresent(
        [String: Set<UUID>].self, forKey: .hiddenDeviceIDsByAccount) ?? [:]
    lastAccountIdentifier = try fields.decodeIfPresent(
      String.self, forKey: .lastAccountIdentifier)
    approvedControllers =
      try fields.decodeIfPresent(
        [UUID: RemotePeerGrant].self, forKey: .approvedControllers) ?? [:]
    approvedTargets =
      try fields.decodeIfPresent(
        [UUID: RemotePeerGrant].self, forKey: .approvedTargets) ?? [:]
    processedRequestExpirations =
      try fields.decodeIfPresent(
        [UUID: Int64].self, forKey: .processedRequestExpirations) ?? [:]
  }

  public mutating func reconcileAccount(_ availability: RemoteAccountAvailability) {
    switch availability {
    case .available(let accountIdentifier):
      let previousAccount =
        lastAccountIdentifier ?? enabledAccountIdentifier
        ?? approvedControllers.values.first?.accountIdentifier
        ?? approvedTargets.values.first?.accountIdentifier
      if let previousAccount, previousAccount != accountIdentifier {
        enabledAccountIdentifier = nil
        approvedControllers = [:]
        approvedTargets = [:]
        processedRequestExpirations = [:]
      }
      lastAccountIdentifier = accountIdentifier
    case .unavailable:
      enabledAccountIdentifier = nil
      approvedControllers = [:]
      approvedTargets = [:]
      processedRequestExpirations = [:]
      lastAccountIdentifier = nil
    case .transient, .unsupported: break
    }
  }

  public mutating func disableRemoteManagement() {
    enabledAccountIdentifier = nil
    approvedControllers = [:]
  }

  public func hiddenDeviceIDs(for accountIdentifier: String?) -> Set<UUID> {
    guard let accountIdentifier else { return [] }
    return hiddenDeviceIDsByAccount[accountIdentifier] ?? []
  }
}

public struct RemotePeerGrant: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  public let name: String
  public let accountIdentifier: String
  public let signingPublicKey: Data
  public let agreementPublicKey: Data
  public let approvedAt: Date

  public init(
    id: UUID, name: String, accountIdentifier: String,
    signingPublicKey: Data, agreementPublicKey: Data, approvedAt: Date
  ) {
    self.id = id
    self.name = name
    self.accountIdentifier = accountIdentifier
    self.signingPublicKey = signingPublicKey
    self.agreementPublicKey = agreementPublicKey
    self.approvedAt = approvedAt
  }
}

public enum RemoteDevicePlatform: String, Codable, Equatable, Sendable {
  case mac, ipad, iphone
}

/// Public discovery data only. Settings, credentials, and operation results use separate records.
public struct RemoteDevice: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let name: String
  public let platform: RemoteDevicePlatform
  public let updatedAt: Date
  public let signingPublicKey: Data?
  public let agreementPublicKey: Data?

  public init(
    id: UUID, name: String, platform: RemoteDevicePlatform, updatedAt: Date,
    signingPublicKey: Data? = nil, agreementPublicKey: Data? = nil
  ) {
    self.id = id
    self.name = name
    self.platform = platform
    self.updatedAt = updatedAt
    self.signingPublicKey = signingPublicKey
    self.agreementPublicKey = agreementPublicKey
  }
}

public enum RemoteAccountAvailability: Equatable, Sendable {
  case available(String)
  case unavailable, transient, unsupported
}

public struct RemoteAccountCheck: Equatable, Sendable {
  public let availability: RemoteAccountAvailability
  public let installation: RemoteInstallation

  public init(availability: RemoteAccountAvailability, installation: RemoteInstallation) {
    self.availability = availability
    self.installation = installation
  }
}

public enum RemoteDirectoryStatus: Equatable, Sendable {
  case checking, ready, signInRequired, cloudUnavailable, offline, failed
}

public enum RemoteManagementTab: Hashable, Sendable {
  case thisDevice, otherDevices
}

public struct RemoteManagementState: Equatable, Sendable {
  public var installation: RemoteInstallation?
  public var accountIdentifier: String?
  public var devices: [RemoteDevice] = []
  public var status: RemoteDirectoryStatus = .checking
  public var selectedTab: RemoteManagementTab = .thisDevice
  public var selectedDeviceID: UUID?
  public var loadOperation: OperationToken?
  public var accountOperation: OperationToken?
  public var sessionOperation: OperationToken?
  public var preferenceOperation: OperationToken?
  public var preferenceFailed = false
  public var pairing = RemotePairingState()
  public var outgoingCommand: RemoteOutgoingCommand?
  public var outgoingCommandOperation: OperationToken?
  public var outgoingCommandDeadlineOperation: OperationToken?
  public var selectedSnapshot: RemoteStatusSnapshot?
  public var editing: RemoteEditingState?
  public var incomingCommand: RemoteCommandRequest?
  public var commandClaimOperation: OperationToken?
  public var commandResultOperation: OperationToken?
  public var remoteSaveOperation: OperationToken?
  public var exhibitionReviewAction: RemoteExhibitionAction?
  public var pendingExhibitionAction: RemoteExhibitionAction?

  public init() {}

  public var enabled: Bool {
    installation?.enabledAccountIdentifier != nil
      && installation?.enabledAccountIdentifier == accountIdentifier
  }
}
