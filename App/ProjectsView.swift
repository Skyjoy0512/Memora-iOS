import SwiftUI

struct ProjectsView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @Binding var query: String
  var isSearching: Bool
  var zoomNamespace: Namespace.ID
  var order: ProjectListOrder
  var recentFirst: Bool
  @Binding var filter: ProjectListFilter
  @State private var renameTarget: MemoraSpace?
  @State private var deleteTarget: MemoraSpace?
  @State private var isShareInboxPresented = false

  var body: some View {
    let latestDates = model.spaceAggregates.compactMapValues(\.latestDate)
    let projects = order.ordered(model.spaces.filter { CollectionSearch.matches(query, fields: [$0.name]) }, latestDates: latestDates)
    let matchingIDs = Set(projects.map(\.id))
    let isAwaitingQuery = isSearching && !CollectionSearch.hasQuery(query)
    let shared = model.cloudSharing.sharedProjects.filter {
      CollectionSearch.matches(query, fields: [$0.name, $0.ownerName])
    }
    let visibleProjects = isAwaitingQuery || filter == .shared ? [] : projects
    let visibleShared = isAwaitingQuery || filter == .mine ? [] : shared
    let total = visibleProjects.count + visibleShared.count
    let recent = !isSearching && recentFirst && !visibleProjects.isEmpty
      ? Array(model.recentProjects.filter { matchingIDs.contains($0.id) }.prefix(3)) : []
    let recentIDs = Set(recent.map(\.id))
    let remaining = visibleProjects.filter { !recentIDs.contains($0.id) }

    ScrollView {
      LazyVStack(alignment: .leading, spacing: MemoraSpacing.lg) {
        if model.shareInboxFailure != nil {
          Button("共有からの取り込みを確認") { isShareInboxPresented = true }
            .font(MemoraTypography.secondary).frame(minHeight: 44).tint(MemoraPalette.textPrimary)
        }
        if isSearching && total > 0 {
          Text("検索結果 \(total)件")
            .font(MemoraTypography.secondary)
            .foregroundStyle(.secondary)
        } else if filter == .all && total > 0 {
          Text("プロジェクト\(total)件")
            .font(MemoraTypography.metadata)
            .foregroundStyle(MemoraPalette.textSecondary)
        }
        if filter != .all {
          HStack {
            Label("表示：\(filter.title)", icon: .line3HorizontalDecrease)
              .font(.subheadline)
            Spacer()
            Button("解除") { filter = .all }
              .frame(minWidth: 44, minHeight: 44)
          }
        }
        if !recent.isEmpty {
          heading("最近開いたプロジェクト", count: nil)
          projectRows(recent)
        }

        if !remaining.isEmpty {
          if !recent.isEmpty { heading("その他のプロジェクト", count: nil) }
          projectRows(remaining)
        } else if visibleProjects.isEmpty && visibleShared.isEmpty {
          if isAwaitingQuery {
            CollectionSearchState(title: "プロジェクトを検索",
              message: "プロジェクト名や、共有した人の名前から探せます。", isEmbedded: true)
          } else if isSearching {
            CollectionSearchState(title: "見つかりませんでした",
              message: "別の語句を入力してください。",
              clear: { query = "" }, clearTitle: "検索をやり直す", isEmbedded: true)
          } else if filter == .shared {
            VStack(alignment: .leading, spacing: 8) {
              Text(filter.emptyTitle).font(MemoraTypography.body.weight(.medium))
              Text(filter.emptyDetail)
                .font(MemoraTypography.secondary).foregroundStyle(.secondary)
            }
            .padding(.vertical, MemoraSpacing.section)
          } else {
            MemoraEmptyState(
              icon: .folder,
              title: filter.emptyTitle,
              message: "録音や資料をプロジェクトにまとめると、ここから開けます。",
              actionTitle: "プロジェクトを作成",
              actionIcon: .plus
            ) {
              model.isFileCreationPresented = true
            }
            .padding(.top, MemoraSpacing.xl)
          }
        }

        if !isSearching, !model.projectChats.isEmpty {
          NavigationLink("チャット履歴", value: LibraryRoute.projectChats(nil))
            .font(MemoraTypography.secondary).frame(minHeight: 44).tint(MemoraPalette.textPrimary)
        }

        if !visibleShared.isEmpty {
          heading("チームから共有", count: visibleShared.count)
          ForEach(visibleShared) { project in
            NavigationLink(value: LibraryRoute.sharedProject(project.id)) {
              HStack(spacing: 12) {
                MemoraInterfaceIcon(icon: project.icon)
                VStack(alignment: .leading, spacing: 4) {
                  Text(project.name).font(MemoraTypography.body.weight(.medium)).lineLimit(2)
                  SharedOwnerBadge(ownerName: project.ownerName)
                  Text("記録 \(project.records.count)件 · 閲覧のみ")
                    .font(MemoraTypography.metadata).foregroundStyle(.secondary)
                }
              }
              .foregroundStyle(.primary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .frame(minHeight: ProjectLayout.minimumRowHeight)
              .padding(.vertical, MemoraSpacing.sm)
              .contentShape(Rectangle())
              .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: project.id, in: zoomNamespace)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, ProjectLayout.horizontalInset)
      .padding(.top, MemoraSpacing.sm)
      .padding(.bottom, model.bottomContentClearance)
    }
    .background(MemoraPalette.background)
    .sheet(item: $renameTarget) { space in RenameSpaceSheet(space: space) }
    .sheet(isPresented: $isShareInboxPresented) { NavigationStack { ShareInboxView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { isShareInboxPresented = false } } } } }
    .confirmationDialog("このプロジェクトを削除しますか？", isPresented: Binding(
      get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
      Button("削除", role: .destructive) {
        if let space = deleteTarget { model.deleteSpace(space.id) }
        deleteTarget = nil
      }
      Button("キャンセル", role: .cancel) { deleteTarget = nil }
    } message: {
      Text("録音・資料・ソースとチャットは削除せず、所属を解除します。")
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
    MemoraSectionHeading(title: title, detail: count.map { "\($0)件" })
  }

  private func projectRows(_ projects: [MemoraSpace]) -> some View {
    LazyVStack(spacing: 0) {
      ForEach(projects) { space in projectLink(space) }
    }
  }

  private func projectLink(_ space: MemoraSpace) -> some View {
    let aggregate = model.spaceAggregates[space.id]
    return ProjectListRow(space: space, zoomNamespace: zoomNamespace, recordCount: aggregate?.meetingCount ?? 0,
      latestRecordDate: aggregate?.latestDate,
      rename: { renameTarget = space },
      share: { Task { await model.shareSpaceWithTeam(space.id) } },
      delete: { deleteTarget = space })
  }
}
