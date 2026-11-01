import SwiftUI

struct HomeActivityLinks: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dynamicTypeSize) private var typeSize
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
    let headingLayout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: MemoraSpacing.xs))
      : AnyLayout(HStackLayout(spacing: MemoraSpacing.md))

    Group {
      if today.isEmpty, dueSoon.isEmpty {
        NavigationLink(value: LibraryRoute.tasks) {
          Label("タスク", icon: .checkmarkCircle)
            .font(MemoraTypography.secondary)
            .frame(minHeight: MemoraSpacing.touchTarget)
        }
        .tint(MemoraPalette.textSecondary)
      } else {
        VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
          headingLayout {
            Text("今日のタスク").font(MemoraTypography.body.weight(.semibold))
              .accessibilityAddTraits(.isHeader)
            if !typeSize.isAccessibilitySize { Spacer() }
            NavigationLink(value: LibraryRoute.tasks) {
              Text("すべて見る")
                .font(MemoraTypography.secondary)
                .frame(minHeight: MemoraSpacing.touchTarget)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("すべてのタスクを見る")
          }
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
    }
    .sheet(item: $editingTask) { task in TaskEditView(task: task) }

    if !recent.isEmpty {
      MemoraSectionHeading(title: "最近使用したプロジェクト")
      ForEach(recent) { space in
        Button { model.openProject(space.id) } label: {
          HStack(spacing: 12) {
            MemoraInterfaceIcon(icon: space.icon)
            Text(space.name).font(MemoraTypography.body.weight(.medium))
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(icon: .chevronRight, size: MemoraIconMetrics.accessory)
              .foregroundStyle(.secondary).accessibilityHidden(true)
          }
          .foregroundStyle(.primary)
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .padding(.vertical, MemoraSpacing.sm)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
  }
}
