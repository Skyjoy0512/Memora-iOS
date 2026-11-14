import Foundation

@MainActor
enum MeetingPDF {
  static func write(meeting: Meeting, tasks: [MemoraTask],
                    onProgress: @escaping @MainActor @Sendable (DocumentPDFProgress) -> Void) async throws -> URL {
    try Task.checkCancellation()
    onProgress(.preparing)
    let content = MeetingPDFContent(title: meeting.displayTitle,
      metadata: "\(meeting.createdAt.formatted(Date.FormatStyle(date: .long, time: .shortened).locale(Locale(identifier: "ja_JP")))) · \(MemoraFormat.duration(meeting.duration)) · \(meeting.source.label)",
      summary: meeting.summary, decisions: meeting.decisions,
      actions: tasks.filter { $0.meetingID == meeting.id }.map { task in
        let state = task.isCompleted ? "完了" : "未完了"
        if let assignee = task.assignee, !assignee.isEmpty { return "[\(state)] \(task.title)（\(assignee)）" }
        return "[\(state)] \(task.title)"
      }, openQuestions: meeting.openQuestions, keyPoints: meeting.keyPoints)
    let cleaned = meeting.displayTitle.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
      .joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    let name = cleaned.isEmpty ? "記録" : String(cleaned.prefix(60))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).pdf")
    let worker = Task.detached(priority: .userInitiated) {
      try DocumentPDFRenderer.write(content.input(), to: url) { value in
        Task { @MainActor in onProgress(value) }
      }
    }
    let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    do {
      try Task.checkCancellation()
      return result
    } catch {
      ArtifactExportFile.removeTemporary([result])
      throw error
    }
  }
}
