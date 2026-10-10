import EventKit
import SwiftUI

/// The landing screen. It answers "what happened today" first, then lets the
/// day unroll as a timeline of everything Memora captured.
struct HomeView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var query = ""
  @State private var isSearching = false
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
  @State private var showsReview = false
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
    let recap = JournalDailyRecap.build(date: selectedDate, meetings: model.meetings,
      tasks: model.tasks, entries: model.lifeLogEntries)

    NavigationStack(path: $model.homePath) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 18) {
          // Searching replaces the journal with its results, so the calendar
          // and the day's timeline step aside instead of sitting under them.
          if isSearching {
            searchResults(entries)
          } else {
            if model.isRecording {
              ActiveRecordingStrip()
            }

            if model.hasSampleContent {
              SampleNoticeRow()
            }

            if let review = model.unreadWeeklyReview {
              WeeklyReviewCard(review: review)
            }

            JournalCalendar(selectedDate: $selectedDate, markedDays: markedDays)

            if recap.hasActivity {
              JournalDailyRecapCard(recap: recap) {
                showsReview = true
              }
            }

            if entries.isEmpty, calendarEvents.isEmpty {
              if !recap.hasActivity { emptyDay }
            } else {
              timelineContent(entries)
            }
            if !recap.hasActivity, !recap.isFuture {
              Button("振り返りを見る") { showsReview = true }
                .font(.subheadline)
                .frame(minHeight: 44)
            }
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
      .toolbarSearch(text: $query, isPresented: $isSearching, prompt: "記録を検索")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          ToolbarIconButton("メニュー", icon: .line3Horizontal) {
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
          ToolbarIconButton("検索", icon: .magnifyingglass, artwork: .searchIntelligence) {
            withAnimation(reduceMotion ? nil : MemoraMotion.control) {
              isSearching = true
            }
          }
          .labelStyle(.iconOnly)
        }

        // The create action is the rightmost item, matching the other tabs.
        ToolbarItem(placement: .primaryAction) {
          ToolbarIconButton("記録を追加", icon: .squareAndPencil) {
            model.isLifeLogCreationPresented = true
          }
          .labelStyle(.iconOnly)
        }
      }
      .sheet(isPresented: $model.isLifeLogCreationPresented) {
        LifeLogCreationSheet()
      }
      .sheet(isPresented: $showsReview) {
        JournalReviewView(date: selectedDate)
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
        case .documents: DocumentsView()
        case .document(let id): DocumentDetailView(documentID: id)
        case .people: PeopleView()
        case .person(let id): PersonDetailView(personID: id)
        case .sharedRecord(let id): SharedRecordView(recordID: id)
        case .sharedProject(let id): SharedProjectView(projectID: id)
        }
      }
    }
  }

  /// The selected day has nothing on it yet.
  private var emptyDay: some View {
    VStack(spacing: 16) {
      Image(icon: .waveformPathEcg)
        .font(.title2)
        .foregroundStyle(.primary)

      VStack(spacing: 6) {
        Text("\(selectedDayLabel)の記録はありません")
          .font(.headline)

        Text(emptyDescription)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      Button("記録を追加") {
        model.isLifeLogCreationPresented = true
      }
      .font(.headline)
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, minHeight: 52)
      .background(.tint, in: Capsule())
      .contentShape(Capsule())
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity)
    .padding(20)
    .memoraCard()
  }

  /// Every day's matches, newest day first. Before anything is typed it says
  /// what the search covers rather than showing the journal behind it.
  @ViewBuilder
  private func searchResults(_ entries: [LifeLogEntry]) -> some View {
    if query.isEmpty {
      ContentUnavailableView(
        "記録を検索",
        icon: .magnifyingglass,
        description: Text("すべての日の記録から、タイトル・内容・記録元で探せます。")
      )
      .padding(.top, 48)
    } else if entries.isEmpty {
      ContentUnavailableView(
        "見つかりませんでした",
        icon: .magnifyingglass,
        description: Text("「\(query)」に一致する記録はありません。予定は検索の対象外です。")
      )
      .padding(.top, 48)
    } else {
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
    }
  }

  /// The lifelog connection lives beside the menu so the journal itself keeps
  /// the full screen.
  private var sourceStatusButton: some View {
    Button {
      model.isSettingsPresented = true
    } label: {
      Label("Omi", icon: isOmiConnected ? .dotRadiowavesLeftAndRight : .link)
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

    VStack(alignment: .leading, spacing: 10) {
      // The day heading the list had before, with the rows grouped under it and
      // the all-day events right below it.
      Text(dayLabel(for: selectedDate))
        .font(.title2.bold())
        .memoraTextReveal()

      if !timeline.allDayEvents.isEmpty {
        allDayEventChips(timeline.allDayEvents)
      }

      LazyVStack(spacing: 0) {
        ForEach(timeline.items) { item in
          timelineRow(item)
        }
      }
    }
  }

  @ViewBuilder
  private func timelineRow(_ item: JournalTimelineItem) -> some View {
    switch item {
    case .entry(let entry):
      entryView(entry)
    case .calendarEvent(let event):
      JournalCalendarEventRow(day: selectedDate, event: event) { openCalendarEvent = $0 }
    case .movement(let movement):
      JournalMovementRow(movement: movement) { openMovement = $0 }
    case .nowMarker:
      nowMarker
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

  /// The "now" line, in the primary colour (red stays for recording only).
  private var nowMarker: some View {
    HStack(spacing: 8) {
      Text("いま")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
      Rectangle()
        .fill(Color.primary.opacity(0.25))
        .frame(height: 1)
    }
    .padding(.vertical, 6)
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
