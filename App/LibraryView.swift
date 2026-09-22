import SwiftUI

struct LibraryView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

  /// The section switch and the live recording strip, as the first rows of the
  /// list so they scroll away with it.
  @ViewBuilder
  private var listHeaderRows: some View {
    sectionSwitch
      .listRowInsets(EdgeInsets(top: 8, leading: 18, bottom: 10, trailing: 18))
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)

    if model.isRecording {
      ActiveRecordingStrip()
        .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 10, trailing: 18))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
  }

  private var filesPage: some View {
    let meetings = matchingMeetings

    return List {
      listHeaderRows

      if meetings.isEmpty {
        Group {
          if query.isEmpty {
            emptyFilesPrompt
          } else {
            ContentUnavailableView.search(text: query)
          }
        }
        .frame(maxWidth: .infinity)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 48, leading: 18, bottom: 48, trailing: 18))
      } else {
        ForEach(meetings) { meeting in
          meetingRow(meeting)
        }

        if query.isEmpty {
          NavigationLink(value: LibraryRoute.allMeetings) {
            Label("すべての会話を一覧で見る", systemImage: "list.bullet")
              .font(.subheadline.weight(.medium))
          }
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
        } else {
          Text("\(meetings.count)件")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .accessibilityLabel("\(meetings.count)件の検索結果")
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .contentMargins(.bottom, model.bottomContentClearance, for: .scrollContent)
    .hideBottomBarOnScroll(RootTab.files.rawValue)
  }

  /// One file card. Tapping opens it, or selects it while a selection is being
  /// made. A left swipe starts selecting with this record already chosen.
  private func meetingRow(_ meeting: Meeting) -> some View {
    Button {
      if isSelectionMode {
        toggleSelection(meeting.id)
      } else {
        model.libraryPath.append(.meeting(meeting.id))
      }
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
    ContentUnavailableView {
      Label("まだファイルがありません", systemImage: "doc.text")
    } description: {
      Text("録音するか、音声ファイルを読み込むとここに整理されます。")
    } actions: {
      Button("議事録を追加", systemImage: "plus") {
        model.isCaptureSourcePresented = true
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
  }

  // MARK: - Selection

  private func beginSelection(with id: UUID) {
    isSelectionMode = true
    selectedMeetingIDs.insert(id)
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

  /// The normal list stays short, but a search shows every match and reports
  /// how many there are, so nothing is hidden behind a cap.
  private var matchingMeetings: [Meeting] {
    if query.isEmpty {
      return Array(model.meetings.prefix(24))
    }
    return model.meetings.filter(matchesQuery)
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
