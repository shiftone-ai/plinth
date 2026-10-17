import Foundation
import Testing

struct TestHTTPResponse {
  let status: Int
  let data: Data
  let text: String
  let headers: [AnyHashable: Any]
}

@MainActor
func request(
  _ url: URL, method: String = "GET", headers: [String: String] = [:], body: String? = nil
) async throws -> TestHTTPResponse {
  var request = URLRequest(url: url)
  request.httpMethod = method
  request.timeoutInterval = 5
  for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
  if let body {
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(body.utf8)
  }
  let (data, response) = try await URLSession.shared.data(for: request)
  let http = try #require(response as? HTTPURLResponse)
  return TestHTTPResponse(
    status: http.statusCode, data: data,
    text: String(bytes: data, encoding: .utf8) ?? "", headers: http.allHeaderFields)
}
