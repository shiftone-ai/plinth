public struct DisplayDescriptor: Equatable, Encodable, Sendable, Identifiable {
  public struct Frame: Equatable, Encodable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
      self.x = x
      self.y = y
      self.width = width
      self.height = height
    }
  }
  public let id: String
  public let name: String
  public let builtIn: Bool
  public let frame: Frame?
  public init(id: String, name: String, builtIn: Bool, frame: Frame? = nil) {
    self.id = id
    self.name = name
    self.builtIn = builtIn
    self.frame = frame
  }
}

public struct MacOutputSettings: Equatable, Codable, Sendable {
  public enum Mode: String, Codable, Sendable { case fixedFullscreen, projectionWindow }
  public var mode: Mode
  public var displayID: String?
  public init(mode: Mode = .fixedFullscreen, displayID: String? = nil) {
    self.mode = mode
    self.displayID = displayID
  }
}

public struct PresentationRequest: Equatable, Sendable {
  public let mode: MacOutputSettings.Mode
  public let displayID: String?
  public let externalDisplayMode: ExternalDisplayMode?
  public let usesExternalDisplay: Bool
  public let externalDisplayRotation: ExternalDisplayRotation
  public init(
    mode: MacOutputSettings.Mode = .fixedFullscreen, displayID: String? = nil,
    externalDisplayMode: ExternalDisplayMode? = nil, usesExternalDisplay: Bool = false,
    externalDisplayRotation: ExternalDisplayRotation = .standard
  ) {
    self.mode = mode
    self.displayID = displayID
    self.externalDisplayMode = externalDisplayMode
    self.usesExternalDisplay = usesExternalDisplay
    self.externalDisplayRotation = externalDisplayRotation
  }
}

public enum DisplaySelection {
  public static func select(_ settings: MacOutputSettings, from displays: [DisplayDescriptor])
    -> DisplayDescriptor?
  {
    if settings.mode == .projectionWindow { return displays.first }
    if let id = settings.displayID { return displays.first { $0.id == id } }
    return displays.first { !$0.builtIn } ?? displays.first
  }
}
