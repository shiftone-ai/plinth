import Foundation

/// The portable part of a saved profile. Device credentials and local preferences never enter it.
public struct CatalogSnapshot: Equatable, Codable, Sendable {
  public let startURL: String
  public let navigation: NavigationPolicy
  public let interaction: InteractionPolicy
  public let idleTimeout: Double
  public let resetMode: ResetMode
  public let recovery: RecoveryPolicy
  public let exhibitionDestination: ExhibitionDestination?
  public let macOutput: MacOutputSettings?
  public let externalDisplayMode: ExternalDisplayMode?
  public let externalDisplayRotation: ExternalDisplayRotation?

  public init?(_ profile: KioskProfile) {
    guard profile.validationIssues.isEmpty else { return nil }
    startURL = profile.startURL
    navigation = profile.navigation
    interaction = profile.interaction
    idleTimeout = profile.idleTimeout
    resetMode = profile.resetMode
    recovery = profile.recovery
    exhibitionDestination = profile.exhibitionDestination
    macOutput = profile.macOutput
    externalDisplayMode = profile.externalDisplayMode
    externalDisplayRotation = profile.externalDisplayRotation
  }

  public func profile(revision: UInt64) -> KioskProfile {
    KioskProfile(
      revision: revision, startURL: startURL, navigation: navigation,
      interaction: interaction, idleTimeout: idleTimeout, resetMode: resetMode,
      recovery: recovery, exhibitionDestination: exhibitionDestination, macOutput: macOutput,
      externalDisplayMode: externalDisplayMode,
      externalDisplayRotation: externalDisplayRotation)
  }

  public var isValid: Bool { profile(revision: 1).validationIssues.isEmpty }
}
