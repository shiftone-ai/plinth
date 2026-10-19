import Foundation

extension RootMediator {
  static func reduceRemoteCommands(
    _ state: RootState, _ envelope: EventEnvelope, context: ReadonlyContext
  ) -> Mediation<RootState> {
    let client = reduceRemoteCommandClient(state, envelope)
    if case .bubble = client {
      return reduceRemoteCommandTarget(state, envelope, context: context)
    }
    return client
  }
}
