import Foundation
import KioskCore
import LocalAuthentication
import Security

@MainActor
public protocol BiometricCredentialPort: AnyObject {
  func status() -> BiometricStatus
  func changeEnabled(_ enabled: Bool, token: OperationToken) async
    -> (BiometricStatus, BiometricChangeOutcome)
  func cancel(_ token: OperationToken)
}

/// The protected Keychain item is the enabled flag. No biometric value enters profile JSON.
@MainActor
public final class BiometricCredentialAdapter: BiometricCredentialPort {
  private let service: String
  private let reason: @MainActor () -> String
  private let account = "administrator-biometric-unlock"
  private var contexts: [OperationToken: LAContext] = [:]
  private var committedEnable: OperationToken?

  public init(service: String, reason: @escaping @MainActor () -> String) {
    self.service = service
    self.reason = reason
  }

  public func status() -> BiometricStatus {
    let context = LAContext()
    var error: NSError?
    let available = context.canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics, error: &error)
    let availability: BiometricAvailability
    if available {
      switch context.biometryType {
      case .touchID: availability = .available(.touchID)
      case .faceID: availability = .available(.faceID)
      default: availability = .unavailable(.notAvailable)
      }
    } else {
      switch error?.code {
      case LAError.biometryNotEnrolled.rawValue: availability = .unavailable(.notEnrolled)
      case LAError.biometryLockout.rawValue: availability = .unavailable(.lockedOut)
      case LAError.passcodeNotSet.rawValue: availability = .unavailable(.passcodeNotSet)
      default: availability = .unavailable(.notAvailable)
      }
    }
    #if os(macOS)
      if case .available = availability, !hasKeychainAccessGroup {
        return BiometricStatus(availability: .unavailable(.storageUnavailable), enabled: false)
      }
    #endif
    if availability == .unavailable(.notEnrolled) {
      // Removing every enrolled biometric invalidates the administrator grant.
      let deleted = SecItemDelete(itemQuery() as CFDictionary)
      let reason: BiometricAvailability =
        deleted == errSecSuccess || deleted == errSecItemNotFound
        ? availability : .unavailable(.storageUnavailable)
      return BiometricStatus(availability: reason, enabled: false)
    }
    var query = itemQuery()
    // Inspect the protected value so Keychain evaluates biometryCurrentSet.
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    let inspection = LAContext()
    inspection.interactionNotAllowed = true
    query[kSecUseAuthenticationContext] = inspection
    var value: CFTypeRef?
    let result = SecItemCopyMatching(query as CFDictionary, &value)
    let enabled: Bool
    switch result {
    case errSecSuccess, errSecInteractionNotAllowed: enabled = true
    case errSecItemNotFound: enabled = false
    default:
      let reason: BiometricAvailability =
        available ? .unavailable(.storageUnavailable) : availability
      return BiometricStatus(availability: reason, enabled: false)
    }
    return BiometricStatus(availability: availability, enabled: enabled)
  }

  public func changeEnabled(_ enabled: Bool, token: OperationToken) async
    -> (BiometricStatus, BiometricChangeOutcome)
  {
    #if os(macOS)
      guard hasKeychainAccessGroup else { return (status(), .failed) }
    #endif
    if !enabled {
      let deleted = SecItemDelete(itemQuery() as CFDictionary)
      return (
        status(), deleted == errSecSuccess || deleted == errSecItemNotFound ? .succeeded : .failed
      )
    }
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    else { return (status(), .failed) }
    contexts[token] = context
    defer { contexts.removeValue(forKey: token) }
    do {
      try await context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: reason())
    } catch {
      let authenticationError = error as NSError
      let cancellationCodes = [
        LAError.userCancel.rawValue, LAError.systemCancel.rawValue, LAError.appCancel.rawValue,
      ]
      let outcome: BiometricChangeOutcome =
        authenticationError.domain == LAError.errorDomain
          && cancellationCodes.contains(authenticationError.code) ? .cancelled : .failed
      return (status(), outcome)
    }
    guard !Task.isCancelled, contexts[token] === context else { return (status(), .cancelled) }
    var accessError: Unmanaged<CFError>?
    guard
      let access = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        .biometryCurrentSet, &accessError)
    else { return (status(), .failed) }
    let deleted = SecItemDelete(itemQuery() as CFDictionary)
    guard deleted == errSecSuccess || deleted == errSecItemNotFound else {
      return (status(), .failed)
    }
    var attributes = itemQuery()
    attributes[kSecValueData] = Data([1])
    attributes[kSecAttrAccessControl] = access
    let added = SecItemAdd(attributes as CFDictionary, nil)
    if added == errSecSuccess { committedEnable = token }
    return (status(), added == errSecSuccess ? .succeeded : .failed)
  }

  public func cancel(_ token: OperationToken) {
    contexts[token]?.invalidate()
    contexts.removeValue(forKey: token)
    if committedEnable == token {
      _ = SecItemDelete(itemQuery() as CFDictionary)
      committedEnable = nil
    }
  }

  private func itemQuery() -> [CFString: Any] {
    var query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
    ]
    #if os(macOS)
      query[kSecUseDataProtectionKeychain] = true
    #endif
    return query
  }

  #if os(macOS)
    private var hasKeychainAccessGroup: Bool {
      guard let task = SecTaskCreateFromSelf(kCFAllocatorDefault),
        let groups = SecTaskCopyValueForEntitlement(
          task, "keychain-access-groups" as CFString, nil) as? [String]
      else { return false }
      return !groups.isEmpty
    }
  #endif
}
