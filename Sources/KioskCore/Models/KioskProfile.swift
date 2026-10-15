import Foundation

public struct KioskProfile: Equatable, Codable, Sendable {
  public var schemaVersion: Int
  public var revision: UInt64
  public var startURL: String
  public var navigation: NavigationPolicy
  public var interaction: InteractionPolicy
  public var idleTimeout: Double
  public var resetMode: ResetMode
  public var recovery: RecoveryPolicy
  public var exhibitionDestination: ExhibitionDestination?
  public var macOutput: MacOutputSettings?
  public var externalDisplayMode: ExternalDisplayMode?
  public var externalDisplayRotation: ExternalDisplayRotation?

  public init(
    schemaVersion: Int = 1, revision: UInt64 = 1, startURL: String,
    navigation: NavigationPolicy, interaction: InteractionPolicy = .init(),
    idleTimeout: Double = 120, resetMode: ResetMode = .newVisitorSession,
    recovery: RecoveryPolicy = .init(), exhibitionDestination: ExhibitionDestination? = nil,
    macOutput: MacOutputSettings? = nil, externalDisplayMode: ExternalDisplayMode? = nil,
    externalDisplayRotation: ExternalDisplayRotation? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.revision = revision
    self.startURL = startURL
    self.navigation = navigation
    self.interaction = interaction
    self.idleTimeout = idleTimeout
    self.resetMode = resetMode
    self.recovery = recovery
    self.exhibitionDestination = exhibitionDestination
    self.macOutput = macOutput
    self.externalDisplayMode = externalDisplayMode
    self.externalDisplayRotation = externalDisplayRotation
  }

  public var automaticallyAllowedOrigin: Origin? {
    navigation.mode == .allowlist ? Origin(urlString: startURL) : nil
  }

  public func evaluateNavigation(_ url: String, enforceOriginRules: Bool = true)
    -> NavigationDecision
  {
    navigation.evaluate(
      url, enforceOriginRules: enforceOriginRules,
      automaticallyAllowedOrigin: automaticallyAllowedOrigin)
  }

  public var validationIssues: [ProfileIssue] {
    var issues: [ProfileIssue] = []
    if schemaVersion != 1 { issues.append(.unsupportedSchema) }
    if revision == 0 { issues.append(.invalidRevision) }
    if !navigation.hasValidRules { issues.append(.invalidNavigationRules) }
    if evaluateNavigation(startURL) != .allow { issues.append(.homeNotAllowed) }
    if !idleTimeout.isFinite || idleTimeout <= 0 { issues.append(.invalidIdleTimeout) }
    if externalDisplayMode?.isValid == false { issues.append(.invalidDisplayMode) }
    if recovery.maximumAttempts < 0 || !recovery.delay.isFinite || recovery.delay <= 0 {
      issues.append(.invalidRecoveryPolicy)
    }
    return issues
  }
}

public enum ProfileIssue: String, Equatable, Sendable {
  case unsupportedSchema, invalidRevision, invalidNavigationRules, homeNotAllowed,
    invalidIdleTimeout, invalidRecoveryPolicy, invalidDisplayMode
}

public enum ResetMode: String, Codable, Sendable {
  case retainWebsiteData, newVisitorSession
}

public struct RecoveryPolicy: Equatable, Codable, Sendable {
  public var maximumAttempts: Int
  public var delay: Double
  public init(maximumAttempts: Int = 3, delay: Double = 2) {
    self.maximumAttempts = maximumAttempts
    self.delay = delay
  }
}

public struct ProfileDraft: Equatable, Sendable {
  public var profile: KioskProfile
  public var idleTimeoutText: String
  public var rules: [OriginRuleDraft]
  public var macOutput: MacOutputSettings { profile.macOutput ?? .init() }
  public var externalDisplayRotation: ExternalDisplayRotation {
    profile.externalDisplayRotation ?? .standard
  }

  public init(profile: KioskProfile) {
    self.profile = profile
    self.idleTimeoutText = String(profile.idleTimeout)
    self.rules = profile.navigation.rules.map {
      OriginRuleDraft(
        id: $0.id, address: $0.inputAddress, includeSubdomains: $0.includeSubdomains)
    }
  }

  public mutating func apply(_ edit: ProfileDraftEdit) -> Bool {
    switch edit {
    case .startURL(let value): profile.startURL = value
    case .navigationMode(let value): profile.navigation.mode = value
    case .allowsHTTP(let value): profile.navigation.allowsHTTP = value
    case .allowsScroll(let value): profile.interaction.allowsScroll = value
    case .allowsDrag(let value): profile.interaction.allowsDrag = value
    case .idleTimeoutText(let value): idleTimeoutText = value
    case .resetMode(let value): profile.resetMode = value
    case .exhibitionDestination(let value): profile.exhibitionDestination = value
    case .externalDisplayMode(let value): profile.externalDisplayMode = value
    case .externalDisplayRotation(let value): profile.externalDisplayRotation = value
    case .macOutputMode(let value):
      var settings = macOutput
      settings.mode = value
      profile.macOutput = settings
    case .macDisplayID(let value):
      var settings = macOutput
      settings.displayID = value
      profile.macOutput = settings
    case .originAddress(let id, let value):
      guard let index = rules.firstIndex(where: { $0.id == id }) else { return false }
      rules[index].address = value
      rules[index].includeSubdomains = false
    }
    return true
  }

  public var validatedProfile: KioskProfile? {
    guard let timeout = Double(idleTimeoutText), timeout.isFinite, timeout > 0 else { return nil }
    var value = profile
    value.idleTimeout = timeout
    let parsedRules = rules.compactMap { $0.rule }
    guard parsedRules.count == rules.count else { return nil }
    value.navigation.rules = parsedRules
    return value.validationIssues.isEmpty ? value : nil
  }

  public var validationIssues: [ProfileIssue] {
    var value = profile
    value.idleTimeout = Double(idleTimeoutText) ?? .nan
    value.navigation.rules = rules.compactMap(\.rule)
    var issues = value.validationIssues
    if value.navigation.rules.count != rules.count && !issues.contains(.invalidNavigationRules) {
      issues.append(.invalidNavigationRules)
    }
    return issues
  }
}

public enum ProfileDraftEdit: Equatable, Sendable {
  case startURL(String)
  case navigationMode(NavigationPolicy.Mode)
  case allowsHTTP(Bool)
  case allowsScroll(Bool)
  case allowsDrag(Bool)
  case idleTimeoutText(String)
  case resetMode(ResetMode)
  case exhibitionDestination(ExhibitionDestination?)
  case externalDisplayMode(ExternalDisplayMode?)
  case externalDisplayRotation(ExternalDisplayRotation?)
  case macOutputMode(MacOutputSettings.Mode)
  case macDisplayID(String?)
  case originAddress(UInt64, String)
}

public struct OriginRuleDraft: Equatable, Sendable, Identifiable {
  public let id: UInt64
  public var address: String
  public var includeSubdomains: Bool
  public init(id: UInt64, address: String, includeSubdomains: Bool = false) {
    self.id = id
    self.address = address
    self.includeSubdomains = includeSubdomains
  }
  public var rule: OriginRule? {
    var value = address.trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.contains("://") { value = "https://" + value }
    guard let separator = value.range(of: "://") else { return nil }
    var authority = String(value[separator.upperBound...])
    let wildcard = authority.hasPrefix("*.")
    if wildcard { authority = String(authority.dropFirst(2)) }
    guard !authority.contains("*"),
      let origin = Origin(urlString: String(value[..<separator.upperBound]) + authority),
      !wildcard || origin.supportsSubdomains
    else { return nil }
    return OriginRule(id: id, origin: origin, includeSubdomains: wildcard || includeSubdomains)
  }
}

public enum ExhibitionDestination: String, Codable, Sendable { case device, externalDisplay }
