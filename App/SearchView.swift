import SwiftUI

struct SearchView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""
  @State private var isAskingAI = false

  var body: some View {
    NavigationStack {
      Group {
        if query.isEmpty {
          discoveryView
        } else {
          resultsView
        }
      }
      .navigationTitle("Ask AI")
      .searchable(
        text: $query,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: "会議、発言、決定、タスク"
      )
      .sheet(isPresented: $isAskingAI) {
        AIQuestionView(scope: .global, suggestedQuestion: query)
      }
    }
  }

  private var discoveryView: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        Button {
          isAskingAI = true
        } label: {
          VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sparkles")
              .font(.title2.weight(.semibold))
              .foregroundStyle(.primary)
            Text("覚えていない言葉でも、\n意味から探せます")
              .font(.title2.bold())
              .foregroundStyle(.primary)
            Text("「田中さんの未完了タスクは？」のように質問してください。")
              .font(.subheadline)
              .foregroundStyle(.secondary)
            Label("Memoraに聞く", systemImage: "arrow.right")
              .font(.headline)
              .foregroundStyle(.primary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(20)
          .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)

        if !model.aiHistory.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text("最近の質問")
              .font(.title2.bold())
            ForEach(model.aiHistory.prefix(3)) { entry in
              Button {
                query = entry.question
                isAskingAI = true
              } label: {
                HStack(alignment: .top, spacing: 12) {
                  Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                  VStack(alignment: .leading, spacing: 4) {
                    Text(entry.question)
                      .font(.body.weight(.medium))
                      .foregroundStyle(.primary)
                    Text(entry.scopeLabel)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 18)
      .padding(.bottom, 32)
    }
  }

  private var resultsView: some View {
    List {
      Section {
        Button {
          isAskingAI = true
        } label: {
          Label("「\(query)」をMemoraに聞く", systemImage: "sparkles")
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(2)
        }
      }

      if !matchingMeetings.isEmpty {
        Section("会議") {
          ForEach(matchingMeetings) { meeting in
            NavigationLink {
              MeetingDetailView(meetingID: meeting.id)
            } label: {
              MeetingRow(meeting: meeting)
            }
          }
        }
      }

      if !matchingTasks.isEmpty {
        Section("タスク") {
          ForEach(matchingTasks) { task in
            TaskRow(task: task, showsSource: true)
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .overlay {
      if matchingMeetings.isEmpty && matchingTasks.isEmpty {
        ContentUnavailableView.search(text: query)
      }
    }
  }

  private var matchingMeetings: [Meeting] {
    model.meetings.filter { meeting in
      meeting.title.localizedCaseInsensitiveContains(query)
        || meeting.summary.localizedCaseInsensitiveContains(query)
        || meeting.decisions.contains { $0.localizedCaseInsensitiveContains(query) }
        || meeting.transcript.contains { $0.text.localizedCaseInsensitiveContains(query) }
    }
  }

  private var matchingTasks: [MemoraTask] {
    model.tasks.filter { $0.title.localizedCaseInsensitiveContains(query) }
  }
}
