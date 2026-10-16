import Foundation
import XCTest
import XCUIAutomation

private struct MacLanguageCase {
  let code: String
  let save: String
  let start: String
  let failure: String
}

private struct MacMenuCase {
  let code: String
  let edit: String
  let quit: String
  let commands: [String]
}

extension KioskWorkflowUITests {
  @MainActor func testMacLocalizationDiagnosticArguments() throws {
    guard ProcessInfo.processInfo.environment["PLINTH_DEDICATED_MAC"] == "1" else {
      throw XCTSkip("GUI tests require an explicitly enabled dedicated Mac.")
    }
    for option in ["-NSShowNonLocalizedStrings", "-NSDoubleLocalizedStrings"] {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "plinth-localization-diagnostic-\(UUID())")
      let app = XCUIApplication()
      app.launchArguments = ["--preview", "-AppleLanguages", "(en)", option, "YES"]
      app.launchEnvironment = [
        "PLINTH_TEST_PROFILE_DIRECTORY": directory.path,
        "PLINTH_TEST_CREDENTIAL_SERVICE": "ai.shiftone.plinth.tests.\(UUID().uuidString)",
        "PLINTH_DEDICATED_MAC": "1",
        "PLINTH_TEST_OS_PRESENTATION": "0",
      ]
      app.launch()
      let start = app.buttons["start-exhibition"]
      XCTAssertTrue(start.waitForExistence(timeout: 5), option)
      if start.exists {
        if option == "-NSDoubleLocalizedStrings" {
          XCTAssertGreaterThan(start.label.count, "Start exhibition".count)
        } else {
          XCTAssertEqual(start.label, "Start exhibition")
        }
        XCTAssertTrue(app.popUpButtons["interface-language"].isHittable)
        attach(app, name: "mac-\(option)-top")
        app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -500)
        XCTAssertTrue(app.switches["biometric-unlock"].isHittable)
        XCTAssertTrue(start.isHittable)
        attach(app, name: "mac-\(option)-bottom")
      }
      app.terminate()
      try? FileManager.default.removeItem(at: directory)
    }
  }

  @MainActor func testLocalizedMacMenus() throws {
    guard ProcessInfo.processInfo.environment["PLINTH_DEDICATED_MAC"] == "1" else {
      throw XCTSkip("GUI tests require an explicitly enabled dedicated Mac.")
    }
    let cases: [MacMenuCase] = [
      .init(
        code: "ja", edit: "編集", quit: "Plinthを終了",
        commands: ["取り消す", "切り取り", "コピー", "貼り付け", "すべて選択"]),
      .init(
        code: "en", edit: "Edit", quit: "Quit Plinth",
        commands: ["Undo", "Cut", "Copy", "Paste", "Select All"]),
      .init(
        code: "ko", edit: "편집", quit: "Plinth 종료",
        commands: ["실행 취소", "잘라내기", "복사", "붙여넣기", "모두 선택"]),
      .init(
        code: "zh-Hans", edit: "编辑", quit: "退出 Plinth",
        commands: ["撤销", "剪切", "复制", "粘贴", "全选"]),
    ]
    for language in cases {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "plinth-menu-ui-\(UUID())")
      let app = XCUIApplication()
      app.launchArguments = ["--preview", "-AppleLanguages", "(\(language.code))"]
      app.launchEnvironment = [
        "PLINTH_TEST_PROFILE_DIRECTORY": directory.path,
        "PLINTH_TEST_CREDENTIAL_SERVICE": "ai.shiftone.plinth.tests.\(UUID().uuidString)",
        "PLINTH_DEDICATED_MAC": "1",
        "PLINTH_TEST_OS_PRESENTATION": "0",
      ]
      app.launch()
      let menuBar = app.menuBars.firstMatch
      XCTAssertTrue(menuBar.waitForExistence(timeout: 5))
      let edit = menuBar.menuBarItems[language.edit]
      XCTAssertTrue(edit.exists)
      if edit.exists {
        edit.click()
        for title in language.commands {
          XCTAssertTrue(app.menuItems[title].exists, "Missing \(title) in \(language.code)")
        }
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
      }
      let application = menuBar.menuBarItems["Plinth"]
      XCTAssertTrue(application.exists)
      if application.exists {
        application.click()
        XCTAssertTrue(app.menuItems[language.quit].exists)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
      }
      app.terminate()
      try? FileManager.default.removeItem(at: directory)
    }
  }

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
    XCTAssertEqual(failure.value as? String, language.failure)
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
