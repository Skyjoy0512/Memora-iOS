import SwiftUI

struct LibraryView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var query = ""

  var body: some View {
    @Bindable var model = model

    NavigationStack(path: $model.libraryPath) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 22) {
          if model.isRecording {
            ActiveRecordingStrip()
              .transition(.opacity.combined(with: .move(edge: .top)))
          }

          switch model.fileSection {
          case .meetingFiles:
            meetingFilesContent
          case .projects:
            projectsContent
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 32)
        .animation(reduceMotion ? nil : MemoraMotion.screen, value: model.isRecording)
        .animation(reduceMotion ? nil : MemoraMotion.screen, value: model.fileSection)
      }
      .compactBottomBarOnScroll()
      .background(Color(uiColor: .systemBackground))
      .navigationTitle("ファイル")
      .searchable(
        text: $query,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: model.fileSection == .meetingFiles ? "ファイルを検索" : "プロジェクトを検索"
      )
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("ファイルメニュー", systemImage: "line.3.horizontal") {
            withAnimation(reduceMotion ? nil : MemoraMotion.screen) {
              model.isFileSidebarPresented = true
            }
          }
          .labelStyle(.iconOnly)
        }
      }
      .navigationDestination(for: LibraryRoute.self) { route in
        switch route {
        case .meeting(let id): MeetingDetailView(meetingID: id)
        case .transcript(let id): TranscriptView(meetingID: id)
        case .space(let id): SpaceDetailView(spaceID: id)
        case .allMeetings: AllMeetingsView()
        case .settings: SettingsView()
        case .stateGallery: StateGalleryView()
        }
      }
    }
  }

  @ViewBuilder
  private var meetingFilesContent: some View {
    if matchingMeetings.isEmpty {
      if query.isEmpty {
        ContentUnavailableView {
          Label("まだ議事録がありません", systemImage: "doc.text")
        } description: {
          Text("録音するか、音声ファイルを読み込むとここに整理されます。")
        } actions: {
          Button("議事録を追加", systemImage: "plus") {
            model.isCaptureSourcePresented = true
          }
          .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
      } else {
        ContentUnavailableView.search(text: query)
          .frame(maxWidth: .infinity)
      }
    } else {
      VStack(alignment: .leading, spacing: 10) {
        Text(query.isEmpty ? "ファイル" : "検索結果")
          .font(.title2.bold())
          .memoraTextReveal()

        LazyVStack(spacing: 0) {
          ForEach(matchingMeetings) { meeting in
            NavigationLink(value: LibraryRoute.meeting(meeting.id)) {
              MeetingRow(meeting: meeting)
            }
            .buttonStyle(.plain)

            if meeting.id != matchingMeetings.last?.id {
              Divider().padding(.leading, 52)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private var projectsContent: some View {
    if matchingSpaces.isEmpty {
      if query.isEmpty {
        ContentUnavailableView {
          Label("プロジェクトを作りましょう", systemImage: "folder")
        } description: {
          Text("関連する議事録をひとつの場所にまとめられます。")
        } actions: {
          Button("プロジェクトを追加", systemImage: "plus") {
            model.isFileCreationPresented = true
          }
          .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
      } else {
        ContentUnavailableView.search(text: query)
          .frame(maxWidth: .infinity)
      }
    } else {
      VStack(alignment: .leading, spacing: 10) {
        Text(query.isEmpty ? "プロジェクト" : "検索結果")
          .font(.title2.bold())
          .memoraTextReveal()

        LazyVStack(spacing: 10) {
          ForEach(matchingSpaces) { space in
            NavigationLink(value: LibraryRoute.space(space.id)) {
              HStack(spacing: 14) {
                MemoraIconBadge(symbol: space.symbol, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                  Text(space.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                  Text("\(meetingCount(for: space.id))件の議事録")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                  .font(.caption.bold())
                  .foregroundStyle(.tertiary)
              }
              .padding(14)
              .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
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
