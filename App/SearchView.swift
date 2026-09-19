import SwiftUI

struct SearchView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""
  @State private var isSearchSheetPresented = false
  @State private var isHistoryPresented = false

  var body: some View {
    NavigationStack {
      Group {
        if model.aiMessages.isEmpty {
          chatEmptyState
        } else {
          chatTranscript
        }
      }
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
      .sheet(isPresented: $isSearchSheetPresented) {
        searchSheet
      }
      .sheet(isPresented: $isHistoryPresented) {
        AIHistoryView(entries: model.aiHistory) { question in
          isHistoryPresented = false
          Task {
            try? await Task.sleep(for: .milliseconds(250))
            model.sendAIChat(question)
          }
        }
      }
    }
  }

  private var chatTranscript: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 22) {
          ForEach(model.aiMessages) { message in
            AIMessageView(message: message, animates: message.id == model.aiMessages.last?.id)
              .id(message.id)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
      }
      .scrollDismissesKeyboard(.interactively)
      .hideBottomBarOnScroll()
      .onChange(of: model.aiMessages.count) { _, _ in
        scrollToLatest(proxy)
      }
      .onAppear {
        scrollToLatest(proxy)
      }
    }
  }

  private func scrollToLatest(_ proxy: ScrollViewProxy) {
    guard let last = model.aiMessages.last else { return }
    withAnimation(.smooth(duration: 0.3)) {
      proxy.scrollTo(last.id, anchor: .bottom)
    }
  }

  private var chatEmptyState: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        Spacer(minLength: 48)

        VStack(alignment: .leading, spacing: 8) {
          Text("何を知りたいですか？")
            .font(.largeTitle.bold())
            .memoraTextReveal()
          Text("会議をまたいで、意味から答えを探します。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .memoraTextReveal(delay: 0.08)
        }

        VStack(spacing: 4) {
          ForEach(Self.suggestions, id: \.title) { suggestion in
            Button {
              model.sendAIChat(suggestion.title)
            } label: {
              HStack(spacing: 14) {
                Image(systemName: suggestion.symbol)
                  .font(.body.weight(.medium))
                  .foregroundStyle(.primary)
                  .frame(width: 34, height: 34)
                  .background(
                    Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                  )

                Text(suggestion.title)
                  .font(.body)
                  .foregroundStyle(.primary)
                  .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
              }
              .padding(.vertical, 8)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }

        Spacer(minLength: 48)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 18)
    }
  }

  private var searchSheet: some View {
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

  private var resultsView: some View {
    List {
      Section {
        Button {
          isSearchSheetPresented = false
          Task {
            try? await Task.sleep(for: .milliseconds(250))
            model.sendAIChat(query)
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

  private static let suggestions: [(title: String, symbol: String)] = [
    ("今週決まったことは？", "checkmark.seal"),
    ("未完了のタスクを教えて", "checkmark.square"),
    ("先週の会議を3行でまとめて", "text.alignleft")
  ]
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
