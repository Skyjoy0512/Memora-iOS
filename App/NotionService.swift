import Foundation

/// Saves a meeting to Notion using the person's own integration token.
enum NotionService {
  enum Failure: Error {
    case missingConfig
    case http(Int)
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

  static func save(meeting: Meeting, tasks: [MemoraTask]) async throws {
    guard let token = KeychainStore.string(forKey: "integration.notion"), !token.isEmpty, !pageID.isEmpty else {
      throw Failure.missingConfig
    }

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

    var request = URLRequest(url: URL(string: "https://api.notion.com/v1/pages")!)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "parent": ["type": "page_id", "page_id": pageID],
      "properties": ["title": ["title": [["type": "text", "text": ["content": meeting.title]]]]],
      "children": children
    ])

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw Failure.http(0) }
    guard (200..<300).contains(http.statusCode) else {
      throw Failure.http(http.statusCode)
    }
  }
}
