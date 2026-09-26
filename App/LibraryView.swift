import EventKit
import SwiftUI

struct LibraryView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var query = ""
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
  /// The next calendar event, shown only while one is coming up.
  @State private var upcoming = UpcomingMeetingStore()
  @State private var isStartingMeeting = false
  @AppStorage("memora.files.layout") private var layout = FileListLayout.card
  @AppStorage("memora.files.sort") private var sort = FileListSort.newest
  @AppStorage("memora.files.filter") private var statusFilter = FileListFilter.all
  @State private var renameTarget: Meeting?
  @State private var moveTarget: Meeting?
  @State private var shareTarget: Meeting?
  var onOpenSidebar: () -> Void

  var body: some View {
    @Bindable var model = model

    NavigationStack(path: $model.libraryPath) {
      // The section switch lives inside the scroll content so it moves out of
      // the way as you read, and the list stays the screen's own scroll view so
      // the title and search bar collapse the way the system expects.
      Group {
        switch model.fileSection {
        case .meetingFiles:
          filesPage
        case .projects:
          projectsPage
        }
      }
      .background(Color(uiColor: .systemBackground))
      .navigationTitle(isSelectionMode ? "\(selectedMeetingIDs.count)件を選択" : "ファイル")
      .searchable(
        text: $query,
        placement: .navigationBarDrawer(displayMode: .automatic),
        prompt: "ファイルやプロジェクトを検索"
      )
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          if isSelectionMode {
            Button("キャンセル") { endSelection() }
          } else {
            Button("メニュー", systemImage: "line.3.horizontal") {
              onOpenSidebar()
            }
            .labelStyle(.iconOnly)
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          if model.fileSection == .projects, !isSelectionMode {
            Button("プロジェクトを作成", systemImage: "folder.badge.plus") {
              model.isFileCreationPresented = true
            }
            .labelStyle(.iconOnly)
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          if model.fileSection == .meetingFiles, !isSelectionMode {
            Menu {
              Picker("表示", selection: $layout) {
                ForEach(FileListLayout.allCases) { Text($0.label).tag($0) }
              }
              Picker("並べ替え", selection: $sort) {
                ForEach(FileListSort.allCases) { Text($0.label).tag($0) }
              }
              Picker("絞り込み", selection: $statusFilter) {
                ForEach(FileListFilter.allCases) { Text($0.label).tag($0) }
              }
              Divider()
              Button("選択", systemImage: "checkmark.circle") {
                beginSelectionMode()
              }
            } label: {
              Label("表示と並べ替え", systemImage: "line.3.horizontal.decrease")
                .labelStyle(.iconOnly)
            }
          }
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if isSelectionMode {
          selectionBar
        }
      }
      .navigationDestination(for: LibraryRoute.self) { route in
        switch route {
        case .meeting(let id):
          MeetingDetailView(meetingID: id)
            .navigationTransition(.zoom(sourceID: id, in: heroNamespace))
        case .transcript(let id): TranscriptView(meetingID: id)
        case .space(let id):
          SpaceDetailView(spaceID: id)
            .navigationTransition(.zoom(sourceID: id, in: heroNamespace))
        case .allMeetings: AllMeetingsView()
        case .settings: SettingsView()
        case .stateGallery: StateGalleryView()
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
      .onChange(of: model.fileSection) { _, _ in endSelection() }
      .task { await upcoming.refresh() }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active else { return }
        Task { await upcoming.refresh() }
      }
      .onChange(of: model.selectedTab) { _, tab in
        guard tab == .files else { return }
        Task { await upcoming.refresh() }
      }
      .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
        Task { await upcoming.refresh() }
      }
    }
  }

  private func startRecording(for meeting: UpcomingMeeting) {
    Task {
      isStartingMeeting = true
      await model.startCapture(event: meeting)
      isStartingMeeting = false
    }
  }

  /// The 「ファイル／プロジェクト」 switch, shared by both pages.
  private var sectionSwitch: some View {
    Picker(
      "表示",
      selection: Binding(
        get: { model.fileSection },
        set: { model.fileSection = $0 }
      )
    ) {
      ForEach(FileSection.allCases) { section in
        Text(section.title).tag(section)
      }
    }
    .pickerStyle(.segmented)
  }

  /// The section switch, the next meeting (only while one is coming up) and the
  /// live recording strip, as the first rows of the list so they scroll away
  /// with it.
  @ViewBuilder
  private var listHeaderRows: some View {
    sectionSwitch
      .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 10, trailing: 18))
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)

    if let meeting = upcoming.meeting {
      UpcomingMeetingLiveCard(meeting: meeting, isStarting: isStartingMeeting) {
        startRecording(for: meeting)
      }
      .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 12, trailing: 18))
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
    let sections = fileSections
    let count = sections.reduce(0) { $0 + $1.meetings.count }

    return List {
      listHeaderRows

      if model.hasSampleContent, query.isEmpty {
        SampleNoticeRow()
          .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 10, trailing: 18))
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
      }

      if statusFilter != .all {
        filterChipRow
      }

      if sections.isEmpty {
        Group {
          if !query.isEmpty {
            ContentUnavailableView.search(text: query)
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
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)
              .textCase(nil)
          }
        }

        if !query.isEmpty {
          Text("\(count)件")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .accessibilityLabel("\(count)件の検索結果")
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    .refreshable {
      await model.refresh()
      await upcoming.refresh()
    }
    .animation(reduceMotion ? nil : MemoraMotion.screen, value: upcoming.meeting?.id)
    .hideBottomBarOnScroll(RootTab.files.rawValue)
  }

  private var filterChipRow: some View {
    HStack(spacing: 8) {
      Label(statusFilter.label, systemImage: "line.3.horizontal.decrease")
        .font(.subheadline.weight(.medium))
      Spacer(minLength: 8)
      Button("解除") { statusFilter = .all }
        .font(.subheadline.weight(.semibold))
    }
    .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 8, trailing: 18))
    .listRowSeparator(.hidden)
    .listRowBackground(Color.clear)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("絞り込み中: \(statusFilter.label)")
  }

  private var filteredEmpty: some View {
    ContentUnavailableView {
      Label("該当する記録はありません", systemImage: "line.3.horizontal.decrease")
    } actions: {
      Button("絞り込みを解除") { statusFilter = .all }
    }
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
        Label("削除", systemImage: "trash")
      }
    }
    .swipeActions(edge: .leading) {
      Button {
        withAnimation(reduceMotion ? nil : MemoraMotion.control) {
          beginSelection(with: meeting.id)
        }
      } label: {
        Label("選択", systemImage: "checkmark.circle")
      }
      .tint(.blue)
    }
    .contextMenu {
      Button("開く", systemImage: "arrow.up.right.square") {
        model.libraryPath.append(.meeting(meeting.id))
      }
      Button("名前を変更", systemImage: "pencil") { renameTarget = meeting }
      Button("プロジェクトへ移動", systemImage: "folder") { moveTarget = meeting }
      Button("共有", systemImage: "square.and.arrow.up") { shareTarget = meeting }
      Button("選択", systemImage: "checkmark.circle") { beginSelection(with: meeting.id) }
      Button("削除", systemImage: "trash", role: .destructive) { model.deleteMeeting(meeting.id) }
    }
  }

  private func cardRow(_ meeting: Meeting) -> some View {
    Button {
      openOrSelect(meeting)
    } label: {
      MeetingCard(
        meeting: meeting,
        isSelecting: isSelectionMode,
        isSelected: selectedMeetingIDs.contains(meeting.id)
      )
      .matchedTransitionSource(id: meeting.id, in: heroNamespace)
    }
    .buttonStyle(.plain)
    .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18))
    .listRowSeparator(.hidden)
    .listRowBackground(Color.clear)
  }

  private func listRow(_ meeting: Meeting) -> some View {
    Button {
      openOrSelect(meeting)
    } label: {
      MeetingRow(meeting: meeting, showsDisclosure: false)
    }
    .buttonStyle(.plain)
    .listRowInsets(EdgeInsets(top: 2, leading: 18, bottom: 2, trailing: 18))
  }

  private func openOrSelect(_ meeting: Meeting) {
    if isSelectionMode {
      toggleSelection(meeting.id)
    } else {
      model.libraryPath.append(.meeting(meeting.id))
    }
  }

  private var selectionBar: some View {
    HStack(spacing: 8) {
      selectionAction("共有", systemImage: "square.and.arrow.up") { shareSelected() }
      selectionAction(
        "チーム",
        systemImage: model.hasTeamPlan ? "person.3.fill" : "person.3"
      ) {
        shareSelectedWithTeam()
      }
      selectionAction("移動", systemImage: "folder") { isBulkSpacePickerPresented = true }
      selectionAction("削除", systemImage: "trash", isDestructive: true) {
        isBulkDeleteConfirmPresented = true
      }
    }
    .padding(6)
    .memoraGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    .padding(.horizontal, 12)
    .padding(.bottom, 8)
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }

  private func selectionAction(
    _ title: String,
    systemImage: String,
    isDestructive: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: systemImage)
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

  private var projectsPage: some View {
    let spaces = matchingSpaces

    return ScrollView {
      LazyVStack(alignment: .leading, spacing: 22) {
        sectionSwitch

        if model.isRecording {
          ActiveRecordingStrip()
        }

        if spaces.isEmpty {
          Group {
            if query.isEmpty {
              createProjectPrompt
            } else {
              ContentUnavailableView.search(text: query)
            }
          }
          .padding(.top, 40)
        } else {
          projectsGrid(spaces)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 18)
      .padding(.top, 8)
      .padding(.bottom, 32)
    }
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    .refreshable { await model.refresh() }
    .hideBottomBarOnScroll(RootTab.files.rawValue)
  }

  private func projectsGrid(_ spaces: [MemoraSpace]) -> some View {
    LazyVGrid(
      columns: [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
      ],
      spacing: 22
    ) {
      ForEach(spaces) { space in
        NavigationLink(value: LibraryRoute.space(space.id)) {
          ProjectFolderTile(
            space: space,
            meetingCount: model.spaceAggregates[space.id]?.meetingCount ?? 0,
            symbols: model.spaceAggregates[space.id]?.icons ?? []
          )
          .matchedTransitionSource(id: space.id, in: heroNamespace)
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var createProjectPrompt: some View {
    Button {
      model.isFileCreationPresented = true
    } label: {
      HStack(spacing: 10) {
        Image(systemName: "plus")
        Text("プロジェクトを作成")
        Spacer()
      }
      .font(.subheadline.weight(.medium))
      .foregroundStyle(.primary)
      .padding(14)
      .frame(maxWidth: .infinity)
      .memoraCard(radius: 18)
    }
    .buttonStyle(.plain)
  }

  private var emptyFilesPrompt: some View {
    VStack(spacing: 16) {
      Image(systemName: "waveform")
        .font(.title2)
        .foregroundStyle(.secondary)

      VStack(spacing: 6) {
        Text("まだファイルがありません")
          .font(.headline)

        Text("録音するか、音声ファイルを読み込むとここに整理されます。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      Button("録音または読み込み") {
        model.isCaptureSourcePresented = true
      }
      .font(.headline)
      .foregroundStyle(Color(uiColor: .systemBackground))
      .frame(maxWidth: .infinity, minHeight: 52)
      .background(Color(uiColor: .label), in: Capsule())
      .contentShape(Capsule())
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity)
    .padding(20)
    .memoraCard()
  }

  // MARK: - Selection

  private func beginSelection(with id: UUID) {
    isSelectionMode = true
    selectedMeetingIDs.insert(id)
  }

  private func beginSelectionMode() {
    withAnimation(reduceMotion ? nil : MemoraMotion.control) {
      isSelectionMode = true
    }
  }

  private func toggleSelection(_ id: UUID) {
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
    var result = model.meetings.filter { statusFilter.matches($0.status) }
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
    return date.formatted(.dateTime.year().month())
  }

  private var matchingSpaces: [MemoraSpace] {
    query.isEmpty ? model.spaces : model.spaces.filter {
      $0.name.localizedCaseInsensitiveContains(query)
    }
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
