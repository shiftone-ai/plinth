import AppIntents
import KioskMobileApp
import UIKit

struct ResetExhibitionIntent: AppIntent {
  static let title = LocalizedStringResource("Reset Exhibition", table: "Shortcuts")

  @available(iOS 26.0, *)
  static var supportedModes: IntentModes { .foreground(.immediate) }

  @available(iOS, deprecated: 26.0)
  static var openAppWhenRun: Bool { true }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard let application = UIApplication.shared.delegate as? MobileApplication,
      application.resetExhibitionFromShortcut()
    else { throw ResetExhibitionError.unavailable }
    return .result(
      dialog: IntentDialog(
        LocalizedStringResource("Exhibition reset started", table: "Shortcuts")))
  }
}

private enum ResetExhibitionError: LocalizedError {
  case unavailable

  var errorDescription: String? {
    String(localized: LocalizedStringResource("Cannot reset exhibition now", table: "Shortcuts"))
  }
}
