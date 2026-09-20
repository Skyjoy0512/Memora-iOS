import SwiftUI

/// Lets a person correct the generated content: title, summary, decisions,
/// open questions and key points. Notes and photos are edited in the notes tab.
struct MeetingContentEditSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var meetingID: UUID

  @State private var title = ""
  @State private var summary = ""
  @State private var decisions = ""
  @State private var openQuestions = ""
  @State private var keyPoints = ""

  var body: some View {
    NavigationStack {
      Form {
        Section("タイトル") {
          TextField("タイトル", text: $title)
        }

        Section("要約") {
          TextField("要約", text: $summary, axis: .vertical)
            .lineLimit(3...8)
        }

        Section {
          TextField("1行に1つ", text: $decisions, axis: .vertical)
            .lineLimit(3...8)
        } header: {
          Text("決まったこと")
        } footer: {
          Text("1行に1つずつ入力します。")
        }

        Section("まだ決まっていないこと") {
          TextField("1行に1つ", text: $openQuestions, axis: .vertical)
            .lineLimit(3...8)
        }

        Section("重要なポイント") {
          TextField("1行に1つ", text: $keyPoints, axis: .vertical)
            .lineLimit(3...8)
        }
      }
      .navigationTitle("内容を編集")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("保存") { save() }
        }
      }
      .onAppear(perform: load)
    }
  }

  private func load() {
    guard let meeting = model.meeting(id: meetingID) else { return }
    title = meeting.title
    summary = meeting.summary
    decisions = meeting.decisions.joined(separator: "\n")
    openQuestions = meeting.openQuestions.joined(separator: "\n")
    keyPoints = meeting.keyPoints.joined(separator: "\n")
  }

  private func save() {
    model.updateMeetingContent(
      id: meetingID,
      title: title,
      summary: summary,
      decisions: Self.lines(decisions),
      openQuestions: Self.lines(openQuestions),
      keyPoints: Self.lines(keyPoints)
    )
    dismiss()
  }

  private static func lines(_ text: String) -> [String] {
    text
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }
}
