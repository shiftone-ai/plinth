import KioskCore
import Testing

func fixtureProfile(startURL: String = "https://example.com/home") throws -> KioskProfile {
  let origin = try #require(Origin(urlString: "https://example.com"))
  return KioskProfile(
    startURL: startURL,
    navigation: .init(rules: [OriginRule(id: 1, origin: origin, includeSubdomains: true)]))
}

func envelope(_ event: Event, source: NodeID = .root, id: UInt64 = 1, now: Double = 0)
  -> EventEnvelope
{
  EventEnvelope(eventID: id, source: source, timestamp: now, event: event)
}

func handled<State>(_ result: Mediation<State>) -> Transition<State>? {
  if case .handled(let value) = result { return value }
  return nil
}

func requireToken(_ token: OperationToken?, sourceLocation: SourceLocation = #_sourceLocation)
  throws -> OperationToken
{
  try #require(token, sourceLocation: sourceLocation)
}

func readyExhibition(profile: KioskProfile) throws -> ExhibitionState {
  let start = try #require(
    handled(ExhibitionMediator.reduce(.init(), envelope(.activateExhibition(profile)))))
  let created = try #require(
    handled(
      ExhibitionMediator.reduce(
        start.state,
        envelope(
          .surfaceCreated(try requireToken(start.state.operation)), source: .webSurface, id: 2))))
  return try #require(
    handled(
      ExhibitionMediator.reduce(
        created.state,
        envelope(
          .webFinished(try requireToken(created.state.operation)), source: .webSurface, id: 3)))
  ).state
}
