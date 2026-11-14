import Foundation
import PDFKit

@main struct MeetingPDFChecks {
  @MainActor static func main() async throws {
    let id = UUID()
    let rows = (1...48).map { "| ROW-\($0) | 確認内容を省略せず、行を保って印刷します。 | 未定 |" }.joined(separator: "\n")
    let summary = "## 議題\n\n**数値123.45**を維持します。\n\n| 項目 | 内容 | 期限 |\n| --- | --- | --- |\n" + rows
    let meeting = Meeting(id: id, title: "架空の会議PDF検証", createdAt: Date(timeIntervalSince1970: 0),
      duration: 1860, source: Source(), summary: summary,
      decisions: ["決定DECISION-END"], openQuestions: ["未決QUESTION-END"], keyPoints: ["重要POINT-END"])
    let tasks = [MemoraTask(title: "除外OTHER-RECORD", meetingID: UUID(), assignee: nil),
                 MemoraTask(title: "行動ACTION-FIRST", meetingID: id, assignee: "担当者A"),
                 MemoraTask(title: "行動ACTION-LAST", meetingID: id, assignee: "", isCompleted: true)]
    var seenWriting = false
    let url = try await MeetingPDF.write(meeting: meeting, tasks: tasks) { progress in
      if case .writing = progress { seenWriting = true }
    }
    defer { ArtifactExportFile.removeTemporary([url]) }
    guard let pdf = PDFDocument(url: url), let text = pdf.string else { fatalError("PDF unreadable") }
    let compact = text.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
    for expected in [meeting.title, "31:00", "録音", "要約", "数値123.45", "ROW-48", "補足の決定事項", "決定DECISION-END",
                     "タスク（現在の状態）", "[未完了]行動ACTION-FIRST（担当者A）", "[完了]行動ACTION-LAST", "補足の未決事項", "未決QUESTION-END", "補足の要点", "重要POINT-END"] {
      precondition(compact.contains(expected), "Missing content: \(expected)")
    }
    precondition(!text.contains("OTHER-RECORD") && pdf.pageCount > 1)
    precondition(text.range(of: "ACTION-FIRST")!.lowerBound < text.range(of: "ACTION-LAST")!.lowerBound)
    await Task.yield()
    precondition(seenWriting)
    let plain = try MeetingPDFContent(title: "空", metadata: "日付", summary: "#ThisIsPlain", decisions: [],
      actions: ["#LiteralAction"], openQuestions: [], keyPoints: []).input()
    precondition(plain.blocks == [.heading(level: 2, text: "要約"), .paragraph("#ThisIsPlain"),
      .heading(level: 2, text: "タスク（現在の状態）"), .bullet(level: 0, marker: .dot, text: "#LiteralAction")])
    let deduplicated = try MeetingPDFContent(title: "本文と同じ事実", metadata: "", summary: "- **承認後に公開する**",
      decisions: ["承認後に公開する"], actions: [], openQuestions: [], keyPoints: []).input()
    precondition(!(deduplicated.blocks ?? []).contains(.heading(level: 2, text: "補足の決定事項")))
    let empty = try MeetingPDFContent(title: "空", metadata: "日付", summary: "", decisions: [], actions: [], openQuestions: [], keyPoints: []).input()
    precondition(empty.blocks == [], "invented empty sections")
    // Cancel when real layout has finished and page writing starts.
    var longMeeting = meeting
    longMeeting.title = "memora-cancel-" + UUID().uuidString
    longMeeting.summary = (1...2_000).map { "段落\($0)。改ページの処理を中断します。" }.joined(separator: "\n\n")
    var cancelled: Task<URL, Error>?
    var cancelledDuringWriting = false
    cancelled = Task {
      try await MeetingPDF.write(meeting: longMeeting, tasks: []) { progress in
        if case .writing = progress {
          cancelledDuringWriting = true
          cancelled?.cancel()
        }
      }
    }
    do {
      let unexpected = try await cancelled!.value
      ArtifactExportFile.removeTemporary([unexpected])
      preconditionFailure("cancelled wrapper returned a file")
    } catch is CancellationError { }
    precondition(cancelledDuringWriting)
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
    precondition(!leftovers.contains { $0.hasPrefix(longMeeting.title) }, "cancel left an output or partial file")
    if CommandLine.arguments.count > 1 {
      let destination = URL(fileURLWithPath: CommandLine.arguments[1])
      try FileManager.default.copyItem(at: url, to: destination)
    }
    print("MeetingPDFChecks passed: \(pdf.pageCount) searchable pages; all existing sections, summary table, metadata, task scope/order/assignee, empty/plain sections, wrapper cancellation")
  }
}

// Minimal snapshots keep the production wrapper host-testable without the SwiftUI model graph.
struct Meeting {
  var id: UUID; var title: String; var createdAt: Date; var duration: TimeInterval; var source: Source
  var summary: String; var decisions: [String]; var openQuestions: [String]; var keyPoints: [String]
  var displayTitle: String { title }
}
struct Source { var label: String { "録音" } }
struct MemoraTask { var title: String; var meetingID: UUID?; var assignee: String?; var isCompleted = false }
enum MemoraFormat { static func duration(_ value: TimeInterval) -> String { "31:00" } }
