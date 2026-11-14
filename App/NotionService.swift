import Foundation

/// Saves a meeting to Notion using the person's own integration token.
enum NotionService {
  enum Failure: Error {
    case missingConfig
    case configurationChanged
    case authorizationChanged
    case http(Int)
    /// The request may or may not have reached Notion. It is never retried on
    /// its own, so a slow answer cannot leave two pages behind.
    case unknownOutcome
  }

  /// Notion accepts at most this many blocks in one request.
  private static let blockLimit = 100
  private static let configurationRevision = IntegrationConfigurationRevision()

  static func configurationDidChange() { configurationRevision.invalidate() }

  @discardableResult
  static func storeToken(_ token: String?) -> Bool {
    configurationDidChange()
    return KeychainStore.set(token, forKey: "integration.notion")
  }

  /// The result of a save: the page that was written, and whether every block
  /// made it. A page that exists but is incomplete is reported with its URL
  /// rather than retried from scratch.
  struct Outcome {
    var pageURL: URL?
    var isComplete: Bool
  }

  static var isConfigured: Bool {
    currentConfiguration() != nil
  }

  static func currentConfiguration() -> NotionSaveConfiguration? {
    readConfiguration(token: { KeychainStore.string(forKey: "integration.notion") },
      parentPageID: { UserDefaults.standard.string(forKey: "memora.notionPageID") })
  }

  static func readConfiguration(token: () -> String?, parentPageID: () -> String?) -> NotionSaveConfiguration? {
    let revision = configurationRevision.current()
    guard let token = token(), !token.isEmpty,
          let pageID = parentPageID(), !pageID.isEmpty,
          configurationRevision.current() == revision else { return nil }
    return NotionSaveConfiguration(token: token, parentPageID: pageID, revision: revision)
  }

  static func save(meeting: Meeting, tasks: [MemoraTask],
    configuration: @escaping () -> NotionSaveConfiguration?,
    transport: @escaping (URLRequest) async throws -> (Data, URLResponse),
    isAuthorized: @escaping @MainActor @Sendable () -> Bool = { true }
  ) async throws -> Outcome {
    try Task.checkCancellation()
    guard let captured = configuration(), !captured.token.isEmpty, !captured.parentPageID.isEmpty else {
      throw Failure.missingConfig
    }
    let sendRequest: (URLRequest) async throws -> Data = { request in
      // Validate immediately before each transport call, including after an
      // executor hop into createPage/append. Never substitute new credentials.
      try ensureCurrent(captured, configuration: configuration)
      guard await isAuthorized() else { throw Failure.authorizationChanged }
      try ensureCurrent(captured, configuration: configuration)
      return try await send(request, transport: transport)
    }

    let children = blocks(meeting: meeting, tasks: tasks)
    let batches = stride(from: 0, to: max(children.count, 1), by: blockLimit).map { start in
      Array(children[start..<min(start + blockLimit, children.count)])
    }

    // The page is created with the first batch, so there is exactly one page
    // even when the record is long.
    let created = try await createPage(
      configuration: captured,
      title: meeting.displayTitle,
      children: batches.first ?? [],
      send: sendRequest
    )

    do {
      guard await isAuthorized() else { throw Failure.authorizationChanged }
      try ensureCurrent(captured, configuration: configuration)
      for batch in batches.dropFirst() {
        try await append(token: captured.token, pageID: created.pageID, children: batch, send: sendRequest)
        guard await isAuthorized() else { throw Failure.authorizationChanged }
        try ensureCurrent(captured, configuration: configuration)
      }
    } catch {
      // A timeout/cancellation or revoked configuration after page creation is
      // not evidence that the page vanished. Preserve its identity for recovery.
      let status: Int?
      if case Failure.http(let code) = error { status = code } else { status = nil }
      throw PartialPageFailure(status: status, pageID: created.pageID, pageURL: created.url)
    }

    return Outcome(pageURL: created.url, isComplete: true)
  }

  /// A created page whose later blocks could not be added. Carries the page so
  /// the person can open what was written.
  struct PartialPageFailure: Error {
    var status: Int?
    var pageID: String
    var pageURL: URL?

    var message: String {
      if let status { return String(localized: "ページは作成されましたが、一部の内容を追加できませんでした（\(status)）。") }
      return String(localized: "ページは作成されましたが、内容の保存を確認できませんでした。Notionで確認してください。自動では再作成しません。")
    }
  }

  private struct CreatedPage {
    var pageID: String
    var url: URL?
  }

  private static func createPage(
    configuration: NotionSaveConfiguration,
    title: String,
    children: [[String: Any]],
    send: (URLRequest) async throws -> Data
  ) async throws -> CreatedPage {
    var request = URLRequest(url: URL(string: "https://api.notion.com/v1/pages")!)
    request.httpMethod = "POST"
    request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
    request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "parent": ["type": "page_id", "page_id": configuration.parentPageID],
      "properties": ["title": ["title": [["type": "text", "text": ["content": title]]]]],
      "children": children
    ])

    let data = try await send(request)
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw Failure.unknownOutcome
    }
    guard let pageIdentifier = object["id"] as? String, UUID(uuidString: pageIdentifier) != nil else {
      throw Failure.unknownOutcome
    }
    let url = (object["url"] as? String).flatMap(URL.init(string:)).flatMap { value in
      value.scheme?.lowercased() == "https" && value.host != nil && value.user == nil && value.password == nil ? value : nil
    }
    return CreatedPage(pageID: pageIdentifier, url: url)
  }

  private static func append(token: String, pageID: String, children: [[String: Any]],
    send: (URLRequest) async throws -> Data
  ) async throws {
    var request = URLRequest(
      url: URL(string: "https://api.notion.com/v1/blocks/\(pageID)/children")!
    )
    request.httpMethod = "PATCH"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["children": children])
    _ = try await send(request)
  }

  /// Sends a request and returns its body. A transport error is reported as an
  /// unknown outcome, because Notion may have received it.
  private static func send(_ request: URLRequest,
    transport: (URLRequest) async throws -> (Data, URLResponse)
  ) async throws -> Data {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await transport(request)
    } catch {
      throw Failure.unknownOutcome
    }
    guard let http = response as? HTTPURLResponse else { throw Failure.unknownOutcome }
    guard (200..<300).contains(http.statusCode) else { throw Failure.http(http.statusCode) }
    return data
  }

  private static func ensureCurrent(_ captured: NotionSaveConfiguration,
    configuration: () -> NotionSaveConfiguration?
  ) throws {
    try Task.checkCancellation()
    guard configuration() == captured else { throw Failure.configurationChanged }
  }

  private static func blocks(meeting: Meeting, tasks: [MemoraTask]) -> [[String: Any]] {
    var children: [[String: Any]] = []
    func heading(_ text: String) {
      children.append([
        "object": "block", "type": "heading_2",
        "heading_2": ["rich_text": [["type": "text", "text": ["content": text]]]]
      ])
    }
    func paragraph(_ text: String) {
      children.append([
        "object": "block", "type": "paragraph",
        "paragraph": ["rich_text": [["type": "text", "text": ["content": text]]]]
      ])
    }
    func bullet(_ text: String) {
      children.append([
        "object": "block", "type": "bulleted_list_item",
        "bulleted_list_item": ["rich_text": [["type": "text", "text": ["content": text]]]]
      ])
    }

    paragraph("\(meeting.createdAt.formatted(Date.FormatStyle(date: .long, time: .shortened).locale(Locale(identifier: "ja_JP")))) · \(MemoraFormat.duration(meeting.duration)) · \(meeting.source.label)")

    if !meeting.summary.isEmpty {
      heading("要約")
      paragraph(meeting.summary)
    }

    let decisions = SummaryContentProjection.supplements(meeting.decisions, markdown: meeting.summary)
    if !decisions.isEmpty {
      heading("決まったこと")
      decisions.forEach(bullet)
    }

    let meetingTasks = tasks.filter { $0.meetingID == meeting.id }
    if !meetingTasks.isEmpty {
      heading("タスク（現在の状態）")
      meetingTasks.forEach { task in
        let state = task.isCompleted ? "完了" : "未完了"
        if let assignee = task.assignee, !assignee.isEmpty {
          bullet("[\(state)] \(task.title)（\(assignee)）")
        } else {
          bullet("[\(state)] \(task.title)")
        }
      }
    }

    let questions = SummaryContentProjection.supplements(meeting.openQuestions, markdown: meeting.summary)
    if !questions.isEmpty {
      heading("まだ決まっていないこと")
      questions.forEach(bullet)
    }

    return children
  }
}
