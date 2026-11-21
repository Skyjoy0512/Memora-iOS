import SwiftUI

struct SpaceDetailView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var spaceID: UUID
  var zoomNamespace: Namespace.ID?
  @State private var selectedTab = ProjectWorkspaceTab.files
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
        MemoraSectionPicker(items: ProjectWorkspaceTab.allCases, selection: $selectedTab, title: \.title)
          .padding(.horizontal, MemoraSpacing.screen)
          .padding(.vertical, MemoraSpacing.sm)
          .accessibilityIdentifier("project.workspace.sections")
        Group {
          switch selectedTab {
          case .chat:
            if chats.isEmpty {
              workspaceEmpty(.chat) {
                if let id = model.createProjectChat(projectID: spaceID) { model.openProjectChat(id) }
              }
            } else {
              workspaceScroll {
                ForEach(chats) { thread in
                  ProjectChatRow(thread: thread)
                    .padding(.vertical, MemoraSpacing.sm)
                }
              }
            }
          case .files:
            if files.isEmpty {
              workspaceEmpty(.files) {
                Task { await model.startCapture(spaceID: spaceID) }
              }
            } else {
              workspaceScroll {
                ForEach(files) { item in
                  ProjectWorkspaceRow(item: item, zoomNamespace: zoomNamespace)
                    .padding(.vertical, MemoraSpacing.sm)
                }
              }
            }
          case .sources:
            if sources.isEmpty {
              workspaceEmpty(.sources) { model.sourceAddProjectID = spaceID }
            } else {
              workspaceScroll {
                ForEach(sources) { item in
                  ProjectWorkspaceRow(item: item, zoomNamespace: zoomNamespace)
                    .padding(.vertical, MemoraSpacing.sm)
                }
              }
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .animation(reduceMotion ? nil : MemoraMotion.control, value: selectedTab)
      .background(MemoraPalette.background)
      .onAppear { model.noteProjectUsed(space.id) }
      .navigationTitle(space.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if selectedTab == .sources {
          ToolbarActionItem(usesSystemBackground: true) {
            ToolbarIconButton("参考資料を追加", icon: .paperclip) {
              model.sourceAddProjectID = spaceID
            }
            .accessibilityHint("このプロジェクトに保存します")
          }
        }
        ToolbarActionItem(usesSystemBackground: true) {
          Menu {
            Button("新しいチャット", icon: .squareAndPencil) {
              if let id = model.createProjectChat(projectID: spaceID) { model.openProjectChat(id) }
            }
            .disabled(model.isRestoring || model.isStoreProtected)
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

  /// One scrolling surface per section, with the same reading width as the composer.
  private func workspaceScroll<Rows: View>(@ViewBuilder rows: () -> Rows) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        rows()
      }
      .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
      .padding(.horizontal, MemoraSpacing.screen)
      .padding(.top, MemoraSpacing.sm)
      .padding(.bottom, model.bottomContentClearance)
      .frame(maxWidth: .infinity)
    }
    .scrollIndicators(.visible)
  }

  private func workspaceEmpty(_ tab: ProjectWorkspaceTab, action: @escaping () -> Void) -> some View {
    ScrollView {
      MemoraEmptyState(
        icon: tab.emptyIcon,
        title: tab.emptyTitle,
        message: tab.emptyDescription,
        actionTitle: tab.emptyActionTitle,
        actionIcon: tab.emptyActionIcon,
        action: action
      )
      .padding(.top, MemoraSpacing.section)
      .padding(.bottom, model.bottomContentClearance)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

}
