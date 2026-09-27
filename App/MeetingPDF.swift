import SwiftUI
import UIKit

/// Renders a meeting summary to an A4 PDF file for the share sheet, so it can
/// be saved to Drive, sent to Notion, or attached to a message. Long records
/// continue onto further pages, each numbered.
@MainActor
enum MeetingPDF {
  enum ExportError: Error {
    /// The record could not be drawn at all.
    case renderFailed
    /// The pages could not be written to a file.
    case writeFailed
    /// The export was cancelled before it finished.
    case cancelled
  }

  /// A4 at 72 dpi. These are plain values and pure drawing, so the pagination
  /// can use them off the main actor.
  private nonisolated static let pageSize = CGSize(width: 595, height: 842)
  private nonisolated static let footerHeight: CGFloat = 36

  /// Renders the record to a temporary A4 PDF. Drawing the text needs the main
  /// actor; building the pages does not, so that part runs off it and reports
  /// progress page by page. Cancelling the calling task stops the work.
  static func write(
    meeting: Meeting,
    tasks: [MemoraTask],
    onProgress: @escaping @MainActor (Double) -> Void
  ) async throws -> URL {
    let renderer = ImageRenderer(content: MeetingPDFContent(meeting: meeting, tasks: tasks))
    renderer.proposedSize = ProposedViewSize(width: pageSize.width, height: nil)
    guard let image = renderer.uiImage, image.size.height > 0 else {
      throw ExportError.renderFailed
    }

    // A unique name, so two exports of the same record never collide in the
    // temporary folder.
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(safeFileName(for: meeting))-\(UUID().uuidString.prefix(8)).pdf")

    let data = try await Task.detached(priority: .userInitiated) { () throws -> Data in
      let bodyHeight = pageSize.height - footerHeight
      let pageCount = max(1, Int(ceil(image.size.height / bodyHeight)))
      var result = Data()

      result = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize)).pdfData { context in
        for index in 0..<pageCount {
          if Task.isCancelled { return }
          context.beginPage()
          let cg = context.cgContext

          // Draw the one tall image shifted up, clipped to this page's body.
          cg.saveGState()
          cg.clip(to: CGRect(x: 0, y: 0, width: pageSize.width, height: bodyHeight))
          cg.translateBy(x: 0, y: -CGFloat(index) * bodyHeight)
          image.draw(in: CGRect(origin: .zero, size: image.size))
          cg.restoreGState()

          drawFooter(page: index + 1, of: pageCount)
          Task { @MainActor in
            onProgress(Double(index + 1) / Double(pageCount))
          }
        }
      }
      guard !Task.isCancelled, !result.isEmpty else { throw ExportError.cancelled }
      return result
    }.value

    do {
      try data.write(to: url, options: .atomic)
    } catch {
      throw ExportError.writeFailed
    }
    return url
  }

  /// Removes the exports once the share sheet is done with them, so the
  /// temporary folder does not fill with copies.
  static func discard(_ items: [Any]) {
    for case let url as URL in items where url.isFileURL {
      try? FileManager.default.removeItem(at: url)
    }
  }

  private nonisolated static func drawFooter(page: Int, of total: Int) {
    let text = "Memora · \(page) / \(total)"
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.systemFont(ofSize: 9),
      .foregroundColor: UIColor.secondaryLabel
    ]
    let size = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(
      at: CGPoint(
        x: (pageSize.width - size.width) / 2,
        y: pageSize.height - footerHeight + 12
      ),
      withAttributes: attributes
    )
  }

  private static func safeFileName(for meeting: Meeting) -> String {
    let name = meeting.title.isEmpty ? "記録" : meeting.title
    let cleaned = name
      .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
      .joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "記録" : String(cleaned.prefix(60))
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

      if MarkdownBlockParser.hasBlockStructure(meeting.summary) {
        // A generated document keeps its headings and action cards on paper.
        VStack(alignment: .leading, spacing: 8) {
          Text("要約")
            .font(.headline)
          MarkdownDocumentView(markdown: meeting.summary)
        }
      } else if !meeting.summary.isEmpty {
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
