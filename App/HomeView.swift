import SwiftUI

/// The landing screen. It answers "what happened today" first, then lets the
/// day unroll as a timeline of everything Memora captured.
struct HomeView: View {
  @Environment(MemoraModel.self) private var model
  @State private var query = ""
  @State private var isCreationPresented = false
  var onOpenSidebar: () -> Void

  var body: some View {
    @Bindable var model = model

    NavigationStack(path: $model.homePath) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 18) {
          if query.isEmpty {
            TodayDigestCard(
              entries: todayEntries,
              meetingCount: todayMeetings.count,
              openTaskCount: openTasks.count
            )

            sourceStatus
          }

          if matchingEntries.isEmpty {
            ContentUnavailableView {
              Label("まだライフログがありません", systemImage: "waveform.path.ecg")
            } description: {
              Text(query.isEmpty
                   ? "録音やOmiから届いた記録、手で足したメモが時間順に並びます。"
                   : "「\(query)」に一致する記録はありません。")
            } actions: {
              if query.isEmpty {
                Button("記録を追加", systemImage: "plus") {
                  isCreationPresented = true
                }
                .buttonStyle(.borderedProminent)
              }
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
      .navigationTitle("ホーム")
      .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "記録を検索")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("メニュー", systemImage: "line.3.horizontal") {
            onOpenSidebar()
          }
          .labelStyle(.iconOnly)
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button("記録を追加", systemImage: "plus") {
            isCreationPresented = true
          }
          .labelStyle(.iconOnly)
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button("設定", systemImage: "gearshape") {
            model.isSettingsPresented = true
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
      model.isSettingsPresented = true
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

  private var todayMeetings: [Meeting] {
    model.meetings.filter { Calendar.current.isDateInToday($0.createdAt) }
  }

  private var openTasks: [MemoraTask] {
    model.tasks.filter { !$0.isCompleted }
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

/// One glance at the day: how much was captured, what still needs doing, and
/// when it all happened.
private struct TodayDigestCard: View {
  @Environment(MemoraModel.self) private var model
  var entries: [LifeLogEntry]
  var meetingCount: Int
  var openTaskCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 3) {
        Text("今日")
          .font(.headline)
        Text(Date.now.formatted(.dateTime.month(.wide).day().weekday(.wide)))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 0) {
        DigestStat(value: meetingCount, label: "会議") {
          model.selectedTab = .files
          model.fileSection = .meetingFiles
        }

        DigestStat(value: openTaskCount, label: "未完了") {
          model.selectedTab = .tasks
        }

        DigestStat(value: entries.count, label: "記録", action: nil)
      }

      if !entries.isEmpty {
        DayTimelineBar(entries: entries)

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
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      LinearGradient(
        colors: [Color.primary.opacity(0.075), Color.primary.opacity(0.025)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      ),
      in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
  }
}

private struct DigestStat: View {
  var value: Int
  var label: String
  var action: (() -> Void)?

  var body: some View {
    if let action {
      Button(action: action) {
        content
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(label) \(value)件")
      .accessibilityHint("\(label)の画面を開きます")
    } else {
      content
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)件")
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("\(value)")
        .font(.title.bold())
        .monospacedDigit()
        .contentTransition(.numericText())
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }
}

/// Places each record along a 24 hour line so the shape of the day is visible
/// before reading a single word.
private struct DayTimelineBar: View {
  var entries: [LifeLogEntry]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
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
        .frame(maxHeight: .infinity, alignment: .center)
      }
      .frame(height: 12)

      if !timeRange.isEmpty {
        Text(timeRange)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("今日の記録は\(entries.count)件。\(timeRange)")
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
