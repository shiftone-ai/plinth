import Foundation
import UIKit
import XCTest
import XCUIAutomation

extension MobileWorkflowUITests {
  @MainActor func testResetExhibitionFromShortcuts() async throws {
    let scenario = ProcessInfo.processInfo.environment["PLINTH_SHORTCUTS_TEST"]
    guard ["1", "physical"].contains(scenario) else {
      throw XCTSkip("Run explicitly on an isolated Simulator or test device")
    }
    continueAfterFailure = false
    let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    shortcuts.activate()
    if springboard.staticTexts["Exhibition reset started"].exists {
      springboard.buttons["Done"].firstMatch.tap()
    }
    let app = XCUIApplication()
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.shortcuts.\(UUID().uuidString)"
    app.launch()
    try await configureStoreReviewDemo(app)
    app.buttons["start-exhibition"].tap()
    let next = app.webViews.links["Next exhibit"]
    try await exists(next, timeout: 30)
    next.tap()
    try await exists(app.webViews.staticTexts["Another view"], timeout: 20)
    attach(app, "shortcuts-before")
    if scenario == "physical" {
      shortcuts.activate()
      let resetCell = shortcuts.cells.matching(
        NSPredicate(format: "label BEGINSWITH %@", "展示をリセット")
      ).firstMatch
      let all = shortcuts.buttons.matching(
        NSPredicate(format: "label == %@", "すべてのショートカット")
      ).firstMatch
      for _ in 0..<3 {
        if resetCell.exists { break }
        if all.exists {
          all.tap()
        } else if shortcuts.buttons["BackButton"].exists {
          shortcuts.buttons["BackButton"].tap()
        }
      }
      // Shortcuts owns the cell label; its run button has a stable system identifier.
      let reset = resetCell.buttons.matching(identifier: "shortcut.button.run").firstMatch
      try await exists(reset)
      reset.tap()
      attach(shortcuts, "physical-shortcut-result")
    } else {
      try await runResetShortcut(shortcuts, springboard: springboard)
    }
    app.activate()
    try await exists(app.webViews.links["Next exhibit"], timeout: 30)
    XCTAssertFalse(app.webViews.staticTexts["Another view"].exists)
    attach(app, "shortcuts-after")
  }

  @MainActor private func runResetShortcut(
    _ shortcuts: XCUIApplication, springboard: XCUIApplication
  ) async throws {
    shortcuts.activate()
    let saved = shortcuts.cells.matching(
      NSPredicate(format: "label BEGINSWITH %@", "Reset Exhibition, ")
    ).firstMatch
    if saved.exists {
      saved.buttons["Reset Exhibition"].tap()
      try await exists(springboard.staticTexts["Exhibition reset started"], timeout: 20)
      attach(shortcuts, "shortcuts-result")
      springboard.buttons["Done"].firstMatch.tap()
      return
    }
    if !shortcuts.buttons["play"].exists && !shortcuts.buttons["Run Shortcut"].exists {
      if !shortcuts.searchFields["Search Actions"].exists {
        shortcuts.buttons["Create Shortcut"].tap()
      }
      let search = shortcuts.searchFields["Search Actions"]
      search.tap()
      if shortcuts.buttons["Clear text"].exists {
        shortcuts.buttons["Clear text"].tap()
      }
      search.typeText("Reset Exhibition")
      if UIDevice.current.userInterfaceIdiom == .pad {
        search.tap()
        search.typeText("\n")
      }
      let action = shortcuts.descendants(matching: .any)["Reset Exhibition"].firstMatch
      XCTAssertTrue(action.waitForExistence(timeout: 25))
      action.tap()
    }
    if UIDevice.current.userInterfaceIdiom == .pad {
      let run = shortcuts.buttons["Run Shortcut"]
      try await enabled(run)
      run.tap()
    } else {
      try await exists(shortcuts.buttons["play"])
      shortcuts.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.94)).tap()
    }
    try await exists(springboard.staticTexts["Exhibition reset started"], timeout: 20)
    attach(shortcuts, "shortcuts-result")
    springboard.buttons["Done"].firstMatch.tap()
  }
}
