import Foundation

@main struct YouTubeCaptionChecks {
  @MainActor static func main() async throws {
    var refresh: String?
    var disconnected = false
    var calls: [String] = []
    var mode = "success"
    var permitted = true
    var owner: YouTubeCaptionService!
    let environment = YouTubeCaptionEnvironment(clientID: { "fixture.apps.googleusercontent.com" },
      refreshToken: { refresh }, storeRefreshToken: { refresh = $0; return true },
      isDisconnected: { disconnected }, setDisconnected: { disconnected = $0 },
      authorize: { url, scheme in
        let fields = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(fields.first { $0.name == "scope" }?.value == YouTubeCaptionService.scope)
        precondition(fields.first { $0.name == "code_challenge_method" }?.value == "S256")
        precondition(fields.first { $0.name == "code_challenge" }!.value!.count == 43)
        let state = fields.first { $0.name == "state" }!.value!
        return URL(string: "\(scheme):/oauth2redirect?state=\(mode == "badState" ? "wrong" : state)&code=fixture")!
      }, cancelAuthorization: {}, transport: { request in
        calls.append(request.url!.path)
        if request.url!.host == "oauth2.googleapis.com" {
          let scope = mode == "wrongScope" ? "gmail.readonly" : YouTubeCaptionService.scope
          return (200, Data("{\"access_token\":\"fixture-access\",\"refresh_token\":\"fixture-refresh\",\"expires_in\":3600,\"scope\":\"\(scope)\"}".utf8))
        }
        precondition(request.url?.host == "www.googleapis.com")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access")
        if request.url!.path == "/youtube/v3/captions" {
          if mode == "forbidden" { return (403, Data()) }
          if mode == "empty" { return (200, Data("{\"items\":[]}".utf8)) }
          if mode == "disconnect" { owner.disconnect() }
          if mode == "revoke" { permitted = false }
          return (200, Data("{\"items\":[{\"id\":\"caption_fixture\",\"snippet\":{\"language\":\"ja\",\"status\":\"serving\",\"isDraft\":false}}]}".utf8))
        }
        precondition(request.url!.path == "/youtube/v3/captions/caption_fixture")
        precondition(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "vtt")
        return (200, Data("WEBVTT\n\n00:00:03.000 --> 00:00:06.000\nOwner supplied captions\n".utf8))
      }, now: { Date(timeIntervalSince1970: 100_000) })
    owner = YouTubeCaptionService(environment: environment)
    do { _ = try await owner.captions(videoID: "memoraqa001"); preconditionFailure("Unauthenticated read") }
    catch YouTubeCaptionService.Failure.notConnected {}
    precondition(calls.isEmpty)
    try await owner.connect()
    precondition(owner.isConnected && refresh == "fixture-refresh")
    let text = try await owner.captions(videoID: "memoraqa001")
    precondition(SubtitleText.blocks(text).first?.time == 3 && text.contains("Owner supplied captions"))
    for value in ["forbidden", "empty", "revoke", "disconnect"] {
      mode = value; permitted = true
      let before = calls.filter { $0.hasSuffix("caption_fixture") }.count
      do { _ = try await owner.captions(videoID: "memoraqa001", isAuthorized: { permitted }); preconditionFailure("Unavailable caption accepted") }
      catch is YouTubeCaptionService.Failure {}
      precondition(calls.filter { $0.hasSuffix("caption_fixture") }.count == before)
    }
    precondition(!owner.isConnected && disconnected && refresh == nil)
    for value in ["badState", "wrongScope"] {
      mode = value
      do { try await owner.connect(); preconditionFailure("Invalid OAuth accepted") }
      catch is YouTubeCaptionService.Failure {}
      precondition(!owner.isConnected && refresh == nil)
    }
    print("YouTubeCaptionChecks: PASS. Production OAuth PKCE/state/scope checks, official list/download endpoints, supplied-caption timeline, 403/empty refusal, revocation/disconnect while fetching, no unauthorized download and separate refresh-token boundary. Mock authorization and HTTP only; no Google account or live API claim.")
  }
}
