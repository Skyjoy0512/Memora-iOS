import SwiftUI

/// What the records hold about one person: when you last met, what they took
/// on, what was decided together, and the meetings and journal entries.
struct PersonDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dynamicTypeSize) private var typeSize
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
    return MemoraList {
      Section { header(memory) }
      if let latest = summary.latestSubstantiveTopic {
        Section("概要") {
          NavigationLink(value: LibraryRoute.meeting(latest.id)) {
            Text(latest.summary)
              .font(MemoraTypography.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      Section("関連する記録") {
        if memory.meetings.isEmpty {
          Text("会議の参加者に追加すると、関連する記録がここに並びます。")
            .font(MemoraTypography.secondary)
            .foregroundStyle(MemoraPalette.textSecondary)
        } else {
          ForEach(memory.meetings) { meeting in
            NavigationLink(value: LibraryRoute.meeting(meeting.id)) {
              MeetingRow(meeting: meeting, showsDisclosure: false)
            }
          }
        }
      }
      PersonSupplementarySections(memory: memory,
        editTask: { editingTask = $0 }, openJournal: { selectedJournal = $0 })
    }
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    .navigationTitle("人物")
    .toolbar {
      ToolbarActionItem {
        Menu {
          Button("この人物についてAIに聞く", icon: .sparkles) { askAgent(about: memory.person) }
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
    let layout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: MemoraSpacing.md))
      : AnyLayout(HStackLayout(alignment: .top, spacing: MemoraSpacing.lg))
    return layout {
      PersonAvatar(name: memory.person.name, size: 48, photoData: memory.person.photoData)
      VStack(alignment: .leading, spacing: 4) {
        Text(memory.person.name)
          .font(MemoraTypography.screenTitle)
        if let note = memory.person.note, !note.isEmpty {
          Text(note)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Text(summary(memory))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
  }

  private func summary(_ memory: PersonMemory) -> String {
    guard let date = memory.lastMet else { return "関連する記録はまだありません" }
    return "記録\(memory.meetings.count)件 · 最新 \(MemoraFormat.documentDate(date))"
  }

  /// Hands the question to the agent, which can read the person's records.
  private func askAgent(about person: Person) {
    model.selectedTab = .askAI
    model.beginPersonConversation(person.id)
  }
}
