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
        // Small collections are faster to scan once, without duplicate cards.
        if !isSearching, model.spaces.count > 3, !recent.isEmpty {
          heading("最近使用", count: nil)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
              ForEach(recent.prefix(3)) { space in recentLink(space) }
            }
          }
        }

        if !projects.isEmpty {
          heading(isSearching ? "検索結果" : "すべてのプロジェクト", count: projects.count)
          LazyVStack(spacing: 12) {
            ForEach(projects) { space in projectLink(space, taskCounts: taskCounts) }
          }
        } else if shared.isEmpty {
          if isSearching {
            ContentUnavailableView.search(text: query)
          } else {
            ContentUnavailableView {
              Label("最初のプロジェクトを作成", icon: .rectangleStack)
            } description: {
              Text("仕事の案件や日々のテーマごとに、記録とタスクをまとめられます。")
            } actions: {
              Button("プロジェクトを作成", icon: .folderBadgePlus) { model.isFileCreationPresented = true }
                .buttonStyle(.borderedProminent)
                .tint(MemoraPalette.action)
                .foregroundStyle(MemoraPalette.actionLabel)
                .disabled(model.isRestoring)
            }
          }
        }

        if !shared.isEmpty {
          heading("チームから共有", count: shared.count)
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
              .memoraCard(fill: MemoraPalette.card)
              .contentShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 18)
      .padding(.top, 8)
      .padding(.bottom, model.bottomContentClearance)
    }
    .background(MemoraPalette.background)
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

  private func heading(_ title: String, count: Int?) -> some View {
    HStack(spacing: 12) {
      Text(title).font(.subheadline.weight(.semibold))
      if let count {
        Spacer(minLength: 12)
        Text("\(count)件").font(.subheadline).monospacedDigit()
      }
    }
    .foregroundStyle(.secondary)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }

  private func recentLink(_ space: MemoraSpace) -> some View {
    NavigationLink(value: LibraryRoute.space(space.id)) {
      HStack(spacing: 10) {
        Image(icon: space.icon).accessibilityHidden(true)
        Text(space.name).font(.subheadline.weight(.medium))
          .lineLimit(2).fixedSize(horizontal: false, vertical: true)
      }
      .foregroundStyle(.primary)
      .frame(width: 172, alignment: .leading)
      .frame(minHeight: 44)
      .padding(14)
      .memoraCard(radius: 16, fill: MemoraPalette.card)
      .contentShape(RoundedRectangle(cornerRadius: 16))
    }
    .buttonStyle(.plain)
  }

  private func projectLink(_ space: MemoraSpace, taskCounts: [UUID: Int]) -> some View {
    let aggregate = model.spaceAggregates[space.id]
    return ProjectCard(space: space, recordCount: aggregate?.meetingCount ?? 0,
      taskCount: taskCounts[space.id] ?? 0, latestRecordDate: aggregate?.latestDate,
      rename: { renameTarget = space },
      share: { Task { await model.shareSpaceWithTeam(space.id) } },
      delete: { deleteTarget = space })
  }
}
