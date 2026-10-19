import SwiftUI

struct HomeActivityLinks: View {
  @Environment(MemoraModel.self) private var model
  @State private var editingTask: MemoraTask?

  var body: some View {
    let calendar = Calendar.current
    let endOfWeek = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: .now)) ?? .now
    let ownOpenTasks = model.ownTasks.filter { !$0.isCompleted }
    let today = ownOpenTasks.filter { $0.workDate.map(calendar.isDateInToday) == true }
    let todayIDs = Set(today.map(\.id))
    let dueSoon = ownOpenTasks.filter { !todayIDs.contains($0.id) && $0.dueDate.map { $0 < endOfWeek } == true }
      .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    let recent = Array(model.recentProjects.prefix(2))

    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("今日のタスク").font(.headline)
        Spacer()
        NavigationLink("すべて見る", value: LibraryRoute.tasks)
          .font(MemoraTypography.secondary).frame(minHeight: 44)
          .accessibilityLabel("すべてのタスクを見る")
      }
      if today.isEmpty, dueSoon.isEmpty {
        Text("今日取り組むタスクや期限の近いタスクはありません。")
          .font(MemoraTypography.secondary).foregroundStyle(.secondary)
      } else {
        if !today.isEmpty {
          Text("今日取り組む").font(.caption).foregroundStyle(.secondary)
          ForEach(today.prefix(3)) { task in TaskRow(task: task, showsSource: true) { editingTask = task } }
        }
        if !dueSoon.isEmpty {
          Text("期限が近いタスク").font(.caption).foregroundStyle(.secondary)
          ForEach(dueSoon.prefix(3)) { task in TaskRow(task: task, showsSource: true) { editingTask = task } }
        }
      }
    }
    .padding(18)
    .memoraCard(fill: MemoraPalette.card)
    .sheet(item: $editingTask) { task in TaskEditView(task: task) }

    if !recent.isEmpty {
      Text("最近使用したプロジェクト").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
        .accessibilityAddTraits(.isHeader)
      ForEach(recent) { space in
        Button { model.openProject(space.id) } label: {
          HStack(spacing: 12) {
            Label(space.name, icon: space.icon).font(.subheadline.weight(.semibold))
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(icon: .chevronRight).foregroundStyle(.secondary).accessibilityHidden(true)
          }
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .padding(.horizontal, MemoraSpacing.screen)
          .padding(.vertical, 8)
          .memoraCard(fill: MemoraPalette.card)
          .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
      }
    }
  }
}
