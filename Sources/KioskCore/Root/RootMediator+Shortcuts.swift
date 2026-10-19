extension RootMediator {
  static func reduceShortcutReset(
    _ state: RootState, _ envelope: EventEnvelope, context: ReadonlyContext
  ) -> Mediation<RootState> {
    guard envelope.source == .platform else { return .reject(state, .wrongSource) }
    if state.mobileExhibitionResumePending,
      [.safeHold, .enteringKiosk].contains(state.mode),
      !state.shortcutResetAcceptedDuringResume, !state.administratorSession,
      let profile = state.activeProfile, state.canPresent(profile)
    {
      var next = state
      next.shortcutResetAcceptedDuringResume = true
      return .handled(.init(next, reply: .accepted))
    }
    guard state.mode == .exhibiting, context.webAvailable,
      let profile = state.activeProfile
    else { return .reject(state, .invalidState) }
    var next = state
    next.input = .init()
    return .handled(
      .init(
        next, reply: .accepted,
        childControls: [.init(.exhibition, .resetExhibition(profile.resetMode))]))
  }
}
