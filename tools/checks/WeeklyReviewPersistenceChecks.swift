import Foundation

// Production review/model logic with a deterministic persistence failure seam.
@main struct WeeklyReviewPersistenceChecks {
  static func main() {
    let model = MemoraModel()
    if case .noContent = model.makeWeeklyReview(containing: .now) {} else { preconditionFailure("empty week") }
    model.meetings = [Meeting()]
    model.rejectWrites = true
    if case .failed = model.makeWeeklyReview(containing: .now) {} else { preconditionFailure("failed initial save") }
    precondition(model.documents.isEmpty)
    model.rejectWrites = false
    guard case .saved(let first) = model.makeWeeklyReview(containing: .now) else { preconditionFailure("first review") }
    model.documents[0].markdown += "\n自分の追記"
    let before = model.documents
    model.meetings[0].decisions = ["新しい決定"]
    model.rejectWrites = true
    if case .failed = model.makeWeeklyReview(containing: .now) {} else { preconditionFailure("failed rewrite") }
    precondition(model.documents == before, "failed save published a candidate")
    model.rejectWrites = false
    guard case .saved(let revised) = model.makeWeeklyReview(containing: .now) else { preconditionFailure("retry") }
    precondition(revised.id == first.id && revised.markdown.hasSuffix("自分の追記") && revised.markdown.contains("新しい決定"))
    model.documents[0].markdown = "自分で本文を全面編集"
    guard case .saved(let personal) = model.makeWeeklyReview(containing: .now) else { preconditionFailure() }
    precondition(personal.markdown == "自分で本文を全面編集")
    print("WeeklyReviewPersistenceChecks passed: empty vs failure, failed create/rewrite preserve memory, retry retains ID/notes, personal rewrite preserved")
  }
}

struct MemoraDocument: Equatable, Codable {
  var id = UUID()
  var title: String
  enum Kind: Codable { case document }
  var kind: Kind
  var markdown: String
  var weekStart: Date?
  var generatedReviewMarkdown: String?
  var updatedAt = Date.now
  var openedAt: Date?
}
struct Meeting {
  var id = UUID()
  var createdAt = Date.now
  var duration: Double = 60
  var displayTitle = "実際の会議"
  var spaceID: UUID?
  var summaryPreview = "記録された内容"
  var decisions: [String] = []
}
struct MemoraTask {
  var isCompleted = false
  var completedAt: Date?
  var dueDate: Date?
  var meetingID: UUID?
  var title = "作業"
  var assignee: String?
}
struct LifeLogEntry {
  var occurredAt = Date.now
  enum Kind { case memo, photo, location }
  var kind = Kind.memo
  var locationName: String?
  var title = "記録"
  var summary = "本文"
}
enum SampleContent {
  static func isSample(meetingID: UUID) -> Bool { false }
  static func isSample(task: MemoraTask) -> Bool { false }
  static func isSample(lifeLogEntry: LifeLogEntry) -> Bool { false }
}
final class MemoraModel {
  var documents: [MemoraDocument] = []
  var meetings: [Meeting] = []
  var tasks: [MemoraTask] = []
  var lifeLogEntries: [LifeLogEntry] = []
  struct Space { var id: UUID; var name: String }
  var spaces: [Space] = []
  var hasCompletedOnboarding = true
  var isRestoring = false
  var isStoreProtected = false
  var rejectWrites = false
  enum StorageKey { static let documents = "documents" }
  func isStoreWritable() -> Bool { !isStoreProtected }
  func persistNow<T: Encodable>(_ value: T, forKey key: String) -> Bool { !rejectWrites }
  func persistDocuments() {}
  func addDocument(_ document: MemoraDocument) -> Bool {
    guard !rejectWrites else { return false }
    documents.insert(document, at: 0); return true
  }
}
