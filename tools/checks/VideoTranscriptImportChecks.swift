import Foundation
import SQLite3

@main struct VideoTranscriptImportChecks {
  @MainActor static func main() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("video-import-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("store.sqlite")
    let model = try MemoraModel(url)
    let project = MemoraSpace(id: UUID(), name: "字幕の保存先", symbol: "folder")
    model.spaces = [project]
    let source = ProjectSource(projectID: project.id, kind: .youtube, title: "検証動画",
      originalURL: URL(string: "https://www.youtube.com/watch?v=abc12345678"))
    model.projectSources = [source]
    let context = LocalImportContext(projectID: project.id, in: model)
    let text = "実際に貼り付けた字幕。\n" + String(repeating: "条件と具体例を残す。", count: 350)
    precondition(VideoTranscript.segments(" \n ") == nil)
    precondition(VideoTranscript.segments(String(repeating: "あ", count: 200_001)) == nil)
    let segments = VideoTranscript.segments(text)!
    precondition(segments.count > 1 && segments.map(\.text).joined() == text)
    precondition(segments.allSatisfy { $0.text.count <= 1_200 && !$0.speakerIsCertain })
    // Fail the second document in the SQLite transaction: neither link nor record may publish.
    var db: OpaquePointer?
    precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, "CREATE TRIGGER reject_video BEFORE INSERT ON documents WHEN NEW.key = 'sources' BEGIN SELECT RAISE(ABORT, 'fixture'); END", nil, nil, nil) == SQLITE_OK)
    precondition(model.importVideoTranscript(text, source: source, context: context) == nil)
    precondition(model.meetings.isEmpty && model.projectSources == [source])
    if case .data = model.store.readOutcome("meetings") { preconditionFailure("partial record persisted") }
    precondition(sqlite3_exec(db, "DROP TRIGGER reject_video", nil, nil, nil) == SQLITE_OK)
    let id = model.importVideoTranscript(text, source: source, context: context)!
    let record = model.meetings[0]
    precondition(record.id == id && record.transcript.map(\.text).joined() == text)
    precondition(record.summary.isEmpty && record.summaryUseCaseID == VideoSummaryTemplate.useCase.id)
    precondition(record.privacy == source.privacy && record.spaceID == project.id && record.audioURL == nil && record.duration == 0)
    precondition(record.notes.contains(source.originalURL!.absoluteString))
    precondition(model.importVideoTranscript(text, source: source, context: context) == id && model.meetings.count == 1)
    let reopened = LocalStore(fileURL: url)
    try reopened.prepare()
    guard case .data(let data) = reopened.readOutcome("meetings") else { preconditionFailure("record missing") }
    let restored = try JSONDecoder().decode([Meeting].self, from: data)[0]
    precondition(restored.summaryUseCaseID == record.summaryUseCaseID && restored.transcript == record.transcript)
    guard case .data(let links) = reopened.readOutcome("sources") else { preconditionFailure("link missing") }
    let restoredSource = try JSONDecoder().decode([ProjectSource].self, from: links)[0]
    precondition(restoredSource.metadata?["videoTranscriptMeetingID"] == id.uuidString && !restoredSource.canProvideText)
    for change in 0..<6 {
      model.projectSources = [source]
      model.meetings = []
      model.isRestoring = false; model.isStoreProtected = false; model.currentTeamID = nil
      let fresh = LocalImportContext(projectID: project.id, in: model)
      if change == 0 { model.aiWorkspaceGeneration = UUID() }
      if change == 1 { model.isRestoring = true }
      if change == 2 { model.isStoreProtected = true }
      if change == 3 { model.currentTeamID = UUID() }
      if change == 4 { model.projectSources[0].privacy.revokeExternalPermissions() }
      if change == 5 { model.projectSources = [] }
      precondition(model.importVideoTranscript(text, source: source, context: fresh) == nil)
      precondition(model.meetings.isEmpty)
    }
    print("VideoTranscriptImportChecks: passed (bounded exact text, no inference, privacy, duplicate prevention, atomic SQLite rollback/reopen, stale workspace/privacy/deletion guards; model state is a fixture)")
  }
}
