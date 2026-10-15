import Testing

@testable import KioskCore

struct OriginRuleDraftTests {
  struct Case: Sendable {
    let address: String
    let scheme: String
    let host: String
    let port: Int
    let subdomains: Bool
  }

  @Test(arguments: [
    Case(
      address: "example.co.jp", scheme: "https", host: "example.co.jp", port: 443, subdomains: false
    ),
    Case(
      address: "*.example.co.jp", scheme: "https", host: "example.co.jp", port: 443,
      subdomains: true),
    Case(
      address: "https://*.example.co.jp:8443", scheme: "https", host: "example.co.jp", port: 8443,
      subdomains: true),
    Case(
      address: "http://*.example.com", scheme: "http", host: "example.com", port: 80,
      subdomains: true),
    Case(
      address: "  https://example.co.jp/path  ", scheme: "https", host: "example.co.jp", port: 443,
      subdomains: false),
    Case(
      address: "https://[::1]:19473", scheme: "https", host: "::1", port: 19473, subdomains: false),
  ])
  func resolvesDomainURLAndWildcard(_ test: Case) throws {
    let rule = try #require(OriginRuleDraft(id: 1, address: test.address).rule)
    #expect(rule.origin.scheme == test.scheme)
    #expect(rule.origin.host == test.host)
    #expect(rule.origin.port == test.port)
    #expect(rule.includeSubdomains == test.subdomains)
    #expect(OriginRuleDraft(id: 1, address: rule.inputAddress).rule == rule)
  }

  @Test(arguments: [
    "*", "*.*.example.com", "foo*.example.com", "*.127.0.0.1", "*.example..com",
    "https://user@example.com", "file:///tmp/page",
  ])
  func rejectsInvalidPatterns(_ address: String) {
    #expect(OriginRuleDraft(id: 1, address: address).rule == nil)
  }

  @Test func wildcardAllowsSubdomainStartURLWithoutSuffixLookalikes() throws {
    let rule = try #require(OriginRuleDraft(id: 1, address: "*.example.co.jp").rule)
    let policy = NavigationPolicy(rules: [rule])
    #expect(policy.evaluate("https://events.example.co.jp/exhibitions/1") == .allow)
    #expect(policy.evaluate("https://example.co.jp") == .allow)
    #expect(policy.evaluate("https://example.co.jp.attacker.invalid") == .cancel(.urlBlocked))
    #expect(policy.evaluate("https://notexample.co.jp") == .cancel(.urlBlocked))
    #expect(policy.evaluate("http://events.example.co.jp") == .cancel(.httpDisabled))
    let profile = KioskProfile(
      startURL: "https://events.example.co.jp/exhibitions/1", navigation: policy)
    let draft = ProfileDraft(profile: profile)
    #expect(draft.rules[0].address == "*.example.co.jp")
    #expect(draft.validatedProfile == profile)
  }
}
