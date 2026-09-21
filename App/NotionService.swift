import Foundation

/// Saves a meeting to Notion using the person's own integration token.
enum NotionService {
  enum Failure: Error {
    case missingConfig
    case http(Int)
    /// The request may or may not have reached Notion. It is never retried on
    /// its own, so a slow answer cannot leave two pages behind.
    case unknownOutcome
  }

  /// Notion accepts at most this many blocks in one request.
  private static let blockLimit = 100

  /// The result of a save: the page that was written, and whether every block
  /// made it. A page that exists but is incomplete is reported with its URL
  /// rather than retried from scratch.
  struct Outcome {
    var pageURL: URL?
    var isComplete: Bool
  }

  static var isConfigured: Bool {
    guard let token = KeychainStore.string(forKey: "integration.notion"), !token.isEmpty else {
      return false
    }
    return !pageID.isEmpty
  }

  private static var pageID: String {
    UserDefaults.standard.string(forKey: "memora.notionPageID") ?? ""
  }

  static func save(meeting: Meeting, tasks: [MemoraTask]) async throws -> Outcome {
    guard let token = KeychainStore.string(forKey: "integration.notion"), !token.isEmpty, !pageID.isEmpty else {
      throw Failure.missingConfig
    }

    let children = blocks(meeting: meeting, tasks: tasks)
    let batches = stride(from: 0, to: max(children.count, 1), by: blockLimit).map { start in
      Array(children[start..<min(start + blockLimit, children.count)])
    }

    // The page is created with the first batch, so there is exactly one page
    // even when the record is long.
    let created = try await createPage(
      token: token,
      title: meeting.title,
      children: batches.first ?? []
    )

    for batch in batches.dropFirst() {
      do {
        try await append(token: token, pageID: created.pageID, children: batch)
      } catch Failure.http(let status) {
        // The page is there with part of the record; say so instead of adding
        // more pages.
        throw PartialPageFailure(status: status, pageID: created.pageID, pageURL: created.url)
      }
    }

    return Outcome(pageURL: created.url, isComplete: true)
  }

  /// A created page whose later blocks could not be added. Carries the page so
  /// the person can open what was written.
  struct PartialPageFailure: Error {
    var status: Int
    var pageID: String
    var pageURL: URL?

    var message: String {
      "ページは作成されましたが、一部の内容を追加できませんでした（\(status)）。"
    }
  }

  private struct CreatedPage {
    var pageID: String
    var url: URL?
  }

  private static func createPage(
    token: String,
    title: String,
    children: [[String: Any]]
  ) async throws -> CreatedPage {
    var request = URLRequest(url: URL(string: "https://api.notion.com/v1/pages")!)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "parent": ["type": "page_id", "page_id": pageID],
      "properties": ["title": ["title": [["type": "text", "text": ["content": title]]]]],
      "children": children
    ])

    let data = try await send(request)
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw Failure.unknownOutcome
    }
    guard let pageIdentifier = object["id"] as? String else {
      throw Failure.unknownOutcome
    }
    let url = (object["url"] as? String).flatMap(URL.init(string:))
    return CreatedPage(pageID: pageIdentifier, url: url)
  }

  private static func append(token: String, pageID: String, children: [[String: Any]]) async throws {
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
  private static func send(_ request: URLRequest) async throws -> Data {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw Failure.unknownOutcome
    }
    guard let http = response as? HTTPURLResponse else { throw Failure.unknownOutcome }
    guard (200..<300).contains(http.statusCode) else { throw Failure.http(http.statusCode) }
    return data
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

    paragraph("\(meeting.createdAt.formatted(date: .long, time: .shortened)) · \(MemoraFormat.duration(meeting.duration)) · \(meeting.source.label)")

    if !meeting.summary.isEmpty {
      heading("要約")
      paragraph(meeting.summary)
    }

    if !meeting.decisions.isEmpty {
      heading("決まったこと")
      meeting.decisions.forEach(bullet)
    }

    let meetingTasks = tasks.filter { $0.meetingID == meeting.id }
    if !meetingTasks.isEmpty {
      heading("次の行動")
      meetingTasks.forEach { task in
        if let assignee = task.assignee, !assignee.isEmpty {
          bullet("\(task.title)（\(assignee)）")
        } else {
          bullet(task.title)
        }
      }
    }

    if !meeting.openQuestions.isEmpty {
      heading("まだ決まっていないこと")
      meeting.openQuestions.forEach(bullet)
    }

    return children
  }
}
