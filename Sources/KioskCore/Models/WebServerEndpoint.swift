public struct WebServerEndpoint: Equatable, Sendable {
  public let url: String?
  public let origins: [Origin]

  public init(url: String?, origins: [Origin]) {
    self.url = url
    self.origins = origins
  }
}
