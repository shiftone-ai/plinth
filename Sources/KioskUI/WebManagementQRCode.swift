import CoreImage.CIFilterBuiltins
import KioskLocalization
import SwiftUI

public struct WebManagementQRCode: View {
  let url: String
  let size: CGFloat
  @Environment(\.locale) private var locale
  @State private var code: CGImage?

  public init(url: String, size: CGFloat = 180) {
    self.url = url
    self.size = size
  }

  public var body: some View {
    ZStack {
      Color.white.frame(width: size, height: size).accessibilityHidden(true)
      if let code {
        Image(code, scale: 1, label: Text(L10n.string("Web management QR code", locale: locale)))
          .interpolation(.none)
          .resizable()
          .scaledToFit()
          .frame(width: size, height: size)
          .accessibilityIdentifier("web-management-qr")
      }
    }
    .onAppear { code = Self.image(for: url) }
    .onChange(of: url) { _, next in code = Self.image(for: next) }
  }

  private static func image(for url: String) -> CGImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(url.utf8)
    filter.correctionLevel = "M"
    guard let image = filter.outputImage else { return nil }
    return CIContext().createCGImage(image, from: image.extent)
  }
}
