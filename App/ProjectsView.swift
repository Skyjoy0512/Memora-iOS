import SwiftUI

struct ProjectsView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("memora.projects.listOrder") private var order = ProjectListOrder.name
  @AppStorage("memora.projects.recentFirst") private var recentFirst = false
  var query: String
  var isSearching: Bool
  @State private var renameTarget: MemoraSpace?
  @State private var deleteTarget: MemoraSpace?
  @State private var isShareInboxPresented = false
  @State private var filter = ProjectListFilter.all

  var body: some View {
    let latestDates = model.spaceAggregates.compactMapValues(\.latestDate)
    let projects = order.ordered(model.spaces.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }, latestDates: latestDates)
    let matchingIDs = Set(projects.map(\.id))
    let shared = model.cloudSharing.sharedProjects.filter {
      query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.ownerName.localizedCaseInsensitiveContains(query)
    }
    let visibleProjects = filter == .shared ? [] : projects
    let visibleShared = filter == .mine ? [] : shared
    let total = visibleProjects.count + visibleShared.count
    let recent = !isSearching && recentFirst && visibleProjects.count > 3
      ? Array(model.recentProjects.filter { matchingIDs.contains($0.id) }.prefix(3)) : []
    let recentIDs = Set(recent.map(\.id))
    let remaining = visibleProjects.filter { !recentIDs.contains($0.id) }

    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        ProjectListFilterBar(selection: $filter)
        if model.shareInboxFailure != nil {
          Button("共有からの取り込みを確認") { isShareInboxPresented = true }
            .font(.subheadline).frame(minHeight: 44).tint(MemoraPalette.textPrimary)
        }
        if total > 0 {
          HStack {
            Text(isSearching ? "検索結果 \(total)件" : "\(total)件")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .accessibilityLabel("プロジェクト\(total)件")
            Spacer()
            if filter != .shared { orderMenu }
          }
        }
        if !recent.isEmpty {
          heading("最近使用", count: nil)
          projectRows(recent)
        }

        if !visibleProjects.isEmpty {
          if !recent.isEmpty, !remaining.isEmpty { heading("その他のプロジェクト", count: nil) }
          projectRows(remaining)
        } else if visibleShared.isEmpty {
          if isSearching {
            ContentUnavailableView.search(text: query)
          } else {
            VStack(alignment: .leading, spacing: 8) {
              Text(filter.emptyTitle).font(.body.weight(.semibold))
              Text(filter.emptyDetail)
                .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.vertical, 32)
          }
        }

        if !model.projectChats.isEmpty {
          NavigationLink("チャット履歴", value: LibraryRoute.projectChats(nil))
            .font(.subheadline).frame(minHeight: 44).tint(MemoraPalette.textPrimary)
        }

        if !visibleShared.isEmpty {
          heading("チームから共有", count: visibleShared.count)
          ForEach(visibleShared) { project in
            NavigationLink(value: LibraryRoute.sharedProject(project.id)) {
              HStack(spacing: 12) {
                Image(icon: project.icon).frame(width: ProjectLayout.iconSide).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                  Text(project.name).font(.body.weight(.semibold)).lineLimit(2)
                  SharedOwnerBadge(ownerName: project.ownerName)
                  Text("記録 \(project.records.count)件 · 閲覧のみ")
                    .font(.footnote).foregroundStyle(.secondary)
                }
              }
              .foregroundStyle(.primary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .frame(minHeight: ProjectLayout.minimumRowHeight)
              .padding(.vertical, 8)
              .contentShape(Rectangle())
              .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, ProjectLayout.horizontalInset)
      .padding(.top, 8)
      .padding(.bottom, model.bottomContentClearance)
    }
    .background(MemoraPalette.background)
    .hideBottomBarOnScroll(RootTab.library.rawValue)
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

  private var orderMenu: some View {
    Menu {
      Picker("並べ替え", selection: $order) {
        ForEach(ProjectListOrder.allCases) { Text($0.title).tag($0) }
      }
      Toggle("最近使用を先に", isOn: $recentFirst)
    } label: {
      Text("並べ替え").font(.subheadline).frame(minHeight: 44)
    }
    .accessibilityValue(order.title)
    .tint(MemoraPalette.textPrimary)
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

  private func projectRows(_ projects: [MemoraSpace]) -> some View {
    LazyVStack(spacing: 0) {
      ForEach(projects) { space in projectLink(space) }
    }
  }

  private func projectLink(_ space: MemoraSpace) -> some View {
    let aggregate = model.spaceAggregates[space.id]
    return ProjectListRow(space: space, recordCount: aggregate?.meetingCount ?? 0,
      latestRecordDate: aggregate?.latestDate,
      rename: { renameTarget = space },
      share: { Task { await model.shareSpaceWithTeam(space.id) } },
      delete: { deleteTarget = space })
  }
}
