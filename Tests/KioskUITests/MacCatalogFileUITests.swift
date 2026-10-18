import Foundation
import XCTest
import XCUIAutomation

extension KioskWorkflowUITests {
  @MainActor func testSettingsCollectionUsesMacFilePanels() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["PLINTH_DEDICATED_MAC"] == "1" else {
      throw XCTSkip("Enable the dedicated Mac UI test scheme.")
    }
    guard environment["PLINTH_TEST_FILE_PROVIDER_UI"] == "1" else {
      throw XCTSkip("Enable file panel UI testing.")
    }
    guard
      environment["PLINTH_TEST_MAC_BUNDLE_ID"]?.hasPrefix("ai.shiftone.plinth.tests.")
        == true
    else { throw XCTSkip("Use an isolated Mac test bundle ID.") }
    continueAfterFailure = false
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "plinth-catalog-mac-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let exported = directory.appendingPathComponent("settings.plinthsettings")
    let app = XCUIApplication()
    app.launchArguments = ["--preview", "-AppleLanguages", "(en)"]
    app.launchEnvironment = [
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
    try await removeMacCatalogEntry(in: app)
    try await importMacCatalog(into: app, from: exported)
  }

  @MainActor private func prepareMacCatalog(in app: XCUIApplication) async throws {
    let startURL = app.textFields["start-url"]
    await waitFor(startURL, timeout: 10)
    replace(startURL, with: "https://example.com/home")
    if startURL.value as? String != "https://example.com/home" {
      replace(startURL, with: "https://example.com/home")
    }
    XCTAssertEqual(startURL.value as? String, "https://example.com/home")
    app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -500)
    let setup = app.secureTextFields["setup-passcode"]
    XCTAssertTrue(setup.isHittable)
    replace(setup, with: "plinth-mac-catalog-passcode")
    app.buttons["save-passcode"].click()
    let save = app.buttons["save-profile"]
    let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: save)
    await fulfillment(of: [ready], timeout: 10)
    save.click()
    let name = app.textFields["catalog-name"]
    if !name.isHittable { app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -800) }
    replace(name, with: "Mac File Verification")
    app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: [])
    app.buttons["catalog-register"].click()
    let entry = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "catalog-entry-")
    ).firstMatch
    await waitFor(entry, timeout: 10)
  }

  @MainActor private func exportMacCatalog(
    from app: XCUIApplication, to exported: URL, directory: URL
  ) async throws {
    let entry = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "catalog-entry-")
    ).firstMatch
    await waitFor(entry, timeout: 10)
    entry.click()
    let export = app.buttons["catalog-export-item"]
    if !export.isHittable {
      app.sheets.firstMatch.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -800)
    }
    let canExport = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: export)
    await fulfillment(of: [canExport], timeout: 10)
    export.click()
    let passphrase = app.secureTextFields["catalog-export-passphrase"]
    await waitFor(passphrase, timeout: 10)
    replace(passphrase, with: "abcdefghijklmnop")
    replace(
      app.secureTextFields["catalog-export-confirm-passphrase"], with: "abcdefghijklmnop")
    app.buttons["catalog-export-save-file"].click()
    let confirm = app.sheets.firstMatch.buttons["OKButton"]
    await waitFor(confirm, timeout: 10)
    attach(app, name: "mac-catalog-save-panel")
    app.typeKey("g", modifierFlags: [.command, .shift])
    app.typeText(directory.path)
    app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
    confirm.click()
    let saved = expectation(
      for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: exported.path) },
      evaluatedWith: self)
    await fulfillment(of: [saved], timeout: 10)
    XCTAssertGreaterThan(try Data(contentsOf: exported).count, 100)
  }

  @MainActor private func removeMacCatalogEntry(in app: XCUIApplication) async throws {
    let entry = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "catalog-entry-")
    ).firstMatch
    await waitFor(entry, timeout: 10)
    entry.click()
    attach(app, name: "mac-catalog-entry-detail")
    let remove = app.buttons["catalog-remove"]
    if !remove.isHittable {
      app.sheets.firstMatch.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -600)
    }
    remove.click()
    app.buttons["action-button-1"].click()
    let removed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: entry)
    await fulfillment(of: [removed], timeout: 10)
  }

  @MainActor private func importMacCatalog(into app: XCUIApplication, from exported: URL)
    async throws
  {
    app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -500)
    let importer = app.buttons["catalog-import-file"]
    let canImport = expectation(
      for: NSPredicate(format: "enabled == true"), evaluatedWith: importer)
    await fulfillment(of: [canImport], timeout: 10)
    importer.click()
    let confirm = app.sheets.firstMatch.buttons["OKButton"]
    await waitFor(confirm, timeout: 10)
    attach(app, name: "mac-catalog-open-panel")
    app.typeKey("g", modifierFlags: [.command, .shift])
    app.typeText(exported.path)
    app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
    confirm.click()
    let passphrase = app.secureTextFields["catalog-import-passphrase"]
    await waitFor(passphrase, timeout: 10)
    replace(passphrase, with: "abcdefghijklmnop")
    app.buttons["catalog-import-review"].click()
    await waitFor(app.staticTexts["Review imported settings"], timeout: 10)
    attach(app, name: "mac-catalog-import-preview")
    let add = app.buttons["catalog-import-confirm"]
    XCTAssertTrue(add.isEnabled)
    add.click()
    let entry = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "catalog-entry-")
    ).firstMatch
    await waitFor(entry, timeout: 10)
    XCTAssertTrue(entry.label.contains("Mac File Verification"))
    XCTAssertTrue(entry.label.contains("https://example.com/home"))
    attach(app, name: "mac-catalog-imported-entry")
  }
}
