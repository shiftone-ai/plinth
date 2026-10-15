public struct SurfacePoint: Equatable, Sendable {
  public let x: Double
  public let y: Double
  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
  public var isValid: Bool {
    x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y)
  }
}

public enum ExternalMouseInput: Equatable, Sendable {
  case move(dx: Double, dy: Double)
  case primaryButton(pressed: Bool)
  case scroll(dx: Double, dy: Double)
  case unlock
}

/// Coordinates are relative to the external viewport, independent of device resolution.
public enum ExternalWebControl: Equatable, Sendable {
  case move(SurfacePoint)
  case activate(SurfacePoint)
  case press(SurfacePoint)
  case release(SurfacePoint)
  case cancelPress
  case scroll(dx: Double, dy: Double)

  public var isValid: Bool {
    switch self {
    case .move(let point), .activate(let point), .press(let point), .release(let point):
      point.isValid
    case .cancelPress: true
    case .scroll(let dx, let dy): dx.isFinite && dy.isFinite && abs(dx) <= 1 && abs(dy) <= 1
    }
  }
}
