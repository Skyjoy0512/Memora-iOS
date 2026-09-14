import SwiftUI

struct LifeLogView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""
  @State private var path: [LibraryRoute] = []

  var body: some View {
    NavigationStack(path: $path) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 18) {
          sourceStatus

          if matchingEntries.isEmpty {
            ContentUnavailableView {
              Label("まだライフログがありません", systemImage: "waveform.path.ecg")
            } description: {
              Text(query.isEmpty ? "Omiなどから届いた日常の記録が、時間順に並びます。" : "「\(query)」に一致する記録はありません。")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
          } else {
            Text(query.isEmpty ? "今日" : "検索結果")
              .font(.title2.bold())
              .memoraTextReveal()

            VStack(spacing: 0) {
              ForEach(matchingEntries) { entry in
                if let meetingID = entry.meetingID {
                  NavigationLink(value: LibraryRoute.meeting(meetingID)) {
                    LifeLogRow(entry: entry)
                  }
                  .buttonStyle(.plain)
                } else {
                  LifeLogRow(entry: entry)
                }

                if entry.id != matchingEntries.last?.id {
                  Divider().padding(.leading, 58)
                }
              }
            }
            .padding(.horizontal, 14)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 32)
      }
      .background(Color(uiColor: .systemBackground))
      .navigationTitle("ライフログ")
      .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "ライフログを検索")
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

  private var sourceStatus: some View {
    Button {
      model.selectedTab = .settings
    } label: {
      HStack(spacing: 12) {
        Image(systemName: isOmiConnected ? "dot.radiowaves.left.and.right" : "link")
          .foregroundStyle(isOmiConnected ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
        VStack(alignment: .leading, spacing: 2) {
          Text(isOmiConnected ? "Omi 接続中" : "ライフログの接続先")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          Text(isOmiConnected ? "新しい記録を待っています" : "Omiは設定からペアリングできます")
            .font(.caption)
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
    .accessibilityHint("レコーダー設定を開きます")
  }

  private var isOmiConnected: Bool {
    if case .connected = model.omiPairingManager.state { return true }
    return false
  }

  private var matchingEntries: [LifeLogEntry] {
    let sorted = model.lifeLogEntries.sorted { $0.createdAt > $1.createdAt }
    guard !query.isEmpty else { return sorted }
    return sorted.filter {
      $0.title.localizedCaseInsensitiveContains(query)
        || $0.summary.localizedCaseInsensitiveContains(query)
        || $0.source.label.localizedCaseInsensitiveContains(query)
    }
  }
}
