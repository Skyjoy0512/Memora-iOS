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

          if model.meetings.isEmpty {
            ContentUnavailableView {
              Label("まだ会話がありません", systemImage: "waveform")
            } description: {
              Text("右下の＋から録音するか、音声を読み込んでください。")
            } actions: {
              Button("新しく追加", systemImage: "plus") {
                model.isCaptureSourcePresented = true
              }
              .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
          } else {
            if query.isEmpty, !model.spaces.isEmpty {
              projectsSection
            }
            if !matchingLifeLogEntries.isEmpty {
              lifeLogSection
            }
            if query.isEmpty || !recentMeetings.isEmpty {
              recentSection
            } else if matchingLifeLogEntries.isEmpty {
              ContentUnavailableView.search(text: query)
                .frame(maxWidth: .infinity)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 32)
        .animation(reduceMotion ? nil : MemoraMotion.screen, value: model.isRecording)
        .animation(reduceMotion ? nil : MemoraMotion.screen, value: model.meetings)
      }
      .background(Color(uiColor: .systemBackground))
      .navigationTitle("ホーム")
      .searchable(
        text: $query,
        placement: .navigationBarDrawer(displayMode: .always),
        prompt: "会話とライフログを検索"
      )
      .navigationDestination(for: LibraryRoute.self) { route in
        switch route {
        case .meeting(let id):
          MeetingDetailView(meetingID: id)
        case .transcript(let id):
          TranscriptView(meetingID: id)
        case .space(let id):
          SpaceDetailView(spaceID: id)
        case .allMeetings:
          AllMeetingsView()
        case .settings:
          SettingsView()
        case .stateGallery:
          StateGalleryView()
        }
      }
    }
  }

  private var projectsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("プロジェクト")
        .font(.headline)
        .memoraTextReveal()

      ScrollView(.horizontal) {
        HStack(spacing: 10) {
          ForEach(model.spaces) { space in
            NavigationLink(value: LibraryRoute.space(space.id)) {
              HStack(spacing: 10) {
                MemoraIconBadge(symbol: space.symbol, size: 30)

                VStack(alignment: .leading, spacing: 2) {
                  Text(space.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                  Text("\(meetingCount(for: space.id))件の会話")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              .padding(.vertical, 8)
              .padding(.horizontal, 10)
              .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
          }
        }
      }
      .scrollIndicators(.hidden)
    }
  }

  private var recentSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(query.isEmpty ? "最近の会話" : "検索結果")
          .font(.title2.bold())
          .memoraTextReveal(delay: 0.04)
        Spacer()
        if query.isEmpty {
          NavigationLink("すべて表示", value: LibraryRoute.allMeetings)
            .font(.subheadline)
        }
      }

      if recentMeetings.isEmpty {
        ContentUnavailableView.search(text: query)
          .frame(maxWidth: .infinity)
      } else {
        LazyVStack(spacing: 0) {
          ForEach(recentMeetings) { meeting in
            NavigationLink(value: LibraryRoute.meeting(meeting.id)) {
              MeetingRow(meeting: meeting)
            }
            .buttonStyle(.plain)

            if meeting.id != recentMeetings.last?.id {
              Divider()
                .padding(.leading, 52)
            }
          }
        }
      }
    }
  }

  private var recentMeetings: [Meeting] {
    let meetings = query.isEmpty ? model.meetings : model.meetings.filter(matchesQuery)
    return Array(meetings.prefix(12))
  }

  private var matchingLifeLogEntries: [LifeLogEntry] {
    let entries = query.isEmpty
      ? model.lifeLogEntries
      : model.lifeLogEntries.filter {
        $0.title.localizedCaseInsensitiveContains(query)
          || $0.summary.localizedCaseInsensitiveContains(query)
          || $0.source.label.localizedCaseInsensitiveContains(query)
      }
    return Array(entries.sorted { $0.createdAt > $1.createdAt }.prefix(4))
  }

  private var lifeLogSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("ライフログ")
          .font(.title2.bold())
          .memoraTextReveal(delay: 0.02)
        Spacer()
        Text("今日")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      VStack(spacing: 0) {
        ForEach(matchingLifeLogEntries) { entry in
          if let meetingID = entry.meetingID {
            NavigationLink(value: LibraryRoute.meeting(meetingID)) {
              LifeLogRow(entry: entry)
            }
            .buttonStyle(.plain)
          } else {
            LifeLogRow(entry: entry)
          }

          if entry.id != matchingLifeLogEntries.last?.id {
            Divider()
              .padding(.leading, 58)
          }
        }
      }
      .padding(.horizontal, 14)
      .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

private struct LifeLogRow: View {
  var entry: LifeLogEntry

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 46, alignment: .leading)

      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(entry.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
          Spacer(minLength: 8)
          Text(entry.source.label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
        Text(entry.summary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.vertical, 12)
    .contentShape(Rectangle())
  }
}

private struct ActiveRecordingStrip: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    Button {
      model.isCapturePresented = true
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "waveform")
          .foregroundStyle(.red)
          .symbolEffect(.variableColor.iterative)

        VStack(alignment: .leading, spacing: 2) {
          Text("録音を続けています")
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
