import WebKit

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

@MainActor
final class ExhibitionWebView: WKWebView {
  #if os(macOS)
    override func menu(for event: NSEvent) -> NSMenu? { nil }
  #endif
}
