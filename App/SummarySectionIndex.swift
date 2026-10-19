import SwiftUI

struct SummarySectionIndex: View {
  @Environment(MemoraModel.self) private var model
  var meeting: Meeting

  var body: some View {
    let sections = TemplateSummary.displaySections(record: meeting)
    if !sections.isEmpty {
      DisclosureGroup("要約の項目と原文") {
        ForEach(sections, id: \.order) { section in
          VStack(alignment: .leading, spacing: 6) {
            Text(section.title).font(.subheadline.bold())
            if !section.content.isEmpty {
              MarkdownDocumentView(markdown: section.content)
            }
            ForEach(section.sourceReferences, id: \.self) { reference in
              if let segment = meeting.transcript.first(where: { $0.id == reference }), meeting.audioURL != nil {
                Button("原文を確認 \(MemoraFormat.duration(segment.timestamp))", icon: .playFill) {
                  model.detailPlaybackRequest = DetailPlaybackRequest(meetingID: meeting.id, time: segment.timestamp)
                }
                .font(.caption)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(MemoraSpacing.md)
          .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: MemoraRadius.field))
        }
        Text("検証できた発言ID・原文引用、または一意な文字一致を表示します。リンクは要約の正しさを保証しません。")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}
