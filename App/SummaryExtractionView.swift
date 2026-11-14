import SwiftUI

/// Supporting extraction stays out of the primary reading flow. Task state is
/// read live from its own store, never from a generated historical checklist.
struct SummaryExtractionView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var meetingID: UUID
  @State private var editsHighlights = false
  @State private var editedFact: SummaryKnowledge.Fact?
  @State private var addsFact = false

  var body: some View {
    let meeting = model.meeting(id: meetingID)
    let version = meeting?.activeSummaryVersion
    let knowledge = version?.knowledge
    let transcriptFingerprint = meeting.flatMap { SummaryEvidence.fingerprint($0.transcript) }
    let current = meeting.map { version?.matches(record: $0) == true } ?? false
    let visibleFacts = knowledge?.facts ?? []
    NavigationStack {
      MemoraForm {
        if let meeting {
          Section {
            if knowledge != nil, !current {
              Text("本文・原文または抽出情報が編集されています。生成時の情報と本人の編集を区別して確認してください。本文とタスクは自動的に書き換えません。")
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
                  Text(fact.category.label + " · " + fact.status.label + (fact.origin == .user ? " · 本人の編集" : "")).font(.caption).foregroundStyle(.secondary)
                  Text(fact.content).textSelection(.enabled)
                  Button("編集", icon: .pencil) { editedFact = fact }
                    .buttonStyle(.borderless)
                    .frame(minHeight: MemoraSpacing.touchTarget)
                    .accessibilityIdentifier("summary.fact.edit.\(fact.id)")
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
          if knowledge != nil {
            Section { Button("抽出情報を追加", icon: .plus) { addsFact = true } }
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
      .sheet(item: $editedFact) { fact in
        if let version { SummaryFactEditor(meetingID: meetingID, versionID: version.id, original: fact) }
      }
      .sheet(isPresented: $addsFact) {
        if let version { SummaryFactEditor(meetingID: meetingID, versionID: version.id) }
      }
      .sheet(isPresented: $editsHighlights) { MeetingHighlightsEditor(meetingID: meetingID) }
    }
  }
}
