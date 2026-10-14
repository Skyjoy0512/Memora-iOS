import Foundation

/// A proposal stays separate from MemoraTask until the edited batch is approved.
struct AgentTaskDraft: Identifiable, Hashable, Sendable {
  var id = UUID()
  var title: String
  var detail = ""
  var assignee = ""
  var dueDate: Date?
  var meetingID: UUID?
  var isSelected = true

  var isValid: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 500
      && detail.count <= 4_000 && assignee.count <= 120
      && (dueDate?.timeIntervalSince1970.isFinite ?? true)
  }

  static func parse(_ items: [[String: Any]]) throws -> [Self] {
    guard (1...30).contains(items.count) else { throw Failure.invalid }
    return try items.map { item in
      guard Set(item.keys).isSubset(of: ["title", "detail", "assignee", "due_date", "meeting_id"]),
            item.values.allSatisfy({ $0 is String }) else { throw Failure.invalid }
      var draft = Self(title: (item["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
        detail: (item["detail"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
        assignee: (item["assignee"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
      if let text = item["meeting_id"] as? String, !text.isEmpty {
        guard let id = UUID(uuidString: text) else { throw Failure.invalid }
        draft.meetingID = id
      }
      if let text = item["due_date"] as? String, !text.isEmpty {
        guard let date = ReviewPeriod.parseDay(text) else { throw Failure.invalid }
        draft.dueDate = date
      }
      guard draft.isValid else { throw Failure.invalid }
      return draft
    }
  }

  static func validatedSelection(_ edited: [Self], originals: [Self], allowedMeetingIDs: Set<UUID>) -> [Self]? {
    guard (1...30).contains(edited.count), Set(edited.map(\.id)).count == edited.count else { return nil }
    let originalByID = Dictionary(originals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    guard edited.allSatisfy({ draft in
      draft.isValid && originalByID[draft.id]?.meetingID == draft.meetingID
        && originalByID[draft.id] != nil && (draft.meetingID.map(allowedMeetingIDs.contains) ?? true)
    }) else { return nil }
    let selected = edited.filter(\.isSelected)
    return selected.isEmpty ? nil : selected
  }

  enum Failure: Error { case invalid }
}
