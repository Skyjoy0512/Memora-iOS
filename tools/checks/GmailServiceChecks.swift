import CryptoKit
import Foundation

@main
struct GmailServiceChecks {
  @MainActor static func failure<T>(_ operation: () async throws -> T) async -> Error {
    do { _ = try await operation(); preconditionFailure("Expected refusal") } catch { return error }
  }

  static func expectExternal(_ error: Error, _ expected: ExternalToolFailure) {
    precondition((error as? ExternalToolFailure)?.localizedDescription == expected.localizedDescription)
  }

  @MainActor static func main() async throws {
    try await connectionAndRefresh()
    await failures()
    await storageAndConfigurationFailures()
    try await disconnectWhileRevoking()
    try await staleReadResponses()
    try await staleAuthorization()
    try await staleInvalidGrant()
    try await readDuringAccountReplacement()
    await cancelledReads()
    print("GmailServiceChecks: passed (production connection/read/refresh/disconnect, immediate local refusal, persisted disconnect tombstone, HTTP failures, cancellation, stale responses, PKCE/callback/scope and message-ID validation; fixture browser/storage/clock/HTTP only, no accounts/network)")
  }

  @MainActor static func connectionAndRefresh() async throws {
    let fixture = GmailServiceFixture()
    fixture.refresh = nil
    let service = GmailService(environment: fixture.environment)
    precondition(!service.isConnected)
    let error = await failure { try await service.read("message1") }
    guard case GmailError.notConnected = error else { preconditionFailure() }
    precondition(fixture.requests.isEmpty)
    try await service.connect()
    precondition(service.isConnected && !service.isWorking && !fixture.disconnected)
    precondition(service.connectedEmail == "connected@example.invalid" && fixture.refresh == "new-fixture-refresh")
    let auth = URLComponents(url: fixture.authorizations[0], resolvingAgainstBaseURL: false)!.queryItems!
    let token = fixture.requests.first { $0.url!.path == "/token" }!
    let form = URLComponents(string: "?" + String(decoding: token.httpBody!, as: UTF8.self))!.queryItems!
    let verifier = form.first { $0.name == "code_verifier" }!.value!
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    precondition(auth.first { $0.name == "code_challenge" }!.value == challenge)
    let before = fixture.requests.count
    let result = try await service.search("  fixture query  ", limit: 1)
    precondition(result.count == 1 && result[0].id == "message1" && result[0].body.isEmpty)
    precondition(fixture.requests.count == before + 2)
    let list = URLComponents(url: fixture.requests[before].url!, resolvingAgainstBaseURL: false)!.queryItems!
    precondition(list.first { $0.name == "maxResults" }!.value == "1")
    precondition(list.first { $0.name == "q" }!.value == "fixture query")
    let mail = try await service.read("message1")
    precondition(mail.body == "本文のfixture" && mail.snippet == "Fixture & text")
    fixture.now.addTimeInterval(3601)
    _ = try await service.read("message1")
    precondition(fixture.requests.filter { $0.url!.path == "/token" }.count == 2)
    precondition(fixture.requests.filter { $0.url!.host == "gmail.googleapis.com" }
      .allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access" })
  }

  @MainActor static func failures() async {
    for status in [401, 403, 404, 429, 500, 502] {
      for tokenFailure in [false, true] {
        let fixture = GmailServiceFixture()
        let service = GmailService(environment: fixture.environment)
        fixture.transportOverride = { request in
          fixture.response(request, status: request.url!.path == "/token" && !tokenFailure ? 200 : status,
            json: request.url!.path == "/token" && !tokenFailure ? nil : ["error": "fixture-error"])
        }
        let error = await failure { try await service.read("message1") }
        expectExternal(error, .http(status))
        precondition(service.isConnected && !fixture.disconnected)
        precondition(fixture.requests.count == (tokenFailure ? 1 : 2))
      }
    }
    for status in [400, 500] {
      let fixture = GmailServiceFixture()
      let service = GmailService(environment: fixture.environment)
      fixture.transportOverride = { fixture.response($0, status: status, json: ["error": "invalid_grant"]) }
      let error = await failure { try await service.read("message1") }
      expectExternal(error, status == 400 ? .authenticationExpired : .failed)
      precondition(service.isConnected == (status == 500) && fixture.disconnected == (status == 400))
    }
    for transportError in [URLError(.timedOut) as Error, URLError(.notConnectedToInternet)] {
      let fixture = GmailServiceFixture()
      let service = GmailService(environment: fixture.environment)
      fixture.transportOverride = { _ in throw transportError }
      _ = await failure { try await service.read("message1") }
      precondition(service.isConnected && fixture.requests.count == 1)
    }
    for id in ["", "../profile", "message1/../../profile", "message1?format=raw", "message1#fragment", "%2f", "bad id", String(repeating: "a", count: 513)] {
      let fixture = GmailServiceFixture()
      let service = GmailService(environment: fixture.environment)
      expectExternal(await failure { try await service.read(id) }, .unavailable)
      precondition(fixture.requests.isEmpty)
    }
    for mode in 0..<5 {
      let fixture = GmailServiceFixture()
      let service = GmailService(environment: fixture.environment)
      fixture.transportOverride = { request in
        if request.url!.path == "/token" { return fixture.response(request) }
        switch mode {
        case 0: return (Data("not-json".utf8), fixture.response(request).1)
        case 1: return fixture.response(request, json: ["id": "another-message"])
        case 2: return fixture.response(request, json: ["messages": "wrong-type"])
        case 3: return fixture.response(request, json: ["messages": [["missing": "id"]]])
        default: return fixture.response(request, json: ["messages": [["id": "../profile"]]])
        }
      }
      _ = await failure {
        if mode < 2 { _ = try await service.read("message1") }
        else { _ = try await service.search("fixture", limit: 8) }
      }
      precondition(fixture.requests.count == 2)
    }
    for mode in 0..<5 {
      let fixture = GmailServiceFixture()
      fixture.refresh = nil
      let service = GmailService(environment: fixture.environment)
      fixture.authorizeOverride = { url, scheme in
        let valid = fixture.callback(url, scheme)
        switch mode {
        case 0: return URL(string: valid.absoluteString.replacingOccurrences(of: "state=", with: "state=wrong"))!
        case 1: return URL(string: valid.absoluteString + "&state=duplicate")!
        case 2: return URL(string: valid.absoluteString.replacingOccurrences(of: "/oauth2redirect", with: "/wrong"))!
        case 3: return URL(string: valid.absoluteString + "&code=duplicate")!
        default: throw GmailError.cancelled
        }
      }
      _ = await failure { try await service.connect() }
      precondition(!service.isConnected && !service.isWorking && fixture.requests.isEmpty && fixture.refresh == nil)
    }
    for payload in [["access_token": "", "refresh_token": "fixture"],
      ["access_token": "fixture", "refresh_token": "fixture", "scope": "openid email"],
      ["access_token": "fixture", "refresh_token": "fixture", "expires_in": -1]] as [[String: Any]] {
      let fixture = GmailServiceFixture()
      fixture.refresh = nil
      let service = GmailService(environment: fixture.environment)
      fixture.transportOverride = { fixture.response($0, json: payload) }
      _ = await failure { try await service.connect() }
      precondition(!service.isConnected && !service.isWorking && fixture.refresh == nil && fixture.requests.count == 1)
    }
    let fixture = GmailServiceFixture()
    let service = GmailService(environment: fixture.environment)
    _ = try! await service.read("message1")
    fixture.transportOverride = { fixture.response($0, status: 401) }
    _ = await failure { try await service.read("message1") }
    fixture.transportOverride = nil
    _ = try! await service.read("message1")
    precondition(fixture.requests.filter { $0.url!.path == "/token" }.count == 2)
  }

  @MainActor static func disconnectWhileRevoking() async throws {
    let fixture = GmailServiceFixture()
    let service = GmailService(environment: fixture.environment)
    _ = try await service.read("message1")
    fixture.failsStorage = true
    let gate = HTTPResponseGate()
    fixture.transportOverride = { request in
      precondition(request.url!.path == "/revoke")
      await gate.pause()
      throw URLError(.timedOut)
    }
    let oldRevision = service.connectionRevision
    let operation = Task { await service.disconnect() }
    await gate.waitForRequest()
    precondition(!service.isConnected && service.connectedEmail == nil && service.isWorking)
    precondition(fixture.disconnected && fixture.refresh != nil && fixture.email == nil && service.connectionRevision != oldRevision)
    let before = fixture.requests.count
    _ = await failure { try await service.read("message1") }
    _ = await failure { try await service.search("fixture", limit: 8) }
    _ = await failure { try await service.connect() }
    await service.disconnect()
    precondition(fixture.requests.count == before && fixture.authorizations.isEmpty)
    let reloaded = GmailService(environment: fixture.environment)
    precondition(!reloaded.isConnected)
    _ = await failure { try await reloaded.read("message1") }
    precondition(fixture.requests.count == before)
    await gate.release()
    await operation.value
    precondition(!service.isWorking && !service.isConnected && fixture.disconnected)
    fixture.failsStorage = false
    fixture.transportOverride = nil
    try await service.connect()
    precondition(service.isConnected && !fixture.disconnected && !service.isWorking)
  }

  @MainActor static func storageAndConfigurationFailures() async {
    let unconfigured = GmailServiceFixture()
    unconfigured.clientID = nil
    let missing = GmailService(environment: unconfigured.environment)
    for error in [await failure { try await missing.connect() }, await failure { try await missing.read("message1") }] {
      guard case GmailError.notConfigured = error else { preconditionFailure() }
    }
    precondition(unconfigured.requests.isEmpty && unconfigured.authorizations.isEmpty && !missing.isWorking)

    let storage = GmailServiceFixture()
    storage.disconnected = true
    storage.failsStorage = true
    let service = GmailService(environment: storage.environment)
    _ = await failure { try await service.connect() }
    precondition(!service.isConnected && !service.isWorking && storage.disconnected)
    precondition(storage.refresh == "fixture-refresh" && storage.requests.count == 1)

    let invalid = GmailServiceFixture()
    invalid.failsStorage = true
    let invalidService = GmailService(environment: invalid.environment)
    invalid.transportOverride = { invalid.response($0, status: 400, json: ["error": "invalid_grant"]) }
    expectExternal(await failure { try await invalidService.read("message1") }, .authenticationExpired)
    precondition(invalid.disconnected && invalid.refresh != nil && !invalidService.isConnected)
    precondition(!GmailService(environment: invalid.environment).isConnected)

    for status in [400, 500] {
      let fixture = GmailServiceFixture()
      let service = GmailService(environment: fixture.environment)
      fixture.transportOverride = { fixture.response($0, status: status) }
      await service.disconnect()
      precondition(!service.isConnected && !service.isWorking && fixture.disconnected && fixture.refresh == nil)
      precondition(fixture.requests.count == 1)
    }
  }

  @MainActor static func staleReadResponses() async throws {
    for phase in ["token", "messages", "message1"] {
      let fixture = GmailServiceFixture()
      let service = GmailService(environment: fixture.environment)
      let gate = HTTPResponseGate()
      fixture.transportOverride = { request in
        if request.url!.lastPathComponent == phase { await gate.pause() }
        return fixture.response(request)
      }
      let operation = Task { await failure { try await service.search("fixture", limit: 2) } }
      await gate.waitForRequest()
      await service.disconnect()
      fixture.transportOverride = nil
      try await service.connect()
      let newRevision = service.connectionRevision
      await gate.release()
      expectExternal(await operation.value, .authenticationExpired)
      precondition(service.isConnected && service.connectionRevision == newRevision && fixture.refresh == "new-fixture-refresh")
      precondition(service.connectedEmail == "connected@example.invalid")
    }
  }

  @MainActor static func staleAuthorization() async throws {
    let fixture = GmailServiceFixture()
    fixture.refresh = nil
    let service = GmailService(environment: fixture.environment)
    let oldAuth = HTTPResponseGate()
    fixture.authorizeOverride = { url, scheme in
      let callback = fixture.callback(url, scheme)
      await oldAuth.pause()
      return callback
    }
    let old = Task { await failure { try await service.connect() } }
    await oldAuth.waitForRequest()
    await service.disconnect()
    fixture.authorizeOverride = nil
    let profile = HTTPResponseGate()
    fixture.transportOverride = { request in
      if request.url!.lastPathComponent == "profile" { await profile.pause() }
      return fixture.response(request)
    }
    let new = Task { try await service.connect() }
    await profile.waitForRequest()
    await oldAuth.release()
    let error = await old.value
    guard case GmailError.cancelled = error else { preconditionFailure() }
    precondition(service.isWorking && service.isConnected)
    await profile.release()
    try await new.value
    precondition(!service.isWorking && service.connectedEmail == "connected@example.invalid")
  }

  @MainActor static func staleInvalidGrant() async throws {
    let fixture = GmailServiceFixture()
    let service = GmailService(environment: fixture.environment)
    let gate = HTTPResponseGate()
    fixture.transportOverride = { request in
      if request.url!.path == "/token" {
        await gate.pause()
        return fixture.response(request, status: 400, json: ["error": "invalid_grant"])
      }
      return fixture.response(request)
    }
    let old = Task { await failure { try await service.read("message1") } }
    await gate.waitForRequest()
    await service.disconnect()
    fixture.transportOverride = nil
    try await service.connect()
    let revision = service.connectionRevision
    await gate.release()
    expectExternal(await old.value, .authenticationExpired)
    precondition(service.isConnected && !fixture.disconnected && service.connectionRevision == revision)
    precondition(fixture.refresh == "new-fixture-refresh")
  }

  @MainActor static func readDuringAccountReplacement() async throws {
    let fixture = GmailServiceFixture()
    let service = GmailService(environment: fixture.environment)
    _ = try await service.read("message1")
    let authorization = HTTPResponseGate()
    fixture.authorizeOverride = { url, scheme in
      let callback = fixture.callback(url, scheme)
      await authorization.pause()
      return callback
    }
    let login = Task { try await service.connect() }
    await authorization.waitForRequest()
    let beforeCommit = service.connectionRevision
    let read = HTTPResponseGate()
    fixture.transportOverride = { request in
      if request.url!.lastPathComponent == "message1" { await read.pause() }
      return fixture.response(request)
    }
    let previousAccount = Task { await failure { try await service.read("message1") } }
    await read.waitForRequest()
    await authorization.release()
    try await login.value
    precondition(service.connectionRevision != beforeCommit)
    await read.release()
    expectExternal(await previousAccount.value, .authenticationExpired)
    precondition(service.isConnected && !service.isWorking && service.connectedEmail == "connected@example.invalid")
  }

  @MainActor static func cancelledReads() async {
    for phase in ["before", "token", "message1"] {
      let fixture = GmailServiceFixture()
      let service = GmailService(environment: fixture.environment)
      let gate = HTTPResponseGate()
      fixture.transportOverride = { request in
        if request.url!.lastPathComponent == phase { await gate.pause() }
        return fixture.response(request)
      }
      let operation = Task { await failure {
        if phase == "before" { withUnsafeCurrentTask { $0?.cancel() } }
        return try await service.read("message1")
      } }
      if phase != "before" {
        await gate.waitForRequest()
        operation.cancel()
        await gate.release()
      }
      let error = await operation.value
      precondition(error is CancellationError)
      precondition(fixture.requests.count == (phase == "before" ? 0 : phase == "token" ? 1 : 2))
    }
  }
}
