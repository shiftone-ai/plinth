import Foundation
import XCTest
import XCUIAutomation

extension MobileWorkflowUITests {
  @MainActor func testOnScreenLanguageChoicePersistsWithSavedSetup() async throws {
    continueAfterFailure = false
    let server = try FixtureServer()
    try await server.start()
    addTeardownBlock { await MainActor.run { server.stop() } }
    let service = "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(ja)"]
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] = service
    addTeardownBlock { await MainActor.run { app.terminate() } }
    app.launch()
    try await selectEachLanguage(app)
    attach(app, "language-selected-zh-Hant")
    try await configureExhibition(
      app, origin: server.origin, language: "selected-zh-Hant",
      controlTitles: (save: "儲存設定", start: "開始展示"))
    try await unlockExhibition(
      app, language: "selected-zh-Hant", incorrectPasscode: "密碼不正確",
      controlTitles: (start: "開始展示", unlock: "管理員解鎖"))
    app.terminate()
    app.launch()
    try await exists(app.webViews.links["Allowed"])
    app.buttons["request-unlock"].tap()
    let unlock = app.secureTextFields["unlock-passcode"]
    try await exists(unlock)
    unlock.tap()
    unlock.typeText("plinth-localization-passcode")
    app.buttons["verify-passcode"].tap()
    try await exists(app.buttons["start-exhibition"])
    XCTAssertEqual(app.buttons["start-exhibition"].label, "開始展示")
    XCTAssertEqual(app.textFields["start-url"].value as? String, server.origin + "/home")
    app.buttons["interface-language"].tap()
    app.buttons["跟隨系統"].tap()
    XCTAssertEqual(app.buttons["start-exhibition"].label, "展示を開始")
    app.terminate()
    app.launch()
    try await exists(app.webViews.links["Allowed"])
    app.buttons["request-unlock"].tap()
    try await exists(unlock)
    unlock.tap()
    unlock.typeText("plinth-localization-passcode")
    app.buttons["verify-passcode"].tap()
    try await exists(app.buttons["start-exhibition"])
    XCTAssertEqual(app.buttons["start-exhibition"].label, "展示を開始")
  }

  @MainActor private func selectEachLanguage(_ app: XCUIApplication) async throws {
    let picker = app.buttons["interface-language"]
    try await exists(picker)
    for (name, start) in [
      ("English", "Start exhibition"),
      ("한국어", "전시 시작"),
      ("简体中文", "开始展示"),
      ("繁體中文", "開始展示"),
    ] {
      picker.tap()
      app.buttons[name].tap()
      XCTAssertEqual(app.buttons["start-exhibition"].label, start)
    }
  }

  @MainActor func testLocalizedSettingsExhibitionAndUnlock() async throws {
    continueAfterFailure = false
    let server = try FixtureServer()
    try await server.start()
    addTeardownBlock { await MainActor.run { server.stop() } }
    let languages = [
      ("ja", "設定を保存", "展示を開始", "パスコードが一致しません", "管理者解除"),
      ("en", "Save settings", "Start exhibition", "Incorrect passcode", "Administrator unlock"),
      ("ko", "설정 저장", "전시 시작", "암호가 일치하지 않습니다", "관리자 잠금 해제"),
      ("zh-Hans", "保存设置", "开始展示", "密码不正确", "管理员解锁"),
      ("zh-Hant", "儲存設定", "開始展示", "密碼不正確", "管理員解鎖"),
    ]
    for (language, saveTitle, startTitle, incorrectPasscode, unlockTitle) in languages {
      let service = "ai.shiftone.plinth.tests.\(UUID().uuidString)"
      let app = XCUIApplication()
      app.launchArguments = ["-AppleLanguages", "(\(language))"]
      app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] = service
      addTeardownBlock { await MainActor.run { app.terminate() } }
      app.launch()
      try await configureExhibition(
        app, origin: server.origin, language: language,
        controlTitles: (save: saveTitle, start: startTitle))
      try await unlockExhibition(
        app, language: language, incorrectPasscode: incorrectPasscode,
        controlTitles: (start: startTitle, unlock: unlockTitle))
      app.terminate()
      if language == "ja" {
        try await verifyEnglishRelaunch(service: service, origin: server.origin)
      }
    }
  }

  @MainActor private func configureExhibition(
    _ app: XCUIApplication, origin: String, language: String,
    controlTitles: (save: String, start: String)
  ) async throws {
    let start = app.buttons["start-exhibition"]
    try await exists(start)
    XCTAssertEqual(start.label, controlTitles.start)
    XCTAssertEqual(app.buttons["save-profile"].label, controlTitles.save)
    let url = app.textFields["start-url"]
    url.tap()
    url.typeText(origin + "/home\n")
    app.buttons["add-origin"].tap()
    let domain = app.textFields["origin-1"]
    domain.tap()
    domain.typeText(origin + "\n")
    app.buttons["add-origin"].tap()
    let secondDomain = app.textFields["origin-2"]
    secondDomain.tap()
    secondDomain.typeText("https://example.org\n")
    let http = app.switches["allow-http"]
    reach(http, app: app)
    http.switches.firstMatch.tap()
    let setup = app.secureTextFields["setup-passcode"]
    reach(setup, app: app)
    setup.tap()
    setup.typeText("plinth-localization-passcode\n")
    let savePasscode = app.buttons["save-passcode"]
    reach(savePasscode, app: app)
    savePasscode.tap()
    let save = app.buttons["save-profile"]
    try await enabled(save)
    attach(app, "settings-\(language)")
    save.tap()
    try await enabled(start)
    start.tap()
    try await exists(app.webViews.links["Allowed"])
  }

  @MainActor private func unlockExhibition(
    _ app: XCUIApplication, language: String, incorrectPasscode: String,
    controlTitles: (start: String, unlock: String)
  ) async throws {
    let requestUnlock = app.buttons["request-unlock"]
    XCTAssertEqual(requestUnlock.label, controlTitles.unlock)
    requestUnlock.tap()
    let unlock = app.secureTextFields["unlock-passcode"]
    try await exists(unlock)
    unlock.tap()
    unlock.typeText("wrong-passcode")
    app.buttons["verify-passcode"].tap()
    try await exists(app.staticTexts[incorrectPasscode])
    attach(app, "unlock-\(language)")
    app.buttons["cancel-unlock"].tap()
    try await exists(app.webViews.links["Allowed"])
    app.buttons["request-unlock"].tap()
    try await exists(unlock)
    unlock.tap()
    unlock.typeText("plinth-localization-passcode")
    app.buttons["verify-passcode"].tap()
    let start = app.buttons["start-exhibition"]
    try await exists(start)
    XCTAssertEqual(start.label, controlTitles.start)
  }

  @MainActor private func verifyEnglishRelaunch(service: String, origin: String) async throws {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)"]
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] = service
    addTeardownBlock { await MainActor.run { app.terminate() } }
    app.launch()
    try await exists(app.webViews.links["Allowed"])
    app.buttons["request-unlock"].tap()
    let unlock = app.secureTextFields["unlock-passcode"]
    try await exists(unlock)
    unlock.tap()
    unlock.typeText("plinth-localization-passcode")
    app.buttons["verify-passcode"].tap()
    try await exists(app.buttons["start-exhibition"])
    XCTAssertEqual(app.buttons["start-exhibition"].label, "Start exhibition")
    XCTAssertEqual(app.textFields["start-url"].value as? String, origin + "/home")
    app.terminate()
  }
}
