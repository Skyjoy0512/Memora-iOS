import EventKit
import SwiftUI

struct LibraryView: View {
  @State private var matchingSourceIDs: Set<UUID> = []
  @State private var completedSourceRequest: SourceSearchRequest?
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.scenePhase) private var scenePhase
  @State private var query = ""
  @State private var isSearching = false
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
  @AppStorage("memora.projects.listOrder") private var projectOrder = ProjectListOrder.name
  @AppStorage("memora.projects.recentFirst") private var showsRecentProjects = false
  @State private var projectFilter = ProjectListFilter.all
  @State private var renameTarget: Meeting?
  @State private var moveTarget: Meeting?
  @State private var shareTarget: Meeting?
  @Namespace private var zoomNamespace
  var onOpenSidebar: () -> Void

  private var librarySectionPicker: some View {
    @Bindable var model = model
    return MemoraTextTabBar(items: LibrarySection.allCases, selection: $model.librarySection,
      horizontalPadding: typeSize.isAccessibilitySize ? MemoraSpacing.sm : MemoraSpacing.screen) { $0.title }
        .accessibilityLabel("ライブラリの表示")
  }

  private var fileViewOptionsMenu: some View {
    Menu {
      fileViewOptions
    } label: {
      Image(icon: .line3HorizontalDecrease, size: MemoraIconMetrics.glyph)
        .foregroundStyle(MemoraPalette.textPrimary)
        .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .tint(MemoraPalette.textPrimary)
    .accessibilityLabel("表示と並べ替え")
  }

  @ViewBuilder
  private var fileViewOptions: some View {
    if typeSize.isAccessibilitySize {
      Button("ファイルを検索", icon: .magnifyingglass) { isSearching = true }
      Divider()
    }
    Picker("表示", selection: $layout) {
      ForEach(FileListLayout.allCases) {
        Text($0 == .card ? "プレビュー付き" : "コンパクト").tag($0)
      }
    }
    .pickerStyle(.menu)
    Picker("並べ替え", selection: $sort) {
      ForEach(FileListSort.allCases) { Text($0.label).tag($0) }
    }
    .pickerStyle(.menu)
    Picker("絞り込み", selection: $statusFilter) {
      ForEach(FileListFilter.allCases) { Text($0.label).tag($0) }
    }
    .pickerStyle(.menu)
    Divider()
    Button("選択", icon: .checkmarkCircle) { beginSelectionMode() }
  }

  private var projectViewOptionsMenu: some View {
    Menu {
      Button("プロジェクトを作成", icon: .folder) { model.isFileCreationPresented = true }
        .disabled(model.isRestoring || model.isStoreProtected)
      if typeSize.isAccessibilitySize {
        Button("プロジェクトを検索", icon: .magnifyingglass) { isSearching = true }
      }
      Divider()
      Picker("表示", selection: $projectFilter) {
        ForEach(ProjectListFilter.allCases) { Text($0.title).tag($0) }
      }
      if projectFilter != .shared {
        Picker("並べ替え", selection: $projectOrder) {
          ForEach(ProjectListOrder.allCases) { Text($0.title).tag($0) }
        }
        Toggle("最近開いたものを先に", isOn: $showsRecentProjects)
      }
    } label: {
      Image(icon: .ellipsis, size: MemoraIconMetrics.glyph)
        .foregroundStyle(MemoraPalette.textPrimary)
        .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .tint(MemoraPalette.textPrimary)
    .accessibilityLabel("プロジェクトの表示オプション")
    .accessibilityValue(projectOrder.title)
  }

  var body: some View {
    @Bindable var model = model

    NavigationStack(path: $model.libraryPath) {
      VStack(spacing: 0) {
        if !isSearching {
          HStack(spacing: 0) {
            librarySectionPicker
            if !typeSize.isAccessibilitySize {
              MemoraIconButton(model.librarySection == .files ? "ファイルを検索" : "プロジェクトを検索",
                icon: .magnifyingglass) { isSearching = true }
            }
            if model.librarySection == .files {
              fileViewOptionsMenu
            } else {
              projectViewOptionsMenu
            }
          }
          .padding(.top, MemoraSpacing.sm)
          .padding(.trailing, MemoraSpacing.md)
          .padding(.bottom, MemoraSpacing.sm)
          // Keep the list at the same origin when its native swipe commits.
          .disabled(isSelectionMode)
        }
        Group {
          if model.librarySection == .files {
            filesPage
          } else {
            ProjectsView(query: $query, isSearching: isSearching, zoomNamespace: zoomNamespace,
              order: projectOrder, recentFirst: showsRecentProjects, filter: $projectFilter)
          }
        }
      }
      .memoraAppear()
      .background(MemoraPalette.background)
      .navigationTitle(isSelectionMode ? "\(selectedMeetingIDs.count)件を選択" : "")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarSearch(text: $query, isPresented: $isSearching, prompt: model.librarySection.searchPrompt,
        selection: isSelectionMode ? (selectedMeetingIDs.count, endSelection) : nil)
      .task(id: sourceSearchRequest) { [request = sourceSearchRequest] in
        guard CollectionSearch.hasQuery(request.query), request.hasSources else { return }
        guard completedSourceRequest != request else { return }
        let matches = await model.matchingSourceIDs(query: request.query)
        guard !Task.isCancelled, sourceSearchRequest == request else { return }
        matchingSourceIDs = matches
        completedSourceRequest = request
      }
      .toolbar {
        if isSelectionMode && !isSearching {
          ToolbarItem(placement: .principal) {
            Text("\(selectedMeetingIDs.count)件を選択")
              .font(.headline)
              .lineLimit(1)
          }
        }

        if isSelectionMode {
          ToolbarItem(placement: .topBarLeading) {
            ToolbarIconButton("キャンセル", icon: .xmark) { endSelection() }
          }
        } else if model.libraryPath.isEmpty {
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
            RecorderStatusToolbarButton(compactWhenDisconnected: true)
          }

        }

      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if isSelectionMode {
          selectionBar
        }
      }
      .onAppear { model.isFileSelectionActive = isSelectionMode }
      .onChange(of: isSearching) { wasSearching, searching in
        if wasSearching, !searching, isSelectionMode { endSelection() }
      }
      .onChange(of: model.meetingTitles) { _, titles in
        guard isSelectionMode else { return }
        selectedMeetingIDs.formIntersection(titles.keys)
      }
      .navigationDestination(for: LibraryRoute.self) { route in
        switch route {
        case .meeting(let id):
          if reduceMotion {
            MeetingDetailView(meetingID: id).memoraAppear()
          } else {
            MeetingDetailView(meetingID: id).memoraAppear()
              .navigationTransition(.zoom(sourceID: id, in: zoomNamespace))
          }
        case .projectSource(let id):
          if reduceMotion {
            LibraryDestinationView(route: route)
          } else {
            LibraryDestinationView(route: route)
              .navigationTransition(.zoom(sourceID: id, in: zoomNamespace))
          }
        case .space(let id):
          if reduceMotion {
            LibraryDestinationView(route: route)
          } else {
            LibraryDestinationView(route: route, zoomNamespace: zoomNamespace)
              .navigationTransition(.zoom(sourceID: id, in: zoomNamespace))
          }
        case .sharedRecord(let id):
          if reduceMotion {
            LibraryDestinationView(route: route)
          } else {
            LibraryDestinationView(route: route)
              .navigationTransition(.zoom(sourceID: id, in: zoomNamespace))
          }
        case .sharedProject(let id):
          if reduceMotion {
            LibraryDestinationView(route: route)
          } else {
            LibraryDestinationView(route: route)
              .navigationTransition(.zoom(sourceID: id, in: zoomNamespace))
          }
        default:
          LibraryDestinationView(route: route, zoomNamespace: reduceMotion ? nil : zoomNamespace)
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
        Button("閉じる", role: .cancel) {}
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
      VStack(spacing: MemoraSpacing.xl) {
        UpcomingEventsRow(
          meetings: upcoming.meetings,
          onRecordInPerson: { meeting, context in
            Task { await model.startCapture(event: meeting, context: context) }
          },
          onRecordOnline: recordOnline
        )
        Divider()
          .padding(.horizontal, MemoraSpacing.screen)
      }
      .disabled(isSelectionMode)
      .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
    }

    if model.isRecording {
      ActiveRecordingStrip()
        .disabled(isSelectionMode)
        .listRowInsets(EdgeInsets(top: 0, leading: MemoraSpacing.screen, bottom: MemoraSpacing.md, trailing: MemoraSpacing.screen))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
  }

  private var sourceSearchRequest: SourceSearchRequest {
    SourceSearchRequest.make(query: query, sources: model.projectSources,
      workspaceGeneration: model.aiWorkspaceGeneration)
  }

  private var filesPage: some View {
    // Searching replaces the list with its results; before anything is typed
    // there is nothing to match, so the files stay out of the way.
    let isAwaitingQuery = isSearching && !CollectionSearch.hasQuery(query)
    let sections = isAwaitingQuery ? [] : fileSections
    let count = sections.reduce(0) { $0 + $1.meetings.count }
    let sharedRecords = model.cloudSharing.sharedRecords
    let hasCompletedSourceSearch = completedSourceRequest == sourceSearchRequest
    let savedSources = isAwaitingQuery || statusFilter != .all ? [] : model.projectSources.filter {
      CollectionSearch.matches(query, fields: [$0.title, $0.summary ?? ""]) ||
        (hasCompletedSourceSearch && matchingSourceIDs.contains($0.id))
    }
    let resultCount = count + savedSources.count
    let isSearchingSourceText = CollectionSearch.hasQuery(query)
      && statusFilter == .all && !model.projectSources.isEmpty && !hasCompletedSourceSearch
    let hasSharedRecords = !isSearching && statusFilter == .all && !sharedRecords.isEmpty
    let hasSavedSources = !savedSources.isEmpty && !isAwaitingQuery

    return List {
      // Keep surrounding rows in place while the native swipe closes.
      if !isSearching {
        listHeaderRows

        if model.hasSampleContent {
          SampleNoticeRow()
            .disabled(isSelectionMode)
            .listRowInsets(EdgeInsets(top: 0, leading: MemoraSpacing.screen, bottom: MemoraSpacing.md, trailing: MemoraSpacing.screen))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
      }

      if statusFilter != .all {
        filterChipRow.disabled(isSelectionMode)
      }

      if sections.isEmpty && !hasSavedSources && !hasSharedRecords {
        Group {
          if isAwaitingQuery {
            CollectionSearchState(title: "ファイルを検索",
              message: "記録や参考資料のタイトル・本文から探せます。", isEmbedded: true)
          } else if isSearchingSourceText {
            ProgressView("参考資料の本文を検索しています…")
              .padding(.vertical, MemoraSpacing.lg)
          } else if CollectionSearch.hasQuery(query) {
            CollectionSearchState(title: "見つかりませんでした",
              message: "別の語句を入力してください。",
              clear: { query = "" }, clearTitle: "検索をやり直す", isEmbedded: true)
          } else if statusFilter != .all {
            filteredEmpty
          } else {
            emptyFilesPrompt
          }
        }
        .frame(maxWidth: .infinity)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(
          top: isSearching ? 0 : MemoraSpacing.section,
          leading: 0,
          bottom: isSearching ? 0 : MemoraSpacing.section,
          trailing: 0
        ))
      } else {
        // Grouped by date, each heading inside the list so it scrolls away.
        ForEach(sections) { section in
          Section {
            ForEach(section.meetings) { meeting in
              meetingRow(meeting)
                .matchedTransitionSource(id: meeting.id, in: zoomNamespace)
            }
          } header: {
            Text(section.title)
              .font(MemoraTypography.secondary.weight(.medium))
              .foregroundStyle(MemoraPalette.textSecondary)
              .textCase(nil)
              .listRowInsets(EdgeInsets(top: 0, leading: ProjectLayout.horizontalInset,
                bottom: 0, trailing: ProjectLayout.horizontalInset))
          }
        }

        // Teammates' records sit in their own section, apart from this person's
        // files, and only while nothing narrows the list.
        if hasSharedRecords {
          Section {
            ForEach(sharedRecords) { record in
              sharedRow(record).disabled(isSelectionMode)
            }
          } header: {
            Label("チームから共有", icon: .person2)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.secondary)
              .textCase(nil)
          }
        }

        if hasSavedSources {
          Section {
            ForEach(savedSources) { source in
              NavigationLink(value: LibraryRoute.projectSource(source.id)) {
                ProjectSourceRow(source: source)
                  .matchedTransitionSource(id: source.id, in: zoomNamespace)
              }
                .disabled(isSelectionMode)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: MemoraSpacing.sm, leading: ProjectLayout.horizontalInset,
                  bottom: MemoraSpacing.sm, trailing: ProjectLayout.horizontalInset))
            }
          } header: {
            Text("参考資料").font(.subheadline.weight(.semibold)).textCase(nil)
          }
        }

        if CollectionSearch.hasQuery(query) {
          Group {
            if isSearchingSourceText {
              ProgressView("参考資料の本文を検索しています…")
            } else {
              Text("\(resultCount)件")
                .accessibilityLabel("\(resultCount)件の検索結果")
            }
          }
          .font(MemoraTypography.secondary)
          .foregroundStyle(.secondary)
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
        }
      }
    }
    // The selection footer changes safe areas while native swipe is settling.
    .transaction(value: isSelectionMode) { transaction in
      transaction.animation = nil
      transaction.disablesAnimations = true
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
    .listRowInsets(EdgeInsets(top: 0, leading: MemoraSpacing.screen, bottom: MemoraSpacing.sm, trailing: MemoraSpacing.screen))
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
  /// made. Swiping from the leading edge starts with this record selected.
  private func meetingRow(_ meeting: Meeting) -> some View {
    Button {
      openOrSelect(meeting)
    } label: {
      LibraryRecordRow(meeting: meeting, showsPreview: layout == .card,
        reservesSelectionSpace: true,
        isSelecting: isSelectionMode, isSelected: selectedMeetingIDs.contains(meeting.id))
    }
    .buttonStyle(.plain)
    .listRowInsets(recordRowInsets)
    .listRowSeparator(layout == .card ? .visible : .hidden, edges: .bottom)
    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    .listRowBackground(Color.clear)
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      if !isSelectionMode {
        Button(role: .destructive) {
          withAnimation(reduceMotion ? nil : MemoraMotion.screen) {
            model.deleteMeeting(meeting.id)
          }
        } label: {
          Label("削除", icon: .trash)
        }
      }
    }
    .swipeActions(edge: .leading) {
      if !isSelectionMode {
        Button {
          beginSelection(with: meeting.id)
        } label: {
          Label("選択", icon: .checkmarkCircle)
        }
        .tint(MemoraPalette.textPrimary)
      }
    }
    .contextMenu {
      if isSelectionMode {
        Button(selectedMeetingIDs.contains(meeting.id) ? "選択を解除" : "選択", icon: .checkmarkCircle) {
          toggleSelection(meeting.id)
        }
      } else {
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
  }

  private var recordRowInsets: EdgeInsets {
    let vertical = layout == .card ? MemoraSpacing.sm : MemoraSpacing.xs
    return EdgeInsets(top: vertical, leading: ProjectLayout.horizontalInset,
      bottom: vertical, trailing: ProjectLayout.horizontalInset)
  }

  /// A teammate's record: opens read-only, with none of the actions that
  /// would change it.
  private func sharedRow(_ record: SharedRecord) -> some View {
    Button {
      model.libraryPath.append(.sharedRecord(record.id))
    } label: {
      LibraryRecordRow(meeting: record.meeting, showsPreview: layout == .card,
        sharedBy: record.ownerName)
        .matchedTransitionSource(id: record.id, in: zoomNamespace)
    }
    .buttonStyle(.plain)
    .listRowInsets(recordRowInsets)
    .listRowSeparator(layout == .card ? .visible : .hidden, edges: .bottom)
    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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
    let columns = Array(repeating: GridItem(.flexible(), spacing: MemoraSpacing.sm),
                        count: typeSize.isAccessibilitySize ? 2 : 4)
    return LazyVGrid(columns: columns, spacing: MemoraSpacing.sm) {
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
    .memoraGlass(in: Capsule())
    .padding(.horizontal, MemoraSpacing.screen)
    .padding(.vertical, MemoraSpacing.sm)
    .background(MemoraPalette.background, ignoresSafeAreaEdges: .bottom)
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
      VStack(spacing: MemoraSpacing.xs) {
        Image(icon: icon, size: 20)
        Text(title)
          .font(.caption2.weight(.medium))
      }
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, minHeight: 48)
      .foregroundStyle(isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(selectedMeetingIDs.isEmpty)
    .accessibilityLabel(title)
    .accessibilityValue("\(selectedMeetingIDs.count)件を選択")
  }

  private var emptyFilesPrompt: some View {
    MemoraEmptyState(
      icon: .waveform,
      title: "ファイルはまだありません",
      message: "録音した会話や取り込んだ資料がここに並びます。",
      actionTitle: "録音する",
      actionIcon: .waveform
    ) {
      Task { await model.performCaptureMenuAction(.recording, projectID: model.visibleProjectID) }
    }
    .padding(.vertical, MemoraSpacing.xl)
  }

  // MARK: - Selection

  private func beginSelection(with id: UUID) {
    InteractionFeedback.shared.send(.selection)
    beginSelectionMode(selecting: id)
  }

  private func beginSelectionMode(selecting id: UUID? = nil) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      // Preserve the search and its inset while the native swipe settles.
      isSelectionMode = true
      selectedMeetingIDs = id.map { [$0] } ?? []
      model.isFileSelectionActive = true
    }
  }

  private func toggleSelection(_ id: UUID) {
    InteractionFeedback.shared.send(.selection)
    if selectedMeetingIDs.contains(id) {
      selectedMeetingIDs.remove(id)
    } else {
      selectedMeetingIDs.insert(id)
    }
  }

  private func endSelection() {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      isSelectionMode = false
      selectedMeetingIDs = []
      model.isFileSelectionActive = false
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
    if CollectionSearch.hasQuery(query) {
      result = result.filter(matchesQuery)
    }
    return sort.ordered(result)
  }

  /// The meetings grouped into date sections, in the order the sort puts them.
  private var fileSections: [FileDateSection] {
    let meetings = matchingMeetings
    if sort == .longest {
      return meetings.isEmpty ? [] : [FileDateSection(id: "duration", title: "録音の長さ順", meetings: meetings)]
    }
    let calendar = Calendar.current
    var sections: [FileDateSection] = []
    for meeting in meetings {
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
    CollectionSearch.matches(query, fields: [model.searchText(for: meeting)])
  }

}

/// A date heading and the meetings under it, for the files list.
private struct FileDateSection: Identifiable {
  var id: String
  var title: String
  var meetings: [Meeting]
}
