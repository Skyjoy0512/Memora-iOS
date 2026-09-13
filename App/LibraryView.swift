import SwiftUI

struct LibraryView: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    @Bindable var model = model

    NavigationStack(path: $model.libraryPath) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 28) {
          CaptureHeroView()

          if model.isRecording {
            ActiveRecordingStrip()
          }

          if model.meetings.isEmpty {
            ContentUnavailableView {
              Label("まだ会話がありません", systemImage: "waveform")
            } description: {
              Text("録音するか音声を読み込むと、ここに要点とタスクが並びます。")
            } actions: {
              Button("録音を始める", systemImage: "record.circle") {
                Task {
                  await model.startCapture()
                }
              }
              .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
          } else {
            if !model.spaces.isEmpty {
              spacesSection
            }
            recentSection
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 32)
      }
      .background(Color(uiColor: .systemBackground))
      .navigationTitle("Memora")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("設定", systemImage: "gearshape") {
            model.isSettingsPresented = true
          }
        }
      }
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

  private var spacesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("スペース")
        .font(.title2.bold())

      ScrollView(.horizontal) {
        HStack(spacing: 10) {
          ForEach(model.spaces) { space in
            NavigationLink(value: LibraryRoute.space(space.id)) {
              HStack(spacing: 10) {
                Image(systemName: space.symbol)
                  .foregroundStyle(.indigo)
                  .frame(width: 34, height: 34)
                  .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                  Text(space.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                  Text("\(meetingCount(for: space.id))件の会話")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              .padding(.vertical, 10)
              .padding(.horizontal, 12)
              .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        Text("最近の会話")
          .font(.title2.bold())
        Spacer()
        NavigationLink("すべて表示", value: LibraryRoute.allMeetings)
          .font(.subheadline)
      }

      LazyVStack(spacing: 0) {
        ForEach(model.meetings.prefix(4)) { meeting in
          NavigationLink(value: LibraryRoute.meeting(meeting.id)) {
            MeetingRow(meeting: meeting)
          }
          .buttonStyle(.plain)

          if meeting.id != model.meetings.prefix(4).last?.id {
            Divider()
              .padding(.leading, 52)
          }
        }
      }
    }
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
