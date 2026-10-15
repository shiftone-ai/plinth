import KioskCore

@MainActor
public protocol EffectExecuting: AnyObject {
  var resultSink: (@MainActor (Event, NodeID) -> Void)? { get set }
  func execute(_ effect: Effect)
  func stop()
}

@MainActor
public protocol EffectPort: AnyObject {
  func perform(_ effect: Effect) async -> Event?
  func cancel(_ token: OperationToken)
  func stop()
  func releasePointer()
  func confinePointer(_ point: SurfacePoint) -> Bool
}

extension EffectPort {
  public func cancel(_ token: OperationToken) {}
  public func releasePointer() {}
  public func confinePointer(_ point: SurfacePoint) -> Bool { false }
}
