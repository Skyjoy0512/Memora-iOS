import SwiftUI

struct SummarySectionIndex: View {
  @Environment(MemoraModel.self) private var model
  var meeting: Meeting

  var body: some View {
    let sections = TemplateSummary.snapshot(record: meeting, templateID: nil,
      preferences: SummaryPreferences(), modelInfo: "").sections
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
                Button("一致する発言 \(MemoraFormat.duration(segment.timestamp))", icon: .playFill) {
                  model.detailPlaybackRequest = DetailPlaybackRequest(meetingID: meeting.id, time: segment.timestamp)
                }
                .font(.caption)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
          .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        Text("原文との一意な文字一致だけを表示します。一致は内容の正しさを保証しません。")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}
