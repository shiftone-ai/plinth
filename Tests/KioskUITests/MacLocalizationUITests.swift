import Foundation
import XCTest
import XCUIAutomation

private struct MacLanguageCase {
  let code: String
  let save: String
  let start: String
  let failure: String
}

extension KioskWorkflowUITests {
  @MainActor func testLocalizedPreviewSettingsExhibitionAndUnlock() async throws {
    guard ProcessInfo.processInfo.environment["PLINTH_DEDICATED_MAC"] == "1" else {
      throw XCTSkip("GUI tests require an explicitly enabled dedicated Mac.")
    }
    continueAfterFailure = false
    let server = try FixtureServer()
    try await server.start()
    addTeardownBlock { await MainActor.run { server.stop() } }
    let languages: [MacLanguageCase] = [
      .init(code: "ja", save: "設定を保存", start: "展示を開始", failure: "管理者パスワードが一致しません"),
      .init(
        code: "en", save: "Save settings", start: "Start exhibition",
        failure: "Incorrect administrator password"),
      .init(code: "ko", save: "설정 저장", start: "전시 시작", failure: "관리자 비밀번호가 일치하지 않습니다"),
      .init(code: "zh-Hans", save: "保存设置", start: "开始展示", failure: "管理员密码不正确"),
    ]
    for language in languages {
      await localizedWorkflow(server: server, language: language)
    }
  }

  @MainActor private func localizedWorkflow(
    server: FixtureServer, language: MacLanguageCase
  ) async {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-localization-ui-\(UUID())")
    let service = "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    let passcode = "plinth-localization-passcode"
    let app = XCUIApplication()
    app.launchArguments = ["--preview", "-AppleLanguages", "(\(language.code))"]
    app.launchEnvironment = [
      "PLINTH_TEST_PROFILE_DIRECTORY": directory.path,
      "PLINTH_TEST_CREDENTIAL_SERVICE": service,
      "PLINTH_DEDICATED_MAC": "1",
      "PLINTH_TEST_OS_PRESENTATION": "0",
    ]
    addTeardownBlock {
      await MainActor.run {
        app.terminate()
        try? FileManager.default.removeItem(at: directory)
      }
    }
    app.launch()
    if language.code == "ja" { verifyLanguagePicker(app) }
    await configure(app, origin: server.origin, passcode: passcode, language: language)
    await unlock(app, passcode: passcode, language: language)
    if language.code == "ja" {
      await verifyEnglishRelaunch(app, origin: server.origin, passcode: passcode)
    }
    app.terminate()
  }

  @MainActor private func verifyLanguagePicker(_ app: XCUIApplication) {
    let picker = app.popUpButtons["interface-language"]
    picker.click()
    app.menuItems["interface-language-en"].click()
    XCTAssertEqual(app.buttons["start-exhibition"].label, "Start exhibition")
    attach(app, name: "settings-selected-en")
    picker.click()
    app.menuItems["interface-language-system"].click()
    XCTAssertEqual(app.buttons["start-exhibition"].label, "展示を開始")
  }

  @MainActor private func configure(
    _ app: XCUIApplication, origin: String, passcode: String, language: MacLanguageCase
  ) async {
    let start = app.buttons["start-exhibition"]
    await waitFor(start, timeout: 10)
    XCTAssertEqual(start.label, language.start)
    XCTAssertEqual(app.buttons["save-profile"].label, language.save)
    attach(app, name: "settings-top-\(language.code)")
    replace(app.textFields["start-url"], with: origin + "/home")
    app.buttons["add-origin"].click()
    replace(app.textFields["origin-1"], with: origin)
    app.buttons["add-origin"].click()
    replace(app.textFields["origin-2"], with: "https://example.org")
    app.switches["allow-http"].click()
    let setup = app.secureTextFields["setup-passcode"]
    app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -500)
    replace(setup, with: passcode)
    app.buttons["save-passcode"].click()
    let save = app.buttons["save-profile"]
    let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
    await fulfillment(of: [ready], timeout: 10)
    save.click()
    let enabled = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: start)
    await fulfillment(of: [enabled], timeout: 10)
    attach(app, name: "settings-bottom-\(language.code)")
    start.click()
    await waitFor(app.webViews.links["Allowed"], timeout: 10)
  }

  @MainActor private func unlock(
    _ app: XCUIApplication, passcode: String, language: MacLanguageCase
  ) async {
    app.typeKey("k", modifierFlags: [.command, .option, .shift])
    let unlock = app.secureTextFields["unlock-passcode"]
    await waitFor(unlock)
    replace(unlock, with: "incorrect-passcode")
    app.buttons["verify-passcode"].click()
    let failure = app.staticTexts["incorrect-credential"]
    await waitFor(failure, timeout: 10)
    XCTAssertEqual(failure.label, language.failure)
    attach(app, name: "unlock-\(language.code)")
    app.buttons["cancel-unlock"].click()
    await waitFor(app.webViews.links["Allowed"], timeout: 10)
    app.typeKey("k", modifierFlags: [.command, .option, .shift])
    await waitFor(unlock)
    replace(unlock, with: passcode)
    app.buttons["verify-passcode"].click()
    let start = app.buttons["start-exhibition"]
    await waitFor(start, timeout: 10)
    XCTAssertEqual(start.label, language.start)
  }

  @MainActor private func verifyEnglishRelaunch(
    _ app: XCUIApplication, origin: String, passcode: String
  ) async {
    app.terminate()
    app.launchArguments = ["--preview", "-AppleLanguages", "(en)"]
    app.launch()
    await waitFor(app.webViews.links["Allowed"], timeout: 10)
    app.typeKey("k", modifierFlags: [.command, .option, .shift])
    let unlock = app.secureTextFields["unlock-passcode"]
    await waitFor(unlock)
    replace(unlock, with: passcode)
    app.buttons["verify-passcode"].click()
    let start = app.buttons["start-exhibition"]
    await waitFor(start, timeout: 10)
    XCTAssertEqual(start.label, "Start exhibition")
    XCTAssertEqual(app.textFields["start-url"].value as? String, origin + "/home")
  }
}
