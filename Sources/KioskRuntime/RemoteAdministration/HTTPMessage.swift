import Foundation

struct HTTPRequest {
  let method: String
  let path: String
  let headers: [String: String]
  let body: Data

  var host: String? { headers["host"] }
  var origin: String? { headers["origin"] }

  enum ParseResult {
    case incomplete
    case invalid
    case complete(HTTPRequest)
  }

  private struct Head {
    let method: String
    let path: String
    let headers: [String: String]
  }

  static func parse(_ bytes: Data) -> ParseResult {
    guard bytes.count <= 32_768 else { return .invalid }
    guard let end = bytes.range(of: Data("\r\n\r\n".utf8)) else {
      return bytes.count <= 8_192 ? .incomplete : .invalid
    }
    guard end.lowerBound <= 8_192,
      let head = String(data: bytes[..<end.lowerBound], encoding: .utf8),
      let parsed = parseHead(head)
    else { return .invalid }
    let headers = parsed.headers
    let length: Int
    if let rawLength = headers["content-length"] {
      guard let value = Int(rawLength), value >= 0, value <= 16_384 else { return .invalid }
      length = value
    } else {
      length = 0
    }
    guard parsed.method != "POST" || headers["content-length"] != nil else { return .invalid }
    let bodyStart = end.upperBound
    guard bytes.count >= bodyStart + length else { return .incomplete }
    guard bytes.count == bodyStart + length else { return .invalid }
    return .complete(
      HTTPRequest(
        method: parsed.method, path: parsed.path, headers: headers,
        body: bytes[bodyStart...]))
  }

  private static func parseHead(_ head: String) -> Head? {
    let lines = head.components(separatedBy: "\r\n")
    guard let first = lines.first else { return nil }
    let words = first.split(separator: " ", omittingEmptySubsequences: false)
    guard words.count == 3, ["GET", "POST"].contains(words[0]), words[2] == "HTTP/1.1",
      words[1].first == "/", !words[1].contains("#"), !words[1].contains("\\")
    else { return nil }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { return nil }
      let key = line[..<colon].lowercased()
      guard
        key.utf8.allSatisfy({
          (48...57).contains($0) || (97...122).contains($0) || $0 == 45
        }), headers[key] == nil
      else { return nil }
      let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      guard !value.contains("\r"), !value.contains("\n"), !value.contains("\0") else {
        return nil
      }
      headers[key] = value
    }
    guard headers["host"] != nil, headers["transfer-encoding"] == nil else { return nil }
    return Head(method: String(words[0]), path: String(words[1]), headers: headers)
  }
}

struct HTTPResponse {
  let status: Int
  let contentType: String
  let body: Data

  init(_ status: Int, _ body: String = "", contentType: String = "text/plain; charset=utf-8") {
    self.status = status
    self.contentType = contentType
    self.body = Data(body.utf8)
  }

  init(_ status: Int, body: Data, contentType: String) {
    self.status = status
    self.contentType = contentType
    self.body = body
  }

  var data: Data {
    let reason: String
    switch status {
    case 200: reason = "OK"
    case 202: reason = "Accepted"
    case 400: reason = "Bad Request"
    case 401: reason = "Unauthorized"
    case 403: reason = "Forbidden"
    case 404: reason = "Not Found"
    case 405: reason = "Method Not Allowed"
    case 409: reason = "Conflict"
    case 422: reason = "Unprocessable Content"
    case 413: reason = "Content Too Large"
    case 429: reason = "Too Many Requests"
    case 503: reason = "Service Unavailable"
    default: reason = "Internal Server Error"
    }
    let header =
      "HTTP/1.1 \(status) \(reason)\r\n"
      + "Content-Type: \(contentType)\r\n"
      + "Content-Length: \(body.count)\r\n"
      + "Connection: close\r\n"
      + "Cache-Control: no-store\r\n"
      + "X-Content-Type-Options: nosniff\r\n"
      + "Referrer-Policy: no-referrer\r\n"
      + "Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; "
      + "connect-src 'self'; form-action 'none'; base-uri 'none'; frame-ancestors 'none'\r\n\r\n"
    return Data(header.utf8) + body
  }
}
