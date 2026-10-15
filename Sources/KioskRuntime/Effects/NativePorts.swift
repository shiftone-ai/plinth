import Foundation
import KioskCore

@MainActor
public protocol WebSurfacePort: AnyObject {
  func create(_ token: OperationToken, mode: ResetMode, interaction: InteractionPolicy)
  func load(_ address: String, token: OperationToken) -> Bool
  func control(_ control: ExternalWebControl, token: OperationToken) async
  func releaseSurface()
  func stop()
}

extension WebSurfacePort {
  public func control(_ control: ExternalWebControl, token: OperationToken) async {}
}

@MainActor
public protocol PresentationPort: AnyObject {
  func apply(_ request: PresentationRequest) -> Bool
  func release()
  func prepareExternalScene(_ token: OperationToken) async -> Bool
  func cancelScenePreparation(_ token: OperationToken)
  func prepareExternalDisplayMode(_ mode: ExternalDisplayMode?, token: OperationToken) async -> Bool
  func cancelDisplayModePreparation(_ token: OperationToken)
  func capturePointer(_ token: OperationToken) async -> Bool
  func releasePointer()
  func cancelPointerCapture(_ token: OperationToken)
  func confinePointer(_ point: SurfacePoint) -> Bool
}

extension PresentationPort {
  public func prepareExternalDisplayMode(_ mode: ExternalDisplayMode?, token: OperationToken) async
    -> Bool
  { false }
  public func cancelDisplayModePreparation(_ token: OperationToken) {}
  public func capturePointer(_ token: OperationToken) async -> Bool { false }
  public func releasePointer() {}
  public func cancelPointerCapture(_ token: OperationToken) {}
  public func confinePointer(_ point: SurfacePoint) -> Bool { false }
}

@MainActor
public protocol DisplayReadingPort: AnyObject {
  var count: Int { get }
  var exhibitionFrame: CGRect? { get }
  var availableDisplays: [DisplayDescriptor] { get }
  func frame(for displayID: String?) -> CGRect?
}

extension DisplayReadingPort {
  public var availableDisplays: [DisplayDescriptor] { [] }
  public func frame(for displayID: String?) -> CGRect? {
    displayID == nil ? exhibitionFrame : nil
  }
}
