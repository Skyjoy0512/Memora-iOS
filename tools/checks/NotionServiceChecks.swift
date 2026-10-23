import Foundation

@main
struct NotionServiceChecks {
  static let pageID = "44517d92-2356-498d-a923-d79d520667e0"
  static let pageURL = "https://www.notion.so/44517d922356498da923d79d520667e0"
  static let initial = NotionSaveConfiguration(token: "fixture-only", parentPageID: "fixture-parent")

  static func response(_ request: URLRequest, status: Int = 200,
    body: Data? = nil
  ) -> (Data, URLResponse) {
    let payload = body ?? Data("{\"id\":\"\(pageID)\",\"url\":\"\(pageURL)\"}".utf8)
    return (payload, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
  }

  static func failure(_ operation: () async throws -> NotionService.Outcome) async -> Error {
    do { _ = try await operation(); preconditionFailure("Expected a failure") }
    catch { return error }
  }

  static func checkPartial(_ error: Error, status: Int? = nil) {
    guard let partial = error as? NotionService.PartialPageFailure else {
      preconditionFailure("Created page identity was lost: \(error)")
    }
    precondition(partial.pageID == pageID && partial.pageURL?.absoluteString == pageURL)
    precondition(partial.status == status && !partial.message.isEmpty)
  }

  static func main() async throws {
    let short = Meeting()
    var long = short
    long.decisions = (0..<220).map { "Decision \($0)" }

    for config in [nil, NotionSaveConfiguration(token: "", parentPageID: "parent"),
      NotionSaveConfiguration(token: "token", parentPageID: "")] {
      var calls = 0
      let error = await failure {
        try await NotionService.save(meeting: short, tasks: [], configuration: { config }, transport: {
          calls += 1; return response($0)
        })
      }
      guard case NotionService.Failure.missingConfig = error else { preconditionFailure() }
      precondition(calls == 0)
    }

    // No invocation of the real Keychain, defaults or network is needed.
    var requests: [URLRequest] = []
    let included = MemoraTask(id: UUID(), title: "Included", meetingID: long.id,
      assignee: "Named owner", isCompleted: false)
    let excluded = MemoraTask(id: UUID(), title: "Excluded", meetingID: UUID(), isCompleted: false)
    let saved = try await NotionService.save(meeting: long, tasks: [included, excluded],
      configuration: { initial }, transport: { requests.append($0); return response($0) })
    precondition(saved.isComplete && saved.pageURL?.absoluteString == pageURL)
    precondition(requests.count == 3 && requests.map(\.httpMethod) == ["POST", "PATCH", "PATCH"])
    var childCounts: [Int] = []
    var allBodies = ""
    for (index, request) in requests.enumerated() {
      precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only")
      precondition(request.value(forHTTPHeaderField: "Notion-Version") == "2022-06-28")
      precondition(request.url?.host == "api.notion.com" && request.url?.scheme == "https")
      let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      childCounts.append((body["children"] as! [[String: Any]]).count)
      allBodies += String(decoding: request.httpBody!, as: UTF8.self)
      if index == 0 {
        precondition((body["parent"] as? [String: String])?["page_id"] == initial.parentPageID)
      } else { precondition(request.url?.path == "/v1/blocks/\(pageID)/children") }
    }
    precondition(childCounts == [100, 100, 26])
    precondition(allBodies.contains("Included") && !allBodies.contains("Excluded"))

    for status in [401, 403, 404, 429, 500, 502] {
      var calls = 0
      let error = await failure {
        try await NotionService.save(meeting: long, tasks: [], configuration: { initial }, transport: {
          calls += 1; return response($0, status: status)
        })
      }
      guard case NotionService.Failure.http(let actual) = error else { preconditionFailure() }
      precondition(actual == status && calls == 1)

      calls = 0
      let partial = await failure {
        try await NotionService.save(meeting: long, tasks: [], configuration: { initial }, transport: {
          calls += 1; return response($0, status: calls == 1 ? 200 : status)
        })
      }
      checkPartial(partial, status: status)
      precondition(calls == 2)
    }

    for transportError in [URLError(.timedOut) as Error, URLError(.notConnectedToInternet), CancellationError()] {
      for failAt in [1, 2, 3] {
        var calls = 0
        let error = await failure {
          try await NotionService.save(meeting: long, tasks: [], configuration: { initial }, transport: {
            calls += 1
            if calls == failAt { throw transportError }
            return response($0)
          })
        }
        if failAt == 1 {
          guard case NotionService.Failure.unknownOutcome = error else { preconditionFailure() }
        } else { checkPartial(error) }
        precondition(calls == failAt)
      }
    }

    for payload in ["not-json", "{}", "{\"id\":\"../escape\"}", "{\"id\":\"\"}"] {
      var calls = 0
      let error = await failure {
        try await NotionService.save(meeting: long, tasks: [], configuration: { initial }, transport: {
          calls += 1; return response($0, body: Data(payload.utf8))
        })
      }
      guard case NotionService.Failure.unknownOutcome = error else { preconditionFailure() }
      precondition(calls == 1)
    }
    for unsafeURL in ["http://www.notion.so/page", "javascript:alert(1)", "https://user:secret@www.notion.so/page"] {
      let payload = try JSONSerialization.data(withJSONObject: ["id": pageID, "url": unsafeURL])
      let outcome = try await NotionService.save(meeting: short, tasks: [], configuration: { initial },
        transport: { response($0, body: payload) })
      precondition(outcome.isComplete && outcome.pageURL == nil)
    }

    // Changes before transport, after creation, mid-append and after the last
    // append must all stop the run. A known page is never silently discarded.
    for replacement in [nil, NotionSaveConfiguration(token: "replacement", parentPageID: initial.parentPageID),
      NotionSaveConfiguration(token: initial.token, parentPageID: "different-parent")] {
      var reads = 0
      var calls = 0
      let before = await failure {
        try await NotionService.save(meeting: long, tasks: [], configuration: {
          reads += 1; return reads == 1 ? initial : replacement
        }, transport: { calls += 1; return response($0) })
      }
      guard case NotionService.Failure.configurationChanged = before else { preconditionFailure() }
      precondition(calls == 0)
      for changeAt in [1, 2, 3] {
        var config: NotionSaveConfiguration? = initial
        calls = 0
        let error = await failure {
          try await NotionService.save(meeting: long, tasks: [], configuration: { config }, transport: {
            calls += 1
            if calls == changeAt { config = replacement }
            return response($0)
          })
        }
        checkPartial(error)
        precondition(calls == changeAt)
      }
    }

    // Cancellation after a successful response can still have created a page,
    // including a single-batch save. Pre-cancelled operations never send.
    for cancelAt in [0, 1, 2, 3] {
      let result = await Task { () -> (Error, Int) in
        var calls = 0
        if cancelAt == 0 { withUnsafeCurrentTask { $0?.cancel() } }
        let error = await failure {
          try await NotionService.save(meeting: cancelAt == 1 ? short : long, tasks: [],
            configuration: { initial }, transport: {
              calls += 1
              if calls == cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
              return response($0)
            })
        }
        return (error, calls)
      }.value
      if cancelAt == 0 { precondition(result.0 is CancellationError) }
      else { checkPartial(result.0) }
      precondition(result.1 == cancelAt)
    }

    for failAt in [1, 2] {
      var calls = 0
      let error = await failure {
        try await NotionService.save(meeting: long, tasks: [], configuration: { initial }, transport: {
          calls += 1
          if calls == failAt { return (Data(), URLResponse(url: $0.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)) }
          return response($0)
        })
      }
      if failAt == 1 {
        guard case NotionService.Failure.unknownOutcome = error else { preconditionFailure() }
      } else { checkPartial(error) }
      precondition(calls == failAt)
    }

    for pauseAt in [1, 2] {
      for cancel in [false, true] {
        let gate = HTTPResponseGate()
        let configuration = NotionFixtureConfiguration(initial)
        let heldMeeting = long
        let operation = Task { () -> (Error, Int) in
          var calls = 0
          let error = await failure {
            try await NotionService.save(meeting: heldMeeting, tasks: [],
              configuration: { configuration.read() }, transport: {
                calls += 1
                if calls == pauseAt { await gate.pause() }
                return response($0)
              })
          }
          return (error, calls)
        }
        await gate.waitForRequest()
        if cancel { operation.cancel() } else { configuration.replace(nil) }
        await gate.release()
        let (error, calls) = await operation.value
        checkPartial(error)
        precondition(calls == pauseAt)
      }
    }

    let reconnected = NotionSaveConfiguration(token: "reconnected-fixture", parentPageID: "another-parent")
    var reconnectCalls = 0
    let recovered = try await NotionService.save(meeting: short, tasks: [], configuration: { reconnected }, transport: {
      reconnectCalls += 1
      precondition($0.value(forHTTPHeaderField: "Authorization") == "Bearer reconnected-fixture")
      return response($0)
    })
    precondition(recovered.isComplete && reconnectCalls == 1)
    print("Notion service checks passed: batching, HTTP failures, cancellation, configuration changes, partial-page recovery and explicit reconnect; fixture transport only, no accounts/network")
  }
}
