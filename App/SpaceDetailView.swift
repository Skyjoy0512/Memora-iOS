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
        MemoraTextTabBar(items: ProjectWorkspaceTab.allCases, selection: $selectedTab) { $0.title }
          .padding(.top, MemoraSpacing.xxs)
          .padding(.bottom, MemoraSpacing.md)

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
                  ProjectWorkspaceRow(item: item)
                    .padding(.vertical, MemoraSpacing.xs)
                }
              }
            }
          case .sources:
            if sources.isEmpty {
              workspaceEmpty(.sources) { model.sourceAddProjectID = spaceID }
            } else {
              workspaceScroll {
                ForEach(sources) { item in
                  ProjectWorkspaceRow(item: item)
                    .padding(.vertical, MemoraSpacing.xs)
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
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          HStack(spacing: 7) {
            Image(icon: .folder)
              .font(MemoraTypography.secondary)
              .foregroundStyle(.secondary)
            Text(space.name)
              .font(.headline)
              .lineLimit(1)
          }
          .accessibilityElement(children: .combine)
          .accessibilityAddTraits(.isHeader)
        }
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

  /// One scrolling surface per tab. Rows are read from the model, never copied
  /// between tabs, and keep the open rhythm of a chat list rather than a table.
  private func workspaceScroll<Rows: View>(@ViewBuilder rows: () -> Rows) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 0) {
        rows()
      }
      .padding(.horizontal, MemoraSpacing.screen)
      .padding(.top, MemoraSpacing.md)
      .padding(.bottom, model.bottomContentClearance)
    }
    .scrollIndicators(.hidden)
    .hideBottomBarOnScroll(model.selectedTab.rawValue)
  }

  private func workspaceEmpty(_ tab: ProjectWorkspaceTab, action: @escaping () -> Void) -> some View {
    VStack(spacing: 0) {
      Spacer(minLength: 32)
      ProjectWorkspaceEmptyState(
        icon: tab.emptyIcon,
        title: tab.emptyTitle,
        message: tab.emptyDescription,
        actionTitle: tab.emptyActionTitle,
        actionIcon: tab.emptyActionIcon,
        action: action
      )
      Spacer(minLength: 36)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
