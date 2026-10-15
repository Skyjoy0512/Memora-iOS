import SwiftUI

struct ProjectTasksView: View {
  @Environment(MemoraModel.self) private var model
  var projectID: UUID
  @State private var includeCompleted = false
  @State private var editingTask: MemoraTask?

  var body: some View {
    if let project = model.space(id: projectID) {
      let tasks = model.projectTasks(projectID: projectID, includeCompleted: includeCompleted)
      List {
        Section {
          ForEach(tasks) { task in
            ProjectTaskRow(task: task) { editingTask = task }
          }
        } header: {
          Text(project.name).textCase(nil)
        }
      }
      .listStyle(.plain).scrollContentBackground(.hidden)
      .background(MemoraPalette.background)
      .overlay {
        if tasks.isEmpty {
          ContentUnavailableView(includeCompleted ? "関連タスクはありません" : "未完了の関連タスクはありません", icon: .checkmarkSquare)
        }
      }
      .navigationTitle("関連タスク").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarActionItem(usesSystemBackground: true) {
          Menu {
            Toggle("完了したタスクも表示", isOn: $includeCompleted)
          } label: {
            ToolbarActionLabel("表示", icon: .line3HorizontalDecrease)
          }
        }
      }
      .sheet(item: $editingTask) { task in TaskEditView(task: task) }
      .hideBottomBarOnScroll(model.selectedTab.rawValue)
      .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
      .tint(MemoraPalette.textPrimary)
    } else {
      ContentUnavailableView("プロジェクトが見つかりません", icon: .folderBadgeQuestionmark)
    }
  }
}
