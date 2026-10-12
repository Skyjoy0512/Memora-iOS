import SwiftUI

struct ProjectsView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  var query: String
  var isSearching: Bool
  @State private var renameTarget: MemoraSpace?
  @State private var deleteTarget: MemoraSpace?

  var body: some View {
    let projects = model.spaces.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    let recent = model.recentProjects
    let taskCounts = model.projectTaskCounts
    let shared = model.cloudSharing.sharedProjects.filter {
      query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.ownerName.localizedCaseInsensitiveContains(query)
    }

    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        if !isSearching, !recent.isEmpty {
          heading("最近使用したプロジェクト")
          ForEach(recent.prefix(3)) { space in projectLink(space, taskCounts: taskCounts) }
        }

        heading("すべてのプロジェクト")
        if projects.isEmpty {
          if isSearching {
            ContentUnavailableView.search(text: query)
          } else {
            ContentUnavailableView {
              Label("プロジェクトはありません", icon: .rectangleStack)
            } description: {
              Text("関連する記録とタスクを、テーマや案件ごとにまとめられます。")
            } actions: {
              Button("プロジェクトを作成", icon: .folderBadgePlus) { model.isFileCreationPresented = true }
            }
          }
        } else {
          ForEach(projects) { space in projectLink(space, taskCounts: taskCounts) }
        }

        if !shared.isEmpty {
          heading("チームから共有")
          ForEach(shared) { project in
            NavigationLink(value: LibraryRoute.sharedProject(project.id)) {
              VStack(alignment: .leading, spacing: 12) {
                SharedOwnerBadge(ownerName: project.ownerName)
                Label(project.name, icon: project.icon).font(.headline)
                Text("記録 \(project.records.count)件 · 閲覧のみ")
                  .font(.subheadline).foregroundStyle(.secondary)
              }
              .foregroundStyle(.primary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(18)
              .memoraCard(fill: Color(uiColor: .secondarySystemGroupedBackground))
              .contentShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 18)
      .padding(.bottom, model.bottomContentClearance)
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .hideBottomBarOnScroll(RootTab.library.rawValue)
    .sheet(item: $renameTarget) { space in RenameSpaceSheet(space: space) }
    .confirmationDialog("このプロジェクトを削除しますか？", isPresented: Binding(
      get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
      Button("削除", role: .destructive) {
        if let space = deleteTarget { model.deleteSpace(space.id) }
        deleteTarget = nil
      }
      Button("キャンセル", role: .cancel) { deleteTarget = nil }
    } message: {
      Text("ファイルと資料は削除されず、未分類に移動します。")
    }
    .task { await model.cloudSharing.refreshIfConfirmed() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await model.cloudSharing.refreshIfConfirmed() } }
    }
    .refreshable {
      await model.refresh()
      await model.cloudSharing.refreshIfConfirmed()
    }
  }

  private func heading(_ title: String) -> some View {
    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
      .accessibilityAddTraits(.isHeader)
  }

  private func projectLink(_ space: MemoraSpace, taskCounts: [UUID: Int]) -> some View {
    NavigationLink(value: LibraryRoute.space(space.id)) {
      ProjectCard(space: space, recordCount: model.spaceAggregates[space.id]?.meetingCount ?? 0,
        taskCount: taskCounts[space.id] ?? 0)
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button("名前を変更", icon: .pencil) { renameTarget = space }
      Button("チームで共有", icon: .personBadgePlus) { Task { await model.shareSpaceWithTeam(space.id) } }
      Button("削除", icon: .trash, role: .destructive) { deleteTarget = space }
    }
  }
}
