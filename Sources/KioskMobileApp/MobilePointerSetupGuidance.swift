#if os(iOS)
  import UIKit

  @MainActor
  enum MobilePointerSetupGuidance {
    static var instructions: String {
      if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .pad {
        return
          "In Settings, choose Full Screen Apps under Multitasking & Gestures, then return to Plinth."
      }
      return "Switch Plinth to full screen."
    }
  }
#endif
