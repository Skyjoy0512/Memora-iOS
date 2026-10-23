import EventKit
import SwiftUI

struct LibraryView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var query = ""
  @State private var isSearching = false
  @Namespace private var heroNamespace
  @State private var isSelectionMode = false
  @State private var selectedMeetingIDs: Set<UUID> = []
  @State private var isBulkDeleteConfirmPresented = false
  @State private var isBulkSpacePickerPresented = false
  @State private var shareItems: [Any] = []
  @State private var isSharing = false
  @State private var temporaryShareURL: URL?
  @State private var isTeamShareNoticePresented = false
  @State private var teamShareErrorMessage: String?
  /// The coming calendar events, shown only while some are coming up.
  @State private var upcoming = UpcomingMeetingStore()
  @AppStorage("memora.files.layout") private var layout = FileListLayout.card
  @AppStorage("memora.files.sort") private var sort = FileListSort.newest
  @AppStorage("memora.files.filter") private var statusFilter = FileListFilter.all
  @State private var renameTarget: Meeting?
  @State private var moveTarget: Meeting?
  @State private var shareTarget: Meeting?
  var onOpenSidebar: () -> Void

  private var librarySectionPicker: some View {
    @Bindable var model = model
    return MemoraTextTabBar(items: LibrarySection.allCases, selection: $model.librarySection, horizontalPadding: MemoraSpacing.screen) {
      $0.title
    }
    .accessibilityLabel("ライブラリの表示")
  }

  /// Sort, filter and selection sit beside the tabs, keeping the navigation bar
  /// to the title and two actions.
  private var fileViewOptions: some View {
    Menu {
      Picker("表示", selection: $layout) {
        ForEach(FileListLayout.allCases) {
          Text($0 == .card ? "プレビュー付き" : "コンパクト").tag($0)
        }
      }
      Picker("並べ替え", selection: $sort) {
        ForEach(FileListSort.allCases) { Text($0.label).tag($0) }
      }
      Picker("絞り込み", selection: $statusFilter) {
        ForEach(FileListFilter.allCases) { Text($0.label).tag($0) }
      }
      Divider()
      Button("選択", icon: .checkmarkCircle) {
        beginSelectionMode()
      }
    } label: {
      Image(icon: .line3HorizontalDecrease, size: MemoraIconMetrics.glyph)
        .foregroundStyle(MemoraPalette.textPrimary)
        .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
        .contentShape(Rectangle())
    }
    .accessibilityLabel("表示と並べ替え")
    .tint(MemoraPalette.textPrimary)
  }

  var body: some View {
    @Bindable var model = model

    NavigationStack(path: $model.libraryPath) {
      VStack(spacing: 0) {
        if !isSearching, !isSelectionMode {
          HStack(spacing: MemoraSpacing.sm) {
            librarySectionPicker
            Spacer(minLength: 0)
            if model.librarySection == .files {
              fileViewOptions
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, MemoraSpacing.md)
          .padding(.trailing, MemoraSpacing.screen)
          .padding(.bottom, MemoraSpacing.sm)
        }
        Group {
          if model.librarySection == .files {
            filesPage
          } else {
            ProjectsView(query: $query, isSearching: isSearching)
          }
        }
      }
      .background(MemoraPalette.background)
      .navigationTitle(isSelectionMode ? "\(selectedMeetingIDs.count)件を選択" : (isSearching ? "" : "ライブラリ"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbarSearch(text: $query, isPresented: $isSearching, prompt: model.librarySection.searchPrompt)
      .toolbar {
        if !isSearching {
          ToolbarItem(placement: .principal) {
            Text(isSelectionMode ? "\(selectedMeetingIDs.count)件を選択" : "ライブラリ")
              .font(.headline)
              .lineLimit(1)
          }
        }

        if isSelectionMode {
          ToolbarItem(placement: .topBarLeading) {
            ToolbarIconButton("キャンセル", icon: .xmark) { endSelection() }
          }
        } else {
          ToolbarActionItem(placement: .topBarLeading) {
            ToolbarIconButton("メニュー", icon: .line3Horizontal) {
              onOpenSidebar()
            }
          }
        }

        // The `if` sits outside the item, so an empty item never leaves an
        // empty glass frame behind.
        if !isSelectionMode {
          ToolbarItem(placement: .topBarTrailing) {
            RecorderStatusToolbarButton()
          }

          if model.librarySection == .files {
            ToolbarActionItem(usesSystemBackground: true) {
              CaptureToolbarButton(spaceID: model.visibleProjectID, tab: .library)
            }
          } else {
            ToolbarActionItem {
              ToolbarIconButton("プロジェクトを作成", icon: .plus) {
                model.isFileCreationPresented = true
              }
              .disabled(model.isRestoring)
            }
          }
        }

      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if isSelectionMode {
          selectionBar
        }
      }
      .onChange(of: isSelectionMode) { _, selecting in
        model.isFileSelectionActive = selecting
      }
      .onAppear { model.isFileSelectionActive = isSelectionMode }
      .navigationDestination(for: LibraryRoute.self) { route in
        switch route {
        case .meeting(let id):
          if model.librarySection == .files {
            MeetingDetailView(meetingID: id)
              .navigationTransition(.zoom(sourceID: id, in: heroNamespace))
          } else {
            MeetingDetailView(meetingID: id)
          }
        default: LibraryDestinationView(route: route)
        }
      }
      .confirmationDialog(
        "選択したファイルを削除しますか？",
        isPresented: $isBulkDeleteConfirmPresented,
        titleVisibility: .visible
      ) {
        Button("削除", role: .destructive) {
          model.deleteMeetings(selectedMeetingIDs)
          endSelection()
        }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("\(selectedMeetingIDs.count)件を「最近削除した項目」へ移動します。30日間は復元できます。")
      }
      .sheet(isPresented: $isBulkSpacePickerPresented) {
        BulkSpacePickerSheet(meetingIDs: selectedMeetingIDs) { endSelection() }
      }
      .sheet(isPresented: $isSharing, onDismiss: cleanUpSharedFiles) {
        ActivityView(items: shareItems, onComplete: cleanUpSharedFiles)
      }
      .sheet(item: $renameTarget) { meeting in
        RenameMeetingSheet(meeting: meeting)
      }
      .sheet(item: $moveTarget) { meeting in
        BulkSpacePickerSheet(meetingIDs: [meeting.id]) {}
      }
      .sheet(item: $shareTarget) { meeting in
        ActivityView(items: [MeetingShareText.make(meeting: meeting, tasks: model.tasks)]) {}
      }
      .alert("チームプランで利用できます", isPresented: $isTeamShareNoticePresented) {
        Button("プランを見る") { model.isPaywallPresented = true }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("チーム共有は、選んだファイルを音声・写真つきのパッケージとして書き出し、チームのメンバーに渡せます。")
      }
      .alert("チーム共有を作成できませんでした", isPresented: teamShareErrorBinding) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(teamShareErrorMessage ?? "")
      }
      .task {
        await upcoming.refresh()
        await model.cloudSharing.refreshIfConfirmed()
      }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active else { return }
        Task {
          await upcoming.refresh()
          await model.cloudSharing.refreshIfConfirmed()
        }
      }
      .onChange(of: model.librarySection) { _, _ in
        query = ""
        isSearching = false
        model.isSearchActive = false
        endSelection()
      }
      .onChange(of: model.selectedTab) { _, tab in
        guard tab == .library else { return }
        Task { await upcoming.refresh() }
      }
      .onChange(of: model.sidebarSearchRequest) { _, request in
        guard request != nil, model.selectedTab == .library, !model.isToolsPresented,
              model.libraryPath.isEmpty else { return }
        endSelection()
        isSearching = true
      }
      .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
        Task { await upcoming.refresh() }
      }
    }
  }

  private func recordOnline(_ meeting: UpcomingMeeting) {
    model.onlineMeetingCaptureEvent = meeting
    model.isOnlineMeetingCapturePresented = true
  }

  /// The coming events (only while some are coming up) and the live recording
  /// strip, as the first rows of the list so they scroll away with it.
  @ViewBuilder
  private var listHeaderRows: some View {
    if !upcoming.meetings.isEmpty {
      VStack(spacing: 18) {
        UpcomingEventsRow(
          meetings: upcoming.meetings,
          onRecordInPerson: { meeting in
            Task { await model.startCapture(event: meeting) }
          },
          onRecordOnline: recordOnline
        )
        Divider()
          .padding(.horizontal, MemoraSpacing.screen)
      }
      // The row pages edge to edge; its own margins line the cards up.
      .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
    }

    if model.isRecording {
      ActiveRecordingStrip()
        .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 10, trailing: 18))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
  }

  private var filesPage: some View {
    // Searching replaces the list with its results; before anything is typed
    // there is nothing to match, so the files stay out of the way.
    let isAwaitingQuery = isSearching && query.isEmpty
    let sections = isAwaitingQuery ? [] : fileSections
    let count = sections.reduce(0) { $0 + $1.meetings.count }
    let sharedRecords = model.cloudSharing.sharedRecords
    let savedSources = isAwaitingQuery ? [] : model.projectSources.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
    let resultCount = count + savedSources.count

    return List {
      if !isSearching {
        listHeaderRows

        if model.hasSampleContent {
          SampleNoticeRow()
            .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 10, trailing: 18))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
      }

      if statusFilter != .all {
        filterChipRow
      }

      // Teammates' records sit in their own section, apart from this person's
      // files, and only while nothing narrows the list.
      if !isSearching, statusFilter == .all, !sharedRecords.isEmpty {
        Section {
          ForEach(sharedRecords) { record in
            sharedRow(record)
          }
        } header: {
          Label("チームから共有", icon: .person2)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
        }
      }

      if !savedSources.isEmpty, !isAwaitingQuery {
        Section {
          ForEach(Array(savedSources.prefix(3))) { source in
            NavigationLink(value: LibraryRoute.projectSource(source.id)) { ProjectSourceRow(source: source) }
          }
          NavigationLink("すべてのソース", value: LibraryRoute.projectSources(nil))
        } header: {
          Text("保存したソース").font(.subheadline.weight(.semibold)).textCase(nil)
        }
      }

      if sections.isEmpty && savedSources.isEmpty {
        Group {
          if isAwaitingQuery {
            MemoraEmptyState(icon: .magnifyingglass, title: "ファイルを検索",
              message: "タイトル、発言、決定、タスクと保存したソースから探せます。")
          } else if !query.isEmpty {
            MemoraEmptyState(icon: .magnifyingglass, title: "見つかりませんでした",
              message: "「\(query)」に一致するファイル・ソースはありません。短い言葉や別の表現で試してください。",
              actionTitle: "検索をやり直す", actionIcon: .xmark) { query = "" }
          } else if statusFilter != .all {
            filteredEmpty
          } else {
            emptyFilesPrompt
          }
        }
        .frame(maxWidth: .infinity)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 48, leading: 18, bottom: 48, trailing: 18))
      } else {
        // Grouped by date, each heading inside the list so it scrolls away.
        ForEach(sections) { section in
          Section {
            ForEach(section.meetings) { meeting in
              meetingRow(meeting)
            }
          } header: {
            Text(section.title)
              .font(MemoraTypography.secondary.weight(.medium))
              .foregroundStyle(MemoraPalette.textSecondary)
              .textCase(nil)
          }
        }

        if !query.isEmpty {
          Text("\(resultCount)件")
            .font(MemoraTypography.secondary)
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .accessibilityLabel("\(resultCount)件の検索結果")
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    .refreshable {
      await model.refresh()
      await upcoming.refresh()
      await model.cloudSharing.refreshIfConfirmed()
    }
  }

  private var filterChipRow: some View {
    HStack(spacing: 8) {
      Label(statusFilter.label, icon: .line3HorizontalDecrease)
        .font(.subheadline.weight(.medium))
      Spacer(minLength: 8)
      Button { statusFilter = .all } label: {
        Text("解除")
          .font(MemoraTypography.secondary.weight(.medium))
          .frame(minWidth: MemoraSpacing.touchTarget, minHeight: MemoraSpacing.touchTarget)
      }
    }
    .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 8, trailing: 18))
    .listRowSeparator(.hidden)
    .listRowBackground(Color.clear)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("絞り込み中: \(statusFilter.label)")
  }

  private var filteredEmpty: some View {
    MemoraEmptyState(icon: .line3HorizontalDecrease, title: "該当する記録はありません",
      message: "絞り込みを解除すると、ほかの記録を確認できます。",
      actionTitle: "絞り込みを解除", actionIcon: .xmark) { statusFilter = .all }
  }

  /// One file row. Tapping opens it, or selects it while a selection is being
  /// made. A left swipe starts selecting with this record already chosen.
  private func meetingRow(_ meeting: Meeting) -> some View {
    Group {
      if layout == .card {
        cardRow(meeting)
      } else {
        listRow(meeting)
      }
    }
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button(role: .destructive) {
        withAnimation(reduceMotion ? nil : MemoraMotion.screen) {
          model.deleteMeeting(meeting.id)
        }
      } label: {
        Label("削除", icon: .trash)
      }
    }
    .swipeActions(edge: .leading) {
      Button {
        withAnimation(reduceMotion ? nil : MemoraMotion.control) {
          beginSelection(with: meeting.id)
        }
      } label: {
        Label("選択", icon: .checkmarkCircle)
      }
      .tint(MemoraPalette.textPrimary)
    }
    .contextMenu {
      Button("開く", icon: .arrowUpRightSquare) {
        model.libraryPath.append(.meeting(meeting.id))
      }
      Button("名前を変更", icon: .pencil) { renameTarget = meeting }
      Button("プロジェクトへ移動", icon: .folder) { moveTarget = meeting }
      Button("共有", icon: .squareAndArrowUp) { shareTarget = meeting }
      Button("選択", icon: .checkmarkCircle) { beginSelection(with: meeting.id) }
      Button("削除", icon: .trash, role: .destructive) { model.deleteMeeting(meeting.id) }
    }
  }

  private func cardRow(_ meeting: Meeting) -> some View {
    Button {
      openOrSelect(meeting)
    } label: {
      LibraryRecordRow(
        meeting: meeting,
        showsPreview: true,
        isSelecting: isSelectionMode,
        isSelected: selectedMeetingIDs.contains(meeting.id)
      )
      .matchedTransitionSource(id: meeting.id, in: heroNamespace)
    }
    .buttonStyle(.plain)
    .listRowInsets(EdgeInsets(top: 8, leading: ProjectLayout.horizontalInset, bottom: 8, trailing: ProjectLayout.horizontalInset))
    .listRowSeparator(.visible, edges: .bottom)
    .alignmentGuide(.listRowSeparatorLeading) { _ in ProjectLayout.iconSide + 12 }
    .listRowBackground(Color.clear)
  }

  private func listRow(_ meeting: Meeting) -> some View {
    Button {
      openOrSelect(meeting)
    } label: {
      LibraryRecordRow(meeting: meeting, showsPreview: false,
        isSelecting: isSelectionMode, isSelected: selectedMeetingIDs.contains(meeting.id))
    }
    .buttonStyle(.plain)
    .listRowInsets(EdgeInsets(top: 8, leading: ProjectLayout.horizontalInset, bottom: 8, trailing: ProjectLayout.horizontalInset))
    .listRowSeparator(.visible, edges: .bottom)
    .alignmentGuide(.listRowSeparatorLeading) { _ in ProjectLayout.iconSide + 12 }
    .listRowBackground(Color.clear)
  }

  /// A teammate's record: opens read-only, with none of the actions that
  /// would change it.
  private func sharedRow(_ record: SharedRecord) -> some View {
    Button {
      model.libraryPath.append(.sharedRecord(record.id))
    } label: {
      LibraryRecordRow(meeting: record.meeting, showsPreview: layout == .card,
        sharedBy: record.ownerName)
    }
    .buttonStyle(.plain)
    .listRowInsets(EdgeInsets(top: 8, leading: ProjectLayout.horizontalInset, bottom: 8, trailing: ProjectLayout.horizontalInset))
    .listRowSeparator(.visible, edges: .bottom)
    .alignmentGuide(.listRowSeparatorLeading) { _ in ProjectLayout.iconSide + 12 }
    .listRowBackground(Color.clear)
  }

  private func openOrSelect(_ meeting: Meeting) {
    if isSelectionMode {
      toggleSelection(meeting.id)
    } else {
      InteractionFeedback.shared.send(.tap)
      model.libraryPath.append(.meeting(meeting.id))
    }
  }

  private var selectionBar: some View {
    HStack(spacing: 8) {
      selectionAction("共有", icon: .squareAndArrowUp) { shareSelected() }
      selectionAction(
        "チーム",
        icon: model.hasTeamPlan ? .person3Fill : .person3
      ) {
        shareSelectedWithTeam()
      }
      selectionAction("移動", icon: .folder) { isBulkSpacePickerPresented = true }
      selectionAction("削除", icon: .trash, isDestructive: true) {
        isBulkDeleteConfirmPresented = true
      }
    }
    .padding(MemoraSpacing.sm)
    .memoraGlass(in: RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
    .padding(.horizontal, MemoraSpacing.md)
    .padding(.bottom, MemoraSpacing.sm)
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }

  private func selectionAction(
    _ title: String,
    icon: MemoraIcon,
    isDestructive: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button {
      InteractionFeedback.shared.send(.tap)
      action()
    } label: {
      VStack(spacing: 3) {
        Image(icon: icon)
          .font(.title3)
        Text(title)
          .font(.caption2.weight(.medium))
      }
      .frame(maxWidth: .infinity, minHeight: 48)
      .foregroundStyle(isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(selectedMeetingIDs.isEmpty)
    .accessibilityLabel(title)
  }

  private var emptyFilesPrompt: some View {
    MemoraEmptyState(
      icon: .waveform,
      title: "ファイルはまだありません",
      message: "録音や読み込んだ音声を、プロジェクトをまたいで一覧できます。",
      actionTitle: "録音または読み込み",
      actionIcon: .plus
    ) {
      model.isCaptureSourcePresented = true
    }
    .padding(.vertical, MemoraSpacing.group)
  }

  // MARK: - Selection

  private func beginSelection(with id: UUID) {
    InteractionFeedback.shared.send(.selection)
    isSelectionMode = true
    selectedMeetingIDs.insert(id)
  }

  private func beginSelectionMode() {
    withAnimation(reduceMotion ? nil : MemoraMotion.control) {
      isSelectionMode = true
    }
  }

  private func toggleSelection(_ id: UUID) {
    InteractionFeedback.shared.send(.selection)
    withAnimation(reduceMotion ? nil : MemoraMotion.control) {
      if selectedMeetingIDs.contains(id) {
        selectedMeetingIDs.remove(id)
      } else {
        selectedMeetingIDs.insert(id)
      }
    }
  }

  private func endSelection() {
    withAnimation(reduceMotion ? nil : MemoraMotion.control) {
      isSelectionMode = false
      selectedMeetingIDs = []
    }
  }

  private func shareSelected() {
    let selected = model.meetings.filter { selectedMeetingIDs.contains($0.id) }
    guard !selected.isEmpty else { return }
    temporaryShareURL = nil
    shareItems = [
      selected
        .map { MeetingShareText.make(meeting: $0, tasks: model.tasks) }
        .joined(separator: "\n\n———\n\n")
    ]
    isSharing = true
  }

  /// Writes the chosen records into a package a teammate can restore. Team plan
  /// only, so it offers the plan rather than producing something for a free user.
  private func shareSelectedWithTeam() {
    guard model.hasTeamPlan else {
      isTeamShareNoticePresented = true
      return
    }
    let ids = selectedMeetingIDs
    guard !ids.isEmpty else { return }
    Task {
      do {
        let url = try await model.makeTeamSharePackage(meetingIDs: ids)
        temporaryShareURL = url
        shareItems = [url]
        isSharing = true
      } catch {
        teamShareErrorMessage = error.localizedDescription
      }
    }
  }

  /// Removes the temporary team package after the share sheet is finished.
  private func cleanUpSharedFiles() {
    guard let url = temporaryShareURL else { return }
    temporaryShareURL = nil
    shareItems = []
    try? FileManager.default.removeItem(at: url)
  }

  private var teamShareErrorBinding: Binding<Bool> {
    Binding {
      teamShareErrorMessage != nil
    } set: { isPresented in
      if !isPresented { teamShareErrorMessage = nil }
    }
  }

  /// Every match, filtered, sorted and grouped by date. The list shows all of
  /// them; `List` draws lazily, so nothing is cut off behind a cap.
  private var matchingMeetings: [Meeting] {
    let records = model.meetings
    var result = records.filter { statusFilter.matches($0.status) }
    if !query.isEmpty {
      result = result.filter(matchesQuery)
    }
    switch sort {
    case .newest: result.sort { $0.createdAt > $1.createdAt }
    case .oldest: result.sort { $0.createdAt < $1.createdAt }
    case .longest: result.sort { $0.duration > $1.duration }
    }
    return result
  }

  /// The meetings grouped into date sections, in the order the sort puts them.
  private var fileSections: [FileDateSection] {
    let calendar = Calendar.current
    var sections: [FileDateSection] = []
    for meeting in matchingMeetings {
      let key = sectionKey(for: meeting.createdAt, calendar: calendar)
      if let index = sections.firstIndex(where: { $0.id == key }) {
        sections[index].meetings.append(meeting)
      } else {
        sections.append(
          FileDateSection(
            id: key,
            title: sectionTitle(for: meeting.createdAt, calendar: calendar),
            meetings: [meeting]
          )
        )
      }
    }
    return sections
  }

  private func sectionKey(for date: Date, calendar: Calendar) -> String {
    if calendar.isDateInToday(date) { return "today" }
    if calendar.isDateInYesterday(date) { return "yesterday" }
    if calendar.isDate(date, equalTo: .now, toGranularity: .weekOfYear) { return "week" }
    if calendar.isDate(date, equalTo: .now, toGranularity: .month) { return "month" }
    let parts = calendar.dateComponents([.year, .month], from: date)
    return "m\(parts.year ?? 0)-\(parts.month ?? 0)"
  }

  private func sectionTitle(for date: Date, calendar: Calendar) -> String {
    if calendar.isDateInToday(date) { return "今日" }
    if calendar.isDateInYesterday(date) { return "昨日" }
    if calendar.isDate(date, equalTo: .now, toGranularity: .weekOfYear) { return "今週" }
    if calendar.isDate(date, equalTo: .now, toGranularity: .month) { return "今月" }
    return MemoraFormat.monthTitle(date)
  }

  private func matchesQuery(_ meeting: Meeting) -> Bool {
    model.searchText(for: meeting).localizedCaseInsensitiveContains(query)
  }

}

/// A date heading and the meetings under it, for the files list.
private struct FileDateSection: Identifiable {
  var id: String
  var title: String
  var meetings: [Meeting]
}
