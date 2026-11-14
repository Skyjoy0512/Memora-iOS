import SwiftUI

/// Keep supporting evidence available without competing with the person's records.
struct PersonSupplementarySections: View {
  var memory: PersonMemory
  var editTask: (MemoraTask) -> Void
  var openJournal: (LifeLogEntry) -> Void

  var body: some View {
    let unresolved = memory.conversationSummary.unresolvedTopics

    if !unresolved.isEmpty {
      Section {
        DisclosureGroup("未解決の話題") {
          ForEach(unresolved.prefix(8)) { topic in
            NavigationLink(value: LibraryRoute.meeting(topic.id)) {
              VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
                Text(topic.unresolved.joined(separator: "\n"))
                Text(topic.title).font(MemoraTypography.metadata).foregroundStyle(.secondary)
              }
            }
          }
        }
      }
    }
    if !memory.assignedTasks.isEmpty {
      Section {
        DisclosureGroup("担当する未完了タスク（\(memory.assignedTasks.count)）") {
          ForEach(memory.assignedTasks) { task in
            TaskRow(task: task, showsSource: true) { editTask(task) }
          }
        }
      }
    }
    if !memory.nameMatchedTasks.isEmpty {
      Section {
        DisclosureGroup("担当名のみ一致・本人未確認") {
          ForEach(memory.nameMatchedTasks) { task in
            TaskRow(task: task, showsSource: true) { editTask(task) }
          }
          Text("タスクの編集で人物を選ぶと、この人の担当として関連付けられます。")
            .font(MemoraTypography.metadata).foregroundStyle(.secondary)
        }
      }
    }
    if !memory.sharedTasks.isEmpty {
      Section {
        DisclosureGroup("一緒の会議で残っていること") {
          ForEach(memory.sharedTasks) { task in
            TaskRow(task: task, showsSource: true) { editTask(task) }
          }
        }
      }
    }
    if !memory.decisions.isEmpty {
      Section {
        DisclosureGroup("関連する会議の決定") {
          ForEach(memory.decisions, id: \.self) { decision in
            NavigationLink(value: LibraryRoute.meeting(decision.meetingID)) {
              VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
                Text(decision.text)
                Text("\(decision.meetingTitle) · \(MemoraFormat.documentDate(decision.date))")
                  .font(MemoraTypography.metadata).foregroundStyle(.secondary)
              }
            }
          }
        }
      }
    }
    if !memory.journalEntries.isEmpty {
      Section {
        DisclosureGroup("関連付けたジャーナル") {
          ForEach(memory.journalEntries) { entry in
            Button { openJournal(entry) } label: { LifeLogRow(entry: entry) }
              .buttonStyle(.plain)
              .accessibilityElement(children: .combine)
              .accessibilityHint("元の記録を開きます")
          }
        }
      }
    }
    if !memory.nameMatchedJournalEntries.isEmpty {
      Section {
        DisclosureGroup("名前の言及のみ・本人未確認") {
          ForEach(memory.nameMatchedJournalEntries) { entry in
            Button { openJournal(entry) } label: { LifeLogRow(entry: entry) }
              .buttonStyle(.plain)
              .accessibilityElement(children: .combine)
              .accessibilityHint("本人未確認の元の記録を開きます")
          }
          Text("記録の編集で人物を選ぶと、この人に関連付けられます。名前の一致だけでは本人と断定しません。")
            .font(MemoraTypography.metadata).foregroundStyle(.secondary)
        }
      }
    }
  }
}
