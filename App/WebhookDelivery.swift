import Foundation

/// Builds what a webhook receives and sends it.
enum WebhookDelivery {
  static let maximumPayloadBytes = 512 * 1024
  static let maximumResponseBytes = 64 * 1024
  /// The record as the receiver sees it. Built on the main actor from the
  /// stored record, so it says exactly what the app shows.
  static func payload(for meeting: Meeting, tasks: [MemoraTask], format: WebhookEndpoint.Format, isTest: Bool) -> Data {
    let body: [String: Any]
    switch format {
    case .json:
      body = [
        "event": isTest ? "test" : "summary.completed",
        "source": "Memora",
        "meeting": [
          "id": meeting.id.uuidString,
          "title": meeting.displayTitle,
          "recordedAt": ISO8601DateFormatter().string(from: meeting.createdAt),
          "durationSeconds": Int(meeting.duration),
          "summaryMarkdown": meeting.summary,
          "overview": meeting.summaryPreview,
          "decisions": meeting.decisions,
          "openQuestions": meeting.openQuestions,
          "keyPoints": meeting.keyPoints,
          "tasks": tasks.map { task in
            [
              "title": task.title,
              "assignee": task.assignee ?? "",
              "dueDate": task.dueDate.map { ISO8601DateFormatter().string(from: $0) } ?? "",
              "completed": task.isCompleted
            ] as [String: Any]
          }
        ] as [String: Any]
      ]
    case .slack:
      var lines = ["*\(meeting.displayTitle)*（\(meeting.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "ja_JP"))))）"]
      if isTest { lines.insert("Memoraからのテスト送信です。", at: 0) }
      let overview = meeting.summaryPreview.trimmingCharacters(in: .whitespacesAndNewlines)
      if !overview.isEmpty { lines.append(String(overview.prefix(600))) }
      if !meeting.decisions.isEmpty {
        lines.append("\n*決まったこと*\n" + meeting.decisions.prefix(8).map { "• \($0)" }.joined(separator: "\n"))
      }
      let open = tasks.filter { !$0.isCompleted }
      if !open.isEmpty {
        lines.append("\n*次にすること*\n" + open.prefix(10).map { task in
          let owner = task.assignee.map { "（\($0)）" } ?? ""
          return "• \(task.title)\(owner)"
        }.joined(separator: "\n"))
      }
      body = ["text": lines.joined(separator: "\n")]
    }
    return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
  }

  /// Sends one payload. Only an https URL is accepted, so a record never
  /// leaves the device unencrypted.
  @MainActor
  static func send(_ payload: Data, to url: URL,
                   configuration: URLSessionConfiguration = .ephemeral,
                   authorize: @escaping @MainActor @Sendable () -> Bool) async -> WebhookResult {
    guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
          url.user == nil, url.password == nil else {
      return WebhookResult(date: .now, succeeded: false, message: "https のURLだけに送信できます。")
    }
    guard !payload.isEmpty, payload.count <= maximumPayloadBytes else {
      return WebhookResult(date: .now, succeeded: false, message: "送信する内容が大きすぎるため、送信を止めました。")
    }
    guard !Task.isCancelled, authorize() else { return cancelledResult }
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Memora", forHTTPHeaderField: "User-Agent")
    request.httpBody = payload
    let settings = (configuration.copy() as? URLSessionConfiguration) ?? .ephemeral
    settings.httpShouldSetCookies = false
    settings.httpCookieStorage = nil
    settings.urlCredentialStorage = nil
    settings.urlCache = nil
    settings.timeoutIntervalForResource = 20
    let session = URLSession(configuration: settings, delegate: WebhookRedirectPolicy(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    do {
      guard !Task.isCancelled, authorize() else { return cancelledResult }
      let (bytes, response) = try await session.bytes(for: request)
      guard !Task.isCancelled, authorize() else { return cancelledResult }
      guard response.expectedContentLength <= maximumResponseBytes else { return oversizedResponseResult }
      var count = 0
      for try await _ in bytes {
        try Task.checkCancellation()
        guard count < maximumResponseBytes else { return oversizedResponseResult }
        count += 1
      }
      guard !Task.isCancelled, authorize() else { return cancelledResult }
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      return (200..<300).contains(status)
        ? WebhookResult(date: .now, succeeded: true, message: "送信しました")
        : WebhookResult(date: .now, succeeded: false, message: "相手先が受け付けませんでした（\(status)）")
    } catch {
      if Task.isCancelled || !authorize() { return cancelledResult }
      return WebhookResult(date: .now, succeeded: false, message: "送信できませんでした。通信環境とURLを確認してください。")
    }
  }

  private static var cancelledResult: WebhookResult {
    .init(date: .now, succeeded: false, message: "設定や送信許可が変わったため、送信を中止しました。")
  }

  private static var oversizedResponseResult: WebhookResult {
    .init(date: .now, succeeded: false, message: "相手先の応答が大きすぎるため、通信を中止しました。")
  }
}
