import SwiftUI

struct LibraryView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var query = ""
  @Namespace private var heroNamespace
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
      .navigationTitle("ファイル")
      .searchable(
        text: $query,
        placement: .navigationBarDrawer(displayMode: .automatic),
        prompt: "ファイルやプロジェクトを検索"
      )
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("メニュー", systemImage: "line.3.horizontal") {
            onOpenSidebar()
          }
          .labelStyle(.iconOnly)
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
          Button {
            model.libraryPath.append(.meeting(meeting.id))
          } label: {
            MeetingCard(meeting: meeting)
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
            ShareLink(item: MeetingShareText.make(meeting: meeting, tasks: model.tasks)) {
              Label("共有", systemImage: "square.and.arrow.up")
            }
            .tint(.blue)
          }
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
    .hideBottomBarOnScroll()
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
    .hideBottomBarOnScroll()
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
            meetingCount: meetingCount(for: space.id),
            symbols: recentSymbols(for: space.id)
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

  private func meetingCount(for spaceID: UUID) -> Int {
    model.meetings.filter { $0.spaceID == spaceID }.count
  }

  /// Up to four icons for the folder preview, newest first.
  private func recentSymbols(for spaceID: UUID) -> [String] {
    model.meetings
      .filter { $0.spaceID == spaceID }
      .sorted { $0.createdAt > $1.createdAt }
      .prefix(4)
      .map { $0.source == .recording ? "waveform" : "square.and.arrow.down" }
  }
}
