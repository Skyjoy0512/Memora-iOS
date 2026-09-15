import SwiftUI

struct LifeLogView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""
  @State private var path: [LibraryRoute] = []
  @State private var isCreationPresented = false

  var body: some View {
    NavigationStack(path: $path) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 18) {
          if query.isEmpty, !todayEntries.isEmpty {
            LifeLogDaySummary(entries: todayEntries)
          }

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
            if !query.isEmpty {
              Text("検索結果")
                .font(.title2.bold())
                .memoraTextReveal()
            }

            ForEach(dayGroups) { group in
              VStack(alignment: .leading, spacing: 10) {
                Text(dayLabel(for: group.day))
                  .font(.title2.bold())
                  .memoraTextReveal()

                LazyVStack(spacing: 0) {
                  ForEach(group.entries) { entry in
                    if let meetingID = entry.meetingID {
                      NavigationLink(value: LibraryRoute.meeting(meetingID)) {
                        LifeLogRow(entry: entry)
                      }
                      .buttonStyle(.plain)
                    } else {
                      LifeLogRow(entry: entry)
                    }
                  }
                }
              }
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 32)
      }
      .hideBottomBarOnScroll()
      .background(Color(uiColor: .systemBackground))
      .navigationTitle("ライフログ")
      .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "ライフログを検索")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("新規作成", systemImage: "plus") {
            isCreationPresented = true
          }
          .labelStyle(.iconOnly)
        }
      }
      .sheet(isPresented: $isCreationPresented) {
        LifeLogCreationSheet()
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

  private var todayEntries: [LifeLogEntry] {
    matchingEntries.filter { Calendar.current.isDateInToday($0.createdAt) }
  }

  private var dayGroups: [LifeLogDayGroup] {
    let grouped = Dictionary(grouping: matchingEntries) {
      Calendar.current.startOfDay(for: $0.createdAt)
    }
    return grouped
      .map { LifeLogDayGroup(day: $0.key, entries: $0.value.sorted { $0.createdAt > $1.createdAt }) }
      .sorted { $0.day > $1.day }
  }

  private func dayLabel(for day: Date) -> String {
    if Calendar.current.isDateInToday(day) { return "今日" }
    if Calendar.current.isDateInYesterday(day) { return "昨日" }
    return day.formatted(date: .abbreviated, time: .omitted)
  }
}

private struct LifeLogDayGroup: Identifiable {
  var day: Date
  var entries: [LifeLogEntry]
  var id: Date { day }
}

private struct LifeLogDaySummary: View {
  var entries: [LifeLogEntry]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text("今日の流れ")
            .font(.headline)
          Text(timeRange)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Text("\(entries.count)件")
          .font(.title2.bold())
      }

      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 4)

          ForEach(entries) { entry in
            Circle()
              .fill(Color.primary)
              .frame(width: 11, height: 11)
              .overlay {
                Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2)
              }
              .offset(x: markerOffset(for: entry.createdAt, width: proxy.size.width))
          }
        }
      }
      .frame(height: 12)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("今日の記録は\(entries.count)件。\(timeRange)")

      HStack(spacing: 14) {
        ForEach(LifeLogKind.allCases) { kind in
          let count = entries.filter { $0.kind == kind }.count
          if count > 0 {
            Label("\(count)", systemImage: kind.symbol)
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .padding(18)
    .background(
      LinearGradient(
        colors: [Color.primary.opacity(0.075), Color.primary.opacity(0.025)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      ),
      in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
  }

  private var timeRange: String {
    guard let earliest = entries.min(by: { $0.createdAt < $1.createdAt })?.createdAt,
          let latest = entries.max(by: { $0.createdAt < $1.createdAt })?.createdAt else { return "" }
    return "\(earliest.formatted(date: .omitted, time: .shortened))–\(latest.formatted(date: .omitted, time: .shortened))"
  }

  private func markerOffset(for date: Date, width: CGFloat) -> CGFloat {
    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
    let minutes = Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    return max(0, min(width - 11, (width - 11) * minutes / 1_440))
  }
}
