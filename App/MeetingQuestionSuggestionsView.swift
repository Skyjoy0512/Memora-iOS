import SwiftUI

struct MeetingQuestionSuggestionsView: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID
  @State private var preparedSnapshot: MeetingSummaryPosterSnapshot?
  @State private var questions: [String] = []

  var body: some View {
    let snapshot = MeetingSummaryPosterSnapshot(meetingID: meetingID, model: model)
    let hasInput = !model.composerDraft.isEmpty || model.composerAttachment != nil || !model.composerMentions.isEmpty
    VStack(alignment: .leading, spacing: 0) {
      if let snapshot, preparedSnapshot == snapshot, !questions.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text("AIに聞く").font(.headline)
        ForEach(questions, id: \.self) { question in
          Button {
            _ = model.stageMeetingQuestion(question, snapshot: snapshot)
          } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
              Text(question).font(.subheadline).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
              Image(icon: .arrowUpRight, size: 16).accessibilityHidden(true)
            }
            .padding(.vertical, 8).frame(minHeight: 44).contentShape(Rectangle())
          }
          .buttonStyle(MemoraQuietButtonStyle())
          .disabled(hasInput || model.isAIChatResponding)
          .accessibilityHint("この記録への質問として入力欄に入れます。自動送信しません")
          .accessibilityIdentifier("summary.question.\(questions.firstIndex(of: question) ?? 0)")
          Divider()
        }

      }
      }
    }
    .task(id: snapshot) {
      guard let snapshot, !Task.isCancelled else { questions = []; preparedSnapshot = nil; return }
      let document = MeetingInfographicSample.resolve(snapshot)
      let prepared = MeetingQuestionSuggestions.make(summary: snapshot.summary, infographic: document)
      guard !Task.isCancelled, snapshot.isCurrent(in: model) else { return }
      questions = prepared
      preparedSnapshot = snapshot
    }
  }
}
