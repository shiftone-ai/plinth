import Foundation
import KioskCore
import Security

@MainActor
final class WebAdministrationHTTPHandler {
  private weak var runtime: RootRuntime?
  private let locale: @MainActor () -> Locale

  init(runtime: RootRuntime, locale: @escaping @MainActor () -> Locale) {
    self.runtime = runtime
    self.locale = locale
  }

  func handle(_ request: HTTPRequest, validHosts: Set<String>) -> HTTPResponse {
    guard let host = request.host, validHosts.contains(host) else { return HTTPResponse(403) }
    if let origin = request.origin, origin != "http://\(host)" { return HTTPResponse(403) }
    if request.method == "POST", request.origin == nil { return HTTPResponse(403) }
    if request.path.hasPrefix("/api/draft/") { return handleDraft(request) }
    if request.path.hasPrefix("/api/exhibition/") { return handleExhibition(request) }
    if ["/api/login", "/api/login/status", "/api/state"].contains(request.path) {
      return handleAuthentication(request)
    }
    return handlePage(request)
  }

  private func handlePage(_ request: HTTPRequest) -> HTTPResponse {
    switch (request.method, request.path) {
    case ("GET", "/"):
      return HTTPResponse(
        200, WebAdministrationPage.html(locale: locale()),
        contentType: "text/html; charset=utf-8")
    case ("GET", "/app.js"):
      return HTTPResponse(
        200, WebAdministrationPage.script,
        contentType: "text/javascript; charset=utf-8")
    case ("GET", "/app.css"):
      return HTTPResponse(
        200, WebAdministrationPage.style,
        contentType: "text/css; charset=utf-8")
    default: return HTTPResponse(404)
    }
  }

  private func handleAuthentication(_ request: HTTPRequest) -> HTTPResponse {
    switch (request.method, request.path) {
    case ("POST", "/api/login"):
      guard let input: LoginInput = jsonBody(request) else { return HTTPResponse(400) }
      guard let token = randomToken() else { return HTTPResponse(500) }
      let reply = runtime?.send(
        .webLoginRequested(password: input.password, candidate: token),
        from: .webAdministration
      ).reply
      switch reply {
      case .accepted: return json(202, LoginTicket(token: token))
      case .rejected(.cooldown): return HTTPResponse(429)
      default: return HTTPResponse(403)
      }
    case ("POST", "/api/login/status"):
      guard let input: TicketInput = jsonBody(request) else { return HTTPResponse(400) }
      let reply = runtime?.send(
        .webLoginStatusRequested(input.token), from: .webAdministration
      ).reply
      switch reply {
      case .webLoginStatus(.pending): return json(200, LoginStatus(status: "pending"))
      case .webLoginStatus(.failed): return json(200, LoginStatus(status: "failed"))
      case .webLoginStatus(.succeeded):
        guard
          runtime?.send(
            .webSessionRequested(input.token, activity: false), from: .webAdministration
          ).reply == .accepted
        else { return HTTPResponse(401) }
        return json(200, LoginStatus(status: "authenticated"))
      default: return HTTPResponse(401)
      }
    case ("GET", "/api/state"):
      guard authorized(request),
        let props = runtime?.webAdministrationProps.props
      else { return HTTPResponse(401) }
      return json(200, props)
    default: return HTTPResponse(404)
    }
  }

  private func handleDraft(_ request: HTTPRequest) -> HTTPResponse {
    switch (request.method, request.path) {
    case ("POST", "/api/draft/edit"):
      guard authorized(request) else { return HTTPResponse(401) }
      guard let input: WebDraftEditInput = jsonBody(request) else { return HTTPResponse(403) }
      return mutationResponse(
        runtime?.send(
          .draftEdited(input.edit), from: .webAdministration
        ).reply)
    case ("POST", "/api/draft/rules/add"):
      guard authorized(request) else { return HTTPResponse(401) }
      guard emptyJSONBody(request) else { return HTTPResponse(400) }
      return mutationResponse(
        runtime?.send(
          .addOriginRuleRequested, from: .webAdministration
        ).reply)
    case ("POST", "/api/draft/rules/remove"):
      guard authorized(request) else { return HTTPResponse(401) }
      guard let input: RuleRemovalInput = jsonBody(request) else { return HTTPResponse(400) }
      return mutationResponse(
        runtime?.send(
          .removeOriginRuleRequested(input.id), from: .webAdministration
        ).reply)
    case ("POST", "/api/draft/save"):
      guard authorized(request) else { return HTTPResponse(401) }
      guard emptyJSONBody(request) else { return HTTPResponse(400) }
      return mutationResponse(
        runtime?.send(
          .saveDraftRequested, from: .webAdministration
        ).reply, acceptedStatus: 202)
    case ("POST", "/api/draft/discard"):
      guard authorized(request) else { return HTTPResponse(401) }
      guard emptyJSONBody(request) else { return HTTPResponse(400) }
      return mutationResponse(
        runtime?.send(
          .discardDraftRequested, from: .webAdministration
        ).reply)
    default: return HTTPResponse(404)
    }
  }

  private func handleExhibition(_ request: HTTPRequest) -> HTTPResponse {
    switch (request.method, request.path) {
    case ("POST", "/api/exhibition/start"):
      guard authorized(request) else { return HTTPResponse(401) }
      guard emptyJSONBody(request) else { return HTTPResponse(400) }
      return mutationResponse(
        runtime?.send(
          .startExhibitionRequested, from: .webAdministration
        ).reply,
        acceptedStatus: 202)
    case ("POST", "/api/exhibition/restart"):
      guard authorized(request) else { return HTTPResponse(401) }
      guard emptyJSONBody(request) else { return HTTPResponse(400) }
      return mutationResponse(
        runtime?.send(
          .webRestartExhibitionRequested, from: .webAdministration
        ).reply,
        acceptedStatus: 202)
    case ("POST", "/api/exhibition/stop"):
      guard authorized(request) else { return HTTPResponse(401) }
      guard emptyJSONBody(request) else { return HTTPResponse(400) }
      return mutationResponse(
        runtime?.send(
          .webStopExhibitionRequested, from: .webAdministration
        ).reply,
        acceptedStatus: 202)
    case ("POST", "/api/exhibition/resume"):
      guard authorized(request) else { return HTTPResponse(401) }
      guard emptyJSONBody(request) else { return HTTPResponse(400) }
      return mutationResponse(
        runtime?.send(
          .webResumeExhibitionRequested, from: .webAdministration
        ).reply,
        acceptedStatus: 202)
    default: return HTTPResponse(404)
    }
  }

  private func authorized(_ request: HTTPRequest) -> Bool {
    guard let token = bearerToken(request) else { return false }
    return runtime?.send(
      .webSessionRequested(token, activity: request.method == "POST"),
      from: .webAdministration
    ).reply == .accepted
  }

  private func emptyJSONBody(_ request: HTTPRequest) -> Bool {
    guard request.headers["content-type"] == "application/json",
      let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]
    else { return false }
    return object.isEmpty
  }

  private func mutationResponse(_ reply: Reply?, acceptedStatus: Int = 200) -> HTTPResponse {
    switch reply {
    case .accepted:
      guard let props = runtime?.webAdministrationProps.props else { return HTTPResponse(503) }
      return json(acceptedStatus, props)
    case .rejected(let reason):
      let status: Int
      switch reason {
      case .invalidProfile: status = 422
      case .invalidState, .alreadySaving, .unsavedDraft, .unsupportedDisplays: status = 409
      case .unauthenticated: status = 401
      default: status = 403
      }
      return json(status, RemoteRejection(reason: reason.rawValue))
    default: return HTTPResponse(403)
    }
  }

  private func jsonBody<T: Decodable>(_ request: HTTPRequest) -> T? {
    guard request.headers["content-type"] == "application/json" else { return nil }
    return try? JSONDecoder().decode(T.self, from: request.body)
  }

  private func bearerToken(_ request: HTTPRequest) -> String? {
    guard let header = request.headers["authorization"], header.hasPrefix("Bearer ") else {
      return nil
    }
    return String(header.dropFirst("Bearer ".count))
  }

  private func randomToken() -> String? {
    var bytes = [UInt8](repeating: 0, count: 32)
    let result = bytes.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
    }
    guard result == errSecSuccess else { return nil }
    return bytes.map { String(format: "%02x", $0) }.joined()
  }

  private func json<T: Encodable>(_ code: Int, _ value: T) -> HTTPResponse {
    guard let data = try? JSONEncoder().encode(value) else { return HTTPResponse(500) }
    return HTTPResponse(code, body: data, contentType: "application/json; charset=utf-8")
  }
}

private struct LoginInput: Decodable { let password: String }
private struct TicketInput: Decodable { let token: String }
private struct LoginTicket: Encodable { let token: String }
private struct LoginStatus: Encodable { let status: String }
private struct RemoteRejection: Encodable { let reason: String }
private struct RuleRemovalInput: Decodable {
  let id: UInt64
  private enum Key: String, CodingKey { case id }
  init(from decoder: any Decoder) throws {
    let allKeys = try decoder.container(keyedBy: AnyCodingKey.self)
    let values = try decoder.container(keyedBy: Key.self)
    guard Set(allKeys.allKeys.map(\.stringValue)) == ["id"] else {
      throw DecodingError.dataCorruptedError(
        forKey: .id, in: values,
        debugDescription: "Unexpected field")
    }
    id = try values.decode(UInt64.self, forKey: .id)
  }
}

private struct WebDraftEditInput: Decodable {
  let edit: ProfileDraftEdit

  private enum Key: String, CodingKey { case field, value, id }

  init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: Key.self)
    let field = try values.decode(String.self, forKey: .field)
    let allKeys = try decoder.container(keyedBy: AnyCodingKey.self)
    let expected: Set<String> =
      field == "originAddress"
      ? ["field", "value", "id"] : ["field", "value"]
    guard Set(allKeys.allKeys.map(\.stringValue)) == expected else {
      throw DecodingError.dataCorruptedError(
        forKey: .field, in: values,
        debugDescription: "Unexpected field")
    }
    switch field {
    case "startURL": edit = .startURL(try values.decode(String.self, forKey: .value))
    case "navigationMode":
      edit = .navigationMode(
        try values.decode(NavigationPolicy.Mode.self, forKey: .value))
    case "allowsHTTP": edit = .allowsHTTP(try values.decode(Bool.self, forKey: .value))
    case "allowsScroll": edit = .allowsScroll(try values.decode(Bool.self, forKey: .value))
    case "allowsDrag": edit = .allowsDrag(try values.decode(Bool.self, forKey: .value))
    case "idleTimeoutText":
      edit = .idleTimeoutText(
        try values.decode(
          String.self,
          forKey: .value))
    case "resetMode": edit = .resetMode(try values.decode(ResetMode.self, forKey: .value))
    case "originAddress":
      edit = .originAddress(
        try values.decode(UInt64.self, forKey: .id),
        try values.decode(String.self, forKey: .value))
    case "exhibitionDestination":
      let destination = try values.decode(ExhibitionDestination.self, forKey: .value)
      edit = .exhibitionDestination(destination == .device ? nil : destination)
    case "externalDisplayMode":
      edit = .externalDisplayMode(
        try values.decodeIfPresent(ExternalDisplayMode.self, forKey: .value))
    case "externalDisplayRotation":
      edit = .externalDisplayRotation(
        try values.decode(ExternalDisplayRotation.self, forKey: .value))
    case "macOutputMode":
      edit = .macOutputMode(
        try values.decode(MacOutputSettings.Mode.self, forKey: .value))
    case "macDisplayID":
      edit = .macDisplayID(
        try values.decodeIfPresent(String.self, forKey: .value))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .field, in: values,
        debugDescription: "Field cannot be edited remotely")
    }
  }
}

private struct AnyCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil
  init(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}
