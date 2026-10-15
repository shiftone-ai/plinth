#if os(iOS)
  import KioskCore
  import SwiftUI

  /// Rendering only: the Web host and its cursor share the same logical viewport.
  struct MobileExternalSurface<Content: View>: View {
    let rotation: ExternalDisplayRotation
    @ViewBuilder let content: Content

    var body: some View {
      GeometryReader { geometry in
        content
          .frame(
            width: rotation.swapsDimensions ? geometry.size.height : geometry.size.width,
            height: rotation.swapsDimensions ? geometry.size.width : geometry.size.height
          )
          .rotationEffect(.degrees(Double(rotation.rawValue)))
          .frame(width: geometry.size.width, height: geometry.size.height)
      }
      .ignoresSafeArea()
    }
  }
#endif
