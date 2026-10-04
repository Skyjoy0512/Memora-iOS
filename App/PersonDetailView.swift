import SwiftUI

/// What the records hold about one person: when you last met, what they took
/// on, what was decided together, and the meetings and journal entries.
struct PersonDetailView: View {
  @Environment(MemoraModel.self) private var model
  var personID: UUID
  @State private var isEditing = false
  @State private var editingTask: MemoraTask?

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
    List {
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

      if !memory.assignedTasks.isEmpty {
        Section("\(memory.person.name)さんが引き受けたこと") {
          ForEach(memory.assignedTasks) { task in
            TaskRow(task: task, showsSource: true) { editingTask = task }
          }
        }
      }

      if !memory.sharedTasks.isEmpty {
        Section("一緒の会議で残っていること") {
          ForEach(memory.sharedTasks) { task in
            TaskRow(task: task, showsSource: true) { editingTask = task }
          }
        }
      }

      if !memory.decisions.isEmpty {
        Section("一緒に決めたこと") {
          ForEach(memory.decisions, id: \.self) { decision in
            NavigationLink(value: LibraryRoute.meeting(decision.meetingID)) {
              VStack(alignment: .leading, spacing: 3) {
                Text(decision.text)
                  .font(.subheadline)
                Text("\(decision.meetingTitle) · \(decision.date.formatted(date: .abbreviated, time: .omitted))")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }

      Section("会議") {
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
        Section("ジャーナル") {
          ForEach(memory.journalEntries) { entry in
            LifeLogRow(entry: entry)
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    .navigationTitle(memory.person.name)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        ToolbarIconButton("編集", icon: .pencil) { isEditing = true }
          .labelStyle(.iconOnly)
      }
    }
    .sheet(isPresented: $isEditing) {
      PersonEditSheet(personID: memory.person.id)
    }
    .sheet(item: $editingTask) { task in
      TaskEditView(task: task)
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
    return "会議\(memory.meetings.count)件 · 最後に会った日 \(lastMet.formatted(date: .abbreviated, time: .omitted))"
  }

  /// Hands the question to the agent, which can read the person's records.
  private func askAgent(about person: Person) {
    model.selectedTab = .askAI
    model.sendAIChat("\(person.name)さんとのこれまでの話、決まったこと、お互いの約束をまとめて")
  }
}
