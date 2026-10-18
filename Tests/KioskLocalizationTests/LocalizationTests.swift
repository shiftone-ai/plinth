import Foundation
import KioskCore
import KioskLocalization
import KioskPresentation
import Testing

struct LocalizationTests {
  @Test(arguments: [
    ("zh-Hans", "zh-Hans"),
    ("zh-CN", "zh-Hans"),
    ("zh-Hant", "en"),
    ("ja-JP", "ja"),
  ])
  func publicPageLanguageMatchesInterface(language: String, expected: String) {
    #expect(L10n.languageCode(for: Locale(identifier: language)) == expected)
  }

  @Test @MainActor func screenLanguageChoicePersistsAndCanReturnToSystem() throws {
    let suite = "ai.shiftone.plinth.tests.language.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = LanguagePreference(defaults: defaults)
    #expect(first.selection == .system)
    first.select(.korean)
    #expect(L10n.string("Save settings", locale: first.locale) == "설정 저장")
    let relaunched = LanguagePreference(defaults: defaults)
    #expect(relaunched.selection == .korean)
    relaunched.select(.system)
    #expect(LanguagePreference(defaults: defaults).selection == .system)
  }

  @Test(arguments: [
    ("ja", "設定を保存"),
    ("en", "Save settings"),
    ("ko", "설정 저장"),
    ("zh-Hans", "保存设置"),
    ("zh-CN", "保存设置"),
    ("zh-TW", "Save settings"),
    ("fr", "Save settings"),
  ])
  func settingsActionUsesTheSelectedLocale(language: String, expected: String) {
    #expect(L10n.string("Save settings", locale: Locale(identifier: language)) == expected)
  }

  @Test func missingTranslationFallsBackToEnglishKey() {
    #expect(
      L10n.string("Missing translation", locale: Locale(identifier: "ko")) == "Missing translation")
  }

  @Test(arguments: [
    ("ja", "開始URLが閲覧先のルールで許可されていません"),
    ("en", "The start URL is not allowed by the navigation rules"),
    ("ko", "시작 URL이 탐색 규칙에서 허용되지 않습니다"),
    ("zh-Hans", "起始 URL 未被浏览规则允许"),
    ("fr", "The start URL is not allowed by the navigation rules"),
  ])
  func invalidStartURLMessageUsesTheSelectedLocale(language: String, expected: String) throws {
    var root = RootState()
    root.mode = .administration
    var administration = AdministrationState()
    administration.draft = ProfileDraft(
      profile: KioskProfile(startURL: "", navigation: .init(rules: [])))
    let message = try #require(
      Presenters.settings(root, administration).validationMessages.first {
        $0.id == .homeNotAllowed
      })
    #expect(L10n.string(message.textKey, locale: Locale(identifier: language)) == expected)
  }

  @Test func presenterInputErrorsResolveToEnglishAndJapanese() throws {
    var administration = AdministrationState()
    var draft = ProfileDraft(
      profile: KioskProfile(
        schemaVersion: 2, revision: 0, startURL: "http://example.com",
        navigation: .init(rules: []), recovery: .init(maximumAttempts: -1),
        externalDisplayMode: .init(width: 0, height: 1080)))
    draft.idleTimeoutText = "0"
    draft.rules = [.init(id: 1, address: "https://not a domain")]
    administration.draft = draft
    var root = RootState()
    root.mode = .administration
    let messages = Dictionary(
      uniqueKeysWithValues: Presenters.settings(root, administration).validationMessages.map {
        ($0.id, $0.textKey)
      })
    for (issue, english, japanese) in [
      (ProfileIssue.unsupportedSchema, "Could not read the settings format", "設定の形式を読み込めません"),
      (.invalidRevision, "Could not read settings", "設定を読み込めません"),
      (.invalidNavigationRules, "Check the domain", "ドメインを確認してください"),
      (
        .homeNotAllowed, "The start URL is not allowed by the navigation rules",
        "開始URLが閲覧先のルールで許可されていません"
      ),
      (.invalidIdleTimeout, "Enter an idle time greater than zero", "無操作の秒数は0より大きい数で入力してください"),
      (.invalidRecoveryPolicy, "Check retry count and interval", "再試行の回数・間隔を確認してください"),
      (.invalidDisplayMode, "Check the resolution", "解像度を確認してください"),
    ] {
      let key = try #require(messages[issue])
      #expect(L10n.string(key, locale: Locale(identifier: "en")) == english)
      #expect(L10n.string(key, locale: Locale(identifier: "ja")) == japanese)
    }
    root.savedProfile = KioskProfile(
      revision: UInt64.max, startURL: "https://example.com", navigation: .init(rules: []))
    let saveLimit = try #require(
      Presenters.settings(root, administration).validationMessages.first {
        $0.id == .invalidRevision
      })
    #expect(
      L10n.string(saveLimit.textKey, locale: Locale(identifier: "en"))
        == "Settings have reached the save limit")
    #expect(
      L10n.string(saveLimit.textKey, locale: Locale(identifier: "ja"))
        == "設定の保存回数が上限に達しています")
  }
}
