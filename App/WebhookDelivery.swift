import Foundation

/// Builds what a webhook receives and sends it.
enum WebhookDelivery {
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
  static func send(_ payload: Data, to url: URL) async -> WebhookResult {
    guard url.scheme?.lowercased() == "https" else {
      return WebhookResult(date: .now, succeeded: false, message: "https のURLだけに送信できます。")
    }
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Memora", forHTTPHeaderField: "User-Agent")
    request.httpBody = payload
    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      return (200..<300).contains(status)
        ? WebhookResult(date: .now, succeeded: true, message: "送信しました")
        : WebhookResult(date: .now, succeeded: false, message: "相手先が受け付けませんでした（\(status)）")
    } catch {
      return WebhookResult(date: .now, succeeded: false, message: "送信できませんでした。通信環境とURLを確認してください。")
    }
  }
}
