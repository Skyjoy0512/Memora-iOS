import Foundation

struct FirebaseMarketplaceClient {
  static var endpoint: URL? {
    guard let raw = Bundle.main.object(forInfoDictionaryKey: "MemoraMarketplaceURL") as? String,
          let url = URL(string: raw), url.scheme == "https", url.host != nil,
          url.user == nil, url.password == nil else { return nil }
    return url
  }
  static var isConfigured: Bool { endpoint != nil && !FirebaseCommunitySession.apiKey.isEmpty }

  @MainActor func call<T: Decodable>(_ body: [String:Any], authenticated: Bool = true) async throws -> T {
    guard let endpoint = Self.endpoint else { throw CommunityError.unconfigured }
    let generation = FirebaseCommunitySession.shared.generation
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"; request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if authenticated { request.setValue("Bearer \(try await FirebaseCommunitySession.shared.token())", forHTTPHeaderField: "Authorization") }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    guard !authenticated || generation == FirebaseCommunitySession.shared.generation else { throw CommunityError.loginRequired }
    let (bytes,response) = try await URLSession.shared.data(for: request)
    guard !authenticated || generation == FirebaseCommunitySession.shared.generation else { throw CommunityError.loginRequired }
    guard bytes.count <= 2 * 1024 * 1024 else { throw CommunityError.invalidContent }
    guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
      let error = try? JSONDecoder().decode(Failure.self, from: bytes)
      throw CommunityError.server(error?.error ?? "現在読み込めません。後でお試しください。")
    }
    return try JSONDecoder().decode(T.self, from: bytes)
  }
  private struct Failure: Decodable { var error: String }
}
