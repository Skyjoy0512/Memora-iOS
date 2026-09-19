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
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 26) {
            if model.isRecording {
              ActiveRecordingStrip()
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if query.isEmpty {
              projectsSection
              filesSection
            } else {
              searchResults
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 18)
          .padding(.bottom, 32)
          .animation(reduceMotion ? nil : MemoraMotion.screen, value: model.isRecording)
        }
        // The sidebar's library rows stay useful as jump targets now that both
        // sections share one screen.
        .onChange(of: model.fileSection) { _, section in
          withAnimation(reduceMotion ? nil : MemoraMotion.screen) {
            proxy.scrollTo(section, anchor: .top)
          }
        }
      }
      .hideBottomBarOnScroll()
      .background(Color(uiColor: .systemBackground))
      .navigationTitle("ファイル")
      .searchable(
        text: $query,
        placement: .navigationBarDrawer(displayMode: .always),
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

  private var projectsSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeader("プロジェクト")

      if matchingSpaces.isEmpty {
        createProjectPrompt
      } else {
        projectsGrid(matchingSpaces)
      }
    }
    .id(FileSection.projects)
  }

  private var filesSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeader("ファイル")

      if matchingMeetings.isEmpty {
        emptyFilesPrompt
      } else {
        filesList(matchingMeetings)
      }
    }
    .id(FileSection.meetingFiles)
  }

  @ViewBuilder
  private var searchResults: some View {
    if matchingSpaces.isEmpty && matchingMeetings.isEmpty {
      ContentUnavailableView.search(text: query)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    } else {
      VStack(alignment: .leading, spacing: 26) {
        sectionHeader("検索結果")

        if !matchingSpaces.isEmpty {
          projectsGrid(matchingSpaces)
        }

        if !matchingMeetings.isEmpty {
          filesList(matchingMeetings)
        }
      }
    }
  }

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.title2.bold())
      .memoraTextReveal()
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

  private func filesList(_ meetings: [Meeting]) -> some View {
    LazyVStack(spacing: 16) {
      ForEach(meetings) { meeting in
        NavigationLink(value: LibraryRoute.meeting(meeting.id)) {
          MeetingCard(meeting: meeting)
            .matchedTransitionSource(id: meeting.id, in: heroNamespace)
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
      .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

  private var matchingMeetings: [Meeting] {
    let result = query.isEmpty ? model.meetings : model.meetings.filter(matchesQuery)
    return Array(result.prefix(24))
  }

  private var matchingSpaces: [MemoraSpace] {
    query.isEmpty ? model.spaces : model.spaces.filter {
      $0.name.localizedCaseInsensitiveContains(query)
    }
  }

  private func matchesQuery(_ meeting: Meeting) -> Bool {
    meeting.title.localizedCaseInsensitiveContains(query)
      || meeting.summary.localizedCaseInsensitiveContains(query)
      || meeting.transcript.contains { $0.text.localizedCaseInsensitiveContains(query) }
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

private struct ActiveRecordingStrip: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    Button {
      model.isCapturePresented = true
    } label: {
      HStack(spacing: 12) {
        Image(systemName: model.isRecordingPaused ? "pause.fill" : "waveform")
          .foregroundStyle(.red)
          .symbolEffect(.variableColor.iterative, isActive: !model.isRecordingPaused)

        VStack(alignment: .leading, spacing: 2) {
          Text(model.isRecordingPaused ? "録音を一時停止中" : "録音を続けています")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          Text("画面を閉じても安全に保存中")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Text(MemoraFormat.duration(model.recordingElapsed))
          .font(.subheadline.monospacedDigit().weight(.medium))
          .foregroundStyle(.primary)
      }
      .padding(14)
      .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityHint("録音画面を表示します")
  }
}
