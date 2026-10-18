import Foundation
import XCTest
import XCUIAutomation

final class SettingsCatalogUITests: XCTestCase {
  @MainActor func testDamagedCollectionCanBeReopenedInAdministration() async throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.catalog.recovery.\(UUID().uuidString)"
    app.launchEnvironment["PLINTH_TEST_ISOLATED_CREDENTIALS"] = "1"
    app.launchEnvironment["PLINTH_TEST_CORRUPT_CATALOG"] = "1"
    addTeardownBlock { await MainActor.run { app.terminate() } }
    app.launch()
    let recover = app.buttons["catalog-recover"]
    reach(recover, in: app)
    recover.tap()
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.585)).tap()
    let importer = app.buttons["catalog-import-file"]
    reach(importer, in: app)
    try await enabled(importer)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "catalog-recovery-ready-to-import"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }

  @MainActor func testExportAndImportWithLocalFiles() async throws {
    guard ProcessInfo.processInfo.environment["PLINTH_TEST_FILE_PROVIDER_UI"] == "1" else {
      throw XCTSkip(
        "Run with TEST_RUNNER_PLINTH_TEST_FILE_PROVIDER_UI=1 on a dedicated iPad Simulator")
    }
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.catalog.file.\(UUID().uuidString)"
    app.launchEnvironment["PLINTH_TEST_ISOLATED_CREDENTIALS"] = "1"
    addTeardownBlock { await MainActor.run { app.terminate() } }
    app.launch()
    try await registerSavedSettings(in: app)
    let export = app.buttons["catalog-export-all"]
    reach(export, in: app)
    try await enabled(export)
    export.tap()
    let passphrase = app.secureTextFields["catalog-export-passphrase"]
    try await exists(passphrase)
    try await enterFilePassphrase(passphrase)
    let confirm = app.secureTextFields["catalog-export-confirm-passphrase"]
    confirm.tap()
    confirm.typeText("abcdefghijklmnop")
    try await secureCount(confirm, count: 16)
    app.buttons["catalog-export-save-file"].tap()
    let files = app.cells["DOC.sidebar.item.On My iPad"]
    try await exists(files)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "catalog-files-before-save"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    app.buttons["Save"].tap()
    let replace = XCUIApplication(bundleIdentifier: "com.apple.springboard")
      .alerts["Replace Existing Item"]
    if replace.waitForExistence(timeout: 2) {
      replace.buttons["Keep Both"].tap()
    }
    let after = XCTAttachment(screenshot: app.screenshot())
    after.name = "catalog-files-after-save"
    after.lifetime = .keepAlways
    add(after)
    let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: files)
    await fulfillment(of: [closed], timeout: 10)
    let entry = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "catalog-entry-")
    ).firstMatch
    reach(entry, in: app)
    entry.tap()
    let remove = app.buttons["catalog-remove"]
    reach(remove, in: app)
    remove.tap()
    app.buttons["Remove"].tap()
    let removed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: entry)
    await fulfillment(of: [removed], timeout: 10)
    let importer = app.buttons["catalog-import-file"]
    reach(importer, in: app)
    try await enabled(importer)
    importer.tap()
    let localFiles = app.cells["DOC.sidebar.item.On My iPad"]
    try await exists(localFiles)
    localFiles.tap()
    let savedFile = app.cells.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "settings.plinthsettings")
    ).firstMatch
    try await exists(savedFile)
    savedFile.tap()
    let importPassphrase = app.secureTextFields["catalog-import-passphrase"]
    try await exists(importPassphrase)
    try await enterFilePassphrase(importPassphrase)
    app.buttons["catalog-import-review"].tap()
    try await exists(app.staticTexts["Review imported settings"])
    try await exists(
      app.staticTexts.matching(
        NSPredicate(format: "label CONTAINS %@", "https://example.com/home")
      ).firstMatch)
    let preview = XCTAttachment(screenshot: app.screenshot())
    preview.name = "catalog-imported-file-preview"
    preview.lifetime = .keepAlways
    add(preview)
    let addToCollection = app.buttons["catalog-import-confirm"]
    try await enabled(addToCollection)
    addToCollection.tap()
    try await exists(entry)
    let imported = XCTAttachment(screenshot: app.screenshot())
    imported.name = "catalog-imported-file-added"
    imported.lifetime = .keepAlways
    add(imported)
  }

  @MainActor func testSavedEntrySurvivesRestartAndLoadsIntoEditor() async throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.catalog.\(UUID().uuidString)"
    app.launchEnvironment["PLINTH_TEST_ISOLATED_CREDENTIALS"] = "1"
    addTeardownBlock { await MainActor.run { app.terminate() } }
    app.launch()
    try await registerSavedSettings(in: app)
    app.terminate()
    app.launch()
    try await unlockIfNeeded(in: app)
    try await loadSavedEntry(in: app)
  }

  @MainActor private func registerSavedSettings(in app: XCUIApplication) async throws {
    let url = app.textFields["start-url"]
    reach(url, in: app)
    url.tap()
    url.typeText("https://example.com/home\n")
    let save = app.buttons["save-profile"]
    reach(save, in: app)
    try await enabled(save)
    save.tap()
    let setup = app.secureTextFields["setup-passcode"]
    reach(setup, in: app)
    setup.tap()
    setup.typeText("plinth-mobile-passcode")
    try await secureCount(setup, count: "plinth-mobile-passcode".count)
    setup.typeText("\n")
    let savePasscode = app.buttons["save-passcode"]
    reach(savePasscode, in: app)
    try await enabled(savePasscode)
    savePasscode.tap()
    let name = app.textFields["catalog-name"]
    reach(name, in: app)
    name.tap()
    name.typeText("A\n")
    let register = app.buttons["catalog-register"]
    try await enabled(register)
    register.tap()
    try await exists(
      app.buttons.matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "catalog-entry-")
      ).firstMatch)
  }

  @MainActor private func unlockIfNeeded(in app: XCUIApplication) async throws {
    guard app.buttons["request-unlock"].exists else { return }
    app.buttons["request-unlock"].tap()
    let unlock = app.secureTextFields["unlock-passcode"]
    try await exists(unlock)
    unlock.tap()
    unlock.typeText("plinth-mobile-passcode")
    try await secureCount(unlock, count: "plinth-mobile-passcode".count)
    app.buttons["verify-passcode"].tap()
  }

  @MainActor private func loadSavedEntry(in app: XCUIApplication) async throws {
    let entry = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "catalog-entry-")
    ).firstMatch
    reach(entry, in: app)
    XCTAssertTrue(entry.label.contains("A"))
    entry.tap()
    try await exists(app.staticTexts["Contents"])
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "catalog-entry-detail"
    screenshot.lifetime = .keepAlways
    add(screenshot)
    let apply = app.buttons["catalog-apply"]
    for _ in 0..<6 where !apply.exists || !apply.isHittable {
      app.collectionViews.element(boundBy: app.collectionViews.count - 1).swipeUp()
    }
    XCTAssertTrue(apply.isHittable)
    apply.tap()
    let restoredURL = app.textFields["start-url"]
    for _ in 0..<8 where !restoredURL.exists || !restoredURL.isHittable {
      app.collectionViews.firstMatch.swipeDown()
    }
    XCTAssertTrue(restoredURL.isHittable)
    XCTAssertEqual(restoredURL.value as? String, "https://example.com/home")
  }

  @MainActor private func reach(_ element: XCUIElement, in app: XCUIApplication) {
    for _ in 0..<5 where !element.exists || !element.isHittable {
      app.collectionViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(element.isHittable)
  }

  @MainActor private func exists(_ element: XCUIElement) async throws {
    let ready = expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: element)
    await fulfillment(of: [ready], timeout: 10)
    _ = try XCTUnwrap(element.exists ? element : nil)
  }

  @MainActor private func enabled(_ element: XCUIElement) async throws {
    let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: element)
    await fulfillment(of: [ready], timeout: 15)
    _ = try XCTUnwrap(element.isEnabled ? element : nil)
  }

  @MainActor private func secureCount(_ element: XCUIElement, count: Int) async throws {
    let ready = expectation(
      for: NSPredicate(format: "value.length == %d", count), evaluatedWith: element)
    await fulfillment(of: [ready], timeout: 5)
    XCTAssertEqual((element.value as? String)?.count, count)
  }

  @MainActor private func enterFilePassphrase(_ field: XCUIElement) async throws {
    field.tap()
    field.typeText("a")
    let app = XCUIApplication()
    // iPadOS can offer an account password for this file passphrase field.
    if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 2) {
      app.buttons["xmark"].tap()
    }
    let count = (field.value as? String)?.count ?? 0
    field.tap()
    field.typeText(count == 1 ? "bcdefghijklmnop" : "abcdefghijklmnop")
    try await secureCount(field, count: 16)
  }
}
