import Foundation
import XCTest
import XCUIAutomation

extension MobileWorkflowUITests {
  @MainActor func testSystemSettingsListsAppLanguages() async throws {
    continueAfterFailure = false
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.launch()
    addTeardownBlock { await MainActor.run { settings.terminate() } }
    let apps = settings.staticTexts["Apps"]
    XCTAssertTrue(apps.waitForExistence(timeout: 10), settings.debugDescription)
    apps.tap()
    let search = settings.searchFields["Search Apps"]
    XCTAssertTrue(search.waitForExistence(timeout: 10), settings.debugDescription)
    search.tap()
    search.typeText("Plinth\n")
    let plinth = settings.staticTexts["Plinth"]
    XCTAssertTrue(plinth.waitForExistence(timeout: 10), settings.debugDescription)
    plinth.tap()
    let language = settings.staticTexts["Language"]
    XCTAssertTrue(language.waitForExistence(timeout: 10), settings.debugDescription)
    language.tap()
    for name in ["English", "日本語", "한국어", "简体中文"] {
      XCTAssertTrue(
        settings.staticTexts[name].waitForExistence(timeout: 10), settings.debugDescription)
    }
    attach(settings, "ios-settings-language-options")
    // Apple's Settings app does not provide an identifier for this language row.
    // swiftlint:disable:next ui_test_japanese_element_lookup
    settings.staticTexts["日本語"].tap()
    attach(settings, "ios-settings-japanese-selected")
    settings.staticTexts["English"].tap()
  }

  @MainActor func testUnsupportedLanguageFallsBackToEnglish() async throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(fr)", "-NSShowNonLocalizedStrings", "YES"]
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    addTeardownBlock { await MainActor.run { app.terminate() } }
    app.launch()
    let start = app.buttons["start-exhibition"]
    try await exists(start)
    XCTAssertEqual(start.label, "Start exhibition")
    XCTAssertEqual(app.buttons["save-profile"].label, "Save settings")
    attach(app, "unsupported-language-en")
  }

  @MainActor func testDoubleLocalizationKeepsSettingsControlsReachable() async throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-NSDoubleLocalizedStrings", "YES"]
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    addTeardownBlock { await MainActor.run { app.terminate() } }
    app.launch()
    let start = app.buttons["start-exhibition"]
    try await exists(start)
    XCTAssertGreaterThan(start.label.count, "Start exhibition".count)
    let language = app.buttons["interface-language"]
    reach(language, app: app)
    XCTAssertTrue(language.isHittable)
    let biometric = app.switches["biometric-unlock"]
    reach(biometric, app: app)
    XCTAssertTrue(biometric.isHittable)
    attach(app, "double-localization-portrait")
    XCUIDevice.shared.orientation = .landscapeLeft
    defer { XCUIDevice.shared.orientation = .portrait }
    for _ in 0..<25 {
      if app.frame.width > app.frame.height { break }
      try await Task.sleep(for: .milliseconds(200))
    }
    XCTAssertGreaterThan(app.frame.width, app.frame.height)
    try await exists(app.buttons["start-exhibition"])
    reach(biometric, app: app)
    XCTAssertTrue(biometric.isHittable)
    try await Task.sleep(for: .seconds(2))
    let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screen.name = "double-localization-landscape"
    screen.lifetime = .keepAlways
    add(screen)
  }

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
    attach(app, "language-selected-zh-Hans")
    try await configureExhibition(
      app, origin: server.origin, language: "selected-zh-Hans",
      controlTitles: (save: "保存设置", start: "开始展示"))
    try await unlockExhibition(
      app, language: "selected-zh-Hans", incorrectPasscode: "管理员密码不正确",
      controlTitles: (start: "开始展示", unlock: "管理员解锁"))
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
    XCTAssertEqual(app.buttons["start-exhibition"].label, "开始展示")
    XCTAssertEqual(app.textFields["start-url"].value as? String, server.origin + "/home")
    app.buttons["interface-language"].tap()
    app.buttons["interface-language-system"].tap()
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
    for (identifier, start) in [
      ("interface-language-en", "Start exhibition"),
      ("interface-language-ko", "전시 시작"),
      ("interface-language-zh-Hans", "开始展示"),
    ] {
      picker.tap()
      app.buttons[identifier].tap()
      XCTAssertEqual(app.buttons["start-exhibition"].label, start)
    }
  }

  @MainActor func testLocalizedSettingsExhibitionAndUnlock() async throws {
    continueAfterFailure = false
    let server = try FixtureServer()
    try await server.start()
    addTeardownBlock { await MainActor.run { server.stop() } }
    let languages = [
      ("ja", "設定を保存", "展示を開始", "管理者パスワードが一致しません", "管理者解除"),
      (
        "en", "Save settings", "Start exhibition", "Incorrect administrator password",
        "Administrator unlock"
      ),
      ("ko", "설정 저장", "전시 시작", "관리자 비밀번호가 일치하지 않습니다", "관리자 잠금 해제"),
      ("zh-Hans", "保存设置", "开始展示", "管理员密码不正确", "管理员解锁"),
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

  @MainActor func testExternalDisplayAccessibilityUsesSelectedLanguage() async throws {
    continueAfterFailure = false
    let server = try FixtureServer()
    try await server.start()
    addTeardownBlock { await MainActor.run { server.stop() } }
    let cases = [
      ("en", "Save settings", "Start exhibition", "External display controls", "Exhibiting"),
      ("ja", "設定を保存", "展示を開始", "外部展示の操作", "展示中"),
      ("ko", "설정 저장", "전시 시작", "외부 전시 제어", "전시 중"),
      ("zh-Hans", "保存设置", "开始展示", "外接显示器控制", "展示中"),
    ]
    for (language, save, start, control, active) in cases {
      let app = XCUIApplication()
      app.launchArguments = ["-AppleLanguages", "(\(language))"]
      app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
        "ai.shiftone.plinth.tests.\(UUID().uuidString)"
      addTeardownBlock { await MainActor.run { app.terminate() } }
      app.launch()
      try await configureExhibition(
        app, origin: server.origin, language: "external-\(language)",
        controlTitles: (save: save, start: start), external: true)
      let controls = app.otherElements["external-control"]
      try await exists(controls)
      XCTAssertEqual(controls.label, control)
      let status = app.descendants(matching: .any)["external-exhibition-active"]
      try await exists(status)
      XCTAssertEqual(status.label, active)
      attach(app, "external-accessibility-\(language)")
      app.terminate()
    }
  }

  @MainActor func testVoiceOverSpeechInSimulator() async throws {
    guard #available(iOS 27.0, *) else { throw XCTSkip("VoiceOver UI testing requires iOS 27") }
    continueAfterFailure = false
    let server = try FixtureServer()
    try await server.start()
    addTeardownBlock { await MainActor.run { server.stop() } }
    let cases = [
      (
        "en", "Save settings", "Start exhibition", "External display controls", "Exhibiting",
        "Administrator unlock"
      ),
      ("ja", "設定を保存", "展示を開始", "外部展示の操作", "展示中", "管理者解除"),
      ("ko", "설정 저장", "전시 시작", "외부 전시 제어", "전시 중", "관리자 잠금 해제"),
      ("zh-Hans", "保存设置", "开始展示", "外接显示器控制", "展示中", "管理员解锁"),
    ]
    for (language, save, start, control, active, unlock) in cases {
      let app = XCUIApplication()
      app.launchArguments = ["-AppleLanguages", "(\(language))"]
      app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
        "ai.shiftone.plinth.tests.\(UUID().uuidString)"
      addTeardownBlock { await MainActor.run { app.terminate() } }
      app.launch()
      try await configureExhibition(
        app, origin: server.origin, language: "voiceover-\(language)",
        controlTitles: (save: save, start: start), external: true)
      let speech = try spokenExternalOutput(app, control: control, active: active, unlock: unlock)
      print("VOICEOVER_\(language)=\(speech.joined(separator: " | "))")
      app.terminate()
    }
  }

  @MainActor @available(iOS 27.0, *)
  private func spokenExternalOutput(
    _ app: XCUIApplication, control: String, active: String, unlock: String
  ) throws -> [String] {
    let voiceOver = XCUIDevice.shared.voiceOverService
    try voiceOver.enable()
    defer { try? voiceOver.disable() }
    XCTAssertTrue(voiceOver.isEnabled, voiceOver.debugDescription)
    app.activate()
    var speech: [String] = []
    for _ in 0..<50 {
      let utterance = try voiceOver.moveForward().utterance
      speech.append(utterance)
      if speech.contains(where: { $0.contains(control) })
        && speech.contains(where: { $0.contains(active) })
        && speech.contains(where: { $0.contains(unlock) })
      {
        break
      }
    }
    XCTAssertTrue(speech.contains { $0.contains(control) }, speech.joined(separator: " | "))
    XCTAssertTrue(speech.contains { $0.contains(active) }, speech.joined(separator: " | "))
    XCTAssertTrue(speech.contains { $0.contains(unlock) }, speech.joined(separator: " | "))
    return speech
  }

  @MainActor func configureExhibition(
    _ app: XCUIApplication, origin: String, language: String,
    controlTitles: (save: String, start: String), external: Bool = false
  ) async throws {
    let start = app.buttons["start-exhibition"]
    try await exists(start)
    XCTAssertEqual(start.label, controlTitles.start)
    XCTAssertEqual(app.buttons["save-profile"].label, controlTitles.save)
    if external {
      app.buttons["exhibition-destination"].tap()
      app.buttons["exhibition-destination-external"].tap()
      if app.buttons["prepare-external-scene"].exists {
        throw XCTSkip("Requires an automatically connected external display scene")
      }
    }
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
    setup.typeText("plinth-localization-passcode")
    try await secureValue(setup, count: "plinth-localization-passcode".count)
    setup.typeText("\n")
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
    try await secureValue(unlock, count: "wrong-passcode".count)
    app.buttons["verify-passcode"].tap()
    let failure = app.staticTexts["incorrect-credential"]
    try await exists(failure)
    XCTAssertEqual(failure.label, incorrectPasscode)
    attach(app, "unlock-\(language)")
    app.buttons["cancel-unlock"].tap()
    try await exists(app.webViews.links["Allowed"])
    app.buttons["request-unlock"].tap()
    try await exists(unlock)
    unlock.tap()
    unlock.typeText("plinth-localization-passcode")
    try await secureValue(unlock, count: "plinth-localization-passcode".count)
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
