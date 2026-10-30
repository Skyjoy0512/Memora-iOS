import SwiftUI

/// What the records hold about one person: when you last met, what they took
/// on, what was decided together, and the meetings and journal entries.
struct PersonDetailView: View {
  @Environment(MemoraModel.self) private var model
  var personID: UUID
  @State private var isEditing = false
  @State private var isPrivacyPresented = false
  @State private var editingTask: MemoraTask?
  @State private var selectedJournal: LifeLogEntry?

  var body: some View {
    Group {
      if let memory = model.memory(of: personID) {
        content(memory)
      } else {
        ContentUnavailableView("見つかりません", icon: .personCropCircleBadgeXmark, description: Text("削除された可能性があります。"))
      }
    }
    .navigationBarTitleDisplayMode(.inline)
  }

  private func content(_ memory: PersonMemory) -> some View {
    let summary = memory.conversationSummary
    return List {
      Section {
        header(memory)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
      }

      Section {
        Button("\(memory.person.name)さんとのことをAIに聞く", icon: .sparkles) {
          askAgent(about: memory.person)
        }
      }

      if let latest = summary.topics.first {
        Section("概要") {
          NavigationLink(value: LibraryRoute.meeting(latest.id)) {
            Text(summary.overview).font(.subheadline)
          }
        }
        Section("話してきたこと") {
          ForEach(summary.topics.prefix(8)) { topic in
            NavigationLink(value: LibraryRoute.meeting(topic.id)) {
              VStack(alignment: .leading, spacing: 4) {
                Text(topic.title).font(.subheadline.weight(.medium))
                if !topic.summary.isEmpty { Text(topic.summary).font(.subheadline).foregroundStyle(.secondary) }
                Text(MemoraFormat.documentDate(topic.date)).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
        if !summary.recentDecisions.isEmpty {
          Section("最近の記録に加わった決定") {
            NavigationLink(value: LibraryRoute.meeting(latest.id)) {
              Text(summary.recentDecisions.joined(separator: "\n")).font(.subheadline)
            }
          }
        }
      }
      if !summary.unresolvedTopics.isEmpty {
        Section("未解決の話題") {
          ForEach(summary.unresolvedTopics.prefix(8)) { topic in
            NavigationLink(value: LibraryRoute.meeting(topic.id)) {
              VStack(alignment: .leading, spacing: 4) {
                Text(topic.unresolved.joined(separator: "\n")).font(.subheadline)
                Text(topic.title).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
      }

      if !memory.assignedTasks.isEmpty {
        Section("担当する未完了タスク") {
          ForEach(memory.assignedTasks) { task in
            TaskRow(task: task, showsSource: true) { editingTask = task }
          }
        }
      }

      if !memory.nameMatchedTasks.isEmpty {
        Section {
          ForEach(memory.nameMatchedTasks) { task in
            TaskRow(task: task, showsSource: true) { editingTask = task }
          }
        } header: { Text("担当名のみ一致・本人未確認") }
        footer: { Text("タスクの編集で人物を選ぶと、この人の担当として関連付けられます。") }
      }

      if !memory.sharedTasks.isEmpty {
        Section("一緒の会議で残っていること") {
          ForEach(memory.sharedTasks) { task in
            TaskRow(task: task, showsSource: true) { editingTask = task }
          }
        }
      }

      if !memory.decisions.isEmpty {
        Section("関連する会議の決定") {
          ForEach(memory.decisions, id: \.self) { decision in
            NavigationLink(value: LibraryRoute.meeting(decision.meetingID)) {
              VStack(alignment: .leading, spacing: 3) {
                Text(decision.text)
                  .font(.subheadline)
                Text("\(decision.meetingTitle) · \(decision.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "ja_JP"))))")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }

      Section("会話タイムライン・関連記録") {
        if memory.meetings.isEmpty {
          Text("まだ一緒の会議はありません。会議の参加者に追加すると、ここに並びます。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else {
          ForEach(memory.meetings) { meeting in
            NavigationLink(value: LibraryRoute.meeting(meeting.id)) {
              MeetingRow(meeting: meeting, showsDisclosure: false)
            }
          }
        }
      }

      if !memory.journalEntries.isEmpty {
        Section("関連付けたジャーナル") {
          ForEach(memory.journalEntries) { entry in
            Button { selectedJournal = entry } label: { LifeLogRow(entry: entry) }
              .buttonStyle(.plain)
              .accessibilityElement(children: .combine)
              .accessibilityHint("元の記録を開きます")
          }
        }
      }
      if !memory.nameMatchedJournalEntries.isEmpty {
        Section {
          ForEach(memory.nameMatchedJournalEntries) { entry in
            Button { selectedJournal = entry } label: { LifeLogRow(entry: entry) }
              .buttonStyle(.plain)
              .accessibilityElement(children: .combine)
              .accessibilityHint("本人未確認の元の記録を開きます")
          }
        } header: { Text("名前の言及のみ・本人未確認") }
        footer: { Text("記録の編集で人物を選ぶと、この人に関連付けられます。名前の一致だけでは本人と断定しません。") }
      }
    }
    .memoraPlainList()
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    .navigationTitle(memory.person.name)
    .toolbar {
      ToolbarActionItem {
        Menu {
          Button("編集", icon: .pencil) { isEditing = true }
          Button("プライバシーと外部送信", icon: .lockShield) { isPrivacyPresented = true }
        } label: {
          ToolbarActionLabel("その他", icon: .ellipsis)
        }
      }
    }
    .sheet(isPresented: $isEditing) {
      PersonEditSheet(personID: memory.person.id)
    }
    .sheet(isPresented: $isPrivacyPresented) {
      RecordPrivacySettingsView(target: .person(personID))
    }
    .sheet(item: $editingTask) { task in
      TaskEditView(task: task)
    }
    .sheet(item: $selectedJournal) { entry in
      LifeLogEntryDetailView(entryID: entry.id)
    }
  }

  private func header(_ memory: PersonMemory) -> some View {
    HStack(spacing: 16) {
      PersonAvatar(name: memory.person.name, size: 64, photoData: memory.person.photoData)
      VStack(alignment: .leading, spacing: 4) {
        Text(memory.person.name)
          .font(.title2.bold())
        if let note = memory.person.note, !note.isEmpty {
          Text(note)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Text(summary(memory))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private func summary(_ memory: PersonMemory) -> String {
    guard let lastMet = memory.lastMet else { return "一緒の会議はまだありません" }
    return "会議\(memory.meetings.count)件 · 最後に会った日 \(lastMet.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "ja_JP"))))"
  }

  /// Hands the question to the agent, which can read the person's records.
  private func askAgent(about person: Person) {
    model.selectedTab = .askAI
    model.beginPersonConversation(person.id)
  }
}
