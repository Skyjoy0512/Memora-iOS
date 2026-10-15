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
      let tasks = model.projectTasks(projectID: spaceID)
      let items = model.workspaceItems(projectID: spaceID)
      let chats = model.projectChats.filter { $0.projectID == spaceID }.sorted { $0.updatedAt > $1.updatedAt }
      let isEmpty = items.isEmpty

      List {
        Section {
          ForEach(chats.prefix(3)) { thread in ProjectChatRow(thread: thread) }
          if chats.isEmpty {
            Text("チャットはまだありません").font(.subheadline).foregroundStyle(.secondary)
              .listRowSeparator(.hidden)
          }
          if chats.count > 3 {
            NavigationLink("すべてのチャットを見る", value: LibraryRoute.projectChats(spaceID))
              .tint(MemoraPalette.textPrimary)
          }
        } header: {
          ProjectSectionHeader("チャット", count: chats.count) {
            Button("新しいチャット", icon: .squareAndPencil) {
              if let id = model.createProjectChat(projectID: spaceID) { model.openProjectChat(id) }
            }.disabled(model.isRestoring || model.isStoreProtected)
          }
        }
        Section {
          ForEach(items.prefix(3)) { item in ProjectWorkspaceRow(item: item) }
          if isEmpty {
            Text("ソースはまだありません").font(.subheadline).foregroundStyle(.secondary)
              .listRowSeparator(.hidden)
          } else {
            NavigationLink("すべてのソースを見る", value: LibraryRoute.projectSources(spaceID))
              .tint(MemoraPalette.textPrimary)
          }
        } header: {
          ProjectSectionHeader("ソース", count: items.count) {
            Button("追加", icon: .plus) { model.sourceAddProjectID = spaceID }
              .accessibilityLabel("ソースを追加")
              .disabled(model.isRestoring || model.isStoreProtected)
          }
        } footer: {
          Text(isEmpty
            ? "録音や資料を追加すると、このプロジェクトについて質問できます。"
            : "取得・解析できた本文がAIの参照候補です。外部AIへの送信は各記録のプライバシー設定に従います。")
        }
        if !tasks.isEmpty {
          Section {
            ForEach(tasks.prefix(3)) { task in
              ProjectTaskRow(task: task) { editingTask = task }
            }
          } header: {
            ProjectSectionHeader("関連タスク", count: tasks.count) {
              NavigationLink("すべて", value: LibraryRoute.projectTasks(spaceID))
                .accessibilityLabel("このプロジェクトの関連タスクをすべて見る")
            }
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
            NavigationLink("関連タスク", value: LibraryRoute.projectTasks(spaceID))
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

}
