import Foundation

/// Talks to a Hindsight memory server over its REST API: `recall` for what to
/// bring into an answer and `retain` for what the person just said, so Ask AI
/// personalizes from the server's long-term memory. Nothing is invented; when
/// the server cannot be reached the call fails and the answer goes on without
/// it.
enum HindsightClient {
  /// A memory as `recall` returns it.
  private struct RecallResponse: Decodable {
    struct Result: Decodable {
      var text: String
    }
    var results: [Result]
  }

  private struct ReflectResponse: Decodable {
    var text: String
  }

  /// The facts that bear on `query`, most relevant first.
  static func recall(query: String, config: HindsightConfig, token: String?) async throws -> [String] {
    let body: [String: Any] = [
      "query": query,
      "budget": "low",
      "max_tokens": 700
    ]
    let data = try await send(path: "memories/recall", method: "POST", body: body, config: config, token: token)
    return try JSONDecoder().decode(RecallResponse.self, from: data).results.map(\.text)
  }

  /// Stores one item. The server extracts the facts and links them in the
  /// background, so a retain returns before the memory is searchable.
  static func retain(content: String, context: String, config: HindsightConfig, token: String?) async throws {
    let item: [String: Any] = [
      "content": content,
      "context": context,
      "timestamp": ISO8601DateFormatter().string(from: .now)
    ]
    _ = try await send(path: "memories", method: "POST", body: ["items": [item]], config: config, token: token)
  }

  /// Answers from the server's memories with reasoning rather than lookup, for
  /// a question that benefits from it. Kept for a later use.
  static func reflect(query: String, config: HindsightConfig, token: String?) async throws -> String {
    let data = try await send(path: "reflect", method: "POST", body: ["query": query], config: config, token: token)
    return try JSONDecoder().decode(ReflectResponse.self, from: data).text
  }

  /// Checks the server answers, so the settings can say whether it is reachable.
  static func check(config: HindsightConfig, token: String?) async throws -> String {
    guard var components = URLComponents(string: normalizedBase(config.baseURL)) else {
      throw HindsightError.notConfigured
    }
    components.path = "/health"
    guard let url = components.url else { throw HindsightError.notConfigured }
    _ = try await send(url: url, method: "GET", body: nil, token: token)
    return "接続できました。"
  }

  // MARK: - Transport

  private static func send(
    path: String,
    method: String,
    body: [String: Any]?,
    config: HindsightConfig,
    token: String?
  ) async throws -> Data {
    guard config.isConfigured, let url = endpoint(config: config, path: path) else {
      throw HindsightError.notConfigured
    }
    return try await send(url: url, method: method, body: body, token: token)
  }

  private static func send(url: URL, method: String, body: [String: Any]?, token: String?) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token, !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw HindsightError.unreachable(error.localizedDescription)
    }
    guard let http = response as? HTTPURLResponse else {
      throw HindsightError.unreachable("応答を解釈できませんでした。")
    }
    guard (200..<300).contains(http.statusCode) else {
      throw HindsightError.server(http.statusCode, String(data: data, encoding: .utf8))
    }
    return data
  }

  /// The bank's endpoint for a path, e.g.
  /// `http://localhost:8888/v1/default/banks/memora/memories/recall`.
  private static func endpoint(config: HindsightConfig, path: String) -> URL? {
    guard var components = URLComponents(string: normalizedBase(config.baseURL)) else { return nil }
    let bank = config.bankID.trimmingCharacters(in: .whitespacesAndNewlines)
    components.path = "/v1/default/banks/\(bank)/\(path)"
    return components.url
  }

  private static func normalizedBase(_ base: String) -> String {
    var text = base.trimmingCharacters(in: .whitespacesAndNewlines)
    while text.hasSuffix("/") { text.removeLast() }
    return text
  }
}

/// Why a Hindsight call could not finish, in words the settings can show.
enum HindsightError: LocalizedError {
  case notConfigured
  case unreachable(String)
  case server(Int, String?)

  var errorDescription: String? {
    switch self {
    case .notConfigured:
      return "接続先またはbank idが未設定です。"
    case .unreachable(let message):
      return "Hindsightに接続できませんでした。\(message)"
    case .server(let status, let detail):
      let reason: String
      switch status {
      case 401, 403:
        reason = "APIキーを確認してください。"
      case 404:
        reason = "bank idまたはURLを確認してください。"
      default:
        reason = detail.map { String($0.prefix(200)) } ?? ""
      }
      return "Hindsightがエラーを返しました（\(status)）。\(reason)"
    }
  }
}
