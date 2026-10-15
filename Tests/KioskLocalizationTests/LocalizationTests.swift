import Foundation
import KioskCore
import KioskLocalization
import KioskPresentation
import Testing

struct LocalizationTests {
  @Test @MainActor func screenLanguageChoicePersistsAndCanReturnToSystem() throws {
    let suite = "ai.shiftone.plinth.tests.language.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = LanguagePreference(defaults: defaults)
    #expect(first.selection == .system)
    first.select(.korean)
    #expect(L10n.string("設定を保存", locale: first.locale) == "설정 저장")
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
    ("zh-Hant", "儲存設定"),
    ("zh-CN", "保存设置"),
    ("zh-TW", "儲存設定"),
    ("fr", "設定を保存"),
  ])
  func settingsActionUsesTheSelectedLocale(language: String, expected: String) {
    #expect(L10n.string("設定を保存", locale: Locale(identifier: language)) == expected)
  }

  @Test func missingTranslationFallsBackToJapanese() {
    #expect(L10n.string("未翻訳の文言", locale: Locale(identifier: "en")) == "未翻訳の文言")
  }

  @Test(arguments: [
    ("ja", "開始URLが閲覧先のルールで許可されていません"),
    ("en", "The start URL is not allowed by the navigation rules"),
    ("ko", "시작 URL이 탐색 규칙에서 허용되지 않습니다"),
    ("zh-Hans", "起始 URL 未被浏览规则允许"),
    ("zh-Hant", "起始 URL 不符合瀏覽規則"),
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
}
