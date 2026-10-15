public enum ExternalDisplayRotation: Int, Codable, CaseIterable, Sendable {
  case standard = 0
  case clockwise = 90
  case upsideDown = 180
  case counterclockwise = 270

  public var swapsDimensions: Bool { self == .clockwise || self == .counterclockwise }
}
