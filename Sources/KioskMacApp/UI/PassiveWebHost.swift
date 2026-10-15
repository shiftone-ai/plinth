import AppKit
import KioskRuntime
import SwiftUI

/// Hosting may change with rendering; the Adapter continues to own the surface.
struct PassiveWebHost: NSViewRepresentable {
  let host: NSView
  func makeNSView(context: Context) -> NSView { host }
  func updateNSView(_ nsView: NSView, context: Context) {}
}
