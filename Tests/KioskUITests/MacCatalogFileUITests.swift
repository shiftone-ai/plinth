import Foundation
import XCTest
import XCUIAutomation

extension KioskWorkflowUITests {
  @MainActor func testSettingsCollectionUsesMacFilePanels() async throws {
    guard ProcessInfo.processInfo.environment["PLINTH_DEDICATED_MAC"] == "1",
      ProcessInfo.processInfo.environment["PLINTH_TEST_FILE_PROVIDER_UI"] == "1"
    else { throw XCTSkip("Run on a dedicated Mac with file panel testing enabled.") }
    continueAfterFailure = false
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-catalog-mac-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let exported = directory.appendingPathComponent("settings.plinthsettings")
    let app = XCUIApplication()
    app.launchArguments = ["--preview", "-AppleLanguages", "(en)"]
    app.launchEnvironment = [
      "PLINTH_TEST_PROFILE_DIRECTORY": directory.path,
      "PLINTH_TEST_CREDENTIAL_SERVICE": "ai.shiftone.plinth.tests.catalog.\(UUID().uuidString)",
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
    try await prepareMacCatalog(in: app)
    try await exportMacCatalog(from: app, to: exported, directory: directory)
    try await importMacCatalog(into: app, from: exported)
  }

  @MainActor private func prepareMacCatalog(in app: XCUIApplication) async throws {
    await waitFor(app.textFields["start-url"], timeout: 10)
    replace(app.textFields["start-url"], with: "https://example.com/home")
    let setup = app.secureTextFields["setup-passcode"]
    if !setup.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -800) }
    replace(setup, with: "plinth-mac-catalog-passcode")
    app.buttons["save-passcode"].click()
    let save = app.buttons["save-profile"]
    let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
    await fulfillment(of: [ready], timeout: 10)
    save.click()
    let name = app.textFields["catalog-name"]
    if !name.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -800) }
    replace(name, with: "Mac File Verification")
    app.buttons["catalog-register"].click()
    let entry = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "catalog-entry-")
    ).firstMatch
    await waitFor(entry, timeout: 10)
  }

  @MainActor private func exportMacCatalog(
    from app: XCUIApplication, to exported: URL, directory: URL
  ) async throws {
    let passphrase = app.secureTextFields["catalog-passphrase"]
    if !passphrase.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -800) }
    replace(passphrase, with: "abcdefghijklmnop")
    replace(app.secureTextFields["catalog-confirm-passphrase"], with: "abcdefghijklmnop")
    let export = app.buttons["catalog-export-all"]
    let canExport = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: export)
    await fulfillment(of: [canExport], timeout: 10)
    export.click()
    await waitFor(app.buttons["Save"], timeout: 10)
    attach(app, name: "mac-catalog-save-panel")
    app.typeKey("g", modifierFlags: [.command, .shift])
    app.typeText(directory.path)
    app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
    app.buttons["Save"].click()
    let saved = expectation(
      for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: exported.path) },
      evaluatedWith: self)
    await fulfillment(of: [saved], timeout: 10)
    XCTAssertGreaterThan(try Data(contentsOf: exported).count, 100)
  }

  @MainActor private func importMacCatalog(into app: XCUIApplication, from exported: URL)
    async throws
  {
    let passphrase = app.secureTextFields["catalog-passphrase"]
    replace(passphrase, with: "abcdefghijklmnop")
    let importer = app.buttons["catalog-import-file"]
    let canImport = expectation(
      for: NSPredicate(format: "enabled == true"), evaluatedWith: importer)
    await fulfillment(of: [canImport], timeout: 10)
    importer.click()
    await waitFor(app.buttons["Open"], timeout: 10)
    attach(app, name: "mac-catalog-open-panel")
    app.typeKey("g", modifierFlags: [.command, .shift])
    app.typeText(exported.path)
    app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
    app.buttons["Open"].click()
    await waitFor(app.staticTexts["Review imported settings"], timeout: 10)
    XCTAssertTrue(app.staticTexts["https://example.com/home"].exists)
    attach(app, name: "mac-catalog-import-preview")
    app.buttons["Cancel"].click()
  }
}
