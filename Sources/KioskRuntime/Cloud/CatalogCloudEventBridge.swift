import KioskCore

@MainActor
public final class CatalogCloudEventBridge {
  public weak var runtime: RootRuntime?

  public init() {}

  public func send(_ event: Event) {
    runtime?.send(event, from: .cloudCatalog)
  }
}
