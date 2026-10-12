import SwiftUI

struct SpaceDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var spaceID: UUID
  @State private var isAskingAI = false
  @State private var isRenaming = false
  @State private var isDeleting = false
  @State private var isAddingFiles = false
  @State private var editingTask: MemoraTask?


  var body: some View {
    if let space = model.space(id: spaceID) {
      let records = ProjectFiling.records(in: spaceID, from: model.meetings)
      let tasks = openTasks(in: records)
      let items = model.workspaceItems(projectID: spaceID)
      let isEmpty = items.isEmpty

      List {
        if isEmpty {
          Section {
            VStack(alignment: .leading, spacing: 12) {
              Text("このプロジェクトに情報を集めましょう").font(.body.weight(.semibold))
              Text("リンク、写真、ファイルなどを追加できます。")
                .font(.subheadline).foregroundStyle(.secondary)
              Button("ソースを追加", icon: .plus) { model.sourceAddProjectID = spaceID }
                .frame(minHeight: 44).tint(MemoraPalette.textPrimary)
                .disabled(model.isRestoring)
            }
            .padding(.vertical, 16)
            .listRowSeparator(.hidden)
          }
        } else {
          Section {
            ForEach(Array(items.prefix(3))) { item in ProjectWorkspaceRow(item: item) }
          } header: {
            HStack {
              Text("ソース").font(.subheadline.weight(.semibold))
              Spacer()
              NavigationLink(value: LibraryRoute.projectSources(spaceID)) {
                Text("すべて見る（\(items.count)）").font(.subheadline)
              }
              .frame(minHeight: 44)
              .tint(MemoraPalette.textPrimary)
            }.textCase(nil)
          }
          if !tasks.isEmpty {
            Section {
              ForEach(Array(tasks.prefix(3))) { task in
                TaskRow(task: task, showsSource: true) { editingTask = task }.buttonStyle(.plain)
              }
              if tasks.count > 3 {
                NavigationLink("すべてのタスク", value: LibraryRoute.tasks)
              }
            } header: { Text("関連タスク").font(.subheadline.weight(.semibold)).textCase(nil) }
          }
        }
      }
      .listStyle(.plain)
      .listSectionSpacing(24)
      .listRowInsets(EdgeInsets(top: 8, leading: ProjectLayout.horizontalInset, bottom: 8, trailing: ProjectLayout.horizontalInset))
      .scrollContentBackground(.hidden)
      .background(MemoraPalette.background)
      .onAppear { model.noteProjectUsed(space.id) }
      .hideBottomBarOnScroll(model.selectedTab.rawValue)
      .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
      .navigationTitle(space.name)
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarActionItem(usesSystemBackground: true) {
          Menu {
            if !isEmpty {
              Button("ソースを追加", icon: .plus) { model.sourceAddProjectID = spaceID }
              Button("既存記録を移動", icon: .folder) { isAddingFiles = true }
            }
            Button("未決事項を質問", icon: .sparkles) { isAskingAI = true }
            Button("チームで共有", icon: .personBadgePlus) {
              Task { await model.shareSpaceWithTeam(space.id) }
            }
            Divider()
            Button("名前を変更", icon: .pencil) { isRenaming = true }
            Button("削除", icon: .trash, role: .destructive) { isDeleting = true }
          } label: {
            ToolbarActionLabel("その他", icon: .ellipsis)
          }
        }
      }
      .sheet(isPresented: $isAddingFiles) { ProjectFilePickerSheet(spaceID: spaceID) }
      .interactionFeedback(.tap, trigger: isAddingFiles) { _, presented in presented }
      .sheet(isPresented: $isAskingAI) {
        AIQuestionView(scope: .space(space.id), askingQuestion: "このプロジェクトでまだ決まっていないことは？")
      }
      .sheet(isPresented: $isRenaming) { RenameSpaceSheet(space: space) }
      .sheet(item: $editingTask) { task in TaskEditView(task: task) }
      .confirmationDialog("このプロジェクトを削除しますか？", isPresented: $isDeleting, titleVisibility: .visible) {
        Button("削除", role: .destructive) {
          if model.deleteSpace(space.id) { dismiss() }
        }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("録音・資料・ソースとチャットは削除せず、所属を解除します。")
      }
    } else {
      ContentUnavailableView("プロジェクトが見つかりません", icon: .folderBadgeQuestionmark)
    }
  }

  private func openTasks(in spaceMeetings: [Meeting]) -> [MemoraTask] {
    let meetingIDs = Set(spaceMeetings.map(\.id))
    return model.tasks.filter { task in
      task.meetingID.map(meetingIDs.contains) == true && !task.isCompleted
    }
  }
}
