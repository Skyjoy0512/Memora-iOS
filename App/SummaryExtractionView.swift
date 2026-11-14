import SwiftUI

/// Supporting extraction stays out of the primary reading flow. Task state is
/// read live from its own store, never from a generated historical checklist.
struct SummaryExtractionView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var meetingID: UUID
  @State private var editsHighlights = false

  var body: some View {
    let meeting = model.meeting(id: meetingID)
    let version = meeting?.activeSummaryVersion
    let knowledge = version?.knowledge
    let transcriptFingerprint = meeting.flatMap { SummaryEvidence.fingerprint($0.transcript) }
    let current = meeting.map { version?.matches(record: $0) == true } ?? false
    let visibleFacts = knowledge?.facts.filter { $0.status.isVisible } ?? []
    NavigationStack {
      MemoraForm {
        if let meeting {
          Section {
            if knowledge != nil, !current {
              Text("本文・原文または抽出リストが編集されています。以下は生成時の抽出情報です。現在の記録に合わせるには、内容を確認して要約し直してください。既存タスクは保持されます。")
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("summary.extraction.stale")
            } else if knowledge == nil {
              Text("この要約には状態付きの抽出情報がありません。保存済みの要点・決定事項・タスクを確認できます。")
                .font(.footnote).foregroundStyle(.secondary)
            }
            Button("要点・決定事項・未決事項を編集", icon: .pencil) { editsHighlights = true }
          }
          if !meeting.keyPoints.isEmpty { Section("保存済みの要点") { ForEach(meeting.keyPoints, id: \.self) { Text($0) } } }
          if !meeting.decisions.isEmpty { Section("保存済みの決定事項") { ForEach(meeting.decisions, id: \.self) { Text($0) } } }
          if !meeting.openQuestions.isEmpty { Section("保存済みの未決事項") { ForEach(meeting.openQuestions, id: \.self) { Text($0) } } }
          Section("タスク") { MeetingTasksSection(meetingID: meetingID) }
          if !visibleFacts.isEmpty {
            Section(current ? "原文からの抽出" : "生成時の抽出") {
              ForEach(visibleFacts) { fact in
                VStack(alignment: .leading, spacing: 8) {
                  Text(fact.category.label + " · " + fact.status.label).font(.caption).foregroundStyle(.secondary)
                  Text(fact.content).textSelection(.enabled)
                  ForEach(fact.sourceReferences ?? [], id: \.self) { reference in
                    if let segment = meeting.transcript.first(where: { $0.id.uuidString.caseInsensitiveCompare(reference.sourceSegmentID) == .orderedSame }),
                       segment.text.contains(reference.quote), version?.sourceFingerprint == transcriptFingerprint {
                      Button(meeting.duration > 0 ? "原文を確認 \(MemoraFormat.duration(segment.timestamp))" : "原文を確認", icon: .textBubble) {
                        dismiss()
                        model.detailPlaybackRequest = DetailPlaybackRequest(meetingID: meetingID,
                          time: meeting.duration > 0 ? segment.timestamp : nil, segmentID: segment.id)
                      }
                      .frame(minHeight: MemoraSpacing.touchTarget)
                      .buttonStyle(.borderless)
                    }
                  }
                }
                .padding(.vertical, 4)
              }
            }
          }
          if let coverage = knowledge?.coverage, !coverage.isEmpty {
            Section {
              ForEach(coverage, id: \.self) { item in
                LabeledContent(item.aspect, value: item.status.label)
              }
            } header: { Text("用途別の確認観点") } footer: {
              Text("未言及は取得できた原文の範囲での状態です。現実に情報が存在しないことは意味しません。")
            }
          }
          Section { SummarySectionIndex(meeting: meeting, onSelect: { dismiss() }) }
        } else { ContentUnavailableView("記録が見つかりません", icon: .docQuestionmark) }
      }
      .navigationTitle("抽出情報を確認")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          ToolbarIconButton("完了", icon: .checkmark) { dismiss() }
        }
      }
      .sheet(isPresented: $editsHighlights) { MeetingHighlightsEditor(meetingID: meetingID) }
    }
  }
}
