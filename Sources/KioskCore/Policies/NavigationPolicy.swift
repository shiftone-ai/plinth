import Foundation

public struct Origin: Equatable, Codable, Sendable {
  public let scheme: String
  public let host: String
  public let port: Int

  public var urlString: String {
    let authority = host.contains(":") ? "[\(host)]" : host
    return "\(scheme)://\(authority):\(port)"
  }

  public var isCanonical: Bool { Origin(urlString: urlString) == self }

  public var supportsSubdomains: Bool {
    !host.contains(":") && !host.split(separator: ".").allSatisfy({ Int($0) != nil })
  }

  public init?(urlString: String) {
    guard !urlString.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
      let url = URL(string: urlString),
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
      components.user == nil, components.password == nil,
      var host = url.host?.lowercased(), !host.isEmpty
    else { return nil }
    if host.hasSuffix(".") { host.removeLast() }
    if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
    guard !host.isEmpty, !host.contains("%"), !host.contains(".."), !host.hasSuffix(".") else {
      return nil
    }
    if !host.contains(":") {
      let labels = host.split(separator: ".", omittingEmptySubsequences: false)
      guard
        labels.allSatisfy({
          !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-")
        }),
        host.count <= 253,
        host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") })
      else { return nil }
      if let last = labels.last, last.allSatisfy(\.isNumber) || last.hasPrefix("0x") {
        // Accept canonical dotted decimal IPs; reject alternative numeric host spellings.
        guard labels.count == 4,
          labels.allSatisfy({
            guard let value = Int($0), (0...255).contains(value) else { return false }
            return String(value) == $0
          })
        else { return nil }
      }
    }
    let port = components.port ?? (scheme == "https" ? 443 : 80)
    guard (1...65535).contains(port) else { return nil }
    self.scheme = scheme
    self.host = host
    self.port = port
  }
}

public struct OriginRule: Equatable, Codable, Sendable {
  public let id: UInt64
  public var origin: Origin
  public var includeSubdomains: Bool

  public init(id: UInt64, origin: Origin, includeSubdomains: Bool = false) {
    self.id = id
    self.origin = origin
    self.includeSubdomains = includeSubdomains
  }

  public func matches(_ candidate: Origin) -> Bool {
    guard origin.scheme == candidate.scheme, origin.port == candidate.port else { return false }
    return origin.host == candidate.host
      || (includeSubdomains && origin.supportsSubdomains
        && candidate.host.hasSuffix("." + origin.host))
  }

  public var inputAddress: String {
    let authority = origin.host.contains(":") ? "[\(origin.host)]" : origin.host
    let wildcard = includeSubdomains && origin.supportsSubdomains ? "*." : ""
    let scheme = origin.scheme == "https" ? "" : "\(origin.scheme)://"
    let port = origin.port == (origin.scheme == "https" ? 443 : 80) ? "" : ":\(origin.port)"
    return scheme + wildcard + authority + port
  }
}

public enum NavigationDecision: Equatable, Sendable {
  case allow
  case cancel(RejectionReason)
}

public struct NavigationPolicy: Equatable, Codable, Sendable {
  public enum Mode: String, Codable, Sendable { case allowlist, denylist }
  public var mode: Mode
  public var rules: [OriginRule]
  public var allowsHTTP: Bool

  public var hasValidRules: Bool {
    Set(rules.map(\.id)).count == rules.count && rules.allSatisfy { $0.origin.isCanonical }
  }

  public init(mode: Mode = .allowlist, rules: [OriginRule], allowsHTTP: Bool = false) {
    self.mode = mode
    self.rules = rules
    self.allowsHTTP = allowsHTTP
  }

  public func evaluate(
    _ url: String, enforceOriginRules: Bool = true, automaticallyAllowedOrigin: Origin? = nil
  ) -> NavigationDecision {
    guard hasValidRules else { return .cancel(.invalidProfile) }
    if !enforceOriginRules && url == "about:blank" { return .allow }
    guard let origin = Origin(urlString: url) else { return .cancel(.invalidURL) }
    guard allowsHTTP || origin.scheme == "https" else { return .cancel(.httpDisabled) }
    if !enforceOriginRules { return .allow }
    let matches =
      rules.contains { $0.matches(origin) }
      || (mode == .allowlist && origin == automaticallyAllowedOrigin)
    return (mode == .allowlist ? matches : !matches) ? .allow : .cancel(.urlBlocked)
  }
}
