#if os(iOS)
  import UIKit

  @MainActor
  enum MobilePointerSetupGuidance {
    static var instructions: String {
      if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .pad {
        return "「設定」の「マルチタスクとジェスチャ」で「フルスクリーンアプリ」を選び、Plinthに戻ってください。"
      }
      return "Plinthを全画面表示にしてください。"
    }
  }
#endif
