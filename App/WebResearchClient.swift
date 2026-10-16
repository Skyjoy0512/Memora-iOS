import Foundation

enum WebResearchClient {
  static let keyName = "memora.braveSearch.apiKey"
  enum Failure: LocalizedError {
    case invalidQuery, noKey, invalidResponse, empty
    var errorDescription: String? {
      switch self {
      case .invalidQuery: "検索語は600文字・75語以内で入力してください。"
      case .noKey: "Web検索設定にBrave Search APIキーを登録してください。"
      case .invalidResponse: "検索サービスの応答を読み取れませんでした。設定や利用上限を確認してください。"
      case .empty: "参照できる検索結果がありません。検索語を変えてください。"
      }
    }
  }
  static func validate(_ query: String) throws -> String {
    let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.count <= 600, value.split(whereSeparator: \.isWhitespace).count <= 75,
          !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw Failure.invalidQuery }
    return value
  }
  static func request(query: String, mode: WebResearchReport.Mode, key: String) throws -> URLRequest {
    let query = try validate(query)
    guard !key.isEmpty, key.count <= 2_000,
          !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw Failure.noKey }
    let path = mode == .search ? "/res/v1/web/search" : "/res/v1/llm/context"
    var url = URLComponents(string: "https://api.search.brave.com\(path)")!
    var items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "count", value: "8"),
                 URLQueryItem(name: "safesearch", value: "moderate")]
    if mode == .deepResearch {
      items += [URLQueryItem(name: "maximum_number_of_urls", value: "6"),
                URLQueryItem(name: "maximum_number_of_tokens", value: "2048"),
                URLQueryItem(name: "maximum_number_of_snippets", value: "12"),
                URLQueryItem(name: "maximum_number_of_snippets_per_url", value: "2")]
    }
    url.queryItems = items
    guard let endpoint = url.url else { throw Failure.invalidQuery }
    var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
    return request
  }
  static func decode(_ data: Data, mode: WebResearchReport.Mode) throws -> [WebResearchSource] {
    guard data.count <= 2 * 1024 * 1024, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.invalidResponse }
    let parent = object[mode == .search ? "web" : "grounding"] as? [String: Any]
    guard let rows = parent?[mode == .search ? "results" : "generic"] as? [[String: Any]] else { throw Failure.invalidResponse }
    var result: [WebResearchSource] = [], seen = Set<URL>()
    for row in rows.prefix(20) {
      guard let raw = row["url"] as? String, let normalized = try? ProjectSourceURL.normalized(raw),
            normalized.kind == .web, seen.insert(normalized.url).inserted else { continue }
      let chunks = mode == .search ? [row["description"] as? String ?? ""] : (row["snippets"] as? [String] ?? [])
      let rawText = String(chunks.prefix(2).map { String($0.prefix(3_000)) }.joined(separator: "\n").prefix(5_000))
      let text = rawText.replacingOccurrences(of: "<[^>]{0,300}>", with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      result.append(WebResearchSource(title: String((row["title"] as? String ?? normalized.url.host ?? "Web").prefix(200)),
        url: normalized.url, text: text, kind: mode == .search ? .searchExcerpt : .extractedPassage,
        publishedAt: (row["page_age"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }))
      if result.count == 8 { break }
    }
    return result
  }
  static func search(query: String, mode: WebResearchReport.Mode, key: String) async throws -> [WebResearchSource] {
    let data = try await ProjectMetadataTransport.data(for: request(query: query, mode: mode, key: key),
      host: "api.search.brave.com", mimeTypes: ["application/json"], maximumBytes: 2 * 1024 * 1024)
    return try decode(data, mode: mode)
  }
}
