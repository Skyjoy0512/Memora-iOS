import SwiftUI
import UIKit

/// Renders a meeting summary to a PDF file for the share sheet, so it can be
/// saved to Drive, sent to Notion, or attached to a message.
@MainActor
enum MeetingPDF {
  static func write(meeting: Meeting, tasks: [MemoraTask]) -> URL? {
    guard let data = data(meeting: meeting, tasks: tasks) else { return nil }

    let safeTitle = meeting.title
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeTitle).pdf")

    do {
      try data.write(to: url)
      return url
    } catch {
      return nil
    }
  }

  static func data(meeting: Meeting, tasks: [MemoraTask]) -> Data? {
    let renderer = ImageRenderer(content: MeetingPDFContent(meeting: meeting, tasks: tasks))
    renderer.proposedSize = ProposedViewSize(width: 595, height: nil)

    var result = Data()
    renderer.render { size, draw in
      let pageRect = CGRect(x: 0, y: 0, width: 595, height: max(size.height, 240))
      result = UIGraphicsPDFRenderer(bounds: pageRect).pdfData { context in
        context.beginPage()
        draw(context.cgContext)
      }
    }
    return result.isEmpty ? nil : result
  }
}

private struct MeetingPDFContent: View {
  var meeting: Meeting
  var tasks: [MemoraTask]

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      VStack(alignment: .leading, spacing: 6) {
        Text(meeting.title)
          .font(.title.bold())
        Text("\(meeting.createdAt.formatted(date: .long, time: .shortened)) · \(MemoraFormat.duration(meeting.duration)) · \(meeting.source.label)")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if !meeting.summary.isEmpty {
        section("要約", paragraphs: [meeting.summary])
      }

      if !meeting.decisions.isEmpty {
        section("決まったこと", bullets: meeting.decisions)
      }

      let meetingTasks = tasks.filter { $0.meetingID == meeting.id }
      if !meetingTasks.isEmpty {
        section("次の行動", bullets: meetingTasks.map { task in
          if let assignee = task.assignee, !assignee.isEmpty {
            return "\(task.title)（\(assignee)）"
          }
          return task.title
        })
      }

      if !meeting.openQuestions.isEmpty {
        section("まだ決まっていないこと", bullets: meeting.openQuestions)
      }

      if !meeting.keyPoints.isEmpty {
        section("重要なポイント", bullets: meeting.keyPoints)
      }

      Spacer(minLength: 0)

      Text("Memora")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(40)
    .frame(width: 595, alignment: .leading)
    .background(Color.white)
    .foregroundStyle(Color.black)
  }

  @ViewBuilder
  private func section(_ title: String, paragraphs: [String] = [], bullets: [String] = []) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)

      ForEach(paragraphs, id: \.self) { text in
        Text(text)
          .font(.body)
          .lineSpacing(3)
      }

      ForEach(bullets, id: \.self) { bullet in
        Text("・\(bullet)")
          .font(.body)
          .lineSpacing(3)
      }
    }
  }
}

/// Presents the system share sheet for files and text.
struct ActivityView: UIViewControllerRepresentable {
  var items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
