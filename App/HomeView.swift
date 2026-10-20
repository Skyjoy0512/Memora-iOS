import EventKit
import SwiftUI

/// The landing screen. It answers "what happened today" first, then lets the
/// day unroll as a timeline of everything Memora captured.
struct HomeView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var query = ""
  @State private var isSearching = false
  /// The journal entry opened from the timeline.
  @State private var openEntry: LifeLogEntry?
  @State private var entryCreationDate: Date?
  /// The day the Journal is showing.
  @State private var selectedDate = Calendar.current.startOfDay(for: .now)
  /// Calendar events for the selected day, read from EventKit when that is on.
  @State private var calendarLoad = MemoraLoadSnapshot<JournalCalendarRequest, [JournalCalendarEvent]>()
  @State private var calendarRefresh = 0
  /// The journey whose station list is open.
  @State private var openMovement: JournalMovement?
  /// The calendar event whose detail sheet is open.
  @State private var openCalendarEvent: JournalCalendarEvent?
  @State private var showsReview = false
  @State private var showsSummary = false
  @State private var editingTask: MemoraTask?
  @State private var backdrops = JournalBackdropSelection()
  @Namespace private var summaryNamespace
  @AppStorage("memora.journal.showCalendarEvents") private var showCalendarEvents = false
  @AppStorage("memora.journal.calendarIDs") private var journalCalendarIDsValue = ""
  @AppStorage("memora.journal.healthReviewEnabled") private var healthEnabled = false
  @State private var healthLoader = HealthReviewService.makeLoader()
  @State private var healthRefreshID = 0

  private var journalCalendarIDs: [String] {
    journalCalendarIDsValue.isEmpty ? [] : journalCalendarIDsValue.components(separatedBy: "\n")
  }
  private var calendarRequest: JournalCalendarRequest {
    .init(date: selectedDate, calendarIDs: journalCalendarIDs, enabled: showCalendarEvents, refresh: calendarRefresh)
  }

  private var calendarEvents: [JournalCalendarEvent] {
    showCalendarEvents ? calendarLoad.value(for: calendarRequest.contentKey) ?? [] : []
  }

  /// The day "today" meant when the screen was last seen, so a journal left
  /// open past midnight follows the new day.
  @State private var todayAnchor = Calendar.current.startOfDay(for: .now)
  var onOpenSidebar: () -> Void

  var body: some View {
    @Bindable var model = model
    let entries = matchingEntries
    let dateLayout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: MemoraSpacing.xs))
      : AnyLayout(HStackLayout(spacing: MemoraSpacing.md))
    let ownTasks = model.ownTasks
    let markedDays = JournalActivityDays.build(
      recordedDays: model.markedLifeLogDays.union(model.markedMeetingDays),
      completedAt: ownTasks.filter { $0.isCompleted }.compactMap(\.completedAt))
    let healthRequest = JournalHealthRequest(period: .day(selectedDate), enabled: healthEnabled,
      teamID: model.currentTeamID, isActive: scenePhase == .active, isReviewPresented: showsReview,
      refreshID: healthRefreshID)
    let visibleHealth = healthRequest.canRead && healthLoader.period == healthRequest.period ? healthLoader.snapshot : nil
    let recap = JournalDailyRecap.build(date: selectedDate, meetings: model.meetings,
      tasks: ownTasks, entries: model.lifeLogEntries, spaces: model.spaces,
      people: model.people, events: calendarEvents, health: visibleHealth)

    NavigationStack(path: $model.homePath) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: MemoraSpacing.xxl) {
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

            VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
              dateLayout {
                Text(MemoraFormat.monthTitle(selectedDate))
                  .font(MemoraTypography.sectionHeading)
                  .fixedSize(horizontal: false, vertical: true)
                  .accessibilityAddTraits(.isHeader)
                if !typeSize.isAccessibilitySize { Spacer(minLength: MemoraSpacing.sm) }
                Button {
                  InteractionFeedback.shared.send(.selection)
                  withAnimation(reduceMotion ? nil : MemoraMotion.control) {
                    selectedDate = Calendar.current.startOfDay(for: .now)
                  }
                } label: {
                  Text("今日")
                    .font(MemoraTypography.secondary.weight(.medium))
                    .frame(minWidth: MemoraSpacing.touchTarget, minHeight: MemoraSpacing.touchTarget)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("今日に戻る")
                .disabled(isViewingToday)
              }
              .frame(minHeight: MemoraSpacing.touchTarget)
              JournalCalendar(selectedDate: $selectedDate, markedDays: markedDays)
            }

            if recap.hasActivity {
              JournalDailyRecapCard(recap: recap, date: selectedDate, backdrop: backdrops.current) {
                showsSummary = true
              }
              .matchedTransitionSource(id: "journalSummary", in: summaryNamespace)
            }

            if healthRequest.canRead, selectedDate <= .now {
              HealthReviewStatusView(loader: healthLoader, period: healthRequest.period) { healthRefreshID += 1 }
                .padding(MemoraSpacing.lg)
                .memoraCard(fill: MemoraPalette.card)
            }

            HomeActivityLinks()

            if showCalendarEvents {
              MemoraLoadingContainer(state: calendarLoad.state(for: calendarRequest.contentKey), label: "この日の予定を確認しています…", activityID: calendarLoad.activityID) {
                EmptyView()
              }
            }

            if entries.isEmpty, calendarEvents.isEmpty, !recap.hasActivity {
              emptyDay
            } else {
              timelineContent(entries, tasks: ownTasks)
            }
            if !recap.hasActivity, !recap.isFuture {
              Button("振り返りを見る") {
                InteractionFeedback.shared.send(.tap)
                showsReview = true
              }
                .font(.subheadline)
                .frame(minHeight: 44)
            }
          }
        }
        .frame(maxWidth: MemoraSpacing.readingWidth, alignment: .leading)
        .padding(.horizontal, MemoraSpacing.screen)
        .frame(maxWidth: .infinity)
        // The floating composer and tab bar do not inset this scroll view, so
        // leave room for the last records to clear them.
        .padding(.bottom, model.bottomContentClearance)
      }
      .hideBottomBarOnScroll(RootTab.home.rawValue)
      .refreshable {
        await model.refresh()
        if healthRequest.canRead { await healthLoader.load(healthRequest.period) }
      }
      .background(MemoraPalette.background)
      .navigationTitle(isSearching ? "" : "ジャーナル")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarSearch(text: $query, isPresented: $isSearching, prompt: "ジャーナルを検索")
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

        ToolbarActionItem {
          ToolbarIconButton("検索", icon: .magnifyingglass) {
            withAnimation(reduceMotion ? nil : MemoraMotion.control) {
              isSearching = true
            }
          }
          .labelStyle(.iconOnly)
        }

        // The create action is the rightmost item, matching the other tabs.
        ToolbarActionItem {
          ToolbarIconButton("記録を追加", icon: .squareAndPencil) {
            beginJournalEntry()
          }
          .labelStyle(.iconOnly)
        }
      }
      .sheet(isPresented: $model.isLifeLogCreationPresented, onDismiss: { entryCreationDate = nil }) {
        LifeLogCreationSheet(date: entryCreationDate ?? .now)
      }
      .sheet(isPresented: $showsReview) {
        JournalReviewView(date: selectedDate)
      }
      .sheet(item: $editingTask) { task in TaskEditView(task: task) }
      .fullScreenCover(isPresented: $showsSummary) {
        if reduceMotion {
          JournalSummaryView(date: selectedDate, backdrops: $backdrops, events: calendarEvents, health: visibleHealth)
        } else {
          JournalSummaryView(date: selectedDate, backdrops: $backdrops, events: calendarEvents, health: visibleHealth)
            .navigationTransition(.zoom(sourceID: "journalSummary", in: summaryNamespace))
        }
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
        calendarRefresh += 1
      }
      .task(id: calendarRequest) { await loadEvents(calendarRequest) }
      .task(id: healthRequest) {
        guard healthRequest.canRead else { healthLoader.clear(); return }
        await healthLoader.load(healthRequest.period, requestsAccess: healthRequest.refreshID > 0)
      }
      .onDisappear { if !showsSummary { healthLoader.clear() } }
      .onChange(of: selectedDate) { _, date in backdrops.select(date) }
      .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
        calendarRefresh += 1
      }
      .navigationDestination(for: LibraryRoute.self) { route in
        LibraryDestinationView(route: route)
      }
    }
  }

  /// UI additions follow the day being read; external new-memo actions keep now.
  private func beginJournalEntry() {
    entryCreationDate = isViewingToday ? .now : selectedDate
    model.isLifeLogCreationPresented = true
  }

  /// The selected day has nothing on it yet.
  private var emptyDay: some View {
    MemoraEmptyState(icon: .waveformPathEcg,
      title: "\(selectedDayLabel)の記録はありません",
      message: LocalizedStringKey(emptyDescription), actionTitle: "記録を追加", actionIcon: .squareAndPencil) {
      InteractionFeedback.shared.send(.tap)
      beginJournalEntry()
    }
  }

  /// Every day's matches, newest day first. Before anything is typed it says
  /// what the search covers rather than showing the journal behind it.
  @ViewBuilder
  private func searchResults(_ entries: [LifeLogEntry]) -> some View {
    if query.isEmpty {
      MemoraEmptyState(icon: .magnifyingglass, title: "記録を検索",
        message: "すべての日の記録から、タイトル・内容・記録元で探せます。予定は検索対象に含みません。")
        .padding(.top, MemoraSpacing.xxl)
    } else if entries.isEmpty {
      MemoraEmptyState(icon: .magnifyingglass, title: "見つかりませんでした",
        message: "「\(query)」に一致する記録はありません。短い言葉や別の表現で試してください。",
        actionTitle: "検索をやり直す", actionIcon: .xmark) { query = "" }
        .padding(.top, MemoraSpacing.xxl)
    } else {
      ForEach(dayGroups(of: entries)) { group in
        VStack(alignment: .leading, spacing: 10) {
          Text(dayLabel(for: group.day))
            .font(.title2.bold())

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

  /// True while the journal is showing the current day.
  private var isViewingToday: Bool {
    Calendar.current.isDateInToday(selectedDate)
  }

  private var selectedDayLabel: String {
    if isViewingToday { return "今日" }
    return MemoraFormat.shortDate(selectedDate)
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
  private func loadEvents(_ request: JournalCalendarRequest) async {
    guard !Task.isCancelled else { return }
    let token = calendarLoad.begin(request.contentKey)
    guard request.enabled else {
      calendarLoad.finish([], isEmpty: true, token: token)
      return
    }
    let events = await CalendarService.events(on: request.date,
      calendarIdentifiers: request.calendarIDs.isEmpty ? nil : request.calendarIDs)
    guard !Task.isCancelled, calendarRequest == request else { calendarLoad.cancel(token); return }
    calendarLoad.finish(events, isEmpty: events.isEmpty, token: token)
  }

  private var emptyDescription: String {
    if isViewingToday {
      return "録音やメモを追加すると、1日の出来事を時間順に振り返れます。"
    }
    return "この日の出来事をメモできます。現在の記録は上部の「今日」から確認できます。"
  }

  /// The selected day's timeline: records, events and movements in morning to
  /// night order, with an "now" line when it is today.
  @ViewBuilder
  private func timelineContent(_ entries: [LifeLogEntry], tasks: [MemoraTask]) -> some View {
    let timeline = JournalTimelineBuilder.build(
      day: selectedDate,
      entries: entries,
      events: calendarEvents,
      meetings: model.meetings,
      tasks: tasks
    )

    VStack(alignment: .leading, spacing: 10) {
      // The day heading the list had before, with the rows grouped under it and
      // the all-day events right below it.
      MemoraSectionHeading(title: "タイムライン", detail: dayLabel(for: selectedDate))

      if !timeline.allDayEvents.isEmpty {
        allDayEventChips(timeline.allDayEvents)
      }

      LazyVStack(spacing: 0) {
        ForEach(Array(timeline.items.enumerated()), id: \.element.id) { index, item in
          let nextDate = index + 1 < timeline.items.count
            ? timeline.items[index + 1].date(on: selectedDate) : nil
          timelineRow(item, connectsToNext: true, nextDate: nextDate)
          if index < timeline.items.count - 1 {
            JournalTimelineAddRow(label: "この間に記録を追加", isLast: false) {
              InteractionFeedback.shared.send(.tap)
              beginJournalEntry()
            }
          }
        }
        JournalTimelineAddRow(label: "記録を追加", isLast: true) {
          InteractionFeedback.shared.send(.tap)
          beginJournalEntry()
        }
      }
    }
  }

  @ViewBuilder
  private func timelineRow(_ item: JournalTimelineItem, connectsToNext: Bool, nextDate: Date?) -> some View {
    switch item {
    case .entry(let entry):
      entryView(entry, connectsToNext: connectsToNext, nextDate: nextDate)
    case .record(let meeting):
      NavigationLink(value: LibraryRoute.meeting(meeting.id)) {
        JournalTimelineRow(time: meeting.createdAt.formatted(date: .omitted, time: .shortened),
          date: meeting.createdAt, icon: meeting.source.icon, connectsToNext: connectsToNext, nextDate: nextDate) {
          VStack(alignment: .leading, spacing: 8) {
            Text(meeting.createdAt.formatted(date: .omitted, time: .shortened))
              .font(.caption.monospacedDigit())
            Text(meeting.displayTitle).font(.headline)
            Text(meeting.summaryPreview.isEmpty ? "記録の詳細を確認" : meeting.summaryPreview)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(3)
          }
        }
      }
      .buttonStyle(.plain)
      .accessibilityHint("記録の詳細を開きます")
    case .calendarEvent(let event):
      JournalCalendarEventRow(day: selectedDate, event: event, onOpen: { openCalendarEvent = $0 }, connectsToNext: connectsToNext, nextDate: nextDate)
    case .movement(let movement):
      JournalMovementRow(movement: movement, onOpen: { openMovement = $0 }, connectsToNext: connectsToNext, nextDate: nextDate)
    case .nowMarker:
      nowMarker
    case .completedTask(let task):
      Button {
        InteractionFeedback.shared.send(.tap)
        editingTask = task
      } label: {
        JournalTimelineRow(time: task.completedAt?.formatted(date: .omitted, time: .shortened) ?? "",
          date: task.completedAt ?? selectedDate, icon: .checkmark, connectsToNext: connectsToNext, nextDate: nextDate) {
          VStack(alignment: .leading, spacing: 8) {
            Text(task.completedAt?.formatted(date: .omitted, time: .shortened) ?? "")
              .font(.caption.monospacedDigit())
            Text(task.title).font(.headline)
            Text("タスクを完了").font(.subheadline).foregroundStyle(.secondary)
          }
        }
      }
      .buttonStyle(.plain)
      .accessibilityHint("タスクの詳細を開きます")
    }
  }

  @ViewBuilder
  private func entryView(_ entry: LifeLogEntry, connectsToNext: Bool = false, nextDate: Date? = nil) -> some View {
    if let meetingID = entry.meetingID {
      NavigationLink(value: LibraryRoute.meeting(meetingID)) {
        LifeLogRow(entry: entry, connectsToNext: connectsToNext, nextDate: nextDate)
      }
      .buttonStyle(.plain)
    } else {
      LifeLogRow(entry: entry, connectsToNext: connectsToNext, nextDate: nextDate)
        .contentShape(Rectangle())
        .onTapGesture {
          InteractionFeedback.shared.send(.tap)
          openEntry = entry
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("記録を開きます")
        .accessibilityAction(named: "開く") {
          InteractionFeedback.shared.send(.tap)
          openEntry = entry
        }
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
    .padding(.vertical, MemoraSpacing.sm)
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
    .padding(.horizontal, MemoraSpacing.md)
    .padding(.vertical, MemoraSpacing.sm)
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
    return MemoraFormat.shortDate(day)
  }
}
