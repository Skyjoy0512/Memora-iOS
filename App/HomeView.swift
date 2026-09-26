import EventKit
import SwiftUI

/// The landing screen. It answers "what happened today" first, then lets the
/// day unroll as a timeline of everything Memora captured.
struct HomeView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @State private var query = ""
  /// The journal entry opened from the timeline.
  @State private var openEntry: LifeLogEntry?
  /// The day the Journal is showing.
  @State private var selectedDate = Calendar.current.startOfDay(for: .now)
  /// Calendar events for the selected day, read from EventKit when that is on.
  @State private var calendarEvents: [JournalCalendarEvent] = []
  /// The journey whose station list is open.
  @State private var openMovement: JournalMovement?
  /// The calendar event whose detail sheet is open.
  @State private var openCalendarEvent: JournalCalendarEvent?
  @AppStorage("memora.journal.showCalendarEvents") private var showCalendarEvents = false
  @AppStorage("memora.journal.calendarIDs") private var journalCalendarIDsValue = ""

  private var journalCalendarIDs: [String] {
    journalCalendarIDsValue.isEmpty ? [] : journalCalendarIDsValue.components(separatedBy: "\n")
  }
  /// The day "today" meant when the screen was last seen, so a journal left
  /// open past midnight follows the new day.
  @State private var todayAnchor = Calendar.current.startOfDay(for: .now)
  var onOpenSidebar: () -> Void

  var body: some View {
    @Bindable var model = model
    let entries = matchingEntries

    NavigationStack(path: $model.homePath) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 18) {
          if model.isRecording {
            ActiveRecordingStrip()
          }

          if model.hasSampleContent, query.isEmpty {
            SampleNoticeRow()
          }

          if query.isEmpty {
            JournalCalendar(selectedDate: $selectedDate, markedDays: markedDays)
          }

          if entries.isEmpty, query.isEmpty ? calendarEvents.isEmpty : true {
            VStack(spacing: 16) {
              Image(systemName: "waveform.path.ecg")
                .font(.title2)
                .foregroundStyle(.secondary)

              VStack(spacing: 6) {
                Text(emptyTitle)
                  .font(.headline)

                Text(emptyDescription)
                  .font(.subheadline)
                  .foregroundStyle(.secondary)
                  .multilineTextAlignment(.center)
              }

              if query.isEmpty {
                Button("記録を追加") {
                  model.isLifeLogCreationPresented = true
                }
                .font(.headline)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(uiColor: .label), in: Capsule())
                .contentShape(Capsule())
                .buttonStyle(.plain)
              }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .memoraCard()
          } else if !query.isEmpty {
            Text("検索結果")
              .font(.title2.bold())
              .memoraTextReveal()

            ForEach(dayGroups(of: entries)) { group in
              VStack(alignment: .leading, spacing: 10) {
                Text(dayLabel(for: group.day))
                  .font(.title2.bold())
                  .memoraTextReveal()

                LazyVStack(spacing: 0) {
                  ForEach(group.entries) { entry in
                    entryView(entry)
                  }
                }
              }
            }
          } else {
            timelineContent(entries)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        // The floating composer and tab bar do not inset this scroll view, so
        // leave room for the last records to clear them.
        .padding(.bottom, model.bottomContentClearance)
      }
      .hideBottomBarOnScroll(RootTab.home.rawValue)
      .refreshable { await model.refresh() }
      .background(Color(uiColor: .systemBackground))
      .navigationTitle("ジャーナル")
      .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "記録を検索")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("メニュー", systemImage: "line.3.horizontal") {
            onOpenSidebar()
          }
          .labelStyle(.iconOnly)
        }

        // The external recorder's state only earns a place here for people who
        // have set one up; the sidebar still reaches the setting either way.
        if isOmiConnected || OmiPairingManager.hasRememberedDevice {
          ToolbarItem(placement: .topBarLeading) {
            sourceStatusButton
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button("設定", systemImage: "gearshape") {
            model.isSettingsPresented = true
          }
          .labelStyle(.iconOnly)
        }
      }
      .sheet(isPresented: $model.isLifeLogCreationPresented) {
        LifeLogCreationSheet()
      }
      .sheet(item: $openEntry) { entry in
        LifeLogEntryDetailView(entryID: entry.id)
      }
      .sheet(item: $openMovement) { movement in
        JournalMovementSheet(movement: movement)
      }
      .sheet(item: $openCalendarEvent) { event in
        CalendarEventSheet(event: event)
      }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active else { return }
        refreshTodayIfNeeded()
        Task { await loadEvents() }
      }
      .task(id: selectedDate) { await loadEvents() }
      .onChange(of: showCalendarEvents) { _, _ in Task { await loadEvents() } }
      .onChange(of: journalCalendarIDsValue) { _, _ in Task { await loadEvents() } }
      .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
        Task { await loadEvents() }
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

  /// The lifelog connection lives beside the menu so the journal itself keeps
  /// the full screen.
  private var sourceStatusButton: some View {
    Button {
      model.isSettingsPresented = true
    } label: {
      Label("Omi", systemImage: isOmiConnected ? "dot.radiowaves.left.and.right" : "link")
        .font(.subheadline.weight(.medium))
        .foregroundStyle(isOmiConnected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
    }
    .accessibilityLabel(isOmiConnected ? "Omi 接続中" : "ライフログの接続先")
    .accessibilityHint("レコーダー設定を開きます")
  }

  /// Days that hold at least one record, for the calendar's dot. Built with the
  /// records rather than scanned on every redraw.
  private var markedDays: Set<Date> {
    model.markedLifeLogDays
  }

  /// True while the journal is showing the current day.
  private var isViewingToday: Bool {
    Calendar.current.isDateInToday(selectedDate)
  }

  private var emptyTitle: String {
    if !query.isEmpty {
      return "見つかりませんでした"
    }
    return "\(selectedDayLabel)の記録はありません"
  }

  private var selectedDayLabel: String {
    if isViewingToday { return "今日" }
    return selectedDate.formatted(.dateTime.month().day())
  }

  /// A journal left open past midnight should move to the new day, unless the
  /// person had picked another day themselves.
  private func refreshTodayIfNeeded() {
    let today = Calendar.current.startOfDay(for: .now)
    guard today != todayAnchor else { return }
    if selectedDate == todayAnchor {
      selectedDate = today
    }
    todayAnchor = today
  }

  private var isOmiConnected: Bool {
    if case .connected = model.omiPairingManager.state { return true }
    return false
  }

  private var matchingEntries: [LifeLogEntry] {
    // A search looks across every day; the journal otherwise shows the day
    // picked in the calendar, taken from the index built with the records.
    let base = query.isEmpty ? entriesForSelectedDay : model.newestLifeLogEntries

    guard !query.isEmpty else { return base }
    return base.filter {
      $0.title.localizedCaseInsensitiveContains(query)
        || $0.summary.localizedCaseInsensitiveContains(query)
        || $0.source.label.localizedCaseInsensitiveContains(query)
    }
  }

  /// The selected day's records, read from the model's day index.
  private var entriesForSelectedDay: [LifeLogEntry] {
    let calendar = Calendar.current
    return model.lifeLogDays.first { calendar.isDate($0.day, inSameDayAs: selectedDate) }?.entries ?? []
  }

  /// Reads the selected day's events when the journal is set to show them.
  private func loadEvents() async {
    guard showCalendarEvents else {
      calendarEvents = []
      return
    }
    let identifiers = journalCalendarIDs.isEmpty ? nil : journalCalendarIDs
    calendarEvents = await CalendarService.events(on: selectedDate, calendarIdentifiers: identifiers)
  }

  private var emptyDescription: String {
    if !query.isEmpty {
      return "「\(query)」に一致する記録はありません。予定は検索の対象外です。"
    }
    if isViewingToday {
      return "録音やOmiから届いた記録、手で足したメモが時間順に並びます。"
    }
    return "この日の記録はまだありません。別の日を選ぶか、カレンダーの「今日」で今日に戻れます。"
  }

  /// The selected day's timeline: records, events and movements in morning to
  /// night order, with an "now" line when it is today.
  @ViewBuilder
  private func timelineContent(_ entries: [LifeLogEntry]) -> some View {
    let timeline = JournalTimelineBuilder.build(
      day: selectedDate,
      entries: entries,
      events: calendarEvents,
      meetings: model.meetings
    )

    if !timeline.allDayEvents.isEmpty {
      allDayEventChips(timeline.allDayEvents)
    }

    ForEach(timeline.items) { item in
      timelineRow(item)
    }
  }

  @ViewBuilder
  private func timelineRow(_ item: JournalTimelineItem) -> some View {
    switch item {
    case .entry(let entry):
      entryView(entry)
    case .calendarEvent(let event):
      calendarEventView(event)
    case .movement(let movement):
      movementView(movement)
    case .nowMarker:
      nowMarkerRow
    }
  }

  @ViewBuilder
  private func entryView(_ entry: LifeLogEntry) -> some View {
    if let meetingID = entry.meetingID {
      NavigationLink(value: LibraryRoute.meeting(meetingID)) {
        LifeLogRow(entry: entry)
      }
      .buttonStyle(.plain)
    } else {
      LifeLogRow(entry: entry)
        .contentShape(Rectangle())
        .onTapGesture { openEntry = entry }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("記録を開きます")
        .accessibilityAction(named: "開く") { openEntry = entry }
    }
  }

  @ViewBuilder
  private func calendarEventView(_ event: JournalCalendarEvent) -> some View {
    if let meetingID = event.meetingID {
      NavigationLink(value: LibraryRoute.meeting(meetingID)) {
        calendarEventLabel(event)
      }
      .buttonStyle(.plain)
    } else {
      Button {
        openCalendarEvent = event
      } label: {
        calendarEventLabel(event)
      }
      .buttonStyle(.plain)
      .accessibilityHint("予定の詳細を開きます")
    }
  }

  private func calendarEventLabel(_ event: JournalCalendarEvent) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(eventTimeText(event))
        .font(.caption.monospacedDigit().weight(.medium))
        .foregroundStyle(.secondary)
        .frame(width: 46, alignment: .leading)

      VStack(alignment: .leading, spacing: 2) {
        Text(event.title)
          .font(.headline)
        HStack(spacing: 4) {
          if let color = event.calendarColor {
            Circle()
              .fill(color)
              .frame(width: 8, height: 8)
          }
          Text(event.calendarTitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(eventTimeText(event))、予定、\(event.title)、\(event.calendarTitle)"
    )
  }

  /// An event still running from the day before shows only its end, so it reads
  /// as a continuation rather than a fresh start.
  private func eventTimeText(_ event: JournalCalendarEvent) -> String {
    let dayStart = Calendar.current.startOfDay(for: selectedDate)
    let end = event.end.formatted(date: .omitted, time: .shortened)
    if event.start < dayStart {
      return "〜\(end)"
    }
    let start = event.start.formatted(date: .omitted, time: .shortened)
    return "\(start)〜\(end)"
  }

  private func movementView(_ movement: JournalMovement) -> some View {
    let stations = movement.entries.map { JournalMovementSheet.stationName(from: $0.title) }

    return Button {
      openMovement = movement
    } label: {
      HStack(alignment: .top, spacing: 12) {
        timeText(movement.start)

        VStack(alignment: .leading, spacing: 2) {
          Text(stations.joined(separator: " → "))
            .font(.headline)
            .lineLimit(2)
          Text(
            "\(movement.start.formatted(date: .omitted, time: .shortened))〜\(movement.end.formatted(date: .omitted, time: .shortened))"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("移動、\(stations.joined(separator: "、"))")
    .accessibilityHint("各駅の時刻を開きます")
  }

  private var nowMarkerRow: some View {
    HStack(spacing: 8) {
      Text("いま")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Rectangle()
        .fill(Color.primary.opacity(0.2))
        .frame(height: 1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("いま")
  }

  private func allDayEventChips(_ events: [JournalCalendarEvent]) -> some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(events) { event in
          if let meetingID = event.meetingID {
            NavigationLink(value: LibraryRoute.meeting(meetingID)) {
              allDayChip(event)
            }
            .buttonStyle(.plain)
          } else {
            Button {
              openCalendarEvent = event
            } label: {
              allDayChip(event)
            }
            .buttonStyle(.plain)
            .accessibilityHint("予定の詳細を開きます")
          }
        }
      }
    }
    .scrollIndicators(.hidden)
  }

  private func allDayChip(_ event: JournalCalendarEvent) -> some View {
    HStack(spacing: 6) {
      if let color = event.calendarColor {
        Circle()
          .fill(color)
          .frame(width: 8, height: 8)
      }
      Text(event.title)
        .font(.caption.weight(.medium))
        .foregroundStyle(.primary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Color.primary.opacity(0.06), in: Capsule())
    .contentShape(Capsule())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("終日の予定、\(event.title)、\(event.calendarTitle)")
  }

  private func timeText(_ date: Date) -> some View {
    Text(date.formatted(date: .omitted, time: .shortened))
      .font(.caption.monospacedDigit().weight(.medium))
      .foregroundStyle(.secondary)
      .frame(width: 46, alignment: .leading)
  }

  private func dayGroups(of entries: [LifeLogEntry]) -> [LifeLogDayGroup] {
    let grouped = Dictionary(grouping: entries) {
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

