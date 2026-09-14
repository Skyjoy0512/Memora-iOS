import SwiftUI

struct SearchView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""
  @State private var isAskingAI = false
  @State private var isSearchSheetPresented = false
  @State private var isHistoryPresented = false

  var body: some View {
    NavigationStack {
      askAIHome
      .navigationTitle("Ask AI")
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("検索", systemImage: "magnifyingglass") {
            isSearchSheetPresented = true
          }
          .labelStyle(.iconOnly)

          Button("履歴", systemImage: "clock.arrow.circlepath") {
            isHistoryPresented = true
          }
          .labelStyle(.iconOnly)
        }
      }
      .sheet(isPresented: $isAskingAI) {
        AIQuestionView(scope: .global, askingQuestion: query)
      }
      .sheet(isPresented: $isSearchSheetPresented) {
        NavigationStack {
          Group {
            if query.isEmpty {
              ContentUnavailableView(
                "会話を検索",
                systemImage: "magnifyingglass",
                description: Text("タイトル、発言、決定、タスクから探せます。")
              )
            } else {
              resultsView
            }
          }
          .navigationTitle("検索")
          .navigationBarTitleDisplayMode(.inline)
          .searchable(text: $query, prompt: "会議、発言、決定、タスク")
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("完了") { isSearchSheetPresented = false }
            }
          }
        }
      }
      .sheet(isPresented: $isHistoryPresented) {
        AIHistoryView(entries: model.aiHistory) { question in
          query = question
          isHistoryPresented = false
          Task {
            try? await Task.sleep(for: .milliseconds(250))
            isAskingAI = true
          }
        }
      }
    }
  }

  private var askAIHome: some View {
    VStack(spacing: 24) {
      Spacer(minLength: 72)

      ThinkingOrbView(state: .breathing, size: 78)

      VStack(spacing: 8) {
        Text("何を知りたいですか？")
          .font(.title2.bold())
          .memoraTextReveal(delay: 0.08)
        Text("言葉を思い出せなくても、会話の意味から探せます。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .memoraTextReveal(delay: 0.16)
      }

      Spacer()
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 24)
    .padding(.bottom, 24)
  }

  private var resultsView: some View {
    List {
      Section {
        Button {
          isSearchSheetPresented = false
          Task {
            try? await Task.sleep(for: .milliseconds(250))
            isAskingAI = true
          }
        } label: {
          Label("「\(query)」をMemoraに聞く", systemImage: "sparkles")
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(2)
        }
      }

      if !matchingMeetings.isEmpty {
        Section("会話") {
          ForEach(matchingMeetings) { meeting in
            NavigationLink {
              MeetingDetailView(meetingID: meeting.id)
            } label: {
              MeetingRow(meeting: meeting, showsDisclosure: false)
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
    .animation(.smooth, value: matchingMeetings)
    .animation(.smooth, value: matchingTasks)
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

private struct AIHistoryView: View {
  @Environment(\.dismiss) private var dismiss
  var entries: [AIConversationEntry]
  var select: (String) -> Void

  var body: some View {
    NavigationStack {
      Group {
        if entries.isEmpty {
          ContentUnavailableView("まだ履歴がありません", systemImage: "clock.arrow.circlepath")
        } else {
          List(entries) { entry in
            Button {
              select(entry.question)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(entry.question)
                  .font(.body.weight(.medium))
                  .foregroundStyle(.primary)
                Text(entry.scopeLabel)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
          }
        }
      }
      .navigationTitle("質問履歴")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完了") { dismiss() }
        }
      }
    }
  }
}
