import Foundation
import UIKit
import XCTest
import XCUIAutomation

final class MobileWorkflowUITests: XCTestCase {
  @MainActor func testStoreReviewDemoOnDevice() async throws {
    guard ProcessInfo.processInfo.environment["PLINTH_STORE_REVIEW_TEST"] == "1" else {
      throw XCTSkip("Run explicitly when preparing App Store screenshots")
    }
    continueAfterFailure = false
    let app = XCUIApplication()
    let language = ProcessInfo.processInfo.environment["PLINTH_STORE_REVIEW_LANGUAGE"] ?? "en"
    app.launchArguments = ["-AppleLanguages", "(\(language))"]
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    app.launch()
    defer { app.terminate() }

    try await configureStoreReviewDemo(app)
    let start = app.buttons["start-exhibition"]
    for _ in 0..<3 {
      app.collectionViews.firstMatch.swipeDown()
    }
    attach(app, "store-settings")

    start.tap()
    let next = app.webViews.links["Next exhibit"]
    try await exists(next, timeout: 30)
    try await prepared(app)
    attach(app, "store-exhibition")
    next.tap()
    try await exists(app.webViews.staticTexts["Another view"], timeout: 20)
    app.buttons["request-unlock"].tap()
    let unlock = app.secureTextFields["unlock-passcode"]
    try await exists(unlock)
    unlock.tap()
    unlock.typeText("plinth-review-passcode")
    app.buttons["verify-passcode"].tap()
    try await exists(start)
    attach(app, "store-administration-after-unlock")
    app.terminate()
    app.launch()
    try await exists(app.webViews.links["Next exhibit"], timeout: 30)
  }

  @MainActor func testAdministratorCanOpenPrivacyAndSupportPages() async throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    let language = ProcessInfo.processInfo.environment["PLINTH_STORE_REVIEW_LANGUAGE"] ?? "en"
    app.launchArguments = ["-AppleLanguages", "(\(language))"]
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    app.launch()
    defer { app.terminate() }

    try await exists(app.buttons["start-exhibition"])
    let browser = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    let headings: (privacy: String, support: String) =
      switch language {
      case "ja": ("プライバシーポリシー", "お問い合わせ")
      case "ko": ("개인정보 처리방침", "문의하기")
      case "zh-Hans": ("隐私政策", "联系我们")
      default: ("Privacy Policy", "Contact us")
      }
    for (link, heading) in [
      ("privacy-policy", headings.privacy),
      ("support", headings.support),
    ] {
      let pageLink = app.descendants(matching: .any)[link]
      reach(pageLink, app: app)
      pageLink.tap()
      try await exists(browser.webViews.staticTexts[heading], timeout: 20)
      browser.terminate()
      app.activate()
      try await exists(app.buttons["start-exhibition"])
    }
  }

  @MainActor func testAdministratorCanReadLicensesAndReturnToSettings() async throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)"]
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    app.launch()
    defer { app.terminate() }

    try await exists(app.buttons["start-exhibition"])
    let licenses = app.buttons["licenses"]
    reach(licenses, app: app)
    licenses.tap()
    try await exists(app.descendants(matching: .any)["license-empty"])
    app.buttons["license-close"].tap()
    try await exists(app.buttons["start-exhibition"])
  }

  @MainActor func testExternalExhibitionAutomaticallyResumesAfterAppSwitch() async throws {
    try requireExternalTestDevice()
    let app = try await configuredExternalExhibition(
      path: "/", rotation: "external-display-rotation-clockwise")
    app.buttons["start-exhibition"].tap()
    try await exists(app.webViews.staticTexts["/"], timeout: 20)
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    for index in 1...3 {
      settings.activate()
      XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
      app.activate()
      try await exists(app.webViews.staticTexts["/"], timeout: 20)
      XCTAssertFalse(app.staticTexts["exhibition-stopped"].exists)
      XCTAssertFalse(app.descendants(matching: .any)["pointer-setup-help"].exists)
      attach(app, "external-return-automatic-\(index)")
    }
    try await unlockExternalExhibition(app)
    settings.activate()
    XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
    app.activate()
    try await exists(app.buttons["start-exhibition"])
    XCTAssertFalse(app.webViews.firstMatch.exists)
    attach(app, "administration-kept-after-return")
  }

  @MainActor func testAutomaticOriginIsReadOnlyAndNeedsNoManualRules() async throws {
    try requireExternalTestDevice()
    let app = try await configuredExternalExhibition(path: "/")
    let destination = app.buttons["exhibition-destination"]
    for _ in 0..<5 where !destination.exists || !destination.isHittable {
      app.collectionViews.firstMatch.swipeDown()
    }
    XCTAssertTrue(destination.isHittable)
    destination.tap()
    app.buttons["exhibition-destination-device"].tap()
    app.buttons["remove-origin-1"].tap()
    XCTAssertFalse(app.textFields["origin-1"].exists)
    let automatic = app.descendants(matching: .any)["automatic-origin"]
    try await exists(automatic)
    XCTAssertLessThan(automatic.frame.height, 100)
    XCTAssertFalse(app.textFields["automatic-origin"].exists)
    XCTAssertFalse(app.buttons["automatic-origin"].exists)
    let field = app.textFields["start-url"]
    let previous = try XCTUnwrap(field.value as? String)
    let changed = previous.replacingOccurrences(of: "127.0.0.1", with: "localhost")
    XCTAssertNotEqual(previous, changed)
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    field.typeText(
      String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count + 2) + changed)
    try await value(field, equals: changed)
    field.typeText("\n")
    XCTAssertTrue((automatic.value as? String)?.contains("localhost") == true)
    attach(app, "automatic-origin-settings")
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    field.typeText(
      String(repeating: XCUIKeyboardKey.delete.rawValue, count: changed.count + 2) + previous)
    try await value(field, equals: previous)
    field.typeText("\n")
    let save = app.buttons["save-profile"]
    try await enabled(save)
    save.tap()
    try await enabled(app.buttons["start-exhibition"])
    app.buttons["start-exhibition"].tap()
    try await exists(app.webViews.staticTexts["/"], timeout: 20)
    app.webViews.links["Allowed"].tap()
    try await exists(app.webViews.staticTexts["/allowed"], timeout: 10)
    attach(app, "automatic-origin-allowed-page")
  }

  @MainActor func testExternalRotationViewportInputAndPersistence() async throws {
    try requireExternalTestDevice()
    #if targetEnvironment(simulator)
      let width = 720
      let height = 480
    #else
      let width = 1920
      let height = 1080
    #endif
    let app = try await configuredExternalExhibition(
      path: "/rotation", allowsScroll: true, allowsDrag: true,
      displayMode: "external-display-mode-\(width)x\(height)",
      rotation: "external-display-rotation-clockwise")
    let rotations = [("右90°", true), ("180°", false), ("左90°", true), ("標準（0°）", false)]
    for (index, rotation) in rotations.enumerated() {
      if index > 0 {
        try await unlockExternalExhibition(app)
        app.buttons["external-display-rotation"].tap()
        app.buttons[rotation.0].tap()
        app.buttons["save-profile"].tap()
        try await enabled(app.buttons["start-exhibition"])
      }
      app.buttons["start-exhibition"].tap()
      let viewport = "Viewport \(rotation.1 ? height : width) × \(rotation.1 ? width : height)"
      try await exists(app.webViews.staticTexts[viewport])
      let controls = app.otherElements["external-control"]
      try await exists(controls)
      controls.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2)).tap()
      try await exists(app.webViews.staticTexts["Corner activated"])
      controls.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65))
        .press(
          forDuration: 0.4,
          thenDragTo: controls.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.65)))
      try await exists(app.webViews.staticTexts["Drop accepted"])
      try await exists(app.webViews.staticTexts["Hover active"])
      controls.swipeUp()
      try await exists(app.webViews.staticTexts["Scrolled"])
      attach(app, "external-rotation-\(index)")
      #if targetEnvironment(simulator)
        try assertSharpExternalCorner(width: width, height: height, index: index)
      #endif
      app.terminate()
      app.launch()
      try await exists(app.webViews.staticTexts[viewport], timeout: 20)
      app.buttons["request-unlock"].tap()
      try await exists(app.secureTextFields["unlock-passcode"])
      app.buttons["cancel-unlock"].tap()
      try await exists(app.webViews.staticTexts[viewport])
    }
  }

  @MainActor private func assertSharpExternalCorner(width: Int, height: Int, index: Int) throws {
    let screen = try XCTUnwrap(XCUIScreen.screens.dropFirst().first)
    let image = try XCTUnwrap(screen.screenshot().image.cgImage)
    let screenWidth = CGFloat(width)
    let screenHeight = CGFloat(height)
    let points = [
      CGPoint(x: screenWidth - 48, y: 32), CGPoint(x: screenWidth - 32, y: screenHeight - 48),
      CGPoint(x: 48, y: screenHeight - 32), CGPoint(x: 32, y: 48),
    ]
    let pixel = try XCTUnwrap(
      image.cropping(to: CGRect(origin: points[index], size: CGSize(width: 1, height: 1))))
    var rgba = [UInt8](repeating: 0, count: 4)
    let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    try rgba.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(
        CGContext(
          data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    XCTAssertGreaterThan(rgba[0], 245, "External corner must retain its solid red color")
    XCTAssertLessThan(rgba[1], 80, "External corner must not be blurred into the white page")
    XCTAssertLessThan(rgba[2], 40, "External corner must not be blurred into the white page")
  }

  @MainActor func testRotatedExternalVideoPlayback() async throws {
    try requireExternalTestDevice()
    let app = try await configuredExternalExhibition(
      path: "/video", rotation: "external-display-rotation-clockwise")
    app.buttons["start-exhibition"].tap()
    try await exists(app.webViews.staticTexts["Video playing"], timeout: 20)
    XCTAssertFalse(app.webViews.staticTexts["Video failed"].exists)
    attach(app, "rotated-external-video-playing")
  }

  @MainActor private func unlockExternalExhibition(_ app: XCUIApplication) async throws {
    app.buttons["request-unlock"].tap()
    let passcode = app.secureTextFields["unlock-passcode"]
    try await exists(passcode)
    passcode.tap()
    passcode.typeText("plinth-mobile-passcode")
    try await secureValue(passcode, count: "plinth-mobile-passcode".count)
    app.buttons["verify-passcode"].tap()
    try await exists(app.buttons["external-display-rotation"])
  }

  @MainActor func testSavedExternalResolutionInSimulator() async throws {
    #if !targetEnvironment(simulator)
      throw XCTSkip("Requires the Simulator's 720x480 external mode")
    #else
      let app = try await configuredExternalExhibition(
        path: "/surface", displayMode: "external-display-mode-720x480")
      app.buttons["start-exhibition"].tap()
      try await exists(app.webViews.staticTexts["Full display"])
      XCTAssertEqual(app.webViews.firstMatch.frame.width, 720)
      XCTAssertEqual(app.webViews.firstMatch.frame.height, 480)
      attach(app, "simulator-selected-720x480")
      for attempt in 1...3 {
        app.terminate()
        app.launch()
        try await exists(app.webViews.staticTexts["Full display"], timeout: 20)
        XCTAssertEqual(app.webViews.firstMatch.frame.width, 720)
        XCTAssertEqual(app.webViews.firstMatch.frame.height, 480)
        attach(app, "simulator-reopened-720x480-\(attempt)")
      }
    #endif
  }

  @MainActor func testExternalResolutionSelectionPersistsAcrossLaunches() async throws {
    try requireExternalTestDevice()
    let app = try await configuredExternalExhibition(
      path: "/surface", displayMode: "external-display-mode-1920x1200")
    app.buttons["start-exhibition"].tap()
    try await exists(app.webViews.staticTexts["Full display"])
    XCTAssertEqual(app.webViews.firstMatch.frame.height, 1200)
    attach(app, "selected-1920x1200")
    app.buttons["request-unlock"].tap()
    let unlock = app.secureTextFields["unlock-passcode"]
    try await exists(unlock)
    unlock.tap()
    unlock.typeText("plinth-mobile-passcode")
    try await secureValue(unlock, count: "plinth-mobile-passcode".count)
    app.buttons["verify-passcode"].tap()
    try await exists(app.buttons["exhibition-destination"])
    let resolution = app.buttons["external-display-mode"]
    try await hittable(resolution)
    resolution.tap()
    app.buttons["external-display-mode-1920x1080"].tap()
    let save = app.buttons["save-profile"]
    try await enabled(save)
    save.tap()
    try await enabled(app.buttons["start-exhibition"])
    attach(app, "saved-1920x1080-settings")
    app.buttons["start-exhibition"].tap()
    try await exists(app.webViews.staticTexts["Full display"])
    XCTAssertEqual(app.webViews.firstMatch.frame.width, 1920)
    XCTAssertEqual(app.webViews.firstMatch.frame.height, 1080)
    attach(app, "selected-1920x1080")
    for attempt in 1...3 {
      app.terminate()
      app.launch()
      try await exists(app.webViews.staticTexts["Full display"], timeout: 20)
      XCTAssertEqual(app.webViews.firstMatch.frame.width, 1920)
      XCTAssertEqual(app.webViews.firstMatch.frame.height, 1080)
      attach(app, "reopened-1920x1080-\(attempt)")
    }
  }

  @MainActor func testExternalSurfaceFillsDisplay() async throws {
    try requireExternalTestDevice()
    try await externalSurface()
  }

  @MainActor func testPhysicalFullHDDisplayInspection() async throws {
    #if targetEnvironment(simulator)
      throw XCTSkip("Requires physical Full HD display inspection")
    #else
      try requireExternalTestDevice()
      let app = try await configuredExternalExhibition(
        path: "/surface", displayMode: "external-display-mode-1920x1080")
      app.buttons["start-exhibition"].tap()
      try await exists(app.webViews.staticTexts["Full display"])
      XCTAssertEqual(app.webViews.firstMatch.frame.width, 1920)
      XCTAssertEqual(app.webViews.firstMatch.frame.height, 1080)
      for corner in ["Top left", "Top right", "Bottom left", "Bottom right"] {
        try await exists(app.webViews.staticTexts[corner])
      }
      attach(app, "physical-full-hd-inspection")
      print("PHYSICAL_FULL_HD_INSPECTION_READY")
      // Keep the verified image visible for the panel observer and external capture driver.
      try await Task.sleep(for: .seconds(90))
    #endif
  }

  @MainActor func testPhysicalExternalDisplayInspection() async throws {
    #if targetEnvironment(simulator)
      throw XCTSkip("Requires physical display inspection")
    #else
      try requireExternalTestDevice()
      try await externalSurface()
      print("EXTERNAL_VISUAL_INSPECTION_READY")
      // Readiness is already asserted. Keep the image visible for physical panel inspection.
      try await Task.sleep(for: .seconds(90))
    #endif
  }

  @MainActor
  private func externalSurface() async throws {
    let app = try await configuredExternalExhibition(path: "/surface")
    app.buttons["start-exhibition"].tap()
    try await exists(app.webViews.staticTexts["Full display"])
    let web = app.webViews.firstMatch
    print("EXTERNAL_WEB_FRAME=\(web.frame)")
    for corner in ["Top left", "Top right", "Bottom left", "Bottom right"] {
      try await exists(app.webViews.staticTexts[corner])
    }
    attach(app, "external-full-surface")
  }

  @MainActor func testExternalFlingContinuesAfterRelease() async throws {
    try requireExternalTestDevice()
    let app = try await configuredExternalExhibition(path: "/scroll", allowsScroll: true)
    app.buttons["start-exhibition"].tap()
    try await exists(app.webViews.staticTexts["At top"])
    let controls = app.otherElements["external-control"]
    try await exists(controls)
    controls.swipeUp(velocity: .fast)
    let momentum = expectation(
      for: NSPredicate(format: "value == %@", "momentum"), evaluatedWith: controls)
    await fulfillment(of: [momentum], timeout: 5)
    XCTAssertEqual(controls.value as? String, "momentum")
    try await exists(app.webViews.staticTexts["Scrolled"])
    attach(app, "external-scroll-momentum")
  }

  @MainActor func testDisplayOnlyExternalOutputAndAdministratorRecovery() async throws {
    try requireExternalTestDevice()
    let app = try await configuredExternalExhibition(path: "/scroll", allowsScroll: true)
    let start = app.buttons["start-exhibition"]
    attach(app, "external-settings")
    start.tap()
    try await exists(app.descendants(matching: .any)["external-exhibition-active"])
    let externalWeb = app.webViews.firstMatch
    try await exists(externalWeb)
    print("EXTERNAL_WEB_FRAME=\(externalWeb.frame)")
    XCTAssertGreaterThan(externalWeb.frame.width, externalWeb.frame.height)
    try await exists(app.webViews.staticTexts["/scroll"])
    let controls = app.otherElements["external-control"]
    try await exists(controls)
    let allowed = app.webViews.links["Allowed"].frame
    controls.coordinate(
      withNormalizedOffset: CGVector(
        dx: (allowed.midX - externalWeb.frame.minX) / externalWeb.frame.width,
        dy: (allowed.midY - externalWeb.frame.minY) / externalWeb.frame.height)
    ).tap()
    try await exists(app.webViews.staticTexts["/allowed"])
    let blocked = app.webViews.links["Blocked"].frame
    controls.coordinate(
      withNormalizedOffset: CGVector(
        dx: (blocked.midX - externalWeb.frame.minX) / externalWeb.frame.width,
        dy: (blocked.midY - externalWeb.frame.minY) / externalWeb.frame.height)
    ).tap()
    XCTAssertFalse(app.webViews.staticTexts["/blocked"].exists)
    XCTAssertTrue(app.webViews.staticTexts["/allowed"].exists)
    try await exists(app.webViews.staticTexts["At top"])
    for _ in 0..<20 {
      if app.webViews.staticTexts["At bottom"].exists { break }
      controls.swipeUp()
    }
    try await exists(app.webViews.staticTexts["Scrolled"])
    try await exists(app.webViews.staticTexts["At bottom"])
    print("EXTERNAL_SCROLL_VISIBLE")
    attach(app, "external-exhibition-device-controls")
    app.buttons["request-unlock"].tap()
    try await exists(app.secureTextFields["unlock-passcode"])
    XCTAssertFalse(app.webViews.firstMatch.exists)
    app.buttons["cancel-unlock"].tap()
    try await exists(app.webViews["exhibition-web-2"])
    try await exists(app.webViews.staticTexts["/scroll"])
    app.buttons["request-unlock"].tap()
    let unlock = app.secureTextFields["unlock-passcode"]
    try await exists(unlock)
    unlock.tap()
    unlock.typeText("plinth-mobile-passcode")
    try await secureValue(unlock, count: "plinth-mobile-passcode".count)
    app.buttons["verify-passcode"].tap()
    try await exists(start)
    start.tap()
    try await exists(app.descendants(matching: .any)["external-exhibition-active"])
    try await exists(app.webViews.staticTexts["/scroll"])
    attach(app, "external-restarted")
  }

  @MainActor func testExternalTouchDragAndAudioActivation() async throws {
    try requireExternalTestDevice()
    let app = try await configuredExternalExhibition(path: "/input", allowsDrag: true)
    app.buttons["start-exhibition"].tap()
    let web = app.webViews.firstMatch
    let controls = app.otherElements["external-control"]
    try await exists(web)
    try await exists(controls)
    func coordinate(_ element: XCUIElement) -> XCUICoordinate {
      let frame = element.frame
      return controls.coordinate(
        withNormalizedOffset: CGVector(
          dx: (frame.midX - web.frame.minX) / web.frame.width,
          dy: (frame.midY - web.frame.minY) / web.frame.height))
    }
    let source = app.webViews.staticTexts["Drag source"]
    let target = app.webViews.staticTexts["Drop target"]
    try await exists(source)
    try await exists(target)
    coordinate(source).press(forDuration: 0.4, thenDragTo: coordinate(target))
    try await exists(app.webViews.staticTexts["Drop accepted"])
    coordinate(app.webViews.buttons["Play audio"]).tap()
    try await exists(app.webViews.staticTexts["Audio playing"])
    attach(app, "external-drag-and-audio")
    app.buttons["request-unlock"].tap()
    try await exists(app.secureTextFields["unlock-passcode"])
    app.buttons["cancel-unlock"].tap()
    try await exists(app.webViews.staticTexts["Drop idle"])
  }

  @MainActor func testExternalVideoPlayback() async throws {
    try requireExternalTestDevice()
    let app = try await configuredExternalExhibition(path: "/video")
    app.buttons["start-exhibition"].tap()
    try await exists(app.webViews.staticTexts["Video playing"], timeout: 20)
    XCTAssertFalse(app.webViews.staticTexts["Video failed"].exists)
    attach(app, "external-video-playing")
  }

  private func requireExternalTestDevice() throws {
    #if !targetEnvironment(simulator)
      guard ProcessInfo.processInfo.environment["PLINTH_EXTERNAL_PHYSICAL_TESTS"] == "1" else {
        throw XCTSkip("Requires explicit enablement with a connected physical external display")
      }
    #endif
  }

  @MainActor func testExternalVideoDisconnectAndReconnect() async throws {
    #if !targetEnvironment(simulator)
      throw XCTSkip("Requires Simulator external display power control")
    #else
      guard ProcessInfo.processInfo.environment["PLINTH_EXTERNAL_HOTPLUG_TEST"] == "1" else {
        throw XCTSkip("Requires the external display test driver")
      }
      let app = try await configuredExternalExhibition(path: "/video")
      let start = app.buttons["start-exhibition"]
      start.tap()
      let web = app.webViews.firstMatch
      try await exists(web)
      XCTAssertGreaterThan(web.frame.width, web.frame.height)
      try await exists(app.webViews.staticTexts["Video playing"], timeout: 20)
      XCTAssertFalse(app.webViews.staticTexts["Video failed"].exists)
      attach(app, "external-video-playing-device")
      // The dedicated driver captures the external surface, then powers it off.
      print("EXTERNAL_VIDEO_DISCONNECT_READY")
      try await exists(app.staticTexts["exhibition-stopped"], timeout: 20)
      XCTAssertFalse(app.webViews.firstMatch.exists)
      attach(app, "external-disconnected-device")
      // Reconnect after the actual stopped state, never after a fixed delay.
      print("EXTERNAL_VIDEO_RECONNECT_READY")
      app.buttons["request-unlock"].tap()
      let unlock = app.secureTextFields["unlock-passcode"]
      try await exists(unlock)
      unlock.tap()
      unlock.typeText("plinth-mobile-passcode")
      try await secureValue(unlock, count: "plinth-mobile-passcode".count)
      app.buttons["verify-passcode"].tap()
      try await enabled(start)
      attach(app, "external-reconnected-settings")
      start.tap()
      try await exists(app.webViews.staticTexts["Video playing"], timeout: 20)
      XCTAssertFalse(app.webViews.staticTexts["Video failed"].exists)
      attach(app, "external-video-restarted-device")
      print("EXTERNAL_VIDEO_RESTARTED")
      // A second disconnect keeps the surface alive until the driver has captured it.
      try await exists(app.staticTexts["exhibition-stopped"], timeout: 20)
      XCTAssertFalse(app.webViews.firstMatch.exists)
    #endif
  }

  @MainActor
  private func configuredExternalExhibition(
    path: String, allowsScroll: Bool = false, allowsDrag: Bool = false, displayMode: String? = nil,
    rotation: String? = nil
  ) async throws
    -> XCUIApplication
  {
    continueAfterFailure = false
    let server = try FixtureServer()
    try await server.start()
    let app = XCUIApplication()
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] =
      "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    app.launchEnvironment["PLINTH_TEST_SCROLL_DIAGNOSTICS"] = "1"
    addTeardownBlock {
      await MainActor.run {
        app.terminate()
        server.stop()
      }
    }
    app.launch()
    let start = app.buttons["start-exhibition"]
    try await exists(start)
    app.buttons["exhibition-destination"].tap()
    app.buttons["exhibition-destination-external"].tap()
    try await exists(app.buttons["external-display-rotation"])
    XCTAssertTrue(app.buttons["exhibition-destination"].isHittable)
    if app.buttons["prepare-external-scene"].exists {
      throw XCTSkip("Requires an automatically connected external display scene")
    }
    attach(app, "external-output-settings")
    if let displayMode {
      app.buttons["external-display-mode"].tap()
      app.buttons[displayMode].tap()
    }
    if let rotation {
      app.buttons["external-display-rotation"].tap()
      app.buttons[rotation].tap()
    }
    app.textFields["start-url"].tap()
    app.textFields["start-url"].typeText(server.origin + path)
    try await value(app.textFields["start-url"], equals: server.origin + path)
    app.textFields["start-url"].typeText("\n")
    app.buttons["add-origin"].tap()
    app.textFields["origin-1"].tap()
    app.textFields["origin-1"].typeText(server.origin)
    try await value(app.textFields["origin-1"], equals: server.origin)
    app.textFields["origin-1"].typeText("\n")
    let http = app.switches["allow-http"]
    reach(http, app: app)
    http.switches.firstMatch.tap()
    if allowsScroll {
      let scroll = app.switches["allow-scroll"].switches.firstMatch
      reach(scroll, app: app)
      scroll.tap()
    }
    if allowsDrag {
      let drag = app.switches["allow-drag"].switches.firstMatch
      reach(drag, app: app)
      drag.tap()
    }
    let setup = app.secureTextFields["setup-passcode"]
    reach(setup, app: app)
    setup.tap()
    setup.typeText("plinth-mobile-passcode")
    try await secureValue(setup, count: "plinth-mobile-passcode".count)
    setup.typeText("\n")
    let savePasscode = app.buttons["save-passcode"]
    reach(savePasscode, app: app)
    savePasscode.tap()
    let save = app.buttons["save-profile"]
    attach(app, "external-before-save")
    try await enabled(save)
    save.tap()
    try await enabled(start)
    return app
  }

  @MainActor func testCurrentSiteCancelledUnlockAndShortIdle() async throws {
    continueAfterFailure = false
    // xcodebuild passes TEST_RUNNER_PLINTH_TEST_SITE_* to the runner for the configured site.
    let site = ProcessInfo.processInfo.environment
    guard let siteLink = site["PLINTH_TEST_SITE_LINK"] else {
      throw XCTSkip("Set PLINTH_TEST_SITE_LINK, and PLINTH_TEST_SITE_URL to configure a Simulator")
    }
    let app = XCUIApplication()
    app.launchEnvironment["PLINTH_TEST_IDLE_SECONDS"] = "5"
    app.launch()
    addTeardownBlock { await MainActor.run { app.terminate() } }
    let web = app.webViews.firstMatch
    #if targetEnvironment(simulator)
      if !web.waitForExistence(timeout: 3), app.buttons["start-exhibition"].exists,
        app.textFields["start-url"].value as? String == site["PLINTH_TEST_SITE_URL"]
      {
        let setup = app.secureTextFields["setup-passcode"]
        reach(setup, app: app)
        setup.tap()
        setup.typeText("plinth-mobile-passcode")
        try await secureValue(setup, count: "plinth-mobile-passcode".count)
        setup.typeText("\n")
        app.buttons["save-passcode"].tap()
        let start = app.buttons["start-exhibition"]
        try await enabled(start)
        start.tap()
      }
    #endif
    guard web.waitForExistence(timeout: 10) else {
      throw XCTSkip("Requires the exhibition profile already configured on this device")
    }
    let about = app.webViews.links[siteLink].firstMatch
    try await hittable(about)
    attach(app, "current-site-initial")
    for index in 1...3 {
      app.buttons["request-unlock"].tap()
      try await exists(app.secureTextFields["unlock-passcode"])
      app.buttons["cancel-unlock"].tap()
      try await exists(app.webViews["exhibition-web-\(index + 1)"])
      try await prepared(app)
      try await hittable(about)
      attach(app, "current-site-after-cancel-\(index)")
    }
    about.tap()
    try await exists(app.webViews["exhibition-web-5"], timeout: 20)
    try await prepared(app)
    try await hittable(about)
    attach(app, "current-site-after-five-second-idle")
  }
  @MainActor func testCaptureCurrentExhibition() {
    let app = XCUIApplication()
    app.activate()
    attach(app, "current-exhibition")
    for web in app.webViews.allElementsBoundByIndex {
      print("EXHIBITION_WEB_FRAME=\(web.frame)")
    }
  }
  @MainActor
  func testSetupAllowedBlockedIdleAndPasscode() async throws {
    continueAfterFailure = false
    let server = try FixtureServer()
    try await server.start()
    let app = XCUIApplication()
    let service = "ai.shiftone.plinth.tests.\(UUID().uuidString)"
    app.launchEnvironment["PLINTH_TEST_CREDENTIAL_SERVICE"] = service
    addTeardownBlock {
      await MainActor.run {
        app.terminate()
        server.stop()
      }
    }
    app.launch()
    let start = app.buttons["start-exhibition"]
    try await exists(start)
    app.textFields["start-url"].tap()
    app.textFields["start-url"].typeText(server.origin + "/home")
    try await value(app.textFields["start-url"], equals: server.origin + "/home")
    app.textFields["start-url"].typeText("\n")
    app.buttons["add-origin"].tap()
    app.textFields["origin-1"].tap()
    app.textFields["origin-1"].typeText(server.origin)
    try await value(app.textFields["origin-1"], equals: server.origin)
    app.textFields["origin-1"].typeText("\n")
    let http = app.switches["allow-http"]
    reach(http, app: app)
    http.switches.firstMatch.tap()
    let idle = app.textFields["idle-seconds"]
    reach(idle, app: app)
    idle.tap()
    let previous = idle.value as? String ?? "120.0"
    idle.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count + 2))
    idle.typeText("5")
    XCTAssertEqual(idle.value as? String, "5")
    idle.typeText("\n")
    let setup = app.secureTextFields["setup-passcode"]
    reach(setup, app: app)
    setup.tap()
    setup.typeText("plinth-mobile-passcode")
    try await secureValue(setup, count: "plinth-mobile-passcode".count)
    setup.typeText("\n")
    app.buttons["save-passcode"].tap()
    print("FIXTURE_FINAL_URL=\(app.textFields["start-url"].value as? String ?? "nil")")
    let save = app.buttons["save-profile"]
    attach(app, "settings-before-save")
    try await enabled(save)
    save.tap()
    try await enabled(start)
    attach(app, "settings")
    start.tap()
    let allowed = app.webViews.links["Allowed"]
    try await exists(allowed)
    app.webViews.links["Blocked"].tap()
    XCTAssertTrue(app.webViews.staticTexts["/home"].exists)
    XCTAssertFalse(app.webViews.staticTexts["/blocked"].exists)
    allowed.tap()
    try await exists(app.webViews.staticTexts["/allowed"])
    try await exists(app.webViews.staticTexts["/home"], timeout: 15)
    attach(app, "exhibition-after-idle")
    app.buttons["request-unlock"].tap()
    let unlock = app.secureTextFields["unlock-passcode"]
    try await exists(unlock)
    unlock.tap()
    unlock.typeText("wrong-passcode")
    try await secureValue(unlock, count: "wrong-passcode".count)
    app.buttons["verify-passcode"].tap()
    try await exists(app.staticTexts["incorrect-credential"])
    app.buttons["cancel-unlock"].tap()
    try await exists(allowed)
    app.buttons["request-unlock"].tap()
    try await exists(unlock)
    unlock.tap()
    unlock.typeText("plinth-mobile-passcode")
    try await secureValue(unlock, count: "plinth-mobile-passcode".count)
    app.buttons["verify-passcode"].tap()
    try await exists(start, timeout: 10)
    attach(app, "administration-after-unlock")
    start.tap()
    try await exists(allowed)
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.activate()
    try await hittable(settings.windows.firstMatch)
    app.activate()
    try await exists(allowed)
    XCTAssertFalse(app.staticTexts["exhibition-stopped"].exists)
    attach(app, "resumed-after-background")
    app.buttons["request-unlock"].tap()
    try await exists(unlock)
    unlock.tap()
    unlock.typeText("plinth-mobile-passcode")
    try await secureValue(unlock, count: "plinth-mobile-passcode".count)
    app.buttons["verify-passcode"].tap()
    try await exists(start)
    start.tap()
    try await exists(allowed)
    attach(app, "restarted-after-background")
  }

  @MainActor
  func reach(_ element: XCUIElement, app: XCUIApplication) {
    for _ in 0..<5 where !element.exists || !element.isHittable {
      app.collectionViews.firstMatch.swipeUp()
    }
    XCTAssertTrue(element.isHittable)
  }

  @MainActor
  func exists(_ element: XCUIElement, timeout: TimeInterval = 10) async throws {
    let ready = expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: element)
    await fulfillment(of: [ready], timeout: timeout)
    _ = try XCTUnwrap(element.exists ? element : nil)
  }

  @MainActor
  private func value(_ element: XCUIElement, equals text: String) async throws {
    let ready = expectation(for: NSPredicate(format: "value == %@", text), evaluatedWith: element)
    await fulfillment(of: [ready], timeout: 5)
    XCTAssertEqual(element.value as? String, text)
  }

  @MainActor
  func secureValue(_ element: XCUIElement, count: Int) async throws {
    let ready = expectation(
      for: NSPredicate(format: "value.length == %d", count), evaluatedWith: element)
    await fulfillment(of: [ready], timeout: 5)
    XCTAssertEqual((element.value as? String)?.count, count)
  }

  @MainActor
  func enabled(_ element: XCUIElement) async throws {
    let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: element)
    await fulfillment(of: [ready], timeout: 15)
    _ = try XCTUnwrap(element.isEnabled ? element : nil)
  }

  @MainActor
  private func hittable(_ element: XCUIElement) async throws {
    let ready = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: element)
    await fulfillment(of: [ready], timeout: 20)
    _ = try XCTUnwrap(element.isHittable ? element : nil)
  }

  @MainActor
  private func configureStoreReviewDemo(_ app: XCUIApplication) async throws {
    let start = app.buttons["start-exhibition"]
    try await exists(start)
    let destination = app.buttons["exhibition-destination"]
    if destination.exists {
      destination.tap()
      app.buttons["exhibition-destination-device"].tap()
    }
    let url = "https://shiftone-ai.github.io/plinth/demo/index.html"
    let field = app.textFields["start-url"]
    field.tap()
    let previous = field.value as? String ?? ""
    field.typeText(
      String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count + 2) + url)
    try await value(field, equals: url)
    field.typeText("\n")

    let setup = app.secureTextFields["setup-passcode"]
    reach(setup, app: app)
    setup.tap()
    setup.typeText("plinth-review-passcode")
    try await secureValue(setup, count: "plinth-review-passcode".count)
    setup.typeText("\n")
    app.buttons["save-passcode"].tap()
    let save = app.buttons["save-profile"]
    try await enabled(save)
    save.tap()
    try await enabled(start)
  }

  @MainActor
  private func prepared(_ app: XCUIApplication) async throws {
    let indicator = app.descendants(matching: .any)["exhibition-preparing"]
    let ready = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: indicator)
    await fulfillment(of: [ready], timeout: 20)
    XCTAssertFalse(indicator.exists)
  }

  @MainActor
  func attach(_ app: XCUIApplication, _ name: String) {
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = name
    screenshot.lifetime = .keepAlways
    add(screenshot)
    if ProcessInfo.processInfo.environment["PLINTH_EXTERNAL_PHYSICAL_TESTS"] == "1" {
      if let screen = XCUIScreen.screens.dropFirst().first {
        let attachment = XCTAttachment(screenshot: screen.screenshot())
        attachment.name = "\(name)-external"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
    }
  }
}
