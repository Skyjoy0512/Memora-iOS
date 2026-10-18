import SwiftUI

struct SpaceDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var spaceID: UUID
  @State private var selectedTab = ProjectWorkspaceTab.chat
  @State private var isAskingAI = false
  @State private var isRenaming = false
  @State private var isDeleting = false
  @State private var isAddingFiles = false

  var body: some View {
    if let space = model.space(id: spaceID) {
      let chats = model.projectChats
        .filter { $0.projectID == spaceID }
        .sorted { $0.updatedAt > $1.updatedAt }
      let files = model.workspaceFiles(projectID: spaceID)
      let sources = model.workspaceSources(projectID: spaceID)

      VStack(spacing: 0) {
        ProjectWorkspaceTabBar(selection: $selectedTab)
          .padding(.horizontal, ProjectLayout.horizontalInset)
          .padding(.bottom, 6)

        Group {
          switch selectedTab {
          case .chat:
            workspaceList(isEmpty: chats.isEmpty) {
              ForEach(chats) { thread in
                ProjectChatRow(thread: thread)
              }
            } empty: {
              emptyState(for: .chat)
            }
          case .files:
            workspaceList(isEmpty: files.isEmpty) {
              ForEach(files) { item in
                ProjectWorkspaceRow(item: item)
              }
            } empty: {
              emptyState(for: .files)
            }
          case .sources:
            workspaceList(isEmpty: sources.isEmpty) {
              ForEach(sources) { item in
                ProjectWorkspaceRow(item: item)
              }
            } empty: {
              emptyState(for: .sources)
            }
          }
        }
        .id(selectedTab)
        .transition(.opacity)
      }
      .animation(reduceMotion ? nil : MemoraMotion.control, value: selectedTab)
      .background(MemoraPalette.background)
      .onAppear { model.noteProjectUsed(space.id) }
      .navigationTitle(space.name)
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        addToolbarItem(spaceID: spaceID)
        ToolbarActionItem(usesSystemBackground: true) {
          Menu {
            Button("ソースを追加", icon: .plus) { model.sourceAddProjectID = spaceID }
            Button("既存記録を移動", icon: .folder) { isAddingFiles = true }
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

  /// One scrolling surface per tab, with the same search-free rhythm as the
  /// project list. Records are read from the model, never copied between tabs.
  private func workspaceList<Rows: View, Empty: View>(
    isEmpty: Bool,
    @ViewBuilder rows: () -> Rows,
    @ViewBuilder empty: () -> Empty
  ) -> some View {
    List {
      rows()
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(MemoraPalette.background)
    .listRowInsets(EdgeInsets(top: 8, leading: ProjectLayout.horizontalInset, bottom: 8, trailing: ProjectLayout.horizontalInset))
    .overlay {
      if isEmpty { empty() }
    }
    .hideBottomBarOnScroll(model.selectedTab.rawValue)
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
  }

  private func emptyState(for tab: ProjectWorkspaceTab) -> some View {
    ContentUnavailableView(
      tab.emptyTitle,
      icon: tab.emptyIcon,
      description: Text(tab.emptyDescription)
    )
  }

  @ToolbarContentBuilder
  private func addToolbarItem(spaceID: UUID) -> some ToolbarContent {
    switch selectedTab {
    case .chat:
      ToolbarItem(placement: .topBarTrailing) {
        ToolbarIconButton("新しいチャット", icon: .squareAndPencil) {
          if let id = model.createProjectChat(projectID: spaceID) { model.openProjectChat(id) }
        }
        .disabled(model.isRestoring || model.isStoreProtected)
      }
    case .files:
      ToolbarActionItem(usesSystemBackground: true) {
        Menu {
          Button("録音を追加", icon: .waveform) {
            Task { await model.startCapture(spaceID: spaceID) }
          }
          Button("既存ファイルを移動", icon: .folder) { isAddingFiles = true }
        } label: {
          ToolbarActionLabel("ファイルを追加", icon: .plus)
        }
      }
    case .sources:
      ToolbarItem(placement: .topBarTrailing) {
        ToolbarIconButton("ソースを追加", icon: .plus) {
          model.sourceAddProjectID = spaceID
        }
        .disabled(model.isRestoring || model.isStoreProtected)
      }
    }
  }
}
