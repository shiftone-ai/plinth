public struct ExternalDisplayMode: Codable, Hashable, Sendable, Identifiable {
  public let width: Int
  public let height: Int
  public let pixelAspectRatio: Double
  public var id: String { "\(width)x\(height)@\(pixelAspectRatio)" }
  public var isValid: Bool {
    width > 0 && height > 0 && pixelAspectRatio.isFinite && pixelAspectRatio > 0
  }

  public init(width: Int, height: Int, pixelAspectRatio: Double = 1) {
    self.width = width
    self.height = height
    self.pixelAspectRatio = pixelAspectRatio
  }
}
