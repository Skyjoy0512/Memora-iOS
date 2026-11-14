import SwiftUI

struct SummarySectionIndex: View {
  @Environment(MemoraModel.self) private var model
  var meeting: Meeting
  var onSelect: (() -> Void)? = nil

  var body: some View {
    let sections = TemplateSummary.displaySections(record: meeting).filter { !$0.sourceReferences.isEmpty }
    if !sections.isEmpty {
      DisclosureGroup("要約の項目と原文") {
        ForEach(sections, id: \.order) { section in
          VStack(alignment: .leading, spacing: 6) {
            Text(section.title).font(.subheadline.bold())
            ForEach(section.sourceReferences, id: \.self) { reference in
              if let segment = meeting.transcript.first(where: { $0.id == reference }) {
                Button("原文を確認 \(MemoraFormat.duration(segment.timestamp))", icon: .playFill) {
                  onSelect?()
                  model.detailPlaybackRequest = DetailPlaybackRequest(meetingID: meeting.id, time: meeting.duration > 0 ? segment.timestamp : nil, segmentID: segment.id)
                }
                .font(.caption)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, MemoraSpacing.sm)
        }
        Text("検証できた発言ID・原文引用、または一意な文字一致を表示します。リンクは要約の正しさを保証しません。")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}
