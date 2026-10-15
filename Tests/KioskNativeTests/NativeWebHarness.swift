import Foundation
import KioskCore
import KioskMacApp
import KioskRuntime

@MainActor
final class NativeWebHarness: EffectExecuting {
  var resultSink: (@MainActor (Event, NodeID) -> Void)?
  let adapter = WebKitAdapter()
  let events: AsyncStream<Event>
  private let continuation: AsyncStream<Event>.Continuation
  private(set) var runtime: RootRuntime!
  let controls = EffectTaskRegistry()
  init(clock: any ClockPort = MonotonicClock()) {
    let stream = AsyncStream<Event>.makeStream()
    events = stream.stream
    continuation = stream.continuation
    runtime = RootRuntime(clock: clock, executor: self)
    adapter.send = { [weak self] event in
      guard let self else { return nil }
      let reply = self.runtime.send(event, from: .webSurface).reply
      self.continuation.yield(event)
      return reply
    }
  }

  func execute(_ effect: Effect) {
    switch effect.kind {
    case .applyPresentation: resultSink?(.presentationApplied(effect.token), .platform)
    case .createSurface(let mode, let interaction):
      adapter.create(effect.token, mode: mode, interaction: interaction)
      resultSink?(.surfaceCreated(effect.token), .webSurface)
    case .releaseSurface:
      adapter.releaseSurface()
      resultSink?(.surfaceReleased(effect.token), .webSurface)
    case .load(let address):
      if !adapter.load(address, token: effect.token) {
        resultSink?(.webFailed(effect.token, .network), .webSurface)
      }
    case .controlExternalWeb(let control):
      controls.start(
        effect.token,
        operation: { [adapter] in
          await adapter.control(control, token: effect.token)
          return nil
        }, completion: { _ in })
    default: break
    }
  }

  func stop() {
    controls.cancelAll()
    adapter.stop()
    resultSink = nil
    continuation.finish()
  }

  func shutdown() {
    let previous = runtime
    runtime = nil
    previous?.stop()
  }
}
