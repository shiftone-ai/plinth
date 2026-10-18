extension RootMediator {
  static func reduceInformation(
    _ state: RootState, _ envelope: EventEnvelope
  ) -> Mediation<RootState> {
    var next = state
    let token = envelope.token(owner: .root, epoch: state.epoch)
    switch envelope.event {
    case .openInformationPageRequested(let page, let locale):
      guard envelope.source == .settings else { return .reject(state, .wrongSource) }
      guard state.mode == .administration else { return .reject(state, .invalidState) }
      next.informationPageOperation = token
      return .handled(
        .init(
          next, reply: .accepted,
          effects: (state.informationPageOperation.map { [Effect(token, .cancelOperation($0))] }
            ?? [])
            + [Effect(token, .openInformationPage(page, locale: locale))]))

    case .informationPageOpenCompleted(let completed):
      guard envelope.source == .platform, state.informationPageOperation == completed else {
        return .reject(state, .staleOperation)
      }
      next.informationPageOperation = nil
      return .handled(.init(next))

    case .openLicensesRequested, .closeLicensesRequested:
      guard envelope.source == .settings else { return .reject(state, .wrongSource) }
      guard state.mode == .administration else { return .reject(state, .invalidState) }
      next.licenseSheetPresented = envelope.event == .openLicensesRequested
      return .handled(.init(next, reply: .accepted))

    default: return .bubble
    }
  }
}
