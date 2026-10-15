import Foundation
import KioskCore
import Testing

struct NavigationPolicyTests {
  @Test func startOriginNeedsNoManualAllowlistRule() {
    let profile = KioskProfile(
      startURL: "https://display.example.com/exhibition", navigation: .init(rules: []))
    #expect(profile.validationIssues.isEmpty)
    #expect(ProfileDraft(profile: profile).validatedProfile == profile)
  }

  @Test(arguments: [
    Case(url: "https://display.example.com:8443/next", expected: .allow),
    Case(url: "https://display.example.com/next", expected: .cancel(.urlBlocked)),
    Case(url: "https://sub.display.example.com:8443", expected: .cancel(.urlBlocked)),
    Case(url: "https://display.example.com.attacker.invalid:8443", expected: .cancel(.urlBlocked)),
    Case(url: "http://display.example.com:8443", expected: .cancel(.httpDisabled)),
    Case(url: "https://example.com/extra", expected: .allow),
  ])
  func automaticPermissionIsLimitedToTheStartOrigin(_ test: Case) throws {
    var profile = try fixtureProfile(startURL: "https://display.example.com:8443/exhibition")
    profile.navigation.rules[0].includeSubdomains = false
    #expect(profile.evaluateNavigation(test.url) == test.expected)
  }

  @Test func changingTheStartURLMovesOnlyItsAutomaticPermission() {
    var profile = KioskProfile(
      startURL: "https://first.example.com/a", navigation: .init(rules: []))
    profile.startURL = "https://second.example.com/b"
    #expect(profile.evaluateNavigation("https://second.example.com/c") == .allow)
    #expect(profile.evaluateNavigation("https://first.example.com/a") == .cancel(.urlBlocked))
    #expect(profile.navigation.rules.isEmpty)
  }

  @Test func automaticPermissionDoesNotBypassDenylistHTTPOrInvalidRules() throws {
    var profile = try fixtureProfile()
    profile.navigation.mode = .denylist
    #expect(profile.automaticallyAllowedOrigin == nil)
    #expect(profile.validationIssues == [.homeNotAllowed])
    profile.navigation.mode = .allowlist
    profile.startURL = "http://example.com"
    #expect(profile.evaluateNavigation(profile.startURL) == .cancel(.httpDisabled))
    profile.startURL = "https://example.com"
    profile.navigation.rules.append(profile.navigation.rules[0])
    #expect(profile.evaluateNavigation(profile.startURL) == .cancel(.invalidProfile))
  }

  struct Case: Sendable {
    let url: String
    let expected: NavigationDecision
  }

  @Test(arguments: [
    Case(url: "https://example.com/a?x=1#section", expected: .allow),
    Case(url: "https://EXAMPLE.com.:443/a", expected: .allow),
    Case(url: "https://sub.example.com", expected: .allow),
    Case(url: "https://example.com.attacker.invalid", expected: .cancel(.urlBlocked)),
    Case(url: "https://notexample.com", expected: .cancel(.urlBlocked)),
    Case(url: "https://example.com:444", expected: .cancel(.urlBlocked)),
    Case(url: "http://example.com", expected: .cancel(.httpDisabled)),
    Case(url: "https://user:secret@example.com", expected: .cancel(.invalidURL)),
    Case(url: "file:///tmp/example", expected: .cancel(.invalidURL)),
    Case(url: "mailto:user@example.com", expected: .cancel(.invalidURL)),
    Case(url: "javascript:alert(1)", expected: .cancel(.invalidURL)),
    Case(url: "/relative", expected: .cancel(.invalidURL)),
    Case(url: "https://", expected: .cancel(.invalidURL)),
    Case(url: "https://example.com:65536", expected: .cancel(.invalidURL)),
    Case(url: "https://example..com", expected: .cancel(.invalidURL)),
    Case(url: "https://example.com..", expected: .cancel(.invalidURL)),
    Case(url: "https://127.1", expected: .cancel(.invalidURL)),
    Case(url: "https://0x7f000001", expected: .cancel(.invalidURL)),
    Case(url: "https://127.000.000.001", expected: .cancel(.invalidURL)),
  ])
  func evaluatesOriginBoundaries(_ test: Case) throws {
    #expect(try fixtureProfile().navigation.evaluate(test.url) == test.expected)
  }

  @Test(arguments: ["https://例え.テスト", "https://xn--r8jz45g.xn--zckzah"])
  func normalizesInternationalHosts(_ url: String) throws {
    let origin = try #require(Origin(urlString: url))
    #expect(origin.host == "xn--r8jz45g.xn--zckzah")
  }

  @Test(arguments: ["http://127.0.0.1:19473", "http://[::1]:19473"])
  func supportsIPOriginsWithoutSchemeExceptions(_ url: String) throws {
    let origin = try #require(Origin(urlString: url))
    let policy = NavigationPolicy(rules: [.init(id: 1, origin: origin)], allowsHTTP: true)
    #expect(policy.evaluate(url + "/fixture") == .allow)
    #expect(
      policy.evaluate(url.replacingOccurrences(of: "19473", with: "19474")) == .cancel(.urlBlocked))
  }

  @Test func subdomainFlagDoesNotExtendIPRulesToDNSNames() throws {
    let origin = try #require(Origin(urlString: "https://127.0.0.1"))
    let rule = OriginRule(id: 1, origin: origin, includeSubdomains: true)
    let candidate = try #require(Origin(urlString: "https://host.example.com"))
    #expect(rule.matches(candidate) == false)
    #expect(Origin(urlString: "https://host.127.0.0.1") == nil)
  }

  @Test func denylistStillRejectsDangerousSchemesAndCredentials() throws {
    var policy = try fixtureProfile().navigation
    policy.mode = .denylist
    #expect(policy.evaluate("https://example.com") == .cancel(.urlBlocked))
    #expect(policy.evaluate("https://elsewhere.invalid") == .allow)
    #expect(policy.evaluate("file:///etc/passwd") == .cancel(.invalidURL))
    #expect(policy.evaluate("https://user@example.net") == .cancel(.invalidURL))
  }

  @Test func disallowsInvalidHomeAndTimingSettings() throws {
    var profile = try fixtureProfile(startURL: "file:///tmp/invalid-start")
    #expect(profile.validationIssues == [.homeNotAllowed])
    profile.startURL = "https://example.com"
    profile.idleTimeout = .infinity
    profile.recovery.delay = .nan
    #expect(profile.validationIssues == [.invalidIdleTimeout, .invalidRecoveryPolicy])
  }

  @Test func corruptDecodedDenylistRulesFailClosed() throws {
    var profile = try fixtureProfile()
    profile.navigation.mode = .denylist
    let encoded = try JSONEncoder().encode(profile)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var navigation = try #require(object["navigation"] as? [String: Any])
    var rules = try #require(navigation["rules"] as? [[String: Any]])
    var origin = try #require(rules[0]["origin"] as? [String: Any])
    origin["host"] = "example..com"
    rules[0]["origin"] = origin
    navigation["rules"] = rules
    object["navigation"] = navigation
    let corrupted = try JSONDecoder().decode(
      KioskProfile.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(corrupted.validationIssues.contains(.invalidNavigationRules))
    #expect(corrupted.navigation.evaluate("https://elsewhere.invalid") == .cancel(.invalidProfile))
  }

  @Test func duplicateRuleIdentityInvalidatesProfile() throws {
    var profile = try fixtureProfile()
    profile.navigation.rules.append(profile.navigation.rules[0])
    #expect(profile.validationIssues.contains(.invalidNavigationRules))
  }
}
